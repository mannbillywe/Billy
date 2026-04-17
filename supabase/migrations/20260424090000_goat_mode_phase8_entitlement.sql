-- ═══════════════════════════════════════════════════════════════════════════════
-- MIGRATION: Goat Mode Phase 8 — entitlement-aware RLS on writes
-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 8 hardening: tighten write-path RLS on Goat Mode tables so that only
-- users with profiles.goat_mode = true can insert/update/delete their own rows.
--
-- What stays the same:
--   • SELECT policies remain user-scoped (auth.uid() = user_id). If a user is
--     de-entitled later, their historical rows stay readable — we don't want
--     data to "disappear" mid-session, and compute never ran for them if they
--     were never entitled in the first place so there is nothing to leak.
--   • The compute backend (runner.py + supabase_io.py) uses the Supabase
--     service_role key, which bypasses RLS. It is NOT affected by this change.
--   • The Edge Function gate (goat-mode-trigger) is unchanged. This migration
--     is defence-in-depth below it.
--
-- What changes:
--   • INSERT / UPDATE / DELETE on user-writable Goat tables now also require
--     that profiles.goat_mode = true for the caller. Any direct Supabase
--     write from a non-entitled user (bypassing the Flutter UI) will be
--     rejected by PostgREST with RLS violation.
--
-- Affected tables / policies:
--   • goat_mode_jobs             — insert (defensive; currently Flutter reads
--                                  only, backend inserts via service_role)
--   • goat_user_inputs           — insert, update, delete
--   • goat_goals                 — insert, update, delete
--   • goat_obligations           — insert, update, delete
--   • goat_mode_recommendations  — update (only mutation surface; insert and
--                                  delete have no client policy by design)
--
-- Rollback:
--   A follow-up migration can `drop policy ... ; create policy ...` to
--   restore the prior user-scope-only shape. The helper function is
--   safe to keep even if the policies are reverted.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Entitlement helper
-- ─────────────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER so the function can always read profiles.goat_mode even if
-- a future RLS tightening on profiles would otherwise hide the row from its
-- own owner. `stable` lets the planner cache it within a single statement.
-- Execution is restricted to authenticated roles (+ service_role for tests).
create or replace function public.goat_mode_enabled_for(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(goat_mode, false)
  from public.profiles
  where id = uid
$$;

comment on function public.goat_mode_enabled_for(uuid) is
  'Goat Mode Phase 8: returns true iff profiles.goat_mode = true for the given user. Used by RLS policies on goat_* tables to gate writes on entitlement.';

revoke all on function public.goat_mode_enabled_for(uuid) from public;
grant execute on function public.goat_mode_enabled_for(uuid) to authenticated, service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. goat_mode_jobs — tighten INSERT
-- ─────────────────────────────────────────────────────────────────────────────
-- Client-side inserts are not used by the current Flutter app (the backend
-- creates job rows with service_role). Keeping an entitlement-aware insert
-- policy is cheap defence-in-depth for any future client-initiated flow.
drop policy if exists goat_mode_jobs_insert on public.goat_mode_jobs;
create policy goat_mode_jobs_insert on public.goat_mode_jobs
  for insert
  with check (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. goat_user_inputs — tighten INSERT / UPDATE / DELETE
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists goat_user_inputs_insert on public.goat_user_inputs;
drop policy if exists goat_user_inputs_update on public.goat_user_inputs;
drop policy if exists goat_user_inputs_delete on public.goat_user_inputs;

create policy goat_user_inputs_insert on public.goat_user_inputs
  for insert
  with check (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );

create policy goat_user_inputs_update on public.goat_user_inputs
  for update
  using (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  )
  with check (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );

create policy goat_user_inputs_delete on public.goat_user_inputs
  for delete
  using (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. goat_goals — tighten INSERT / UPDATE / DELETE
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists goat_goals_insert on public.goat_goals;
drop policy if exists goat_goals_update on public.goat_goals;
drop policy if exists goat_goals_delete on public.goat_goals;

create policy goat_goals_insert on public.goat_goals
  for insert
  with check (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );

create policy goat_goals_update on public.goat_goals
  for update
  using (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  )
  with check (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );

create policy goat_goals_delete on public.goat_goals
  for delete
  using (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. goat_obligations — tighten INSERT / UPDATE / DELETE
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists goat_obligations_insert on public.goat_obligations;
drop policy if exists goat_obligations_update on public.goat_obligations;
drop policy if exists goat_obligations_delete on public.goat_obligations;

create policy goat_obligations_insert on public.goat_obligations
  for insert
  with check (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );

create policy goat_obligations_update on public.goat_obligations
  for update
  using (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  )
  with check (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );

create policy goat_obligations_delete on public.goat_obligations
  for delete
  using (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. goat_mode_recommendations — tighten UPDATE (only client-write surface)
-- ─────────────────────────────────────────────────────────────────────────────
-- INSERT and DELETE on goat_mode_recommendations have no client policy by
-- design (backend-only). UPDATE is the only mutation that flows through the
-- Flutter client (dismiss / snooze / resolve). Gate it on entitlement too.
drop policy if exists goat_mode_recommendations_update on public.goat_mode_recommendations;
create policy goat_mode_recommendations_update on public.goat_mode_recommendations
  for update
  using (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  )
  with check (
    auth.uid() = user_id
    and public.goat_mode_enabled_for(auth.uid())
  );


-- ═══════════════════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run manually if needed)
-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Confirm the helper function exists and is SECURITY DEFINER:
--      select proname, prosecdef from pg_proc
--      where proname = 'goat_mode_enabled_for';
--
-- 2. Inspect the tightened policies:
--      select schemaname, tablename, policyname, cmd, qual, with_check
--      from pg_policies
--      where tablename in (
--        'goat_mode_jobs','goat_user_inputs','goat_goals',
--        'goat_obligations','goat_mode_recommendations'
--      )
--      order by tablename, cmd, policyname;
-- ═══════════════════════════════════════════════════════════════════════════════
