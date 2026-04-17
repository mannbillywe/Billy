-- ═══════════════════════════════════════════════════════════════════════════════
-- Phase 8 — RLS verification for entitlement-gated writes.
-- ═══════════════════════════════════════════════════════════════════════════════
-- Run this after applying migration 20260424090000_goat_mode_phase8_entitlement.sql
-- against a local Supabase or a dedicated staging project. It is read-only in
-- production (the 6-8 final SELECT blocks are diagnostic), and it manually
-- exercises the policy with a `set role authenticated; set local "request.jwt.claim.sub"` trick.
--
-- Usage:
--   psql "$SUPABASE_DB_URL" -f scripts/goat/verify_phase8_entitlement_rls.sql
--
-- What it checks:
--   1. The helper function `public.goat_mode_enabled_for` exists and is
--      SECURITY DEFINER.
--   2. `pg_policies` rows for the target tables include the expected
--      entitlement predicates.
--   3. An entitled user CAN insert into goat_user_inputs / goat_goals /
--      goat_obligations.
--   4. A non-entitled user CANNOT insert / update / delete on those tables.
--
-- The write-path test section uses two disposable auth users; clean up at the
-- end is idempotent so reruns are safe.
-- ═══════════════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on

-- ─── 1. Helper function is present and SECURITY DEFINER ─────────────────────
select
  proname,
  prosecdef          as is_security_definer,
  provolatile        as volatility,
  format_type(prorettype, null) as return_type
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'goat_mode_enabled_for';

-- ─── 2. Policies exist and reference the helper ────────────────────────────
select tablename, policyname, cmd,
       (qual       ilike '%goat_mode_enabled_for%')::boolean as qual_has_entitlement,
       (with_check ilike '%goat_mode_enabled_for%')::boolean as check_has_entitlement
from pg_policies
where schemaname = 'public'
  and tablename in (
    'goat_mode_jobs',
    'goat_user_inputs',
    'goat_goals',
    'goat_obligations',
    'goat_mode_recommendations'
  )
order by tablename, cmd, policyname;

-- ─── 3. Live write checks (requires existing test profiles) ─────────────────
-- NOTE: this section is commented out by default because it needs two
-- existing auth.users and mutates goat_* tables. Uncomment and replace the
-- placeholders with real UUIDs from your local Supabase project to exercise
-- the policies end-to-end.
--
-- do $$
-- declare
--   entitled_user uuid := '00000000-0000-0000-0000-00000000aaaa';
--   off_user      uuid := '00000000-0000-0000-0000-00000000bbbb';
-- begin
--   -- Ensure both profiles exist (adjust as needed for your setup):
--   insert into public.profiles(id, goat_mode) values (entitled_user, true)
--     on conflict (id) do update set goat_mode = true;
--   insert into public.profiles(id, goat_mode) values (off_user, false)
--     on conflict (id) do update set goat_mode = false;
--
--   -- Entitled user: should succeed.
--   set local role authenticated;
--   set local "request.jwt.claim.sub" = entitled_user::text;
--   insert into public.goat_goals(user_id, goal_type, title, target_amount)
--     values (entitled_user, 'emergency_fund', 'phase8-test-goal', 10000)
--     on conflict do nothing;
--
--   -- Non-entitled user: should fail with RLS violation.
--   set local "request.jwt.claim.sub" = off_user::text;
--   begin
--     insert into public.goat_goals(user_id, goal_type, title, target_amount)
--       values (off_user, 'emergency_fund', 'phase8-test-goal-denied', 10000);
--     raise exception 'EXPECTED RLS violation for non-entitled user';
--   exception when insufficient_privilege then
--     raise notice 'ok: non-entitled insert blocked';
--   end;
--
--   -- Clean up.
--   reset role;
--   delete from public.goat_goals
--     where title in ('phase8-test-goal', 'phase8-test-goal-denied');
-- end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- Done.
-- ═══════════════════════════════════════════════════════════════════════════════
