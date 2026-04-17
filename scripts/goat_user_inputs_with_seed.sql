-- ============================================================================
-- Goat Mode user-input tables + seed data
--
-- WHAT THIS DOES
--   1. (Re)creates the 3 user-facing Goat tables (goat_user_inputs,
--      goat_goals, goat_obligations) with the exact schema that was dropped
--      by scripts/cleanup_goat_mode_v1.sql. Forward-compatible with
--      20260423120000_goat_mode_v1.sql if Goat Mode is re-enabled later.
--   2. Seeds one user with realistic INR values: salary inputs, 4 goals,
--      3 obligations (rent / EMI / insurance).
--
-- HOW TO USE
--   Replace EVERY occurrence of <USER_UUID> below with the real auth user id,
--   then paste into Supabase SQL Editor and run. The script is idempotent:
--     - tables use CREATE TABLE IF NOT EXISTS
--     - seed uses ON CONFLICT DO NOTHING / UPSERT so re-running is safe.
--
-- REQUIREMENTS
--   - public.profiles row for that user must already exist (auth signup).
--   - public.accounts and public.recurring_series can be NULL in seed rows;
--     no hard dependency is enforced.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Shared updated_at helper (reuse the Billy convention helper if present)
-- ---------------------------------------------------------------------------
create or replace function public.set_invoice_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. goat_user_inputs  (one row per user; declared planning inputs)
-- ---------------------------------------------------------------------------
create table if not exists public.goat_user_inputs (
  user_id                         uuid          primary key
    references public.profiles(id) on delete cascade,
  monthly_income                  numeric(12,2) null check (monthly_income is null or monthly_income >= 0),
  income_currency                 text          not null default 'INR',
  pay_frequency                   text          null
    check (pay_frequency is null or pay_frequency in ('weekly','biweekly','semimonthly','monthly','other')),
  salary_day                      integer       null check (salary_day is null or salary_day between 1 and 31),
  emergency_fund_target_months    numeric(5,2)  null check (emergency_fund_target_months is null or emergency_fund_target_months >= 0),
  liquidity_floor                 numeric(12,2) null check (liquidity_floor is null or liquidity_floor >= 0),
  household_size                  integer       null check (household_size is null or household_size >= 0),
  dependents                      integer       null check (dependents is null or dependents >= 0),
  risk_tolerance                  text          null
    check (risk_tolerance is null or risk_tolerance in ('conservative','balanced','aggressive')),
  planning_horizon_months         integer       null check (planning_horizon_months is null or planning_horizon_months between 1 and 60),
  tone_preference                 text          null
    check (tone_preference is null or tone_preference in ('calm','direct','coaching')),
  notes                           jsonb         not null default '{}'::jsonb,
  created_at                      timestamptz   not null default now(),
  updated_at                      timestamptz   not null default now()
);

comment on table public.goat_user_inputs is
  'One row per user. Declared planning/setup inputs used by Goat Mode (income, targets, horizon, tone).';

drop trigger if exists goat_user_inputs_touch_updated_at on public.goat_user_inputs;
create trigger goat_user_inputs_touch_updated_at
  before update on public.goat_user_inputs
  for each row execute function public.set_invoice_updated_at();

alter table public.goat_user_inputs enable row level security;

drop policy if exists goat_user_inputs_select on public.goat_user_inputs;
drop policy if exists goat_user_inputs_insert on public.goat_user_inputs;
drop policy if exists goat_user_inputs_update on public.goat_user_inputs;
drop policy if exists goat_user_inputs_delete on public.goat_user_inputs;

create policy goat_user_inputs_select on public.goat_user_inputs
  for select using (auth.uid() = user_id);
create policy goat_user_inputs_insert on public.goat_user_inputs
  for insert with check (auth.uid() = user_id);
create policy goat_user_inputs_update on public.goat_user_inputs
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy goat_user_inputs_delete on public.goat_user_inputs
  for delete using (auth.uid() = user_id);


-- ---------------------------------------------------------------------------
-- 2. goat_goals  (user-declared goals)
-- ---------------------------------------------------------------------------
create table if not exists public.goat_goals (
  id                uuid          primary key default gen_random_uuid(),
  user_id           uuid          not null references public.profiles(id) on delete cascade,
  goal_type         text          not null
    check (goal_type in ('emergency_fund','savings','purchase','travel','debt_payoff','investment','other')),
  title             text          not null,
  target_amount     numeric(12,2) not null check (target_amount > 0),
  current_amount    numeric(12,2) not null default 0 check (current_amount >= 0),
  target_date       date          null,
  priority          integer       not null default 3 check (priority between 1 and 5),
  status            text          not null default 'active'
    check (status in ('active','paused','completed','abandoned')),
  linked_account_id uuid          null references public.accounts(id) on delete set null,
  metadata          jsonb         not null default '{}'::jsonb,
  created_at        timestamptz   not null default now(),
  updated_at        timestamptz   not null default now()
);

