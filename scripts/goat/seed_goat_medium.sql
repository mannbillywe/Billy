-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Goat Mode — MEDIUM fixture                                         ║
-- ║  Persona: goat_medium_user                                          ║
-- ║  Readiness: L2 (operational + declared setup)                       ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- Purpose:
--   Goat-side setup for the MEDIUM persona. Seeds a complete goat_user_inputs
--   row plus one emergency-fund goat_goal. Operational seed rows
--   (transactions / accounts / budgets / recurring / lend_borrow) are NOT
--   created here — see TODO comments.
--
-- Prerequisites:
--   1. auth.users row exists for this persona (paste UUID below).
--   2. Goat Mode v1 migration applied.
--
-- Operational-data prerequisites (to be satisfied in Phase 2+ backend tests):
--   TODO [operational seed]: 180 days of `transactions` (~220 rows) with
--     one recurring monthly income of ₹65,000 and a realistic mix of
--     expense categories. Pattern should mimic `scripts/seed_manng_data.sql`.
--   TODO [operational seed]: 2 `accounts` — one savings (e.g. ₹120,000) and
--     one credit_card (e.g. ₹-8,500). `updated_at` within last 7 days.
--   TODO [operational seed]: 2 `budgets` + their current + 2 previous
--     `budget_periods`, with Food monthly ₹8,000 showing a mild overrun
--     pattern (108–112 %) so that budget-overrun logic has signal.
--   TODO [operational seed]: 1 `recurring_series` (e.g. OTT ₹499/monthly)
--     with 4 confirmed `recurring_occurrences`.
--   TODO [operational seed]: 2 `lend_borrow_entries` (one pending, one settled).

DO $$
DECLARE
  -- ┌──────────────────────────────────────────────────────────────────┐
  -- │  PASTE THE auth.users UUID FOR goat_medium_user BELOW            │
  -- └──────────────────────────────────────────────────────────────────┘
  uid uuid := '00000000-0000-0000-0000-0000med10002';

  -- Stable id for the emergency-fund goal so re-runs are idempotent.
  goal_ef_id uuid := '00000000-0000-0000-0000-0000med1900a1';

  -- Try to attach the goal to a savings account if one already exists.
  savings_acc uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = uid) THEN
    RAISE EXCEPTION
      'No profile for uid=%. Create the auth user first, then rerun.', uid;
  END IF;

  RAISE NOTICE 'Seeding Goat MEDIUM fixture for user: %', uid;

  -- Feature flag on.
  UPDATE public.profiles
     SET goat_mode  = true,
         updated_at = now()
   WHERE id = uid;

  -- Clean any prior Goat rows for this user (idempotent re-run).
  DELETE FROM public.goat_mode_recommendations WHERE user_id = uid;
  DELETE FROM public.goat_mode_job_events      WHERE user_id = uid;
  DELETE FROM public.goat_mode_snapshots       WHERE user_id = uid;
  DELETE FROM public.goat_mode_jobs            WHERE user_id = uid;
  DELETE FROM public.goat_obligations          WHERE user_id = uid;
  DELETE FROM public.goat_goals                WHERE user_id = uid;
  DELETE FROM public.goat_user_inputs          WHERE user_id = uid;

  -- ─── goat_user_inputs (L2 complete) ─────────────────────────────────
  INSERT INTO public.goat_user_inputs (
    user_id,
    monthly_income,
    income_currency,
    pay_frequency,
    salary_day,
    emergency_fund_target_months,
    liquidity_floor,
    household_size,
    dependents,
    risk_tolerance,
    planning_horizon_months,
    tone_preference,
    notes
  ) VALUES (
    uid,
    65000.00,
    'INR',
    'monthly',
    1,
    3,
    5000.00,
    2,
    0,
    'balanced',
    6,
    'calm',
    '{"seed":"medium","source":"scripts/goat/seed_goat_medium.sql"}'::jsonb
  );

  -- ─── goat_goals: emergency fund @ ₹150k, current ₹45k ──────────────
  -- Attach to an existing savings account if one exists; otherwise leave null.
  SELECT id INTO savings_acc
    FROM public.accounts
   WHERE user_id = uid AND type = 'savings' AND is_active = true
   ORDER BY created_at
   LIMIT 1;

  INSERT INTO public.goat_goals (
    id, user_id, goal_type, title,
    target_amount, current_amount, target_date,
    priority, status, linked_account_id, metadata
  ) VALUES (
    goal_ef_id,
    uid,
    'emergency_fund',
    'Emergency fund — 3 months',
    150000.00,
    45000.00,
    (current_date + interval '10 months')::date,
    1,
    'active',
    savings_acc,
    '{"seed":"medium"}'::jsonb
  );

  RAISE NOTICE 'MEDIUM fixture ready. goat_user_inputs row + 1 emergency-fund goal seeded.';
  RAISE NOTICE 'Expected at compute time: readiness_level=L2, coverage_score~60 once operational TODOs are seeded.';
END $$;
