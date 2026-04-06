-- GOAT Feature 2: manual accounts, income streams, planned cash events, forecast snapshots (deterministic engine in app).

-- ─── financial_accounts ─────────────────────────────────────────────
create table if not exists public.financial_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  account_type text not null check (account_type in ('cash','bank','wallet','credit_card','loan','other')),
  source text not null default 'manual' check (source in ('manual','aggregated','imported')),
  is_primary boolean not null default false,
  include_in_safe_to_spend boolean not null default true,
  current_balance numeric(14,2) not null default 0,
  available_credit numeric(14,2),
  currency text not null default 'INR',
  institution_name text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists financial_accounts_user_idx on public.financial_accounts (user_id);

-- ─── account_balance_snapshots ───────────────────────────────────────
create table if not exists public.account_balance_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  account_id uuid not null references public.financial_accounts(id) on delete cascade,
  balance numeric(14,2) not null,
  snapshot_at timestamptz not null default now(),
  source text not null default 'manual' check (source in ('manual','system','aggregated','imported'))
);

create index if not exists account_balance_snapshots_user_account_idx
  on public.account_balance_snapshots (user_id, account_id, snapshot_at desc);

-- ─── income_streams ─────────────────────────────────────────────────
create table if not exists public.income_streams (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  source text not null default 'manual' check (source in ('manual','detected','hybrid')),
  status text not null default 'active' check (status in ('active','paused','cancelled','suggested')),
  frequency text not null check (frequency in ('weekly','biweekly','monthly','irregular','custom')),
  expected_amount numeric(12,2) not null,
  next_expected_date date,
  confidence numeric(5,2),
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists income_streams_user_status_next_idx
  on public.income_streams (user_id, status, next_expected_date);

-- ─── planned_cashflow_events (one-off future inflows/outflows) ─────
create table if not exists public.planned_cashflow_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  event_date date not null,
  amount numeric(14,2) not null,
  direction text not null check (direction in ('inflow','outflow')),
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists planned_cashflow_events_user_date_idx
  on public.planned_cashflow_events (user_id, event_date);

-- ─── cashflow_forecast_snapshots (optional persist) ─────────────────
create table if not exists public.cashflow_forecast_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  horizon_days int not null,
  start_date date not null,
  end_date date not null,
  base_balance numeric(14,2) not null,
  projected_min_balance numeric(14,2) not null,
  projected_end_balance numeric(14,2) not null,
  safe_to_spend_now numeric(14,2) not null,
  risk_level text not null check (risk_level in ('low','medium','high')),
  forecast_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists cashflow_forecast_snapshots_user_created_idx
  on public.cashflow_forecast_snapshots (user_id, created_at desc);

-- ─── cashflow_scenarios (what-if) ───────────────────────────────────
create table if not exists public.cashflow_scenarios (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text,
  scenario_type text not null default 'what_if' check (scenario_type in ('what_if','stress','custom')),
  inputs jsonb not null default '{}'::jsonb,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists cashflow_scenarios_user_idx on public.cashflow_scenarios (user_id, created_at desc);

-- ─── Touch updated_at ───────────────────────────────────────────────
create or replace function public.goat_finance_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists financial_accounts_touch on public.financial_accounts;
create trigger financial_accounts_touch
  before update on public.financial_accounts
  for each row execute procedure public.goat_finance_touch_updated_at();

drop trigger if exists income_streams_touch on public.income_streams;
create trigger income_streams_touch
  before update on public.income_streams
  for each row execute procedure public.goat_finance_touch_updated_at();

drop trigger if exists planned_cashflow_events_touch on public.planned_cashflow_events;
create trigger planned_cashflow_events_touch
  before update on public.planned_cashflow_events
  for each row execute procedure public.goat_finance_touch_updated_at();

-- ─── RLS ────────────────────────────────────────────────────────────
alter table public.financial_accounts enable row level security;
alter table public.account_balance_snapshots enable row level security;
alter table public.income_streams enable row level security;
alter table public.planned_cashflow_events enable row level security;
alter table public.cashflow_forecast_snapshots enable row level security;
alter table public.cashflow_scenarios enable row level security;

drop policy if exists financial_accounts_select on public.financial_accounts;
drop policy if exists financial_accounts_insert on public.financial_accounts;
drop policy if exists financial_accounts_update on public.financial_accounts;
drop policy if exists financial_accounts_delete on public.financial_accounts;
create policy financial_accounts_select on public.financial_accounts for select to authenticated
  using (auth.uid() = user_id);
create policy financial_accounts_insert on public.financial_accounts for insert to authenticated
  with check (auth.uid() = user_id);
create policy financial_accounts_update on public.financial_accounts for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy financial_accounts_delete on public.financial_accounts for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists account_balance_snapshots_select on public.account_balance_snapshots;
drop policy if exists account_balance_snapshots_insert on public.account_balance_snapshots;
create policy account_balance_snapshots_select on public.account_balance_snapshots for select to authenticated
  using (auth.uid() = user_id);
create policy account_balance_snapshots_insert on public.account_balance_snapshots for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists income_streams_select on public.income_streams;
drop policy if exists income_streams_insert on public.income_streams;
drop policy if exists income_streams_update on public.income_streams;
drop policy if exists income_streams_delete on public.income_streams;
create policy income_streams_select on public.income_streams for select to authenticated
  using (auth.uid() = user_id);
create policy income_streams_insert on public.income_streams for insert to authenticated
  with check (auth.uid() = user_id);
create policy income_streams_update on public.income_streams for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy income_streams_delete on public.income_streams for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists planned_cashflow_events_select on public.planned_cashflow_events;
drop policy if exists planned_cashflow_events_insert on public.planned_cashflow_events;
drop policy if exists planned_cashflow_events_update on public.planned_cashflow_events;
drop policy if exists planned_cashflow_events_delete on public.planned_cashflow_events;
create policy planned_cashflow_events_select on public.planned_cashflow_events for select to authenticated
  using (auth.uid() = user_id);
create policy planned_cashflow_events_insert on public.planned_cashflow_events for insert to authenticated
  with check (auth.uid() = user_id);
create policy planned_cashflow_events_update on public.planned_cashflow_events for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy planned_cashflow_events_delete on public.planned_cashflow_events for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists cashflow_forecast_snapshots_select on public.cashflow_forecast_snapshots;
drop policy if exists cashflow_forecast_snapshots_insert on public.cashflow_forecast_snapshots;
create policy cashflow_forecast_snapshots_select on public.cashflow_forecast_snapshots for select to authenticated
  using (auth.uid() = user_id);
create policy cashflow_forecast_snapshots_insert on public.cashflow_forecast_snapshots for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists cashflow_scenarios_select on public.cashflow_scenarios;
drop policy if exists cashflow_scenarios_insert on public.cashflow_scenarios;
drop policy if exists cashflow_scenarios_delete on public.cashflow_scenarios;
create policy cashflow_scenarios_select on public.cashflow_scenarios for select to authenticated
  using (auth.uid() = user_id);
create policy cashflow_scenarios_insert on public.cashflow_scenarios for insert to authenticated
  with check (auth.uid() = user_id);
create policy cashflow_scenarios_delete on public.cashflow_scenarios for delete to authenticated
  using (auth.uid() = user_id);

comment on table public.financial_accounts is 'GOAT manual/aggregated balances for cash-flow forecast.';
comment on table public.income_streams is 'Expected recurring inflows for deterministic forecast.';