comment on table public.goat_goals is
  'User-declared goals for Goat Mode.';

create index if not exists goat_goals_user_active_idx
  on public.goat_goals(user_id, priority)
  where status = 'active';

create index if not exists goat_goals_user_status_idx
  on public.goat_goals(user_id, status);

drop trigger if exists goat_goals_touch_updated_at on public.goat_goals;
create trigger goat_goals_touch_updated_at
  before update on public.goat_goals
  for each row execute function public.set_invoice_updated_at();

alter table public.goat_goals enable row level security;

drop policy if exists goat_goals_select on public.goat_goals;
drop policy if exists goat_goals_insert on public.goat_goals;
drop policy if exists goat_goals_update on public.goat_goals;
drop policy if exists goat_goals_delete on public.goat_goals;

create policy goat_goals_select on public.goat_goals
  for select using (auth.uid() = user_id);
create policy goat_goals_insert on public.goat_goals
  for insert with check (auth.uid() = user_id);
create policy goat_goals_update on public.goat_goals
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy goat_goals_delete on public.goat_goals
  for delete using (auth.uid() = user_id);


-- ---------------------------------------------------------------------------
-- 3. goat_obligations  (declared recurring debts/liabilities)
-- ---------------------------------------------------------------------------
create table if not exists public.goat_obligations (
  id                         uuid          primary key default gen_random_uuid(),
  user_id                    uuid          not null references public.profiles(id) on delete cascade,
  obligation_type            text          not null
    check (obligation_type in ('emi','credit_card_min','rent','insurance','loan','student_loan','other')),
  lender_name                text          null,
  current_outstanding        numeric(14,2) null check (current_outstanding is null or current_outstanding >= 0),
  monthly_due                numeric(12,2) null check (monthly_due is null or monthly_due >= 0),
  due_day                    integer       null check (due_day is null or due_day between 1 and 31),
  interest_rate              numeric(6,3)  null check (interest_rate is null or interest_rate >= 0),
  cadence                    text          not null default 'monthly'
    check (cadence in ('weekly','biweekly','monthly','quarterly','yearly')),
  linked_recurring_series_id uuid          null references public.recurring_series(id) on delete set null,
  status                     text          not null default 'active'
    check (status in ('active','paid_off','defaulted','cancelled')),
  metadata                   jsonb         not null default '{}'::jsonb,
  created_at                 timestamptz   not null default now(),
  updated_at                 timestamptz   not null default now()
);

comment on table public.goat_obligations is
  'Declared recurring obligations not fully captured by recurring_series (EMIs, CC mins, rent, insurance).';

create index if not exists goat_obligations_user_active_idx
  on public.goat_obligations(user_id)
  where status = 'active';

drop trigger if exists goat_obligations_touch_updated_at on public.goat_obligations;
create trigger goat_obligations_touch_updated_at
  before update on public.goat_obligations
  for each row execute function public.set_invoice_updated_at();

alter table public.goat_obligations enable row level security;

drop policy if exists goat_obligations_select on public.goat_obligations;
drop policy if exists goat_obligations_insert on public.goat_obligations;
drop policy if exists goat_obligations_update on public.goat_obligations;
drop policy if exists goat_obligations_delete on public.goat_obligations;

create policy goat_obligations_select on public.goat_obligations
  for select using (auth.uid() = user_id);
create policy goat_obligations_insert on public.goat_obligations
  for insert with check (auth.uid() = user_id);
create policy goat_obligations_update on public.goat_obligations
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy goat_obligations_delete on public.goat_obligations
  for delete using (auth.uid() = user_id);

commit;


-- ============================================================================
-- SEED DATA
-- Replace <USER_UUID> with the real user id (4 occurrences) before running.
-- Re-running is safe (upsert / on-conflict).
-- ============================================================================

begin;

