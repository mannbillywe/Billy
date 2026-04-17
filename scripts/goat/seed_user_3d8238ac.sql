-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Goat Mode — SINGLE-UUID demo seed                                        ║
-- ║  Target user: 3d8238ac-97bd-49e5-9ee7-1966447bae7c                        ║
-- ║                                                                           ║
-- ║  Purpose                                                                  ║
-- ║  -------                                                                  ║
-- ║  Populate EVERY table that Goat Mode reads (backend/app/goat/supabase_io) ║
-- ║  with a realistic 90-day dataset so that all compute layers produce       ║
-- ║  visible output when you open Goat Mode for this user.                    ║
-- ║                                                                           ║
-- ║  Readiness target: L3 (declared inputs + goals + obligations present).    ║
-- ║                                                                           ║
-- ║  What the compute layers should surface after this seed                   ║
-- ║  -----------------------------------------------------                    ║
-- ║  • Coverage ≥ 85 (all setup tables filled).                               ║
-- ║  • Budget overrun rec     — Dining ₹3,000 cap blown to ~₹4,500.           ║
-- ║  • Anomaly-review rec     — ₹24,999 Amazon spike vs baseline.             ║
-- ║  • Duplicate-cluster rec  — two Swiggy charges 5 min apart.               ║
-- ║  • Recurring-drift rec    — Netflix 649 → 749 last month.                 ║
-- ║  • Goal-shortfall rec     — Emergency fund pace off.                      ║
-- ║  • Missed-payment-risk    — EMI due-day within 3 days, low SBI balance.   ║
-- ║  • Liquidity warning      — liquid ~₹176k vs floor ₹150k.                 ║
-- ║                                                                           ║
-- ║  Prerequisites                                                            ║
-- ║  -------------                                                            ║
-- ║  1. auth.users row for this UUID already exists (user has signed up).     ║
-- ║  2. profiles row exists (auto-created by on_auth_user_created trigger).   ║
-- ║  3. Migrations applied:                                                   ║
-- ║       20260423120000_goat_mode_v1.sql                                     ║
-- ║       20260424090000_goat_mode_phase8_entitlement.sql                     ║
-- ║  4. Default categories table is populated (user_id IS NULL rows).         ║
-- ║                                                                           ║
-- ║  Run                                                                      ║
-- ║  ---                                                                      ║
-- ║  Paste into Supabase SQL Editor OR run with:                              ║
-- ║    psql "$DATABASE_URL" -f scripts/goat/seed_user_3d8238ac.sql            ║
-- ║  Idempotent — safe to re-run.                                             ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

DO $$
DECLARE
  uid            uuid := '3d8238ac-97bd-49e5-9ee7-1966447bae7c';
  today          date := current_date;

  -- Deterministic account ids so re-runs are idempotent.
  acct_hdfc      uuid := '3d8238ac-0000-4001-a001-000000000001';
  acct_sbi       uuid := '3d8238ac-0000-4001-a002-000000000002';
  acct_cc        uuid := '3d8238ac-0000-4001-a003-000000000003';
  acct_cash      uuid := '3d8238ac-0000-4001-a004-000000000004';

  -- Category lookups (defaults installed by earlier migration).
  cat_groc       uuid;
  cat_dine       uuid;
  cat_transport  uuid;
  cat_utilities  uuid;
  cat_shopping   uuid;
  cat_subs       uuid;
  cat_health     uuid;
  cat_food       uuid;
  cat_other      uuid;
