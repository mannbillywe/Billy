-- ============================================================================
-- MIGRATION: Goat Mode v1 — compute tables + user-input tables + access ledger
-- ============================================================================
-- Re-introduces the Goat Mode schema after the April 11 rollback. Adds only
-- Goat Mode-specific tables; does NOT touch any existing app tables.
--
-- Tables:
--   * goat_mode_jobs               compute lifecycle (written by backend)
--   * goat_mode_snapshots          computed payload per (user,scope,fingerprint)
--   * goat_mode_job_events         per-step audit / debug
--   * goat_mode_recommendations    rec lifecycle (open/dismissed/snoozed/...)
--   * goat_user_inputs             declared planning inputs (1 row/user)
--   * goat_goals                   user-declared goals
--   * goat_obligations             declared recurring debts / liabilities
--   * goat_mode_access             admin-managed access ledger (mirrors into
--                                  profiles.goat_mode so existing UI gating
--                                  keeps working without changes)
--
-- Flow: backend (service_role) writes compute tables. Flutter reads compute
-- tables under RLS (users only see their own rows). Access control lives in
-- goat_mode_access; a trigger keeps profiles.goat_mode in sync.
-- ============================================================================

-- 0. Shared updated_at helper (reuse Billy convention)
create or replace function public.set_invoice_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ─── 1. goat_mode_jobs ─────────────────────────────────────────────────────
create table if not exists public.goat_mode_jobs (
  id                   uuid          primary key default gen_random_uuid(),
  user_id              uuid          not null references public.profiles(id) on delete cascade,
  scope                text          not null
    check (scope in ('overview','cashflow','budgets','recurring','debt','goals','full')),
  trigger_source       text          not null default 'manual'
    check (trigger_source in ('manual','scheduled','post_event','system')),
  status               text          not null default 'queued'
    check (status in ('queued','running','succeeded','partial','failed','cancelled')),
  readiness_level      text          null
    check (readiness_level is null or readiness_level in ('L1','L2','L3')),
  range_start          date          null,
  range_end            date          null,
  data_fingerprint     text          null,
  request_payload      jsonb         not null default '{}'::jsonb,
  backend_request_id   text          null,
  model_versions       jsonb         not null default '{}'::jsonb,
  error_code           text          null,
  error_message        text          null,
  started_at           timestamptz   null,
  finished_at          timestamptz   null,
  created_at           timestamptz   not null default now(),
  updated_at           timestamptz   not null default now()
);

comment on table public.goat_mode_jobs is
  'Goat Mode compute lifecycle. One row per backend run.';

create index if not exists goat_mode_jobs_user_idx
  on public.goat_mode_jobs(user_id, created_at desc);
create index if not exists goat_mode_jobs_user_status_idx
  on public.goat_mode_jobs(user_id, status);
create index if not exists goat_mode_jobs_active_idx
  on public.goat_mode_jobs(user_id, scope, created_at desc)
  where status in ('queued','running');

drop trigger if exists goat_mode_jobs_touch_updated_at on public.goat_mode_jobs;
create trigger goat_mode_jobs_touch_updated_at
  before update on public.goat_mode_jobs
  for each row execute function public.set_invoice_updated_at();

alter table public.goat_mode_jobs enable row level security;
drop policy if exists goat_mode_jobs_select on public.goat_mode_jobs;
drop policy if exists goat_mode_jobs_insert on public.goat_mode_jobs;
create policy goat_mode_jobs_select on public.goat_mode_jobs
  for select using (auth.uid() = user_id);
create policy goat_mode_jobs_insert on public.goat_mode_jobs
  for insert with check (auth.uid() = user_id);


-- ─── 2. goat_mode_snapshots ────────────────────────────────────────────────
create table if not exists public.goat_mode_snapshots (
  id                              uuid          primary key default gen_random_uuid(),
  job_id                          uuid          null references public.goat_mode_jobs(id) on delete set null,
  user_id                         uuid          not null references public.profiles(id) on delete cascade,
  scope                           text          not null
    check (scope in ('overview','cashflow','budgets','recurring','debt','goals','full')),
  range_start                     date          null,
  range_end                       date          null,
  data_fingerprint                text          not null,
  snapshot_status                 text          not null default 'completed'
    check (snapshot_status in ('completed','partial','failed')),
  readiness_level                 text          not null
    check (readiness_level in ('L1','L2','L3')),
  confidence_summary              jsonb         not null default '{}'::jsonb,
  coverage_json                   jsonb         not null default '{}'::jsonb,
  summary_json                    jsonb         not null default '{}'::jsonb,
  metrics_json                    jsonb         not null default '{}'::jsonb,
  forecast_json                   jsonb         not null default '{}'::jsonb,
  anomalies_json                  jsonb         not null default '{}'::jsonb,
  risk_json                       jsonb         not null default '{}'::jsonb,
  recommendations_summary_json    jsonb         not null default '{}'::jsonb,
  ai_layer                        jsonb         not null default '{}'::jsonb,
  ai_validated                    boolean       not null default false,
  generated_at                    timestamptz   not null default now(),
  created_at                      timestamptz   not null default now(),
  updated_at                      timestamptz   not null default now()
);