-- 1) goat_user_inputs — 1 row per user, upsert on PK
insert into public.goat_user_inputs (
  user_id, monthly_income, income_currency, pay_frequency, salary_day,
  emergency_fund_target_months, liquidity_floor,
  household_size, dependents,
  risk_tolerance, planning_horizon_months, tone_preference,
  notes
) values (
  '<USER_UUID>'::uuid,
  75000.00, 'INR', 'monthly', 1,
  6.0,       25000.00,
  3,         1,
  'balanced', 24, 'direct',
  jsonb_build_object(
    'city', 'Bengaluru',
    'employment', 'salaried',
    'seeded_at', now()
  )
)
on conflict (user_id) do update set
  monthly_income               = excluded.monthly_income,
  income_currency              = excluded.income_currency,
  pay_frequency                = excluded.pay_frequency,
  salary_day                   = excluded.salary_day,
  emergency_fund_target_months = excluded.emergency_fund_target_months,
  liquidity_floor              = excluded.liquidity_floor,
  household_size               = excluded.household_size,
  dependents                   = excluded.dependents,
  risk_tolerance               = excluded.risk_tolerance,
  planning_horizon_months      = excluded.planning_horizon_months,
  tone_preference              = excluded.tone_preference,
  notes                        = excluded.notes,
  updated_at                   = now();


-- 2) goat_goals — 4 realistic goals. Deterministic IDs so re-runs dedupe.
--    (uuid v5-style: derive a stable id from user_id + goal key).
insert into public.goat_goals (
  id, user_id, goal_type, title,
  target_amount, current_amount, target_date,
  priority, status, metadata
)
select
  md5('<USER_UUID>' || ':' || g.key)::uuid,
  '<USER_UUID>'::uuid,
  g.goal_type, g.title,
  g.target_amount, g.current_amount, g.target_date,
  g.priority, 'active',
  jsonb_build_object('seeded', true, 'key', g.key)
from (values
  ('emergency_fund_6m', 'emergency_fund', 'Emergency fund - 6 months expenses',
     450000.00,  95000.00,  (current_date + interval '12 months')::date, 1),
  ('goa_trip',          'travel',         'Goa trip 2026',
      85000.00,  22000.00,  (current_date + interval '6 months')::date,  3),
  ('cc_payoff',         'debt_payoff',    'Pay off HDFC credit card',
      48000.00,  12000.00,  (current_date + interval '4 months')::date,  2),
  ('laptop_upgrade',    'purchase',       'MacBook Air M4 upgrade',
     130000.00,  40000.00,  (current_date + interval '10 months')::date, 4)
) as g(key, goal_type, title, target_amount, current_amount, target_date, priority)
on conflict (id) do update set
  target_amount  = excluded.target_amount,
  current_amount = excluded.current_amount,
  target_date    = excluded.target_date,
  priority       = excluded.priority,
  title          = excluded.title,
  updated_at     = now();


-- 3) goat_obligations — rent, home-loan EMI, term insurance
insert into public.goat_obligations (
  id, user_id, obligation_type, lender_name,
  current_outstanding, monthly_due, due_day, interest_rate,
  cadence, status, metadata
)
select
  md5('<USER_UUID>' || ':' || o.key)::uuid,
  '<USER_UUID>'::uuid,
  o.obligation_type, o.lender_name,
  o.current_outstanding, o.monthly_due, o.due_day, o.interest_rate,
  'monthly', 'active',
  jsonb_build_object('seeded', true, 'key', o.key)
from (values
  ('rent',         'rent',      'Landlord (Koramangala 2BHK)',
     null,       28000.00,  5,  null),
  ('home_loan',    'emi',       'SBI Home Loan',
    1850000.00,  22500.00, 10,  8.500),
  ('term_ins',     'insurance', 'HDFC Life Click 2 Protect',
     null,        1800.00, 15,  null)
) as o(key, obligation_type, lender_name, current_outstanding, monthly_due, due_day, interest_rate)
on conflict (id) do update set
  current_outstanding = excluded.current_outstanding,
  monthly_due         = excluded.monthly_due,
  due_day             = excluded.due_day,
  interest_rate       = excluded.interest_rate,
  lender_name         = excluded.lender_name,
  updated_at          = now();

commit;


-- ============================================================================
-- VERIFY
-- ============================================================================
select 'goat_user_inputs' as tbl, count(*) as rows
from   public.goat_user_inputs where user_id = '<USER_UUID>'::uuid
union all
select 'goat_goals',        count(*)
from   public.goat_goals       where user_id = '<USER_UUID>'::uuid
union all
select 'goat_obligations',  count(*)
from   public.goat_obligations where user_id = '<USER_UUID>'::uuid;

-- Expected:
--   goat_user_inputs  1
--   goat_goals        4
--   goat_obligations  3
