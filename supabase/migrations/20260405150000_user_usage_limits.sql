-- User usage limits: configurable per-user caps on OCR scans and data refreshes.
-- Locks users out after hitting their limit until the period resets.

create table public.user_usage_limits (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,

  -- OCR scan counters
  ocr_scans_used int not null default 0,
  ocr_scans_limit int not null default 5,

  -- Data refresh counters
  refresh_used int not null default 0,
  refresh_limit int not null default 5,

  -- Period boundaries (monthly by default)
  period_start timestamptz not null default date_trunc('month', now()),
  period_end timestamptz not null default (date_trunc('month', now()) + interval '1 month'),

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index user_usage_limits_user_id_idx on public.user_usage_limits(user_id);

-- RLS: users can read their own row; only service_role / admin can update limits
alter table public.user_usage_limits enable row level security;

create policy "Users can read own usage"
  on public.user_usage_limits for select
  using (auth.uid() = user_id);

create policy "Users can update own counters"
  on public.user_usage_limits for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Function to auto-reset counters if the period has elapsed
create or replace function public.maybe_reset_usage(p_user_id uuid)
returns public.user_usage_limits as $$
declare
  row public.user_usage_limits;
begin
  select * into row from public.user_usage_limits where user_id = p_user_id;

  if row is null then
    insert into public.user_usage_limits (user_id)
    values (p_user_id)
    returning * into row;
  end if;

  if now() >= row.period_end then
    update public.user_usage_limits
    set ocr_scans_used = 0,
        refresh_used = 0,
        period_start = date_trunc('month', now()),
        period_end = date_trunc('month', now()) + interval '1 month',
        updated_at = now()
    where user_id = p_user_id
    returning * into row;
  end if;

  return row;
end;
$$ language plpgsql security definer;

-- Function to increment OCR scan counter; returns the updated row.
-- Raises an exception if the limit would be exceeded.
create or replace function public.increment_ocr_scan(p_user_id uuid)
returns public.user_usage_limits as $$
declare
  row public.user_usage_limits;
begin
  row := public.maybe_reset_usage(p_user_id);

  if row.ocr_scans_used >= row.ocr_scans_limit then
    raise exception 'OCR scan limit reached (% / %). Upgrade or wait for next period.', row.ocr_scans_used, row.ocr_scans_limit;
  end if;

  update public.user_usage_limits
  set ocr_scans_used = ocr_scans_used + 1, updated_at = now()
  where user_id = p_user_id
  returning * into row;

  return row;
end;
$$ language plpgsql security definer;

-- Function to increment refresh counter.
create or replace function public.increment_refresh_count(p_user_id uuid)
returns public.user_usage_limits as $$
declare
  row public.user_usage_limits;
begin
  row := public.maybe_reset_usage(p_user_id);

  if row.refresh_used >= row.refresh_limit then
    raise exception 'Refresh limit reached (% / %). Upgrade or wait for next period.', row.refresh_used, row.refresh_limit;
  end if;

  update public.user_usage_limits
  set refresh_used = refresh_used + 1, updated_at = now()
  where user_id = p_user_id
  returning * into row;

  return row;
end;
$$ language plpgsql security definer;

-- Auto-create usage row for new users (update existing trigger function)
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      split_part(new.email, '@', 1)
    ),
    new.raw_user_meta_data->>'avatar_url'
  );

  insert into public.user_usage_limits (user_id)
  values (new.id);

  return new;
end;
$$ language plpgsql security definer;

-- Backfill: create usage rows for existing users who don't have one yet
insert into public.user_usage_limits (user_id)
select p.id from public.profiles p
where not exists (
  select 1 from public.user_usage_limits u where u.user_id = p.id
);
