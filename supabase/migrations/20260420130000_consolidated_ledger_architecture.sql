-- ═══════════════════════════════════════════════════════════════════════════════
-- CONSOLIDATED MIGRATION: GOAT cleanup + Billy Ledger Architecture
-- ═══════════════════════════════════════════════════════════════════════════════
-- Safe to run against the current database state. Every statement is
-- idempotent (IF EXISTS / IF NOT EXISTS / DROP-then-CREATE for policies).
-- Run this in the Supabase SQL editor as a single execution.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1 — GOAT cleanup: drop all GOAT-era tables, functions, columns
-- ─────────────────────────────────────────────────────────────────────────────

-- 1a. Storage policy cleanup (bucket data must be removed via the Storage API / dashboard)
drop policy if exists "statement_files_delete_own" on storage.objects;
drop policy if exists "statement_files_update_own" on storage.objects;
drop policy if exists "statement_files_insert_own" on storage.objects;
drop policy if exists "statement_files_select_own" on storage.objects;

-- 1b. GOAT setup tables
drop table if exists public.goat_dashboard_preferences cascade;
drop table if exists public.goat_setup_drafts           cascade;
drop table if exists public.goat_setup_state             cascade;

-- 1c. Statement pipeline (GOAT elaborate versions)
drop table if exists public.statement_row_reviews       cascade;
drop table if exists public.statement_raw_extractions   cascade;
drop table if exists public.statement_import_reviews    cascade;
drop table if exists public.statement_document_links    cascade;
drop table if exists public.canonical_financial_events  cascade;
drop table if exists public.statement_transactions      cascade;
drop table if exists public.statement_transactions_raw  cascade;
drop table if exists public.statement_imports           cascade;
drop table if exists public.statement_accounts          cascade;

-- 1d. Goals system
drop table if exists public.goal_contributions    cascade;
drop table if exists public.goal_rules            cascade;
drop table if exists public.goal_recommendations  cascade;
drop table if exists public.goals                 cascade;

-- 1e. Recurring (GOAT version — different schema from our target)
drop table if exists public.recurring_notification_rules cascade;
drop table if exists public.recurring_change_events      cascade;
drop table if exists public.recurring_occurrences        cascade;
drop table if exists public.recurring_series             cascade;

-- 1f. Finance / forecast tables
drop table if exists public.account_balance_snapshots     cascade;
drop table if exists public.financial_accounts            cascade;
drop table if exists public.cashflow_forecast_snapshots   cascade;
drop table if exists public.cashflow_scenarios            cascade;
drop table if exists public.income_streams                cascade;
drop table if exists public.planned_cashflow_events       cascade;

-- 1g. GOAT functions
drop function if exists public.goat_setup_reserve_ai_slot(uuid);
drop function if exists public.goat_setup_release_ai_slot(uuid);
drop function if exists public.goat_setup_touch_updated_at();
drop function if exists public.goat_dashboard_prefs_touch_updated_at();
drop function if exists public.goat_statements_touch_updated_at();
drop function if exists public.goat_goals_touch_updated_at();
drop function if exists public.goat_finance_touch_updated_at();
drop function if exists public.recurring_touch_updated_at();

-- 1h. GOAT columns on profiles & documents
alter table public.profiles  drop constraint if exists profiles_goat_analysis_lens_check;
alter table public.profiles  drop column if exists goat_analysis_lens;
alter table public.profiles  drop column if exists goat;
alter table public.documents drop column if exists exclude_from_goat_smart_analytics;

comment on table public.app_api_keys is
  'Shared keys for Edge Functions: provider gemini (default OCR + analytics).';


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2 — Drop dead splits tables
-- ─────────────────────────────────────────────────────────────────────────────

drop policy if exists "Users can read own splits"                      on public.splits;
drop policy if exists "Users can insert own splits"                    on public.splits;
drop policy if exists "Users can update own splits"                    on public.splits;
drop policy if exists "Users can delete own splits"                    on public.splits;
drop policy if exists "Users can read participants of own splits"      on public.split_participants;
drop policy if exists "Users can insert participants for own splits"   on public.split_participants;