comment on table public.goat_mode_snapshots is
  'Computed Goat Mode payload. Coverage is merged into coverage_json.';

create unique index if not exists goat_mode_snapshots_unique_fp
  on public.goat_mode_snapshots(user_id, scope, data_fingerprint);
create index if not exists goat_mode_snapshots_user_scope_idx
  on public.goat_mode_snapshots(user_id, scope, generated_at desc);
create index if not exists goat_mode_snapshots_job_idx
  on public.goat_mode_snapshots(job_id)
  where job_id is not null;

drop trigger if exists goat_mode_snapshots_touch_updated_at on public.goat_mode_snapshots;
create trigger goat_mode_snapshots_touch_updated_at
  before update on public.goat_mode_snapshots
  for each row execute function public.set_invoice_updated_at();

alter table public.goat_mode_snapshots enable row level security;
drop policy if exists goat_mode_snapshots_select on public.goat_mode_snapshots;
create policy goat_mode_snapshots_select on public.goat_mode_snapshots
  for select using (auth.uid() = user_id);


-- ─── 3. goat_mode_job_events ───────────────────────────────────────────────
create table if not exists public.goat_mode_job_events (
  id          uuid          primary key default gen_random_uuid(),
  job_id      uuid          not null references public.goat_mode_jobs(id) on delete cascade,
  user_id     uuid          not null references public.profiles(id) on delete cascade,
  step        text          not null
    check (step in (
      'dispatch','input_load','deterministic','forecast','anomaly',
      'risk','recommendation','ai','persist','callback','teardown'
    )),
  status      text          not null
    check (status in (
      'started','finished','warning','error',
      'validation_failed','ai_rejected','fallback_used','skipped'
    )),
  severity    text          not null default 'info'
    check (severity in ('info','warn','error')),
  message     text          null,
  detail      jsonb         not null default '{}'::jsonb,
  created_at  timestamptz   not null default now()
);

comment on table public.goat_mode_job_events is
  'Per-step audit for Goat Mode jobs. Backend-only; users can read their own.';

create index if not exists goat_mode_job_events_job_idx
  on public.goat_mode_job_events(job_id, created_at);
create index if not exists goat_mode_job_events_user_severity_idx
  on public.goat_mode_job_events(user_id, severity, created_at desc)
  where severity in ('warn','error');

alter table public.goat_mode_job_events enable row level security;
drop policy if exists goat_mode_job_events_select on public.goat_mode_job_events;
create policy goat_mode_job_events_select on public.goat_mode_job_events
  for select using (auth.uid() = user_id);


-- ─── 4. goat_user_inputs ───────────────────────────────────────────────────
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


-- ─── 5. goat_goals ─────────────────────────────────────────────────────────
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

create index if not exists goat_goals_user_active_idx
  on public.goat_goals(user_id, priority) where status = 'active';
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


-- ─── 6. goat_obligations ───────────────────────────────────────────────────
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

create index if not exists goat_obligations_user_active_idx
  on public.goat_obligations(user_id) where status = 'active';

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


-- ─── 7. goat_mode_recommendations ──────────────────────────────────────────
create table if not exists public.goat_mode_recommendations (
  id                    uuid          primary key default gen_random_uuid(),
  user_id               uuid          not null references public.profiles(id) on delete cascade,
  snapshot_id           uuid          null references public.goat_mode_snapshots(id) on delete set null,
  job_id                uuid          null references public.goat_mode_jobs(id) on delete set null,
  recommendation_kind   text          not null
    check (recommendation_kind in (
      'budget_overrun','anomaly_review','liquidity_warning','goal_shortfall',
      'missed_payment_risk','recurring_drift','duplicate_cluster','missing_input',
      'uncategorized_cleanup','recovery_iou','other'
    )),
  severity              text          not null
    check (severity in ('info','watch','warn','critical')),
  priority              integer       not null check (priority between 0 and 100),
  impact_score          numeric(4,3)  null check (impact_score is null or impact_score between 0 and 1),
  effort_score          numeric(4,3)  null check (effort_score is null or effort_score between 0 and 1),
  confidence            numeric(4,3)  null check (confidence   is null or confidence   between 0 and 1),
  rec_fingerprint       text          not null,
  entity_type           text          null,
  entity_id             uuid          null,
  observation_json      jsonb         not null default '{}'::jsonb,
  recommendation_json   jsonb         not null default '{}'::jsonb,
  status                text          not null default 'open'
    check (status in ('open','dismissed','snoozed','resolved','expired')),
  snoozed_until         timestamptz   null,
  expires_at            timestamptz   null,
  created_at            timestamptz   not null default now(),
  updated_at            timestamptz   not null default now()
);

