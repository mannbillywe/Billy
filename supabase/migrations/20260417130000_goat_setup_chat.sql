-- GOAT Setup / Readiness: chat-first wizard state + AI drafts (no money truth in drafts until app applies).

-- ─── goat_setup_state ─────────────────────────────────────────────
create table if not exists public.goat_setup_state (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  status text not null default 'not_started'
    check (status in ('not_started','in_progress','completed','skipped')),
  current_step text,
  completed_steps jsonb not null default '[]'::jsonb,
  skipped_steps jsonb not null default '[]'::jsonb,
  readiness_score integer not null default 0
    check (readiness_score >= 0 and readiness_score <= 100),
  critical_missing jsonb not null default '[]'::jsonb,
  optional_missing jsonb not null default '[]'::jsonb,
  setup_version integer not null default 1,
  started_at timestamptz,
  completed_at timestamptz,
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists goat_setup_state_user_idx on public.goat_setup_state (user_id);

-- ─── goat_setup_drafts ────────────────────────────────────────────
create table if not exists public.goat_setup_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  setup_state_id uuid not null references public.goat_setup_state(id) on delete cascade,
  source_message text not null,
  parsed_payload jsonb not null default '{}'::jsonb,
  parse_confidence numeric(5,2),
  parse_status text not null default 'draft'
    check (parse_status in ('draft','reviewed','applied','discarded')),
  ai_call_index integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists goat_setup_drafts_user_idx on public.goat_setup_drafts (user_id, created_at desc);
create index if not exists goat_setup_drafts_state_idx on public.goat_setup_drafts (setup_state_id, created_at desc);

-- ─── updated_at ───────────────────────────────────────────────────
create or replace function public.goat_setup_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists goat_setup_state_touch on public.goat_setup_state;
create trigger goat_setup_state_touch
  before update on public.goat_setup_state
  for each row execute procedure public.goat_setup_touch_updated_at();

drop trigger if exists goat_setup_drafts_touch on public.goat_setup_drafts;
create trigger goat_setup_drafts_touch
  before update on public.goat_setup_drafts
  for each row execute procedure public.goat_setup_touch_updated_at();

-- ─── AI call budget (Edge service_role only; not exposed to authenticated clients) ─
create or replace function public.goat_setup_reserve_ai_slot(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid;
  cur int;
  newc int;
begin
  select id, coalesce((metadata->>'ai_calls_used')::int, 0)
    into sid, cur
  from public.goat_setup_state
  where user_id = p_user_id
  for update;

  if not found then
    insert into public.goat_setup_state (user_id, status, started_at, last_seen_at, metadata)
    values (
      p_user_id,
      'in_progress',
      now(),
      now(),
      jsonb_build_object('ai_calls_used', 1)
    )
    returning id into sid;
    return jsonb_build_object('ok', true, 'setup_state_id', sid, 'calls_after', 1);
  end if;

  if cur >= 2 then
    return jsonb_build_object('ok', false, 'reason', 'limit_exceeded');
  end if;

  newc := cur + 1;
  update public.goat_setup_state
  set
    metadata = jsonb_set(coalesce(metadata, '{}'::jsonb), '{ai_calls_used}', to_jsonb(newc), true),
    status = case when status = 'not_started' then 'in_progress' else status end,
    started_at = coalesce(started_at, now()),
    last_seen_at = now(),
    updated_at = now()
  where id = sid;

  return jsonb_build_object('ok', true, 'setup_state_id', sid, 'calls_after', newc);
end;
$$;

create or replace function public.goat_setup_release_ai_slot(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid;
  cur int;
begin
  select id, coalesce((metadata->>'ai_calls_used')::int, 0)
    into sid, cur
  from public.goat_setup_state
  where user_id = p_user_id
  for update;

  if not found or cur <= 0 then
    return;
  end if;

  update public.goat_setup_state
  set
    metadata = jsonb_set(coalesce(metadata, '{}'::jsonb), '{ai_calls_used}', to_jsonb(cur - 1), true),
    updated_at = now()
  where id = sid;
end;
$$;

revoke all on function public.goat_setup_reserve_ai_slot(uuid) from public;
revoke all on function public.goat_setup_release_ai_slot(uuid) from public;
grant execute on function public.goat_setup_reserve_ai_slot(uuid) to service_role;
grant execute on function public.goat_setup_release_ai_slot(uuid) to service_role;

-- ─── RLS ──────────────────────────────────────────────────────────
alter table public.goat_setup_state enable row level security;
alter table public.goat_setup_drafts enable row level security;

drop policy if exists goat_setup_state_select on public.goat_setup_state;
drop policy if exists goat_setup_state_insert on public.goat_setup_state;
drop policy if exists goat_setup_state_update on public.goat_setup_state;
drop policy if exists goat_setup_state_delete on public.goat_setup_state;
create policy goat_setup_state_select on public.goat_setup_state for select to authenticated
  using (auth.uid() = user_id);
create policy goat_setup_state_insert on public.goat_setup_state for insert to authenticated
  with check (auth.uid() = user_id);
create policy goat_setup_state_update on public.goat_setup_state for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy goat_setup_state_delete on public.goat_setup_state for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists goat_setup_drafts_select on public.goat_setup_drafts;
drop policy if exists goat_setup_drafts_insert on public.goat_setup_drafts;
drop policy if exists goat_setup_drafts_update on public.goat_setup_drafts;
drop policy if exists goat_setup_drafts_delete on public.goat_setup_drafts;
create policy goat_setup_drafts_select on public.goat_setup_drafts for select to authenticated
  using (auth.uid() = user_id);
create policy goat_setup_drafts_insert on public.goat_setup_drafts for insert to authenticated
  with check (auth.uid() = user_id);
create policy goat_setup_drafts_update on public.goat_setup_drafts for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy goat_setup_drafts_delete on public.goat_setup_drafts for delete to authenticated
  using (auth.uid() = user_id);

comment on table public.goat_setup_state is 'GOAT onboarding/setup progress, readiness cache, AI call budget metadata.';
comment on table public.goat_setup_drafts is 'Structured setup payloads from Gemini; applied only after user review in app.';