drop table if exists public.split_participants cascade;
drop table if exists public.splits             cascade;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3 — Canonical transactions table
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.transactions (
  id                   uuid          primary key default gen_random_uuid(),
  user_id              uuid          not null references public.profiles(id) on delete cascade,
  amount               numeric(12,2) not null,
  currency             text          not null default 'INR',
  date                 date          not null,
  type                 text          not null check (type in ('expense','income','transfer','lend','borrow','settlement_out','settlement_in','refund','recurring')),
  title                text          not null,
  description          text,
  category_id          uuid          references public.categories(id),
  category_source      text          check (category_source in ('manual','ai','rule','import','legacy')),
  payment_method       text,
  source_type          text          not null check (source_type in ('scan','manual','statement','group_split','settlement','recurring','linked_account','system')),
  source_document_id   uuid          references public.documents(id) on delete set null,
  source_import_id     uuid,
  effective_amount     numeric(12,2),
  group_id             uuid          references public.expense_groups(id) on delete set null,
  group_expense_id     uuid,
  lend_borrow_id       uuid,
  settlement_id        uuid,
  status               text          not null default 'confirmed' check (status in ('draft','confirmed','pending','voided','disputed')),
  is_recurring         boolean       not null default false,
  recurring_series_id  uuid,
  notes                text,
  tags                 text[],
  extracted_data       jsonb,
  created_at           timestamptz   not null default now(),
  updated_at           timestamptz   not null default now()
);

create index if not exists transactions_user_id_idx    on public.transactions(user_id);
create index if not exists transactions_date_idx       on public.transactions(user_id, date desc);
create index if not exists transactions_type_idx       on public.transactions(user_id, type);
create index if not exists transactions_source_doc_idx on public.transactions(source_document_id) where source_document_id is not null;
create index if not exists transactions_group_idx      on public.transactions(group_id)           where group_id is not null;
create index if not exists transactions_category_idx   on public.transactions(category_id)        where category_id is not null;
create index if not exists transactions_status_idx     on public.transactions(user_id, status);

alter table public.transactions enable row level security;

drop policy if exists "txn_select" on public.transactions;
drop policy if exists "txn_insert" on public.transactions;
drop policy if exists "txn_update" on public.transactions;
drop policy if exists "txn_delete" on public.transactions;

create policy "txn_select" on public.transactions for select using (auth.uid() = user_id);
create policy "txn_insert" on public.transactions for insert with check (auth.uid() = user_id);
create policy "txn_update" on public.transactions for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "txn_delete" on public.transactions for delete using (auth.uid() = user_id);

drop trigger if exists transactions_touch_updated_at on public.transactions;
create trigger transactions_touch_updated_at
  before update on public.transactions
  for each row execute function set_invoice_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 4 — Activity events (audit / activity feed)
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.activity_events (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references public.profiles(id) on delete cascade,
  event_type      text        not null check (event_type in (
    'transaction_created','transaction_updated','transaction_voided','transaction_disputed',
    'group_expense_created','group_expense_updated','group_expense_deleted',
    'settlement_created','settlement_confirmed','settlement_rejected',
    'lend_created','borrow_created','lend_settled','borrow_settled',
    'group_member_added','group_member_removed',
    'budget_created','budget_exceeded',
    'recurring_detected','recurring_due',
    'dispute_opened','dispute_resolved',
    'document_scanned','statement_imported'
  )),
  actor_user_id   uuid        not null references public.profiles(id),
  target_user_id  uuid        references public.profiles(id),
  group_id        uuid        references public.expense_groups(id),
  transaction_id  uuid        references public.transactions(id) on delete set null,
  entity_type     text,
  entity_id       uuid,
  summary         text        not null,
  details         jsonb,
  previous_state  jsonb,
  visibility      text        not null default 'private' check (visibility in ('private','group','public')),
  created_at      timestamptz not null default now()
);