create unique index if not exists goat_mode_recommendations_open_unique
  on public.goat_mode_recommendations(user_id, rec_fingerprint)
  where status = 'open';
create index if not exists goat_mode_recommendations_user_open_idx
  on public.goat_mode_recommendations(user_id, priority desc, created_at desc)
  where status in ('open','snoozed');
create index if not exists goat_mode_recommendations_user_kind_idx
  on public.goat_mode_recommendations(user_id, recommendation_kind, created_at desc);
create index if not exists goat_mode_recommendations_snapshot_idx
  on public.goat_mode_recommendations(snapshot_id)
  where snapshot_id is not null;

drop trigger if exists goat_mode_recommendations_touch_updated_at on public.goat_mode_recommendations;
create trigger goat_mode_recommendations_touch_updated_at
  before update on public.goat_mode_recommendations
  for each row execute function public.set_invoice_updated_at();

alter table public.goat_mode_recommendations enable row level security;
drop policy if exists goat_mode_recommendations_select on public.goat_mode_recommendations;
drop policy if exists goat_mode_recommendations_update on public.goat_mode_recommendations;
create policy goat_mode_recommendations_select on public.goat_mode_recommendations
  for select using (auth.uid() = user_id);
create policy goat_mode_recommendations_update on public.goat_mode_recommendations
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);


-- ─── 8. goat_mode_access (admin access ledger) ─────────────────────────────
-- Dedicated table that admins write into to grant / revoke Goat Mode access.
-- A trigger keeps profiles.goat_mode in sync, so the Flutter app keeps using
-- its existing profile gating (profileGoatModeEnabled) without any changes.
create table if not exists public.goat_mode_access (
  user_id     uuid          primary key references public.profiles(id) on delete cascade,
  enabled     boolean       not null default true,
  enabled_at  timestamptz   not null default now(),
  enabled_by  uuid          null references auth.users(id) on delete set null,
  source      text          not null default 'admin_sql'
    check (source in ('admin_sql','admin_ui','beta_invite','self_signup','migration','other')),
  notes       text          null,
  created_at  timestamptz   not null default now(),
  updated_at  timestamptz   not null default now()
);

comment on table public.goat_mode_access is
  'Admin-managed Goat Mode access ledger. Trigger mirrors enabled → profiles.goat_mode so client UI gating (profileGoatModeEnabled) reflects this table automatically.';

create index if not exists goat_mode_access_enabled_idx
  on public.goat_mode_access(enabled, enabled_at desc);

drop trigger if exists goat_mode_access_touch_updated_at on public.goat_mode_access;
create trigger goat_mode_access_touch_updated_at
  before update on public.goat_mode_access
  for each row execute function public.set_invoice_updated_at();

-- Trigger: whenever goat_mode_access changes, mirror into profiles.goat_mode.
create or replace function public.goat_mode_access_sync_profile()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op = 'INSERT' or tg_op = 'UPDATE') then
    update public.profiles
       set goat_mode = coalesce(new.enabled, false)
     where id = new.user_id
       and (goat_mode is distinct from coalesce(new.enabled, false));
    return new;
  elsif (tg_op = 'DELETE') then
    update public.profiles
       set goat_mode = false
     where id = old.user_id
       and goat_mode is distinct from false;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists goat_mode_access_sync_profile_trg on public.goat_mode_access;
create trigger goat_mode_access_sync_profile_trg
  after insert or update or delete on public.goat_mode_access
  for each row execute function public.goat_mode_access_sync_profile();

alter table public.goat_mode_access enable row level security;

-- Admin-only: no client INSERT/UPDATE/DELETE policies. Backfill / grants run
-- via SQL with the service_role key. Users may see whether THEY have access
-- (useful for settings surfaces, though the UI reads profiles.goat_mode
-- directly today).
drop policy if exists goat_mode_access_select_self on public.goat_mode_access;
create policy goat_mode_access_select_self on public.goat_mode_access
  for select using (auth.uid() = user_id);


-- ─── Backfill: reflect anyone already flagged goat_mode=true into the ledger
insert into public.goat_mode_access (user_id, enabled, source, notes)
select p.id, true, 'migration', 'backfilled from profiles.goat_mode'
  from public.profiles p
 where p.goat_mode = true
on conflict (user_id) do nothing;
