-- Cached analytics / AI insights (one row per user per range preset). No auto-regeneration on read.

create table if not exists public.analytics_insight_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  range_preset text not null check (range_preset in ('1W', '1M', '3M')),
  range_start date not null,
  range_end date not null,
  data_fingerprint text not null,
  deterministic jsonb not null default '{}'::jsonb,
  ai_layer jsonb,
  generated_at timestamptz not null default now(),
  unique (user_id, range_preset)
);

create index if not exists analytics_insight_snapshots_user_idx
  on public.analytics_insight_snapshots (user_id);

comment on table public.analytics_insight_snapshots is
  'User-scoped cached analytics payload; refreshed only via explicit Edge Function invoke (manual).';

alter table public.analytics_insight_snapshots enable row level security;

create policy "Users read own analytics snapshots"
  on public.analytics_insight_snapshots for select
  using (auth.uid() = user_id);

create policy "Users upsert own analytics snapshots"
  on public.analytics_insight_snapshots for insert
  with check (auth.uid() = user_id);

create policy "Users update own analytics snapshots"
  on public.analytics_insight_snapshots for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users delete own analytics snapshots"
  on public.analytics_insight_snapshots for delete
  using (auth.uid() = user_id);
