-- Recurring bills and subscription tracking.

create table public.recurring_series (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'INR',
  category_id uuid references public.categories(id),
  cadence text not null check (cadence in ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  anchor_date date not null,
  next_due date,
  detection_source text not null default 'manual' check (detection_source in ('manual','pattern','statement')),
  vendor_pattern text,
  is_active boolean not null default true,
  auto_confirm boolean not null default false,
  remind_days_before integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index recurring_series_user_idx on public.recurring_series(user_id);
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

-- Individual occurrences of recurring charges
create table public.recurring_occurrences (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.recurring_series(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  due_date date not null,
  actual_amount numeric(12,2),
  transaction_id uuid references public.transactions(id) on delete set null,
  status text not null default 'upcoming' check (status in ('upcoming','confirmed','missed','skipped')),
  created_at timestamptz not null default now()
);

create unique index recurring_occ_unique on public.recurring_occurrences(series_id, due_date);
create index recurring_occ_user_idx on public.recurring_occurrences(user_id, due_date);

alter table public.recurring_occurrences enable row level security;
create policy "ro_select" on public.recurring_occurrences for select using (auth.uid() = user_id);
create policy "ro_insert" on public.recurring_occurrences for insert with check (auth.uid() = user_id);
create policy "ro_update" on public.recurring_occurrences for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "ro_delete" on public.recurring_occurrences for delete using (auth.uid() = user_id);
