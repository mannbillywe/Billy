-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Goat Mode — SPARSE fixture                                         ║
-- ║  Persona: goat_sparse_user                                          ║
-- ║  Readiness: L1 (operational-only, no declared inputs)               ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- Purpose:
--   Goat-side setup for the SPARSE persona. The sparse persona defines the
--   "bare minimum" behaviour: no declared income, no goals, no obligations,
--   no goat_user_inputs row. This script only flips the feature flag and
--   clears any pre-existing Goat setup rows, so the L1 pathway is exercised.
--
-- Prerequisites:
--   1. The auth.users row for this persona must exist. Create it via the
--      app sign-up flow or via Supabase Studio, then paste the UUID below.
--   2. Apply the Goat Mode v1 migration first:
--        supabase db reset         (or)
--        psql -f supabase/migrations/20260423120000_goat_mode_v1.sql
--
-- Operational-data prerequisites (NOT created here — create separately when
-- you build end-to-end backend tests in Phase 2+):
--   TODO [operational seed]: 10–15 confirmed `transactions` over the last
--     14–21 days, all `type='expense'`, across 3 categories, one vendor
--     repeated twice. Use `scripts/seed_manng_data.sql` as a reference for
--     style / payment_method / extracted_data shape.
--   TODO [operational seed]: NO accounts, NO budgets, NO recurring_series,
--     NO lend_borrow_entries, NO statement_imports for this user.

DO $$
DECLARE
  -- ┌──────────────────────────────────────────────────────────────────┐
  -- │  PASTE THE auth.users UUID FOR goat_sparse_user BELOW            │
  -- └──────────────────────────────────────────────────────────────────┘
  uid uuid := '00000000-0000-0000-0000-00005pa15e01';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = uid) THEN
    RAISE EXCEPTION
      'No profile for uid=%. Create the auth user first, then rerun.', uid;
  END IF;

  RAISE NOTICE 'Seeding Goat SPARSE fixture for user: %', uid;

  -- Ensure the Goat Mode flag is ON so the app surfaces the feature.
  UPDATE public.profiles
     SET goat_mode  = true,
         updated_at = now()
   WHERE id = uid;

  -- Clean slate on Goat setup tables. Operational tables are NOT touched.
  DELETE FROM public.goat_mode_recommendations WHERE user_id = uid;
  DELETE FROM public.goat_mode_job_events      WHERE user_id = uid;
  DELETE FROM public.goat_mode_snapshots       WHERE user_id = uid;
  DELETE FROM public.goat_mode_jobs            WHERE user_id = uid;
  DELETE FROM public.goat_obligations          WHERE user_id = uid;
  DELETE FROM public.goat_goals                WHERE user_id = uid;
  DELETE FROM public.goat_user_inputs          WHERE user_id = uid;

  RAISE NOTICE 'SPARSE fixture ready. No goat_user_inputs/goals/obligations seeded.';
  RAISE NOTICE 'Expected at compute time: readiness_level=L1, coverage_score<=10.';
END $$;