create index if not exists activity_events_user_idx   on public.activity_events(user_id, created_at desc);
create index if not exists activity_events_group_idx  on public.activity_events(group_id, created_at desc) where group_id is not null;
create index if not exists activity_events_entity_idx on public.activity_events(entity_type, entity_id);

alter table public.activity_events enable row level security;

drop policy if exists "ae_select" on public.activity_events;
drop policy if exists "ae_insert" on public.activity_events;

create policy "ae_select" on public.activity_events for select
  using (auth.uid() = user_id or auth.uid() = actor_user_id or auth.uid() = target_user_id);
create policy "ae_insert" on public.activity_events for insert
  with check (auth.uid() = actor_user_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 5 — Disputes
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.disputes (
  id                  uuid          primary key default gen_random_uuid(),
  user_id             uuid          not null references public.profiles(id) on delete cascade,
  entity_type         text          not null check (entity_type in ('group_expense','settlement','lend_borrow')),
  entity_id           uuid          not null,
  group_id            uuid          references public.expense_groups(id),
  transaction_id      uuid          references public.transactions(id),
  reason              text          not null,
  proposed_amount     numeric(12,2),
  proposed_resolution text,
  status              text          not null default 'open' check (status in ('open','acknowledged','resolved','withdrawn')),
  resolved_by         uuid          references public.profiles(id),
  resolution_notes    text,
  created_at          timestamptz   not null default now(),
  updated_at          timestamptz   not null default now()
);

create index if not exists disputes_user_idx   on public.disputes(user_id);
create index if not exists disputes_group_idx  on public.disputes(group_id)               where group_id is not null;
create index if not exists disputes_entity_idx on public.disputes(entity_type, entity_id);

alter table public.disputes enable row level security;

drop policy if exists "disputes_select" on public.disputes;
drop policy if exists "disputes_insert" on public.disputes;
drop policy if exists "disputes_update" on public.disputes;

create policy "disputes_select" on public.disputes for select
  using (auth.uid() = user_id or (group_id is not null and public.user_is_expense_group_member(group_id)));
create policy "disputes_insert" on public.disputes for insert
  with check (auth.uid() = user_id);
create policy "disputes_update" on public.disputes for update
  using (auth.uid() = user_id or auth.uid() = resolved_by);

drop trigger if exists disputes_touch_updated_at on public.disputes;
create trigger disputes_touch_updated_at
  before update on public.disputes
  for each row execute function set_invoice_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 6 — Budgets + budget periods
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.budgets (
  id               uuid          primary key default gen_random_uuid(),
  user_id          uuid          not null references public.profiles(id) on delete cascade,
  name             text          not null,
  category_id      uuid          references public.categories(id),
  amount           numeric(12,2) not null check (amount > 0),
  period           text          not null default 'monthly' check (period in ('weekly','monthly','yearly')),
  currency         text          not null default 'INR',
  rollover_enabled boolean       not null default false,
  is_active        boolean       not null default true,
  start_date       date          not null default current_date,
  end_date         date,
  created_at       timestamptz   not null default now(),
  updated_at       timestamptz   not null default now()
);

create unique index if not exists budgets_user_category_active
  on public.budgets(user_id, category_id)
  where (is_active = true and category_id is not null);

create index if not exists budgets_user_idx on public.budgets(user_id);

alter table public.budgets enable row level security;

drop policy if exists "budgets_select" on public.budgets;
drop policy if exists "budgets_insert" on public.budgets;
drop policy if exists "budgets_update" on public.budgets;
drop policy if exists "budgets_delete" on public.budgets;

create policy "budgets_select" on public.budgets for select using (auth.uid() = user_id);
create policy "budgets_insert" on public.budgets for insert with check (auth.uid() = user_id);
create policy "budgets_update" on public.budgets for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "budgets_delete" on public.budgets for delete using (auth.uid() = user_id);

drop trigger if exists budgets_touch_updated_at on public.budgets;
create trigger budgets_touch_updated_at
  before update on public.budgets
  for each row execute function set_invoice_updated_at();

create table if not exists public.budget_periods (
  id              uuid          primary key default gen_random_uuid(),
  budget_id       uuid          not null references public.budgets(id) on delete cascade,
  user_id         uuid          not null references public.profiles(id) on delete cascade,
  period_start    date          not null,
  period_end      date          not null,
  spent           numeric(12,2) not null default 0,
  rollover_amount numeric(12,2) not null default 0,
  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now()
);

create unique index if not exists budget_periods_unique   on public.budget_periods(budget_id, period_start);
create index if not exists budget_periods_user_idx        on public.budget_periods(user_id, period_start desc);

alter table public.budget_periods enable row level security;

drop policy if exists "bp_select" on public.budget_periods;
drop policy if exists "bp_insert" on public.budget_periods;
drop policy if exists "bp_update" on public.budget_periods;
drop policy if exists "bp_delete" on public.budget_periods;

create policy "bp_select" on public.budget_periods for select using (auth.uid() = user_id);
create policy "bp_insert" on public.budget_periods for insert with check (auth.uid() = user_id);
create policy "bp_update" on public.budget_periods for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "bp_delete" on public.budget_periods for delete using (auth.uid() = user_id);

drop trigger if exists budget_periods_touch_updated_at on public.budget_periods;
create trigger budget_periods_touch_updated_at
  before update on public.budget_periods
  for each row execute function set_invoice_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 7 — Recurring series + occurrences (fresh — old GOAT version dropped above)
-- ─────────────────────────────────────────────────────────────────────────────

create table public.recurring_series (
  id                uuid          primary key default gen_random_uuid(),
  user_id           uuid          not null references public.profiles(id) on delete cascade,
  title             text          not null,
  amount            numeric(12,2) not null check (amount > 0),
  currency          text          not null default 'INR',
  category_id       uuid          references public.categories(id),
  cadence           text          not null check (cadence in ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  anchor_date       date          not null,
  next_due          date,
  detection_source  text          not null default 'manual' check (detection_source in ('manual','pattern','statement')),
  vendor_pattern    text,
  is_active         boolean       not null default true,
  auto_confirm      boolean       not null default false,
  remind_days_before integer      not null default 1,
  created_at        timestamptz   not null default now(),
  updated_at        timestamptz   not null default now()
);

create index recurring_series_user_idx     on public.recurring_series(user_id);
create index recurring_series_next_due_idx on public.recurring_series(user_id, next_due)
  where (recurring_series.is_active = true);

alter table public.recurring_series enable row level security;

create policy "rs_select" on public.recurring_series for select using (auth.uid() = user_id);
create policy "rs_insert" on public.recurring_series for insert with check (auth.uid() = user_id);
create policy "rs_update" on public.recurring_series for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "rs_delete" on public.recurring_series for delete using (auth.uid() = user_id);

create trigger recurring_series_touch_updated_at
  before update on public.recurring_series
  for each row execute function set_invoice_updated_at();

create table public.recurring_occurrences (
  id              uuid          primary key default gen_random_uuid(),
  series_id       uuid          not null references public.recurring_series(id) on delete cascade,
  user_id         uuid          not null references public.profiles(id) on delete cascade,
  due_date        date          not null,
  actual_amount   numeric(12,2),
  transaction_id  uuid          references public.transactions(id) on delete set null,
  status          text          not null default 'upcoming' check (status in ('upcoming','confirmed','missed','skipped')),
  created_at      timestamptz   not null default now()
);

create unique index recurring_occ_unique   on public.recurring_occurrences(series_id, due_date);
create index recurring_occ_user_idx        on public.recurring_occurrences(user_id, due_date);

alter table public.recurring_occurrences enable row level security;

create policy "ro_select" on public.recurring_occurrences for select using (auth.uid() = user_id);
create policy "ro_insert" on public.recurring_occurrences for insert with check (auth.uid() = user_id);
create policy "ro_update" on public.recurring_occurrences for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "ro_delete" on public.recurring_occurrences for delete using (auth.uid() = user_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 8 — Statement imports (fresh — old GOAT version dropped above)
-- ─────────────────────────────────────────────────────────────────────────────

create table public.statement_imports (
  id                     uuid        primary key default gen_random_uuid(),
  user_id                uuid        not null references public.profiles(id) on delete cascade,
  file_path              text        not null,
  file_name              text        not null,
  mime_type              text,
  source_type            text        not null default 'upload' check (source_type in ('upload','email','api')),
  account_name           text,
  account_type           text,
  institution_name       text,
  statement_period_start date,
  statement_period_end   date,
  status                 text        not null default 'uploaded' check (status in ('uploaded','processing','review','completed','failed')),
  row_count              integer,
  imported_count         integer     default 0,
  skipped_count          integer     default 0,
  error_message          text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index statement_imports_user_idx on public.statement_imports(user_id, created_at desc);

alter table public.statement_imports enable row level security;

create policy "si_select" on public.statement_imports for select using (auth.uid() = user_id);
create policy "si_insert" on public.statement_imports for insert with check (auth.uid() = user_id);
create policy "si_update" on public.statement_imports for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "si_delete" on public.statement_imports for delete using (auth.uid() = user_id);

create trigger statement_imports_touch_updated_at
  before update on public.statement_imports
  for each row execute function set_invoice_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 9 — Accounts (for future net-worth / balance tracking)
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.accounts (
  id              uuid          primary key default gen_random_uuid(),
  user_id         uuid          not null references public.profiles(id) on delete cascade,
  name            text          not null,
  type            text          not null check (type in ('checking','savings','credit_card','cash','investment','loan','other')),
  institution     text,
  currency        text          not null default 'INR',
  current_balance numeric(14,2) not null default 0,
  is_asset        boolean       not null default true,
  is_active       boolean       not null default true,
  is_linked       boolean       not null default false,
  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now()
);

create index if not exists accounts_user_idx on public.accounts(user_id);

alter table public.accounts enable row level security;

drop policy if exists "accounts_select" on public.accounts;
drop policy if exists "accounts_insert" on public.accounts;
drop policy if exists "accounts_update" on public.accounts;
drop policy if exists "accounts_delete" on public.accounts;

create policy "accounts_select" on public.accounts for select using (auth.uid() = user_id);
create policy "accounts_insert" on public.accounts for insert with check (auth.uid() = user_id);
create policy "accounts_update" on public.accounts for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "accounts_delete" on public.accounts for delete using (auth.uid() = user_id);

drop trigger if exists accounts_touch_updated_at on public.accounts;
create trigger accounts_touch_updated_at
  before update on public.accounts
  for each row execute function set_invoice_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 10 — Enhance existing tables with transaction links
-- ─────────────────────────────────────────────────────────────────────────────

-- group_settlements: add confirmation workflow + transaction link
alter table public.group_settlements
  add column if not exists status         text        not null default 'pending'
    check (status in ('pending','confirmed','rejected')),
  add column if not exists confirmed_at   timestamptz,
  add column if not exists transaction_id uuid        references public.transactions(id);

-- lend_borrow_entries: add transaction link
alter table public.lend_borrow_entries
  add column if not exists transaction_id uuid references public.transactions(id);

-- group_expenses: add transaction link
alter table public.group_expenses
  add column if not exists transaction_id uuid references public.transactions(id);

create index if not exists group_settlements_txn_idx on public.group_settlements(transaction_id)  where transaction_id is not null;
create index if not exists lend_borrow_txn_idx       on public.lend_borrow_entries(transaction_id) where transaction_id is not null;
create index if not exists group_expenses_txn_idx    on public.group_expenses(transaction_id)      where transaction_id is not null;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 11 — Backfill canonical transactions from existing data
-- ─────────────────────────────────────────────────────────────────────────────

-- Phase A: documents → transactions (skip rows that already have a transaction)
insert into public.transactions (
  user_id, amount, currency, date, type, title, description,
  category_id, category_source, source_type, source_document_id,
  effective_amount, status, extracted_data, created_at, updated_at
)
select
  d.user_id,
  d.amount,
  coalesce(d.currency, 'INR'),
  d.date,
  'expense',
  coalesce(d.vendor_name, 'Expense'),
  d.description,
  d.category_id,
  d.category_source,
  case when d.extracted_data->>'invoice_id' is not null then 'scan' else 'manual' end,
  d.id,
  d.amount,
  case d.status when 'draft' then 'draft' else 'confirmed' end,
  d.extracted_data,
  d.created_at,
  d.updated_at
from public.documents d
where not exists (
  select 1 from public.transactions t where t.source_document_id = d.id
);

-- Phase B: link group_expenses → transactions via shared document_id
update public.group_expenses ge
set transaction_id = t.id
from public.transactions t
where t.source_document_id = ge.document_id
  and ge.document_id is not null
  and ge.transaction_id is null;

-- Phase C: link lend_borrow_entries → transactions via shared document_id
update public.lend_borrow_entries lb
set transaction_id = t.id
from public.transactions t
where t.source_document_id = lb.document_id
  and lb.document_id is not null
  and lb.transaction_id is null;

-- Phase D: create transactions for group_expenses with no document link
insert into public.transactions (
  user_id, amount, currency, date, type, title,
  source_type, group_id, group_expense_id, effective_amount,
  status, created_at
)
select
  ge.paid_by_user_id,
  ge.amount,
  'INR',
  ge.expense_date,
  'expense',
  ge.title,
  'group_split',
  ge.group_id,
  ge.id,
  coalesce(
    (select gep.share_amount from public.group_expense_participants gep
     where gep.expense_id = ge.id and gep.user_id = ge.paid_by_user_id),
    ge.amount
  ),
  'confirmed',
  ge.created_at
from public.group_expenses ge
where ge.transaction_id is null
  and ge.document_id is null;

-- Link back
update public.group_expenses ge
set transaction_id = t.id
from public.transactions t
where t.group_expense_id = ge.id
  and ge.transaction_id is null;

-- Phase E: create transactions for lend_borrow_entries with no document link
insert into public.transactions (
  user_id, amount, currency, date, type, title,
  source_type, lend_borrow_id, effective_amount, status, created_at
)
select
  lb.user_id,
  lb.amount,
  'INR',
  lb.created_at::date,
  case lb.type when 'lent' then 'lend' else 'borrow' end,
  coalesce(lb.counterparty_name, 'IOU'),
  'manual',
  lb.id,
  0,
  'confirmed',
  lb.created_at
from public.lend_borrow_entries lb
where lb.transaction_id is null
  and lb.document_id is null;

-- Link back
update public.lend_borrow_entries lb
set transaction_id = t.id
from public.transactions t
where t.lend_borrow_id = lb.id
  and lb.transaction_id is null;


-- ═══════════════════════════════════════════════════════════════════════════════
-- DONE. The database now has:
--   • transactions          — canonical financial ledger
--   • activity_events       — audit trail / activity feed
--   • disputes              — collaboration dispute resolution
--   • budgets + periods     — planning layer
--   • recurring_series + occ — subscription / bill tracking
--   • statement_imports     — simplified import tracking
--   • accounts              — future net-worth / balance tracking
--   • group_settlements     — now with confirmation workflow
--   • lend_borrow_entries   — now linked to transactions
--   • group_expenses        — now linked to transactions
--   • All GOAT-era tables removed
--   • splits tables removed
--   • Existing data backfilled into transactions
-- ═══════════════════════════════════════════════════════════════════════════════
