-- GOAT Dashboard: persisted period/lens defaults and pins (optional; profile.goat_analysis_lens remains global lens).

create table if not exists public.goat_dashboard_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  default_lens text not null default 'smart'
    check (default_lens in ('smart','statements_only','ocr_only','combined_raw')),
  default_period_mode text not null default 'calendar_month'
    check (default_period_mode in ('calendar_month','statement_cycle','custom_range')),
  default_date_basis text not null default 'transaction_date'
    check (default_date_basis in ('transaction_date','posted_date')),
  default_range_preset text not null default 'this_month',
  pinned_accounts jsonb not null default '[]'::jsonb,
  pinned_goals jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists goat_dashboard_preferences_user_idx on public.goat_dashboard_preferences (user_id);

create or replace function public.goat_dashboard_prefs_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists goat_dashboard_preferences_touch on public.goat_dashboard_preferences;
create trigger goat_dashboard_preferences_touch
  before update on public.goat_dashboard_preferences
  for each row execute procedure public.goat_dashboard_prefs_touch_updated_at();

alter table public.goat_dashboard_preferences enable row level security;

drop policy if exists goat_dashboard_preferences_select on public.goat_dashboard_preferences;
drop policy if exists goat_dashboard_preferences_insert on public.goat_dashboard_preferences;
drop policy if exists goat_dashboard_preferences_update on public.goat_dashboard_preferences;
drop policy if exists goat_dashboard_preferences_delete on public.goat_dashboard_preferences;

create policy goat_dashboard_preferences_select on public.goat_dashboard_preferences for select to authenticated
  using (auth.uid() = user_id);
create policy goat_dashboard_preferences_insert on public.goat_dashboard_preferences for insert to authenticated
  with check (auth.uid() = user_id);
create policy goat_dashboard_preferences_update on public.goat_dashboard_preferences for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy goat_dashboard_preferences_delete on public.goat_dashboard_preferences for delete to authenticated
  using (auth.uid() = user_id);

comment on table public.goat_dashboard_preferences is 'GOAT dashboard UI defaults (period mode, date basis, pins).';