BEGIN
  -- ─── 0. Guard: profile must exist ─────────────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = uid) THEN
    RAISE EXCEPTION
      'No profiles row for %. Create the auth user first (sign-up flow), then rerun.',
      uid;
  END IF;

  RAISE NOTICE '── Goat Mode demo seed ──';
  RAISE NOTICE 'user      : %', uid;
  RAISE NOTICE 'today     : %', today;

  -- ─── 1. Enable the entitlement (Phase 8 gate) ─────────────────────────────
  UPDATE public.profiles
     SET goat_mode           = true,
         preferred_currency  = COALESCE(preferred_currency, 'INR'),
         display_name        = COALESCE(display_name, 'Demo User'),
         updated_at          = now()
   WHERE id = uid;

  -- ─── 2. Wipe prior Goat + operational rows for this uid (idempotency) ────
  --   Order matters because of FKs (children before parents).
  DELETE FROM public.goat_mode_recommendations WHERE user_id = uid;
  DELETE FROM public.goat_mode_job_events      WHERE user_id = uid;
  DELETE FROM public.goat_mode_snapshots       WHERE user_id = uid;
  DELETE FROM public.goat_mode_jobs            WHERE user_id = uid;
  DELETE FROM public.goat_obligations          WHERE user_id = uid;
  DELETE FROM public.goat_goals                WHERE user_id = uid;
  DELETE FROM public.goat_user_inputs          WHERE user_id = uid;

  DELETE FROM public.transactions        WHERE user_id = uid;
  DELETE FROM public.documents           WHERE user_id = uid;
  DELETE FROM public.budgets             WHERE user_id = uid;
  DELETE FROM public.recurring_series    WHERE user_id = uid;
  DELETE FROM public.lend_borrow_entries WHERE user_id = uid;
  DELETE FROM public.accounts
    WHERE id IN (acct_hdfc, acct_sbi, acct_cc, acct_cash);

  -- ─── 3. Category id lookups ──────────────────────────────────────────────
  SELECT id INTO cat_groc      FROM public.categories
    WHERE user_id IS NULL AND name = 'Groceries'      LIMIT 1;
  SELECT id INTO cat_dine      FROM public.categories
    WHERE user_id IS NULL AND name = 'Dining'         LIMIT 1;
  SELECT id INTO cat_transport FROM public.categories
    WHERE user_id IS NULL AND name = 'Transportation' LIMIT 1;
  SELECT id INTO cat_utilities FROM public.categories
    WHERE user_id IS NULL AND name = 'Utilities'      LIMIT 1;
  SELECT id INTO cat_shopping  FROM public.categories
    WHERE user_id IS NULL AND name = 'Shopping'       LIMIT 1;
  SELECT id INTO cat_subs      FROM public.categories
    WHERE user_id IS NULL AND name = 'Subscriptions'  LIMIT 1;
  SELECT id INTO cat_health    FROM public.categories
    WHERE user_id IS NULL AND name = 'Healthcare'     LIMIT 1;
  SELECT id INTO cat_food      FROM public.categories
    WHERE user_id IS NULL AND name = 'Food & Beverage' LIMIT 1;
  SELECT id INTO cat_other     FROM public.categories
    WHERE user_id IS NULL AND name = 'Other'          LIMIT 1;

  -- Require at least the primary categories to exist.
  IF cat_groc IS NULL OR cat_dine IS NULL OR cat_transport IS NULL
     OR cat_utilities IS NULL OR cat_shopping IS NULL OR cat_subs IS NULL THEN
    RAISE EXCEPTION
      'Default categories missing. Ensure public.categories is seeded with user_id=NULL rows first.';
  END IF;

  -- ─── 4. Accounts ─────────────────────────────────────────────────────────
  INSERT INTO public.accounts
    (id, user_id, name, type, institution, currency, current_balance, is_asset)
  VALUES
    (acct_hdfc, uid, 'HDFC Savings',     'savings',     'HDFC Bank',  'INR', 132000.00, true),
    (acct_sbi,  uid, 'SBI Salary',       'checking',    'SBI',        'INR',  42000.00, true),
    (acct_cc,   uid, 'ICICI Amazon Pay', 'credit_card', 'ICICI Bank', 'INR', -18400.00, false),
    (acct_cash, uid, 'Cash',             'cash',        NULL,         'INR',   2400.00, true);

  -- ─── 5. Expense transactions — last 90 days, dates relative to today ─────
  -- Daily layer, pattern layer, anomaly layer and budget layer all need
  -- confirmed expenses with real dates to chew on. Each row below encodes
  -- the days-ago offset directly so this seed stays meaningful in any week.
  --
  -- Ordered oldest → newest for readability.
  INSERT INTO public.transactions
    (user_id, amount, currency, date, type, title, description,
     category_id, category_source, payment_method, source_type,
     effective_amount, status, account_id)
  VALUES
    -- ── > 60 days ago (pattern baseline)
    (uid, 2890.00, 'INR', today - 86, 'expense', 'BigBasket',       'Groceries',       cat_groc,      'manual', 'UPI',         'manual', 2890.00, 'confirmed', acct_hdfc),
    (uid, 1499.00, 'INR', today - 85, 'expense', 'Airtel Fiber',    'Utilities',       cat_utilities, 'manual', 'Auto-debit',  'manual', 1499.00, 'confirmed', acct_hdfc),
    (uid,  520.00, 'INR', today - 83, 'expense', 'Uber',            'Transportation',  cat_transport, 'manual', 'UPI',         'manual',  520.00, 'confirmed', acct_hdfc),
    (uid,  649.00, 'INR', today - 82, 'expense', 'Netflix',         'Subscriptions',   cat_subs,      'manual', 'Credit Card', 'manual',  649.00, 'confirmed', acct_cc),
    (uid,  725.00, 'INR', today - 80, 'expense', 'Swiggy',          'Dining',          cat_dine,      'manual', 'UPI',         'manual',  725.00, 'confirmed', acct_hdfc),
    (uid, 2100.00, 'INR', today - 78, 'expense', 'Electricity Board','Utilities',      cat_utilities, 'manual', 'UPI',         'manual', 2100.00, 'confirmed', acct_hdfc),
    (uid, 2780.00, 'INR', today - 76, 'expense', 'Reliance Fresh',  'Groceries',       cat_groc,      'manual', 'UPI',         'manual', 2780.00, 'confirmed', acct_hdfc),
    (uid, 3100.00, 'INR', today - 73, 'expense', 'Petrol Pump - HP','Transportation',  cat_transport, 'manual', 'UPI',         'manual', 3100.00, 'confirmed', acct_hdfc),
    (uid,  410.00, 'INR', today - 71, 'expense', 'Zomato',          'Dining',          cat_dine,      'manual', 'UPI',         'manual',  410.00, 'confirmed', acct_hdfc),
    (uid, 2199.00, 'INR', today - 68, 'expense', 'Myntra',          'Shopping',        cat_shopping,  'manual', 'Credit Card', 'manual', 2199.00, 'confirmed', acct_cc),
    (uid,  890.00, 'INR', today - 66, 'expense', 'Apollo Pharmacy', 'Healthcare',      cat_health,    'manual', 'UPI',         'manual',  890.00, 'confirmed', acct_hdfc),

    -- ── 30–60 days ago
    (uid, 2670.00, 'INR', today - 58, 'expense', 'BigBasket',       'Groceries',       cat_groc,      'manual', 'UPI',         'manual', 2670.00, 'confirmed', acct_hdfc),
    (uid,  598.00, 'INR', today - 56, 'expense', 'Swiggy',          'Dining',          cat_dine,      'manual', 'UPI',         'manual',  598.00, 'confirmed', acct_hdfc),
    (uid, 1499.00, 'INR', today - 55, 'expense', 'Airtel Fiber',    'Utilities',       cat_utilities, 'manual', 'Auto-debit',  'manual', 1499.00, 'confirmed', acct_hdfc),
    (uid,  345.00, 'INR', today - 54, 'expense', 'Uber',            'Transportation',  cat_transport, 'manual', 'UPI',         'manual',  345.00, 'confirmed', acct_hdfc),
    (uid,  649.00, 'INR', today - 52, 'expense', 'Netflix',         'Subscriptions',   cat_subs,      'manual', 'Credit Card', 'manual',  649.00, 'confirmed', acct_cc),
    (uid, 1980.00, 'INR', today - 49, 'expense', 'Electricity Board','Utilities',      cat_utilities, 'manual', 'UPI',         'manual', 1980.00, 'confirmed', acct_hdfc),
    (uid, 4599.00, 'INR', today - 47, 'expense', 'Amazon',          'Shopping',        cat_shopping,  'manual', 'Credit Card', 'manual', 4599.00, 'confirmed', acct_cc),
    (uid, 2920.00, 'INR', today - 44, 'expense', 'DMart',           'Groceries',       cat_groc,      'manual', 'Cash',        'manual', 2920.00, 'confirmed', acct_cash),
    (uid,  780.00, 'INR', today - 42, 'expense', 'PVR Cinemas',     'Entertainment',   cat_other,     'manual', 'UPI',         'manual',  780.00, 'confirmed', acct_hdfc),
    (uid,  412.00, 'INR', today - 40, 'expense', 'Uber',            'Transportation',  cat_transport, 'manual', 'UPI',         'manual',  412.00, 'confirmed', acct_hdfc),
    (uid, 2800.00, 'INR', today - 37, 'expense', 'Petrol Pump - HP','Transportation',  cat_transport, 'manual', 'UPI',         'manual', 2800.00, 'confirmed', acct_hdfc),
    (uid,  623.00, 'INR', today - 34, 'expense', 'Zomato',          'Dining',          cat_dine,      'manual', 'UPI',         'manual',  623.00, 'confirmed', acct_hdfc),
    (uid,  119.00, 'INR', today - 33, 'expense', 'Spotify Premium', 'Subscriptions',   cat_subs,      'manual', 'Credit Card', 'manual',  119.00, 'confirmed', acct_cc),
    (uid, 1850.00, 'INR', today - 31, 'expense', 'Electricity Board','Utilities',      cat_utilities, 'manual', 'UPI',         'manual', 1850.00, 'confirmed', acct_hdfc),

    -- ── Current month: last 30 days (this is where the alerts land)
    (uid, 3150.00, 'INR', today - 28, 'expense', 'BigBasket',       'Groceries',       cat_groc,      'manual', 'UPI',         'manual', 3150.00, 'confirmed', acct_hdfc),
    (uid, 1499.00, 'INR', today - 27, 'expense', 'Airtel Fiber',    'Utilities',       cat_utilities, 'manual', 'Auto-debit',  'manual', 1499.00, 'confirmed', acct_hdfc),
    (uid,  749.00, 'INR', today - 26, 'expense', 'Netflix',         'Subscriptions — price drift', cat_subs, 'manual', 'Credit Card', 'manual',  749.00, 'confirmed', acct_cc),
    (uid,  310.00, 'INR', today - 25, 'expense', 'Uber',            'Transportation',  cat_transport, 'manual', 'UPI',         'manual',  310.00, 'confirmed', acct_hdfc),
    (uid,  645.00, 'INR', today - 24, 'expense', 'Zomato',          'Dining',          cat_dine,      'manual', 'UPI',         'manual',  645.00, 'confirmed', acct_hdfc),
    (uid, 2199.00, 'INR', today - 22, 'expense', 'Amazon',          'Shopping',        cat_shopping,  'manual', 'Credit Card', 'manual', 2199.00, 'confirmed', acct_cc),
    (uid,  920.00, 'INR', today - 21, 'expense', 'Swiggy',          'Dining',          cat_dine,      'manual', 'UPI',         'manual',  920.00, 'confirmed', acct_hdfc),
    (uid, 2900.00, 'INR', today - 19, 'expense', 'Petrol Pump - HP','Transportation',  cat_transport, 'manual', 'UPI',         'manual', 2900.00, 'confirmed', acct_hdfc),
    (uid,  220.00, 'INR', today - 18, 'expense', 'Chai Point',      'Food & Beverage', cat_food,      'manual', 'Cash',        'manual',  220.00, 'confirmed', acct_cash),
    (uid,  410.00, 'INR', today - 16, 'expense', 'Starbucks',       'Food & Beverage', cat_food,      'manual', 'UPI',         'manual',  410.00, 'confirmed', acct_hdfc),
    (uid, 1260.00, 'INR', today - 15, 'expense', 'Zomato',          'Dining',          cat_dine,      'manual', 'UPI',         'manual', 1260.00, 'confirmed', acct_hdfc),
    (uid, 2980.00, 'INR', today - 13, 'expense', 'BigBasket',       'Groceries',       cat_groc,      'manual', 'UPI',         'manual', 2980.00, 'confirmed', acct_hdfc),
    (uid, 2050.00, 'INR', today - 12, 'expense', 'Electricity Board','Utilities',      cat_utilities, 'manual', 'UPI',         'manual', 2050.00, 'confirmed', acct_hdfc),

    -- Anomaly — shopping spike (≈6× the 30-day mean)
    (uid,24999.00, 'INR', today - 10, 'expense', 'Amazon',          'Shopping — spike', cat_shopping, 'manual', 'Credit Card', 'manual',24999.00, 'confirmed', acct_cc),

    -- Duplicate-cluster — same vendor, same day, suspiciously close amounts
    (uid,  399.00, 'INR', today -  9, 'expense', 'Swiggy',          'Dining — dup A',  cat_dine,      'manual', 'UPI',         'manual',  399.00, 'confirmed', acct_hdfc),
    (uid,  401.00, 'INR', today -  9, 'expense', 'Swiggy',          'Dining — dup B',  cat_dine,      'manual', 'UPI',         'manual',  401.00, 'confirmed', acct_hdfc),

    (uid,  340.00, 'INR', today -  7, 'expense', 'Uber',            'Transportation',  cat_transport, 'manual', 'UPI',         'manual',  340.00, 'confirmed', acct_hdfc),
    (uid, 1100.00, 'INR', today -  6, 'expense', 'Apollo Pharmacy', 'Healthcare',      cat_health,    'manual', 'UPI',         'manual', 1100.00, 'confirmed', acct_hdfc),

    -- Dining budget push (budget cap 3k, we now land ~4.5k this month)
    (uid,  840.00, 'INR', today -  5, 'expense', 'Zomato',          'Dining',          cat_dine,      'manual', 'UPI',         'manual',  840.00, 'confirmed', acct_hdfc),
    (uid,  675.00, 'INR', today -  3, 'expense', 'Swiggy',          'Dining',          cat_dine,      'manual', 'UPI',         'manual',  675.00, 'confirmed', acct_hdfc),

    (uid, 2450.00, 'INR', today -  2, 'expense', 'DMart',           'Groceries',       cat_groc,      'manual', 'Cash',        'manual', 2450.00, 'confirmed', acct_cash),
    (uid,  520.00, 'INR', today -  1, 'expense', 'Rapido',          'Transportation',  cat_transport, 'manual', 'UPI',         'manual',  520.00, 'confirmed', acct_hdfc),
    (uid,  895.00, 'INR', today     , 'expense', 'Zomato',          'Dining',          cat_dine,      'manual', 'UPI',         'manual',  895.00, 'confirmed', acct_hdfc);

  -- ─── 6. Salary income (so the cashflow forecast has an inflow signal) ────
  INSERT INTO public.transactions
    (user_id, amount, currency, date, type, title, description,
     source_type, effective_amount, status, account_id)
  VALUES
    (uid, 90000.00, 'INR', today - 92, 'income', 'Salary', 'Monthly salary', 'manual', 90000.00, 'confirmed', acct_sbi),
    (uid, 90000.00, 'INR', today - 62, 'income', 'Salary', 'Monthly salary', 'manual', 90000.00, 'confirmed', acct_sbi),
    (uid, 90000.00, 'INR', today - 31, 'income', 'Salary', 'Monthly salary', 'manual', 90000.00, 'confirmed', acct_sbi);

  -- ─── 7. Budgets (Dining is intentionally too small — triggers rec) ───────
  INSERT INTO public.budgets
    (user_id, name, category_id, amount, period, currency, is_active, start_date)
  VALUES
    (uid, 'Groceries',      cat_groc,      8000.00,  'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Dining',         cat_dine,      3000.00,  'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Transportation', cat_transport, 5000.00,  'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Shopping',       cat_shopping, 10000.00,  'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Subscriptions',  cat_subs,      2000.00,  'monthly', 'INR', true, date_trunc('month', today)::date);

  -- ─── 8. Recurring series (drift signal for Netflix) ──────────────────────
  INSERT INTO public.recurring_series
    (user_id, title, amount, currency, category_id, cadence,
     anchor_date, next_due, detection_source, is_active)
  VALUES
    (uid, 'Netflix',      649.00, 'INR', cat_subs,      'monthly', today - 82, today +  4, 'manual', true),
    (uid, 'Airtel Fiber',1499.00, 'INR', cat_utilities, 'monthly', today - 85, today +  5, 'manual', true),
    (uid, 'Spotify',      119.00, 'INR', cat_subs,      'monthly', today - 33, today + 26, 'manual', true),
    (uid, 'Electricity', 2000.00, 'INR', cat_utilities, 'monthly', today - 78, today + 17, 'manual', true);

  -- ─── 9. Lend / borrow ledger ─────────────────────────────────────────────
  INSERT INTO public.lend_borrow_entries
    (user_id, counterparty_name, amount, type, status, due_date, notes)
  VALUES
    (uid, 'Rahul',  5000.00, 'lent',     'pending', today + 12, 'Weekend trip split'),
    (uid, 'Vikram', 8000.00, 'borrowed', 'pending', today +  8, 'Covered rent gap');

  -- ─── 10. Declared Goat setup inputs (readiness: L3) ──────────────────────
  INSERT INTO public.goat_user_inputs (
    user_id, monthly_income, income_currency, pay_frequency, salary_day,
    emergency_fund_target_months, liquidity_floor, household_size, dependents,
    risk_tolerance, planning_horizon_months, tone_preference, notes
  ) VALUES (
    uid, 90000.00, 'INR', 'monthly', 1,
    6.0, 150000.00, 2, 1,
    'balanced', 12, 'direct',
    jsonb_build_object(
      'seeded_by',   'seed_user_3d8238ac.sql',
      'seeded_on',   to_char(now(), 'YYYY-MM-DD'),
      'readiness',   'L3'
    )
  );

  -- ─── 11. Goals (emergency fund is intentionally behind pace) ─────────────
  INSERT INTO public.goat_goals
    (user_id, goal_type, title, target_amount, current_amount,
     target_date, priority, status, metadata)
  VALUES
    (uid, 'emergency_fund', 'Emergency Fund (6 months)',
     540000.00,  80000.00, today + 180, 1, 'active',
     '{"source":"seed"}'::jsonb),
    (uid, 'savings', 'Vacation — Goa Dec',
      75000.00,  22000.00, today + 240, 3, 'active',
     '{"source":"seed"}'::jsonb),
    (uid, 'debt_payoff', 'Clear credit-card revolve',
      20000.00,   5000.00, today +  90, 2, 'active',
     '{"source":"seed"}'::jsonb);

  -- ─── 12. Obligations (EMI + rent — one due-day is close to today) ────────
  INSERT INTO public.goat_obligations
    (user_id, obligation_type, lender_name, current_outstanding,
     monthly_due, due_day, interest_rate, cadence, status, metadata)
  VALUES
    -- due_day anchored 2 days ahead of today so missed-payment-risk fires predictably.
    (uid, 'emi',    'HDFC Personal Loan',  280000.00,  9500.00,  extract(day from (today + 2))::int,  11.25, 'monthly', 'active', '{"source":"seed"}'::jsonb),
    (uid, 'rent',   'Landlord',                 NULL, 24000.00,  5,  NULL,  'monthly', 'active', '{"source":"seed"}'::jsonb),
    (uid, 'credit_card_min', 'ICICI Amazon Pay', 18400.00,  1840.00, 12,  38.00, 'monthly', 'active', '{"source":"seed"}'::jsonb);

  -- ─── 13. Summary ────────────────────────────────────────────────────────
  RAISE NOTICE 'accounts          : %', (SELECT count(*) FROM public.accounts          WHERE user_id = uid);
  RAISE NOTICE 'transactions      : %', (SELECT count(*) FROM public.transactions      WHERE user_id = uid);
  RAISE NOTICE '  expenses 30d    : %', (SELECT count(*) FROM public.transactions
                                          WHERE user_id = uid AND type = 'expense'
                                            AND date >= today - 30);
  RAISE NOTICE 'budgets           : %', (SELECT count(*) FROM public.budgets           WHERE user_id = uid);
  RAISE NOTICE 'recurring_series  : %', (SELECT count(*) FROM public.recurring_series  WHERE user_id = uid);
  RAISE NOTICE 'lend_borrow       : %', (SELECT count(*) FROM public.lend_borrow_entries WHERE user_id = uid);
  RAISE NOTICE 'goat_user_inputs  : %', (SELECT count(*) FROM public.goat_user_inputs  WHERE user_id = uid);
  RAISE NOTICE 'goat_goals        : %', (SELECT count(*) FROM public.goat_goals        WHERE user_id = uid);
  RAISE NOTICE 'goat_obligations  : %', (SELECT count(*) FROM public.goat_obligations  WHERE user_id = uid);
  RAISE NOTICE '── Seed complete. Open Goat Mode for this user to trigger a run. ──';
END $$;
