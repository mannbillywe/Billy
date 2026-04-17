-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Goat Mode — RICH fixture                                           ║
-- ║  Persona: goat_rich_user                                            ║
-- ║  Readiness: L3 (operational + setup + long history + uploads)       ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- Purpose:
--   Goat-side setup for the RICH persona. Seeds a full goat_user_inputs row,
--   three goat_goals, and two goat_obligations. Operational seed rows are
--   NOT created here — the rich persona depends on a long operational
--   history that we will reuse from `scripts/seed_manng_data.sql` style
--   scripts in Phase 2+.
--
-- Prerequisites:
--   1. auth.users row exists for this persona (paste UUID below).
--   2. Goat Mode v1 migration applied.
--
-- Operational-data prerequisites (satisfied in Phase 2+):
--   TODO [operational seed]: 12 months of `transactions` (~1,200 rows) with
--     one regular payroll income stream + 2 occasional incomes; at least
--     9 categories; plausible seasonality (Dec/Jan spike).
--   TODO [operational seed]: 4 `accounts` — 2 savings, 1 checking,
--     1 credit_card — with fresh current balances AND a synthetic monthly
--     history (for balance-trend tests).
--   TODO [operational seed]: 5 `budgets` (Food, Transport, Entertainment,
--     Utilities, Shopping) + at least 3 prior `budget_periods` each.
--   TODO [operational seed]: 4 `recurring_series` + 1 pending
--     `recurring_suggestion` + 1 amount-drift event.
--   TODO [operational seed]: 4 `lend_borrow_entries` (2 pending, 1 overdue,
--     1 settled).
--   TODO [operational seed]: 3 `statement_imports` with ~120 rows each;
--     2 disputes open.

DO $$
DECLARE
  -- ┌──────────────────────────────────────────────────────────────────┐
  -- │  PASTE THE auth.users UUID FOR goat_rich_user BELOW              │
  -- └──────────────────────────────────────────────────────────────────┘
  uid uuid := '00000000-0000-0000-0000-00005r1c1003';

  -- Stable ids so re-runs stay idempotent.
  goal_ef_id       uuid := '00000000-0000-0000-0000-00005r1c9001';
  goal_vac_id      uuid := '00000000-0000-0000-0000-00005r1c9002';
  goal_laptop_id   uuid := '00000000-0000-0000-0000-00005r1c9003';
  ob_emi_id        uuid := '00000000-0000-0000-0000-00005r1cb001';
  ob_ccmin_id      uuid := '00000000-0000-0000-0000-00005r1cb002';

  savings_acc uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = uid) THEN
    RAISE EXCEPTION
      'No profile for uid=%. Create the auth user first, then rerun.', uid;
  END IF;

  RAISE NOTICE 'Seeding Goat RICH fixture for user: %', uid;

  UPDATE public.profiles
     SET goat_mode  = true,
         updated_at = now()
   WHERE id = uid;

  -- Idempotent reset of Goat rows for this user.
  DELETE FROM public.goat_mode_recommendations WHERE user_id = uid;
  DELETE FROM public.goat_mode_job_events      WHERE user_id = uid;
  DELETE FROM public.goat_mode_snapshots       WHERE user_id = uid;
  DELETE FROM public.goat_mode_jobs            WHERE user_id = uid;
  DELETE FROM public.goat_obligations          WHERE user_id = uid;
  DELETE FROM public.goat_goals                WHERE user_id = uid;
  DELETE FROM public.goat_user_inputs          WHERE user_id = uid;

  -- ─── goat_user_inputs (full L2 declarations) ────────────────────────
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
    145000.00,
    'INR',
    'monthly',
    1,
    6,
    15000.00,
    3,
    1,
    'balanced',
    12,
    'direct',
    '{"seed":"rich","source":"scripts/goat/seed_goat_rich.sql"}'::jsonb
  );

  -- ─── goat_goals × 3 ─────────────────────────────────────────────────
  SELECT id INTO savings_acc
    FROM public.accounts
   WHERE user_id = uid AND type = 'savings' AND is_active = true
   ORDER BY created_at
   LIMIT 1;

  INSERT INTO public.goat_goals (
    id, user_id, goal_type, title,
    target_amount, current_amount, target_date,
    priority, status, linked_account_id, metadata
  ) VALUES
    (goal_ef_id,     uid, 'emergency_fund', 'Emergency fund — 6 months',
     870000.00, 420000.00, (current_date + interval '14 months')::date,
     1, 'active', savings_acc, '{"seed":"rich"}'::jsonb),
    (goal_vac_id,    uid, 'travel',         'Japan trip',
     250000.00,  90000.00, (current_date + interval '9 months')::date,
     3, 'active', NULL, '{"seed":"rich"}'::jsonb),
    (goal_laptop_id, uid, 'purchase',       'New MacBook',
     180000.00,  25000.00, (current_date + interval '6 months')::date,
     4, 'active', NULL, '{"seed":"rich"}'::jsonb);

  -- ─── goat_obligations × 2 ───────────────────────────────────────────
  INSERT INTO public.goat_obligations (
    id, user_id, obligation_type, lender_name,
    current_outstanding, monthly_due, due_day, interest_rate,
    cadence, status, metadata
  ) VALUES
    (ob_emi_id,   uid, 'emi',              'HDFC Auto Loan',
     450000.00, 18500.00, 5, 9.250, 'monthly', 'active',
     '{"seed":"rich","note":"auto loan"}'::jsonb),
    (ob_ccmin_id, uid, 'credit_card_min',  'Amazon Pay ICICI',
      12450.00,   625.00, 23, 41.880, 'monthly', 'active',
     '{"seed":"rich","note":"credit card minimum"}'::jsonb);

  RAISE NOTICE 'RICH fixture ready. goat_user_inputs row + 3 goals + 2 obligations seeded.';
  RAISE NOTICE 'Expected at compute time (after operational TODOs seeded): readiness_level=L3, coverage_score>=85.';
END $$;
