-- GOAT Recurring center + optional GOAT Gemini provider row (insert key via Dashboard; provider = 'goat_gemini').
-- Deterministic billing state lives in these tables; AI is advisory only (separate Edge + key).

-- ─── recurring_series ─────────────────────────────────────────────────
create table if not exists public.recurring_series (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('bill','subscription','income','transfer')),
  source text not null check (source in ('manual','detected','hybrid')),
  status text not null default 'active' check (status in ('active','paused','cancelled','suggested')),
  title text not null,
  normalized_merchant text,
  merchant_display_name text,
  category_id uuid references public.categories(id) on delete set null,
  frequency text not null check (frequency in ('weekly','biweekly','monthly','quarterly','yearly','custom')),
  interval_count int not null default 1,
  day_of_month int,
  day_of_week int,
  month_of_year int,
  next_due_date date,
  last_observed_date date,
  expected_amount numeric(12,2),
  amount_tolerance_pct numeric(5,2) not null default 20,
  currency text not null default 'INR',
  autopay_enabled boolean not null default false,
  autopay_method text check (autopay_method is null or autopay_method in ('upi_autopay','card_autopay','bank_auto_debit','manual','cash','other')),
  reminder_days_before int not null default 3,
  provider_reference text,
  confidence numeric(5,2),
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists recurring_series_user_status_next_idx
  on public.recurring_series (user_id, status, next_due_date);

-- ─── recurring_occurrences ───────────────────────────────────────────
create table if not exists public.recurring_occurrences (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.recurring_series(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  due_date date not null,
  expected_amount numeric(12,2),
  actual_amount numeric(12,2),
  matched_document_id uuid references public.documents(id) on delete set null,
  status text not null default 'upcoming' check (status in ('upcoming','paid','missed','skipped','overdue','cancelled')),
  paid_at timestamptz,
  detection_source text not null default 'system' check (detection_source in ('system','manual','ai_assisted')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists recurring_occurrences_user_due_status_idx
  on public.recurring_occurrences (user_id, due_date, status);
create index if not exists recurring_occurrences_series_due_idx
  on public.recurring_occurrences (series_id, due_date);

-- ─── recurring_notification_rules ─────────────────────────────────────
create table if not exists public.recurring_notification_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  series_id uuid not null references public.recurring_series(id) on delete cascade,
  channel text not null default 'in_app' check (channel in ('in_app','push','email')),
  days_before int not null default 3,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ─── recurring_change_events ─────────────────────────────────────────
create table if not exists public.recurring_change_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  series_id uuid not null references public.recurring_series(id) on delete cascade,
  change_type text not null check (change_type in (
    'price_change','schedule_shift','reactivate','skip','duplicate_charge','amount_smoothing','other'
  )),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists recurring_change_events_series_idx
  on public.recurring_change_events (series_id, created_at desc);

-- ─── updated_at touch ───────────────────────────────────────────────
create or replace function public.recurring_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists recurring_series_touch on public.recurring_series;
create trigger recurring_series_touch
  before update on public.recurring_series
  for each row execute procedure public.recurring_touch_updated_at();

drop trigger if exists recurring_occurrences_touch on public.recurring_occurrences;
create trigger recurring_occurrences_touch
  before update on public.recurring_occurrences
  for each row execute procedure public.recurring_touch_updated_at();

drop trigger if exists recurring_notification_rules_touch on public.recurring_notification_rules;
create trigger recurring_notification_rules_touch
  before update on public.recurring_notification_rules
  for each row execute procedure public.recurring_touch_updated_at();

-- ─── RLS ─────────────────────────────────────────────────────────────
alter table public.recurring_series enable row level security;
alter table public.recurring_occurrences enable row level security;
alter table public.recurring_notification_rules enable row level security;
alter table public.recurring_change_events enable row level security;

drop policy if exists recurring_series_select on public.recurring_series;
drop policy if exists recurring_series_insert on public.recurring_series;
drop policy if exists recurring_series_update on public.recurring_series;
drop policy if exists recurring_series_delete on public.recurring_series;
drop policy if exists recurring_occurrences_select on public.recurring_occurrences;
drop policy if exists recurring_occurrences_insert on public.recurring_occurrences;
drop policy if exists recurring_occurrences_update on public.recurring_occurrences;
drop policy if exists recurring_occurrences_delete on public.recurring_occurrences;
drop policy if exists recurring_notification_rules_select on public.recurring_notification_rules;
drop policy if exists recurring_notification_rules_insert on public.recurring_notification_rules;
drop policy if exists recurring_notification_rules_update on public.recurring_notification_rules;
drop policy if exists recurring_notification_rules_delete on public.recurring_notification_rules;
drop policy if exists recurring_change_events_select on public.recurring_change_events;
drop policy if exists recurring_change_events_insert on public.recurring_change_events;

create policy recurring_series_select on public.recurring_series for select to authenticated
  using (auth.uid() = user_id);
create policy recurring_series_insert on public.recurring_series for insert to authenticated
  with check (auth.uid() = user_id);
create policy recurring_series_update on public.recurring_series for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy recurring_series_delete on public.recurring_series for delete to authenticated
  using (auth.uid() = user_id);

create policy recurring_occurrences_select on public.recurring_occurrences for select to authenticated
  using (auth.uid() = user_id);
create policy recurring_occurrences_insert on public.recurring_occurrences for insert to authenticated
  with check (auth.uid() = user_id);
create policy recurring_occurrences_update on public.recurring_occurrences for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy recurring_occurrences_delete on public.recurring_occurrences for delete to authenticated
  using (auth.uid() = user_id);

create policy recurring_notification_rules_select on public.recurring_notification_rules for select to authenticated
  using (auth.uid() = user_id);
create policy recurring_notification_rules_insert on public.recurring_notification_rules for insert to authenticated
  with check (auth.uid() = user_id);
create policy recurring_notification_rules_update on public.recurring_notification_rules for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy recurring_notification_rules_delete on public.recurring_notification_rules for delete to authenticated
  using (auth.uid() = user_id);

create policy recurring_change_events_select on public.recurring_change_events for select to authenticated
  using (auth.uid() = user_id);
create policy recurring_change_events_insert on public.recurring_change_events for insert to authenticated
  with check (auth.uid() = user_id);

comment on table public.recurring_series is 'GOAT recurring bills/subscriptions; deterministic cadence and amounts.';
comment on table public.recurring_occurrences is 'Per-due instances; match documents without LLM deciding paid state.';
