-- GOAT Feature 3: goals + sinking funds (deterministic math in app; RLS per user).

-- ─── goals ─────────────────────────────────────────────────────────
create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  goal_type text not null check (goal_type in (
    'emergency_fund','sinking_fund','purchase','travel','bill_buffer','debt_paydown','custom'
  )),
  status text not null default 'active' check (status in ('active','paused','completed','archived')),
  target_amount numeric(14,2) not null,
  current_amount numeric(14,2) not null default 0,
  target_date date,
  monthly_target numeric(14,2),
  weekly_target numeric(14,2),
  priority int not null default 3,
  linked_category_id uuid references public.categories(id) on delete set null,
  linked_recurring_series_id uuid references public.recurring_series(id) on delete set null,
  linked_account_id uuid references public.financial_accounts(id) on delete set null,
  auto_allocate boolean not null default false,
  notes text,
  color text,
  icon text,
  -- none = forecast ignores; soft = shown in UI only; hard = reduces safe-to-spend (monthly commitment).
  forecast_reserve text not null default 'none' check (forecast_reserve in ('none','soft','hard')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists goals_user_status_idx on public.goals (user_id, status);
create index if not exists goals_user_type_idx on public.goals (user_id, goal_type);

-- ─── goal_contributions ─────────────────────────────────────────────
create table if not exists public.goal_contributions (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(14,2) not null,
  contribution_type text not null check (contribution_type in (
    'manual','scheduled','auto_allocated','roundup','transfer'
  )),
  contributed_at timestamptz not null default now(),
  note text,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists goal_contributions_goal_idx
  on public.goal_contributions (goal_id, contributed_at desc);
create index if not exists goal_contributions_user_idx on public.goal_contributions (user_id);

-- ─── goal_rules ───────────────────────────────────────────────────
create table if not exists public.goal_rules (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rule_type text not null check (rule_type in (
    'monthly_fixed','weekly_fixed','percentage_of_income','leftover_sweep','bill_linked'
  )),
  rule_value numeric(14,2) not null,
  enabled boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists goal_rules_goal_idx on public.goal_rules (goal_id);

-- ─── goal_recommendations (deterministic suggestions + user dismiss/accept) ─
create table if not exists public.goal_recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text,
  suggestion_key text not null,
  suggestion_type text not null check (suggestion_type in (
    'annual_bill','quarterly_bill','planned_event','recurring_series','emergency_fund','category_pattern','custom'
  )),
  ref_id uuid,
  ref_table text,
  suggested_target_amount numeric(14,2),
  suggested_target_date date,
  status text not null default 'pending' check (status in ('pending','accepted','dismissed')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, suggestion_key)
);

create index if not exists goal_recommendations_user_status_idx
  on public.goal_recommendations (user_id, status);

-- ─── updated_at ────────────────────────────────────────────────────
create or replace function public.goat_goals_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists goals_updated_at on public.goals;
create trigger goals_updated_at
  before update on public.goals
  for each row execute procedure public.goat_goals_touch_updated_at();

drop trigger if exists goal_rules_updated_at on public.goal_rules;
create trigger goal_rules_updated_at
  before update on public.goal_rules
  for each row execute procedure public.goat_goals_touch_updated_at();

drop trigger if exists goal_recommendations_updated_at on public.goal_recommendations;
create trigger goal_recommendations_updated_at
  before update on public.goal_recommendations
  for each row execute procedure public.goat_goals_touch_updated_at();

-- ─── RLS ───────────────────────────────────────────────────────────
alter table public.goals enable row level security;
alter table public.goal_contributions enable row level security;
alter table public.goal_rules enable row level security;
alter table public.goal_recommendations enable row level security;

drop policy if exists goals_select on public.goals;
drop policy if exists goals_insert on public.goals;
drop policy if exists goals_update on public.goals;
drop policy if exists goals_delete on public.goals;
create policy goals_select on public.goals for select to authenticated using (auth.uid() = user_id);
create policy goals_insert on public.goals for insert to authenticated with check (auth.uid() = user_id);
create policy goals_update on public.goals for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy goals_delete on public.goals for delete to authenticated using (auth.uid() = user_id);

drop policy if exists goal_contributions_select on public.goal_contributions;
drop policy if exists goal_contributions_insert on public.goal_contributions;
drop policy if exists goal_contributions_delete on public.goal_contributions;
create policy goal_contributions_select on public.goal_contributions for select to authenticated using (auth.uid() = user_id);
create policy goal_contributions_insert on public.goal_contributions for insert to authenticated with check (auth.uid() = user_id);
create policy goal_contributions_delete on public.goal_contributions for delete to authenticated using (auth.uid() = user_id);

drop policy if exists goal_rules_select on public.goal_rules;
drop policy if exists goal_rules_insert on public.goal_rules;
drop policy if exists goal_rules_update on public.goal_rules;
drop policy if exists goal_rules_delete on public.goal_rules;
create policy goal_rules_select on public.goal_rules for select to authenticated using (auth.uid() = user_id);
create policy goal_rules_insert on public.goal_rules for insert to authenticated with check (auth.uid() = user_id);
create policy goal_rules_update on public.goal_rules for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy goal_rules_delete on public.goal_rules for delete to authenticated using (auth.uid() = user_id);

drop policy if exists goal_recommendations_select on public.goal_recommendations;
drop policy if exists goal_recommendations_insert on public.goal_recommendations;
drop policy if exists goal_recommendations_update on public.goal_recommendations;
drop policy if exists goal_recommendations_delete on public.goal_recommendations;
create policy goal_recommendations_select on public.goal_recommendations for select to authenticated using (auth.uid() = user_id);
create policy goal_recommendations_insert on public.goal_recommendations for insert to authenticated with check (auth.uid() = user_id);
create policy goal_recommendations_update on public.goal_recommendations for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy goal_recommendations_delete on public.goal_recommendations for delete to authenticated using (auth.uid() = user_id);

comment on table public.goals is 'GOAT savings goals and sinking funds; deterministic progress in app.';
comment on column public.goals.forecast_reserve is 'hard: monthly commitment reduces safe-to-spend; soft: informational only.';
