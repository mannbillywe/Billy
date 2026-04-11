-- Budget system: per-category or total spending limits with period tracking.

create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  category_id uuid references public.categories(id),
  amount numeric(12,2) not null check (amount > 0),
  period text not null default 'monthly' check (period in ('weekly','monthly','yearly')),
  currency text not null default 'INR',
  rollover_enabled boolean not null default false,
  is_active boolean not null default true,
  start_date date not null default current_date,
  end_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index budgets_user_category_active
  on public.budgets(user_id, category_id)
  where is_active = true and category_id is not null;

create index budgets_user_idx on public.budgets(user_id);

alter table public.budgets enable row level security;
create policy "budgets_select" on public.budgets for select using (auth.uid() = user_id);
create policy "budgets_insert" on public.budgets for insert with check (auth.uid() = user_id);
create policy "budgets_update" on public.budgets for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "budgets_delete" on public.budgets for delete using (auth.uid() = user_id);

create trigger budgets_touch_updated_at
  before update on public.budgets
  for each row execute function set_invoice_updated_at();

-- Budget period actuals tracking
create table if not exists public.budget_periods (
  id uuid primary key default gen_random_uuid(),
  budget_id uuid not null references public.budgets(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  spent numeric(12,2) not null default 0,
  rollover_amount numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index budget_periods_unique on public.budget_periods(budget_id, period_start);
create index budget_periods_user_idx on public.budget_periods(user_id, period_start desc);

alter table public.budget_periods enable row level security;
create policy "bp_select" on public.budget_periods for select using (auth.uid() = user_id);
create policy "bp_insert" on public.budget_periods for insert with check (auth.uid() = user_id);
create policy "bp_update" on public.budget_periods for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "bp_delete" on public.budget_periods for delete using (auth.uid() = user_id);

create trigger budget_periods_touch_updated_at
  before update on public.budget_periods
  for each row execute function set_invoice_updated_at();
