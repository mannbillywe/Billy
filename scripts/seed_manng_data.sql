-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Billy — FULL RESET + 12-month daily seed for user Nitin                ║
-- ║  Target user: f308f807-00eb-46ce-9468-63cd7c8d3c0f                      ║
-- ║                                                                          ║
-- ║  What this does                                                          ║
-- ║  --------------                                                          ║
-- ║  1. WIPES every row that belongs to the target user across every table  ║
-- ║     the app and Goat Mode read/write (transactions, documents, budgets, ║
-- ║     recurring_series, lend_borrow_entries, activity_events, accounts,   ║
-- ║     goat_* tables). Other users are untouched.                          ║
-- ║  2. Ensures default categories exist (no-op if already present).        ║
-- ║  3. Seeds 5 accounts, 12 months of salary, and 365 days of expenses     ║
-- ║     (5-10 realistic transactions per day, drawn from a vendor pool).    ║
-- ║  4. Mirrors every expense into public.documents so the pre-Goat UI      ║
-- ║     (dashboard cards, analytics totals, 7d/1W/1M/3M trend, category     ║
-- ║     pie, savings tips) has data to render.                              ║
-- ║  5. Seeds budgets, recurring_series, lend_borrow, goals, obligations,   ║
-- ║     goat_user_inputs so Goat Mode reaches readiness L3.                 ║
-- ║                                                                          ║
-- ║  Run                                                                     ║
-- ║  ---                                                                     ║
-- ║  Paste into Supabase SQL Editor (service-role session), or              ║
-- ║    psql "$DATABASE_URL" -f scripts/seed_manng_data.sql                  ║
-- ║  Re-runnable — wipes-then-reseeds the target user every time.           ║
-- ║                                                                          ║
-- ║  !! DESTRUCTIVE FOR THE TARGET USER ONLY !!                             ║
-- ║  ------------------------------------------                             ║
-- ║  Do NOT run against a user whose real history you want to keep.         ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DO $$
DECLARE
  uid           uuid := 'f308f807-00eb-46ce-9468-63cd7c8d3c0f';
  today         date := current_date;
  start_d       date := current_date - 364;   -- 365 days inclusive
  d             date;
  txn_count     int;
  i             int;
  pick          int;
  mo            int;          -- month index 0..11 (oldest .. newest) for salary

  -- Deterministic account ids so re-runs map payments cleanly.
  acct_hdfc     uuid := 'a0f30880-0000-4001-a001-000000000001';
  acct_sbi      uuid := 'a0f30880-0000-4001-a002-000000000002';
  acct_cc       uuid := 'a0f30880-0000-4001-a003-000000000003';
  acct_cash     uuid := 'a0f30880-0000-4001-a004-000000000004';
  acct_mf       uuid := 'a0f30880-0000-4001-a005-000000000005';

  -- Category ids (resolved below from defaults).
  cat_groc      uuid;
  cat_dine      uuid;
  cat_trans     uuid;
  cat_util      uuid;
  cat_shop      uuid;
  cat_subs      uuid;
  cat_health    uuid;
  cat_food      uuid;
  cat_ent       uuid;
  cat_other     uuid;

  -- Parallel vendor arrays: vendors[i] ∈ cats[i] with amount ∈ [lo[i], hi[i]].
  vendors       text[];
  cats          uuid[];
  pays          text[];          -- payment method per vendor
  accts         uuid[];          -- account per vendor (follows pay method)
  lo            int[];
  hi            int[];

  vendor_name   text;
  vendor_cat    uuid;
  vendor_pay    text;
  vendor_acct   uuid;
  vendor_amt    numeric(12,2);

  salary_amt    numeric(12,2);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = uid) THEN
    RAISE EXCEPTION
      'No profiles row for %. Sign the user up first, then rerun.', uid;
  END IF;

  -- Deterministic "random" so every run of this script produces the same
  -- shape. Comment this out for real variability.
  PERFORM setseed(0.42);

  RAISE NOTICE '── Billy seed: full wipe + 12m daily for % ──', uid;
  RAISE NOTICE 'date range        : % .. %', start_d, today;

  -- ─── 0. Profile flags ────────────────────────────────────────────────────
  UPDATE public.profiles
     SET display_name       = COALESCE(display_name, 'Nitin'),
         preferred_currency = COALESCE(preferred_currency, 'INR'),
         goat_mode          = true,
         updated_at         = now()
   WHERE id = uid;

  -- ─── 1. WIPE every user-owned row (FK-safe order) ────────────────────────
  DELETE FROM public.goat_mode_recommendations WHERE user_id = uid;
  DELETE FROM public.goat_mode_job_events      WHERE user_id = uid;
  DELETE FROM public.goat_mode_snapshots       WHERE user_id = uid;
  DELETE FROM public.goat_mode_jobs            WHERE user_id = uid;
  DELETE FROM public.goat_obligations          WHERE user_id = uid;
  DELETE FROM public.goat_goals                WHERE user_id = uid;
  DELETE FROM public.goat_user_inputs          WHERE user_id = uid;

  DELETE FROM public.activity_events           WHERE user_id = uid;
  DELETE FROM public.transactions              WHERE user_id = uid;
  DELETE FROM public.documents                 WHERE user_id = uid;
  DELETE FROM public.budgets                   WHERE user_id = uid;
  DELETE FROM public.recurring_series          WHERE user_id = uid;
  DELETE FROM public.lend_borrow_entries       WHERE user_id = uid;
  DELETE FROM public.accounts                  WHERE user_id = uid;

  -- ─── 2. Default categories (idempotent) ──────────────────────────────────
  INSERT INTO public.categories (id, user_id, name, icon, color, is_default)
  SELECT gen_random_uuid(), NULL, c.name, c.icon, c.color, true
  FROM (VALUES
    ('Food & Beverage', '🍔', '#F97316'),
    ('Dining',          '🍽️', '#EF4444'),
    ('Groceries',       '🛒', '#22C55E'),
    ('Transportation',  '🚕', '#3B82F6'),
    ('Shopping',        '🛍️', '#EC4899'),
    ('Utilities',       '⚡', '#F59E0B'),
    ('Entertainment',   '🎬', '#8B5CF6'),
    ('Healthcare',      '🏥', '#EF4444'),
    ('Education',       '📚', '#06B6D4'),
    ('Housing',         '🏠', '#8B5CF6'),
    ('Subscriptions',   '📱', '#10B981'),
    ('Maintenance',     '🔧', '#6B7280'),
    ('Stationery',      '✏️', '#A855F7'),
    ('Equipment',       '💻', '#0EA5E9'),
    ('Borrow',          '📥', '#EF4444'),
    ('Lend',            '📤', '#06B6D4'),
    ('Other',           '📦', '#6B7280')
  ) c(name, icon, color)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.categories x
    WHERE x.user_id IS NULL AND x.name = c.name
  );

  -- Resolve category ids.
  SELECT id INTO cat_groc   FROM public.categories WHERE user_id IS NULL AND name='Groceries'       LIMIT 1;
  SELECT id INTO cat_dine   FROM public.categories WHERE user_id IS NULL AND name='Dining'          LIMIT 1;
  SELECT id INTO cat_trans  FROM public.categories WHERE user_id IS NULL AND name='Transportation'  LIMIT 1;
  SELECT id INTO cat_util   FROM public.categories WHERE user_id IS NULL AND name='Utilities'       LIMIT 1;
  SELECT id INTO cat_shop   FROM public.categories WHERE user_id IS NULL AND name='Shopping'        LIMIT 1;
  SELECT id INTO cat_subs   FROM public.categories WHERE user_id IS NULL AND name='Subscriptions'   LIMIT 1;
  SELECT id INTO cat_health FROM public.categories WHERE user_id IS NULL AND name='Healthcare'      LIMIT 1;
  SELECT id INTO cat_food   FROM public.categories WHERE user_id IS NULL AND name='Food & Beverage' LIMIT 1;
  SELECT id INTO cat_ent    FROM public.categories WHERE user_id IS NULL AND name='Entertainment'   LIMIT 1;
  SELECT id INTO cat_other  FROM public.categories WHERE user_id IS NULL AND name='Other'           LIMIT 1;

  -- ─── 3. Accounts (known ids; FK targets for transactions below) ──────────
  INSERT INTO public.accounts
    (id, user_id, name, type, institution, currency, current_balance, is_asset)
  VALUES
    (acct_hdfc, uid, 'HDFC Savings',     'savings',     'HDFC Bank',  'INR', 245800.00, true),
    (acct_sbi,  uid, 'SBI Salary',       'checking',    'SBI',        'INR',  58320.00, true),
    (acct_cc,   uid, 'ICICI Amazon Pay', 'credit_card', 'ICICI Bank', 'INR', -12450.00, false),
    (acct_cash, uid, 'Cash',             'cash',        NULL,         'INR',   3200.00, true),
    (acct_mf,   uid, 'Groww MF',         'investment',  'Groww',      'INR', 125000.00, true);

  -- ─── 4. Vendor pool (index-aligned arrays) ───────────────────────────────
  vendors := ARRAY[
    -- Groceries (0-4)
    'BigBasket','DMart','Reliance Fresh','Spencer''s','More Supermarket',
    -- Dining (5-10)
    'Swiggy','Zomato','Dominos','KFC','McDonald''s','Haldiram',
    -- Transportation (11-16)
    'Uber','Ola','Rapido','Petrol Pump - HP','Indian Oil','Metro Card',
    -- Utilities (17-21)
    'Airtel Fiber','Jio Fiber','Electricity Board','BESCOM','Gas Bill',
    -- Shopping (22-26)
    'Amazon','Flipkart','Myntra','Ajio','Decathlon',
    -- Subscriptions (27-31)
    'Netflix','Spotify Premium','Prime Video','Hotstar','YouTube Premium',
    -- Healthcare (32-34)
    'Apollo Pharmacy','MedPlus','PharmEasy',
    -- Food & Beverage (35-38)
    'Chai Point','Starbucks','Cafe Coffee Day','Third Wave Coffee',
    -- Entertainment (39-41)
    'PVR Cinemas','INOX','BookMyShow'
  ];
  cats := ARRAY[
    cat_groc, cat_groc, cat_groc, cat_groc, cat_groc,
    cat_dine, cat_dine, cat_dine, cat_dine, cat_dine, cat_dine,
    cat_trans, cat_trans, cat_trans, cat_trans, cat_trans, cat_trans,
    cat_util, cat_util, cat_util, cat_util, cat_util,
    cat_shop, cat_shop, cat_shop, cat_shop, cat_shop,
    cat_subs, cat_subs, cat_subs, cat_subs, cat_subs,
    cat_health, cat_health, cat_health,
    cat_food, cat_food, cat_food, cat_food,
    cat_ent, cat_ent, cat_ent
  ];
  pays := ARRAY[
    'UPI','Cash','UPI','Cash','UPI',
    'UPI','UPI','UPI','UPI','Cash','Cash',
    'UPI','UPI','UPI','UPI','UPI','UPI',
    'Auto-debit','Auto-debit','UPI','UPI','Cash',
    'Credit Card','Credit Card','Credit Card','Credit Card','Credit Card',
    'Credit Card','Credit Card','Credit Card','Credit Card','Credit Card',
    'UPI','UPI','UPI',
    'Cash','UPI','UPI','UPI',
    'UPI','UPI','UPI'
  ];
  accts := ARRAY[
    acct_hdfc, acct_cash, acct_hdfc, acct_cash, acct_hdfc,
    acct_hdfc, acct_hdfc, acct_hdfc, acct_hdfc, acct_cash, acct_cash,
    acct_hdfc, acct_hdfc, acct_hdfc, acct_hdfc, acct_hdfc, acct_hdfc,
    acct_hdfc, acct_hdfc, acct_hdfc, acct_hdfc, acct_cash,
    acct_cc, acct_cc, acct_cc, acct_cc, acct_cc,
    acct_cc, acct_cc, acct_cc, acct_cc, acct_cc,
    acct_hdfc, acct_hdfc, acct_hdfc,
    acct_cash, acct_hdfc, acct_hdfc, acct_hdfc,
    acct_hdfc, acct_hdfc, acct_hdfc
  ];
  lo := ARRAY[
    800, 500, 600, 500, 700,
    150, 180, 250, 300, 200, 400,
     80, 70, 50,1800,1700,100,
    1499,999,1500,1400, 600,
    500, 400, 600, 400, 800,
    649,119, 299,299, 129,
    150, 120, 150,
     80,220,150,180,
    250, 250, 200
  ];
  hi := ARRAY[
    3800,3200,3500,2800,3200,
    1100,1200,1400,1000,800,2200,
     550, 500, 350,3500,3200,600,
    1499,999,2600,2500,1200,
    4500,3800,3500,3000,4500,
     649,119, 299,299, 129,
    1600,1400,1500,
     220, 520, 380, 420,
    1200,1100,1000
  ];

  -- ─── 5. Daily expense loop (5..10 rows/day) ──────────────────────────────
  d := start_d;
  WHILE d <= today LOOP
    txn_count := 5 + floor(random() * 6)::int;   -- 5..10
    FOR i IN 1..txn_count LOOP
      pick := 1 + floor(random() * array_length(vendors, 1))::int;
      vendor_name := vendors[pick];
      vendor_cat  := cats[pick];
      vendor_pay  := pays[pick];
      vendor_acct := accts[pick];
      vendor_amt  := lo[pick] + floor(random() * (hi[pick] - lo[pick] + 1))::int;

      INSERT INTO public.transactions
        (user_id, amount, currency, date, type, title, description,
         category_id, category_source, payment_method, source_type,
         effective_amount, status, account_id)
      VALUES
        (uid, vendor_amt, 'INR', d, 'expense', vendor_name, vendor_name,
         vendor_cat, 'manual', vendor_pay, 'manual',
         vendor_amt, 'confirmed', vendor_acct);
    END LOOP;
    d := d + 1;
  END LOOP;

  -- ─── 6. Monthly salary (12 entries, last day of each past month) ─────────
  FOR mo IN 0..11 LOOP
    -- End of month for each of the last 12 months.
    d := (date_trunc('month', today) - (mo * interval '1 month')
          + interval '1 month' - interval '1 day')::date;
    -- Small raise every quarter for a realistic ramp.
    salary_amt := 85000 + (11 - mo) * 1000;
    INSERT INTO public.transactions
      (user_id, amount, currency, date, type, title, description,
       source_type, effective_amount, status, account_id)
    VALUES
      (uid, salary_amt, 'INR', d, 'income',
       'Salary - ' || to_char(d, 'Mon YYYY'),
       'Monthly salary', 'manual', salary_amt, 'confirmed', acct_sbi);
  END LOOP;

  -- ─── 7. Mirror every seeded expense into public.documents ────────────────
  -- Pre-Goat UI reads from documents via SupabaseService.fetchDocuments();
  -- Goat compute reads from transactions. Mirror keeps both surfaces alive.
  INSERT INTO public.documents
    (user_id, type, vendor_name, amount, currency, tax_amount, date,
     category_id, description, payment_method, status, extracted_data,
     category_source)
  SELECT
    t.user_id,
    'receipt',
    t.title,
    t.amount,
    t.currency,
    0,
    t.date,
    t.category_id,
    t.description,
    t.payment_method,
    'saved',
    jsonb_build_object(
      'seeded_by',             'seed_manng_data.sql',
      'source_transaction_id', t.id,
      'synthetic',             true
    ),
    'manual'
  FROM public.transactions t
  WHERE t.user_id = uid
    AND t.type   = 'expense';

  -- ─── 8. Budgets (active for current month) ───────────────────────────────
  INSERT INTO public.budgets
    (user_id, name, category_id, amount, period, currency, is_active, start_date)
  VALUES
    (uid, 'Groceries',      cat_groc,   12000.00, 'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Dining',          cat_dine,   6000.00, 'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Transportation',  cat_trans,  8000.00, 'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Utilities',       cat_util,   5000.00, 'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Shopping',        cat_shop,  10000.00, 'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Subscriptions',   cat_subs,   2000.00, 'monthly', 'INR', true, date_trunc('month', today)::date),
    (uid, 'Entertainment',   cat_ent,    2500.00, 'monthly', 'INR', true, date_trunc('month', today)::date);

  -- ─── 9. Recurring series (drifts + bills) ────────────────────────────────
  INSERT INTO public.recurring_series
    (user_id, title, amount, currency, category_id, cadence,
     anchor_date, next_due, detection_source, is_active)
  VALUES
    (uid, 'Netflix',         649.00, 'INR', cat_subs, 'monthly', today - 335, today +  5, 'manual', true),
    (uid, 'Spotify Premium', 119.00, 'INR', cat_subs, 'monthly', today - 330, today + 10, 'manual', true),
    (uid, 'Airtel Fiber',   1499.00, 'INR', cat_util, 'monthly', today - 333, today +  7, 'manual', true),
    (uid, 'Electricity',    2000.00, 'INR', cat_util, 'monthly', today - 325, today + 15, 'manual', true),
    (uid, 'YouTube Premium', 129.00, 'INR', cat_subs, 'monthly', today - 240, today + 25, 'manual', true);

  -- ─── 10. Lend / Borrow ledger ────────────────────────────────────────────
  INSERT INTO public.lend_borrow_entries
    (user_id, counterparty_name, amount, type, status, due_date, notes)
  VALUES
    (uid, 'Rahul',   5000.00, 'lent',     'pending',  today + 12, 'Weekend trip split'),
    (uid, 'Priya',   3000.00, 'lent',     'settled',  today - 90, 'Dinner share (closed)'),
    (uid, 'Vikram',  8000.00, 'borrowed', 'pending',  today +  8, 'Rent gap cover'),
    (uid, 'Sneha',   2000.00, 'lent',     'pending',  today + 45, 'Movie + dinner'),
    (uid, 'Arjun',  12000.00, 'borrowed', 'settled',  today -160, 'Laptop repair (closed)'),
    (uid, 'Meera',   4500.00, 'lent',     'pending',  today + 60, 'Shopping split'),
    (uid, 'Karthik', 6000.00, 'borrowed', 'pending',  today + 30, 'Emergency cash');

  -- ─── 11. Goat user inputs / goals / obligations (readiness L3) ───────────
  INSERT INTO public.goat_user_inputs (
    user_id, monthly_income, income_currency, pay_frequency, salary_day,
    emergency_fund_target_months, liquidity_floor, household_size, dependents,
    risk_tolerance, planning_horizon_months, tone_preference, notes
  ) VALUES (
    uid, 90000.00, 'INR', 'monthly', 1,
    6.0, 150000.00, 2, 1,
    'balanced', 12, 'direct',
    jsonb_build_object(
      'seeded_by', 'seed_manng_data.sql',
      'seeded_on', to_char(now(), 'YYYY-MM-DD'),
      'readiness', 'L3'
    )
  );

  INSERT INTO public.goat_goals
    (user_id, goal_type, title, target_amount, current_amount,
     target_date, priority, status, metadata)
  VALUES
    (uid, 'emergency_fund', 'Emergency Fund (6 months)', 540000.00, 125000.00, today + 180, 1, 'active', '{"source":"seed"}'::jsonb),
    (uid, 'savings',        'Vacation — Goa Dec',        75000.00,  22000.00, today + 240, 3, 'active', '{"source":"seed"}'::jsonb),
    (uid, 'debt_payoff',    'Clear credit-card revolve', 20000.00,   5000.00, today +  90, 2, 'active', '{"source":"seed"}'::jsonb);

  INSERT INTO public.goat_obligations
    (user_id, obligation_type, lender_name, current_outstanding,
     monthly_due, due_day, interest_rate, cadence, status, metadata)
  VALUES
    (uid, 'emi',             'HDFC Personal Loan',  280000.00,  9500.00, extract(day from (today + 2))::int, 11.25, 'monthly', 'active', '{"source":"seed"}'::jsonb),
    (uid, 'rent',            'Landlord',                 NULL, 24000.00,  5, NULL,  'monthly', 'active', '{"source":"seed"}'::jsonb),
    (uid, 'credit_card_min', 'ICICI Amazon Pay',     18400.00,  1840.00, 12, 38.00, 'monthly', 'active', '{"source":"seed"}'::jsonb);

  -- ─── 12. Summary ─────────────────────────────────────────────────────────
  RAISE NOTICE '── Seed complete ──';
  RAISE NOTICE 'accounts          : %', (SELECT count(*) FROM public.accounts          WHERE user_id = uid);
  RAISE NOTICE 'transactions      : %', (SELECT count(*) FROM public.transactions      WHERE user_id = uid);
  RAISE NOTICE '  expenses total  : %', (SELECT count(*) FROM public.transactions      WHERE user_id = uid AND type='expense');
  RAISE NOTICE '  expenses 30d    : %', (SELECT count(*) FROM public.transactions      WHERE user_id = uid AND type='expense' AND date >= today - 30);
  RAISE NOTICE '  income (salary) : %', (SELECT count(*) FROM public.transactions      WHERE user_id = uid AND type='income');
  RAISE NOTICE 'documents         : %', (SELECT count(*) FROM public.documents         WHERE user_id = uid);
  RAISE NOTICE 'budgets           : %', (SELECT count(*) FROM public.budgets           WHERE user_id = uid);
  RAISE NOTICE 'recurring_series  : %', (SELECT count(*) FROM public.recurring_series  WHERE user_id = uid);
  RAISE NOTICE 'lend_borrow       : %', (SELECT count(*) FROM public.lend_borrow_entries WHERE user_id = uid);
  RAISE NOTICE 'goat_user_inputs  : %', (SELECT count(*) FROM public.goat_user_inputs  WHERE user_id = uid);
  RAISE NOTICE 'goat_goals        : %', (SELECT count(*) FROM public.goat_goals        WHERE user_id = uid);
  RAISE NOTICE 'goat_obligations  : %', (SELECT count(*) FROM public.goat_obligations  WHERE user_id = uid);
  RAISE NOTICE 'total expense sum : ₹%', (SELECT to_char(COALESCE(sum(amount),0),'FM999,999,999.00') FROM public.transactions WHERE user_id = uid AND type='expense');
  RAISE NOTICE '── Refresh the dashboard: 1W / 1M / 3M / 6M / 1Y charts    ──';
  RAISE NOTICE '── should all light up. Then open Goat Mode → Run analysis. ──';
END $$;
