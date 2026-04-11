-- ═══════════════════════════════════════════════════════════════════════════════
-- MIGRATION: Money OS Enhancements
-- Statement import rows, AI suggestions, merchant canonical, recurring suggestions
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Statement Import Rows — row-level parsed data from statement imports
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.statement_import_rows (
  id                uuid          primary key default gen_random_uuid(),
  import_id         uuid          not null references public.statement_imports(id) on delete cascade,
  user_id           uuid          not null references public.profiles(id) on delete cascade,
  row_index         integer       not null,
  raw_date          text,
  parsed_date       date,
  raw_description   text,
  cleaned_description text,
  raw_amount        text,
  parsed_amount     numeric(12,2),
  raw_balance       text,
  parsed_balance    numeric(14,2),
  debit_or_credit   text          check (debit_or_credit in ('debit','credit')),
  category_suggestion text,
  merchant_suggestion text,
  matched_transaction_id uuid    references public.transactions(id) on delete set null,
  matched_recurring_id   uuid    references public.recurring_series(id) on delete set null,
  is_duplicate      boolean       not null default false,
  is_transfer       boolean       not null default false,
  review_status     text          not null default 'pending'
    check (review_status in ('pending','accepted','ignored','duplicate','needs_review')),
  created_transaction_id uuid    references public.transactions(id) on delete set null,
  notes             text,
  created_at        timestamptz   not null default now()
);

create index if not exists sir_import_idx on public.statement_import_rows(import_id, row_index);
create index if not exists sir_user_idx   on public.statement_import_rows(user_id, created_at desc);
create index if not exists sir_review_idx on public.statement_import_rows(user_id, review_status)
  where review_status = 'pending';

alter table public.statement_import_rows enable row level security;

create policy "sir_select" on public.statement_import_rows for select using (auth.uid() = user_id);
create policy "sir_insert" on public.statement_import_rows for insert with check (auth.uid() = user_id);
create policy "sir_update" on public.statement_import_rows for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "sir_delete" on public.statement_import_rows for delete using (auth.uid() = user_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Merchant Canonical — normalized merchant names
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.merchant_canonical (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        references public.profiles(id) on delete cascade,
  raw_name        text        not null,
  canonical_name  text        not null,
  category_id     uuid        references public.categories(id),
  logo_url        text,
  source          text        not null default 'manual'
    check (source in ('manual','ai','system','import')),
  created_at      timestamptz not null default now()
);

create index if not exists mc_user_raw_idx on public.merchant_canonical(user_id, lower(raw_name));
create unique index if not exists mc_unique_raw on public.merchant_canonical(user_id, lower(raw_name));

alter table public.merchant_canonical enable row level security;

create policy "mc_select" on public.merchant_canonical for select
  using (user_id is null or auth.uid() = user_id);
create policy "mc_insert" on public.merchant_canonical for insert
  with check (auth.uid() = user_id);
create policy "mc_update" on public.merchant_canonical for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. AI Suggestions — unified suggestion/review inbox
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.ai_suggestions (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references public.profiles(id) on delete cascade,
  suggestion_type   text        not null check (suggestion_type in (
    'category','merchant_normalize','recurring_detect','duplicate_warning',
    'import_match','settlement_suggest','split_suggest','anomaly_alert',
    'ocr_correction','budget_warning'
  )),
  entity_type       text,
  entity_id         uuid,
  title             text        not null,
  description       text,
  confidence        numeric(3,2) check (confidence >= 0 and confidence <= 1),
  suggested_action  jsonb,
  status            text        not null default 'pending'
    check (status in ('pending','accepted','dismissed','snoozed','expired')),
  snoozed_until     timestamptz,
  feedback          text        check (feedback in ('helpful','not_helpful','wrong')),
  expires_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists ais_user_status_idx on public.ai_suggestions(user_id, status, created_at desc);
create index if not exists ais_entity_idx      on public.ai_suggestions(entity_type, entity_id);
create index if not exists ais_type_idx        on public.ai_suggestions(user_id, suggestion_type)
  where status = 'pending';

alter table public.ai_suggestions enable row level security;

create policy "ais_select" on public.ai_suggestions for select using (auth.uid() = user_id);
create policy "ais_insert" on public.ai_suggestions for insert with check (auth.uid() = user_id);
create policy "ais_update" on public.ai_suggestions for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "ais_delete" on public.ai_suggestions for delete using (auth.uid() = user_id);

drop trigger if exists ais_touch_updated_at on public.ai_suggestions;
create trigger ais_touch_updated_at
  before update on public.ai_suggestions
  for each row execute function set_invoice_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Recurring Suggestions — pattern detection feedback
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.recurring_suggestions (
  id                  uuid        primary key default gen_random_uuid(),
  user_id             uuid        not null references public.profiles(id) on delete cascade,
  vendor_pattern      text        not null,
  suggested_cadence   text        check (suggested_cadence in ('weekly','biweekly','monthly','quarterly','yearly')),
  avg_amount          numeric(12,2),
  occurrence_count    integer     not null default 0,
  first_seen          date,
  last_seen           date,
  sample_transaction_ids uuid[],
  status              text        not null default 'pending'
    check (status in ('pending','confirmed','dismissed','snoozed','suppressed')),
  created_series_id   uuid        references public.recurring_series(id) on delete set null,
  snoozed_until       timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists rs_user_status_idx on public.recurring_suggestions(user_id, status);
create unique index if not exists rs_user_vendor_idx on public.recurring_suggestions(user_id, lower(vendor_pattern))
  where status not in ('dismissed','suppressed');

alter table public.recurring_suggestions enable row level security;

create policy "rsg_select" on public.recurring_suggestions for select using (auth.uid() = user_id);
create policy "rsg_insert" on public.recurring_suggestions for insert with check (auth.uid() = user_id);
create policy "rsg_update" on public.recurring_suggestions for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "rsg_delete" on public.recurring_suggestions for delete using (auth.uid() = user_id);

drop trigger if exists rsg_touch_updated_at on public.recurring_suggestions;
create trigger rsg_touch_updated_at
  before update on public.recurring_suggestions
  for each row execute function set_invoice_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Analytics Fingerprint — avoid wasteful recomputation
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.analytics_insight_snapshots
  add column if not exists data_fingerprint text,
  add column if not exists deterministic jsonb,
  add column if not exists ai_layer jsonb;

-- Add account_id + counter_account_id to transactions for transfers
alter table public.transactions
  add column if not exists account_id         uuid references public.accounts(id) on delete set null,
  add column if not exists counter_account_id uuid references public.accounts(id) on delete set null;

create index if not exists txn_account_idx on public.transactions(account_id) where account_id is not null;


-- ─────────────────────────────────────────────────────────────────────────────
-- DONE
-- ─────────────────────────────────────────────────────────────────────────────
