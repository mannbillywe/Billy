-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Billy Seed Data — User "Manng"                                    ║
-- ║  ~1 year of realistic financial data (Apr 2025 → Apr 2026)         ║
-- ║  Paste into Supabase SQL Editor and run.                           ║
-- ║  ⚠  Replace <USER_UUID> with the actual auth.users UUID for Manng  ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ─── Step 0: Set the user UUID ───────────────────────────────────────
-- Run:  select id, email from auth.users;
-- Then replace every occurrence of the placeholder below.
DO $$
DECLARE
  uid uuid;
BEGIN
  -- ┌────────────────────────────────────────────────────────┐
  -- │  PASTE YOUR UUID BELOW                                │
  -- └────────────────────────────────────────────────────────┘
  uid := 'PASTE-YOUR-UUID-HERE';

  RAISE NOTICE 'Seeding data for user: %', uid;

  -- ─── Step 1: Update profile ──────────────────────────────────────
  UPDATE public.profiles SET
    display_name       = 'Manng',
    preferred_currency = 'INR',
    goat_mode          = true,
    updated_at         = now()
  WHERE id = uid;

  -- ─── Step 2: Default categories (idempotent) ────────────────────
  INSERT INTO public.categories (id, user_id, name, icon, color, is_default) VALUES
    (gen_random_uuid(), NULL, 'Food & Beverage',  '🍔', '#F97316', true),
    (gen_random_uuid(), NULL, 'Dining',           '🍽️', '#EF4444', true),
    (gen_random_uuid(), NULL, 'Groceries',        '🛒', '#22C55E', true),
    (gen_random_uuid(), NULL, 'Transportation',   '🚕', '#3B82F6', true),
    (gen_random_uuid(), NULL, 'Shopping',         '🛍️', '#EC4899', true),
    (gen_random_uuid(), NULL, 'Utilities',        '⚡', '#F59E0B', true),
    (gen_random_uuid(), NULL, 'Entertainment',    '🎬', '#8B5CF6', true),
    (gen_random_uuid(), NULL, 'Healthcare',       '🏥', '#EF4444', true),
    (gen_random_uuid(), NULL, 'Education',        '📚', '#06B6D4', true),
    (gen_random_uuid(), NULL, 'Housing',          '🏠', '#8B5CF6', true),
    (gen_random_uuid(), NULL, 'Subscriptions',    '📱', '#10B981', true),
    (gen_random_uuid(), NULL, 'Maintenance',      '🔧', '#6B7280', true),
    (gen_random_uuid(), NULL, 'Stationery',       '✏️', '#A855F7', true),
    (gen_random_uuid(), NULL, 'Equipment',        '💻', '#0EA5E9', true),
    (gen_random_uuid(), NULL, 'Borrow',           '📥', '#EF4444', true),
    (gen_random_uuid(), NULL, 'Lend',             '📤', '#06B6D4', true),
    (gen_random_uuid(), NULL, 'Other',            '📦', '#6B7280', true)
  ON CONFLICT DO NOTHING;

  -- ─── Step 3: Accounts ───────────────────────────────────────────
  INSERT INTO public.accounts (id, user_id, name, type, institution, currency, current_balance, is_asset) VALUES
    ('a0000001-0000-0000-0000-000000000001', uid, 'HDFC Savings',    'savings',     'HDFC Bank',    'INR', 245800.00, true),
    ('a0000001-0000-0000-0000-000000000002', uid, 'SBI Salary',      'checking',    'SBI',          'INR', 58320.00,  true),
    ('a0000001-0000-0000-0000-000000000003', uid, 'Amazon Pay ICICI','credit_card', 'ICICI Bank',   'INR', -12450.00, false),
    ('a0000001-0000-0000-0000-000000000004', uid, 'Cash',            'cash',        NULL,           'INR', 3200.00,   true),
    ('a0000001-0000-0000-0000-000000000005', uid, 'Groww MF',        'investment',  'Groww',        'INR', 125000.00, true)
  ON CONFLICT (id) DO NOTHING;

  -- ─── Helper: get category id by name ────────────────────────────
  -- We'll use a temp table for quick lookups
  CREATE TEMP TABLE _cat_map (name text, cid uuid) ON COMMIT DROP;
  INSERT INTO _cat_map (name, cid)
    SELECT c.name, c.id FROM public.categories c
    WHERE c.user_id IS NULL OR c.user_id = uid;

  -- ─── Step 4: Documents + Transactions (12 months) ──────────────
  -- Each month gets a realistic mix of expenses

  -- ════════════════════ APRIL 2025 ════════════════════
  INSERT INTO public.documents (id, user_id, type, vendor_name, amount, currency, date, category_id, description, status, payment_method, extracted_data, category_source) VALUES
    (gen_random_uuid(), uid, 'receipt',  'Swiggy',              489.00,  'INR', '2025-04-03', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'BigBasket',          2340.00,  'INR', '2025-04-05', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Airtel Fiber',       1499.00,  'INR', '2025-04-07', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'Auto-debit', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Uber',                345.00,  'INR', '2025-04-08', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Amazon',             4599.00,  'INR', '2025-04-10', (SELECT cid FROM _cat_map WHERE name='Shopping' LIMIT 1),        'Shopping',        'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'DMart',              3120.00,  'INR', '2025-04-14', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'Cash', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Netflix',             649.00,  'INR', '2025-04-15', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   'Subscriptions',   'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Zomato',              623.00,  'INR', '2025-04-18', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   2800.00,  'INR', '2025-04-20', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  1850.00,  'INR', '2025-04-22', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Chai Point',          180.00,  'INR', '2025-04-25', (SELECT cid FROM _cat_map WHERE name='Food & Beverage' LIMIT 1), 'Food & Beverage', 'saved', 'Cash', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Decathlon',          3450.00,  'INR', '2025-04-28', (SELECT cid FROM _cat_map WHERE name='Shopping' LIMIT 1),        'Shopping',        'saved', 'Credit Card', '{"source":"manual"}', 'manual');

  -- ════════════════════ MAY 2025 ════════════════════
  INSERT INTO public.documents (id, user_id, type, vendor_name, amount, currency, date, category_id, description, status, payment_method, extracted_data, category_source) VALUES
    (gen_random_uuid(), uid, 'receipt',  'Reliance Fresh',     1890.00,  'INR', '2025-05-02', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Ola',                 278.00,  'INR', '2025-05-04', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'PVR Cinemas',         780.00,  'INR', '2025-05-06', (SELECT cid FROM _cat_map WHERE name='Entertainment' LIMIT 1),   'Entertainment',   'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Spotify Premium',     119.00,  'INR', '2025-05-07', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   'Subscriptions',   'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Swiggy',              725.00,  'INR', '2025-05-09', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Airtel Fiber',       1499.00,  'INR', '2025-05-10', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'Auto-debit', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Apollo Pharmacy',     890.00,  'INR', '2025-05-12', (SELECT cid FROM _cat_map WHERE name='Healthcare' LIMIT 1),      'Healthcare',      'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'BigBasket',          2670.00,  'INR', '2025-05-15', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Myntra',             2199.00,  'INR', '2025-05-18', (SELECT cid FROM _cat_map WHERE name='Shopping' LIMIT 1),        'Shopping',        'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   3100.00,  'INR', '2025-05-22', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  2100.00,  'INR', '2025-05-24', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Zomato',              410.00,  'INR', '2025-05-28', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI',  '{"source":"manual"}', 'manual');

  -- ════════════════════ JUNE 2025 ════════════════════
  INSERT INTO public.documents (id, user_id, type, vendor_name, amount, currency, date, category_id, description, status, payment_method, extracted_data, category_source) VALUES
    (gen_random_uuid(), uid, 'receipt',  'DMart',              3540.00,  'INR', '2025-06-01', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'Cash',  '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Rapido',              165.00,  'INR', '2025-06-03', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI',   '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Flipkart',           7899.00,  'INR', '2025-06-05', (SELECT cid FROM _cat_map WHERE name='Equipment' LIMIT 1),       'Equipment',       'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Netflix',             649.00,  'INR', '2025-06-07', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   'Subscriptions',   'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Starbucks',           520.00,  'INR', '2025-06-10', (SELECT cid FROM _cat_map WHERE name='Food & Beverage' LIMIT 1), 'Food & Beverage', 'saved', 'UPI',   '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'AWS',                1250.00,  'INR', '2025-06-12', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   'Subscriptions',   'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Uber',                412.00,  'INR', '2025-06-15', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI',   '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Lenskart',           2490.00,  'INR', '2025-06-18', (SELECT cid FROM _cat_map WHERE name='Healthcare' LIMIT 1),      'Healthcare',      'saved', 'UPI',   '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  1980.00,  'INR', '2025-06-20', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI',   '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Swiggy',              598.00,  'INR', '2025-06-24', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI',   '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - Indian Oil', 2650.00, 'INR', '2025-06-27', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1), 'Transportation', 'saved', 'UPI', '{"source":"manual"}', 'manual');

  -- ════════════════════ JULY – SEPTEMBER 2025 (bulk) ══════════════
  INSERT INTO public.documents (id, user_id, type, vendor_name, amount, currency, date, category_id, description, status, payment_method, extracted_data, category_source) VALUES
    -- July
    (gen_random_uuid(), uid, 'receipt',  'BigBasket',          2890.00, 'INR', '2025-07-02', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Airtel Fiber',       1499.00, 'INR', '2025-07-05', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'Auto-debit', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Zomato',              867.00, 'INR', '2025-07-08', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Croma',             12500.00, 'INR', '2025-07-12', (SELECT cid FROM _cat_map WHERE name='Equipment' LIMIT 1),       'Equipment',       'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Uber',                520.00, 'INR', '2025-07-15', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  2350.00, 'INR', '2025-07-20', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   2900.00, 'INR', '2025-07-24', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'DMart',              2780.00, 'INR', '2025-07-28', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'Cash', '{"source":"manual"}', 'manual'),
    -- August
    (gen_random_uuid(), uid, 'receipt',  'Swiggy',              945.00, 'INR', '2025-08-01', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Reliance Fresh',     2150.00, 'INR', '2025-08-04', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'YouTube Premium',     129.00, 'INR', '2025-08-05', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   'Subscriptions',   'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Ola',                 389.00, 'INR', '2025-08-08', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Amazon',             5699.00, 'INR', '2025-08-12', (SELECT cid FROM _cat_map WHERE name='Shopping' LIMIT 1),        'Shopping',        'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  1750.00, 'INR', '2025-08-18', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   3200.00, 'INR', '2025-08-22', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Medplus Pharmacy',    650.00, 'INR', '2025-08-25', (SELECT cid FROM _cat_map WHERE name='Healthcare' LIMIT 1),      'Healthcare',      'saved', 'Cash', '{"source":"manual"}', 'manual'),
    -- September
    (gen_random_uuid(), uid, 'receipt',  'BigBasket',          3100.00, 'INR', '2025-09-01', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Zomato',              534.00, 'INR', '2025-09-05', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Netflix',             649.00, 'INR', '2025-09-07', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   'Subscriptions',   'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Urban Company',      1200.00, 'INR', '2025-09-10', (SELECT cid FROM _cat_map WHERE name='Maintenance' LIMIT 1),     'Maintenance',     'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Rapido',              210.00, 'INR', '2025-09-12', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'DMart',              2450.00, 'INR', '2025-09-16', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'Cash', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  2020.00, 'INR', '2025-09-20', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   2750.00, 'INR', '2025-09-25', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual');

  -- ════════════════════ OCTOBER – DECEMBER 2025 ═══════════════════
  INSERT INTO public.documents (id, user_id, type, vendor_name, amount, currency, date, category_id, description, status, payment_method, extracted_data, category_source) VALUES
    (gen_random_uuid(), uid, 'receipt',  'Swiggy',              680.00, 'INR', '2025-10-02', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'BigBasket',          2920.00, 'INR', '2025-10-06', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Airtel Fiber',       1499.00, 'INR', '2025-10-08', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'Auto-debit', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Flipkart',           3299.00, 'INR', '2025-10-15', (SELECT cid FROM _cat_map WHERE name='Shopping' LIMIT 1),        'Shopping',        'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  2200.00, 'INR', '2025-10-20', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   3050.00, 'INR', '2025-10-24', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    -- November (Diwali month — higher spend)
    (gen_random_uuid(), uid, 'receipt',  'Amazon (Diwali Sale)',15999.00,'INR', '2025-11-02', (SELECT cid FROM _cat_map WHERE name='Shopping' LIMIT 1),        'Shopping',        'saved', 'Credit Card', '{"source":"manual","notes":"Diwali sale"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'BigBasket',          4200.00, 'INR', '2025-11-05', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Haldiram',           1800.00, 'INR', '2025-11-08', (SELECT cid FROM _cat_map WHERE name='Food & Beverage' LIMIT 1), 'Food & Beverage', 'saved', 'Cash', '{"source":"manual","notes":"Diwali sweets"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Uber',                890.00, 'INR', '2025-11-12', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Netflix',             649.00, 'INR', '2025-11-15', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   'Subscriptions',   'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  2400.00, 'INR', '2025-11-20', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   3400.00, 'INR', '2025-11-25', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    -- December
    (gen_random_uuid(), uid, 'receipt',  'Reliance Fresh',     2780.00, 'INR', '2025-12-01', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'BookMyShow',          950.00, 'INR', '2025-12-05', (SELECT cid FROM _cat_map WHERE name='Entertainment' LIMIT 1),   'Entertainment',   'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Zomato',              720.00, 'INR', '2025-12-08', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Airtel Fiber',       1499.00, 'INR', '2025-12-10', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'Auto-debit', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   2950.00, 'INR', '2025-12-18', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  1900.00, 'INR', '2025-12-22', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI', '{"source":"manual"}', 'manual');

  -- ════════════════════ JANUARY – MARCH 2026 ═════════════════════
  INSERT INTO public.documents (id, user_id, type, vendor_name, amount, currency, date, category_id, description, status, payment_method, extracted_data, category_source) VALUES
    (gen_random_uuid(), uid, 'receipt',  'BigBasket',          3340.00, 'INR', '2026-01-03', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Swiggy',              590.00, 'INR', '2026-01-06', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Airtel Fiber',       1499.00, 'INR', '2026-01-08', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'Auto-debit', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Uber',                456.00, 'INR', '2026-01-12', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  2050.00, 'INR', '2026-01-20', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   2850.00, 'INR', '2026-01-25', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    -- February
    (gen_random_uuid(), uid, 'receipt',  'DMart',              2650.00, 'INR', '2026-02-02', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'Cash', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Zomato',              485.00, 'INR', '2026-02-05', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Myntra',             3450.00, 'INR', '2026-02-08', (SELECT cid FROM _cat_map WHERE name='Shopping' LIMIT 1),        'Shopping',        'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Netflix',             649.00, 'INR', '2026-02-10', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   'Subscriptions',   'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Apollo Pharmacy',    1100.00, 'INR', '2026-02-15', (SELECT cid FROM _cat_map WHERE name='Healthcare' LIMIT 1),      'Healthcare',      'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  1850.00, 'INR', '2026-02-20', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   2700.00, 'INR', '2026-02-24', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    -- March
    (gen_random_uuid(), uid, 'receipt',  'BigBasket',          2980.00, 'INR', '2026-03-02', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Swiggy',              715.00, 'INR', '2026-03-06', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Airtel Fiber',       1499.00, 'INR', '2026-03-08', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'Auto-debit', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Coursera',           4200.00, 'INR', '2026-03-12', (SELECT cid FROM _cat_map WHERE name='Education' LIMIT 1),       'Education',       'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Uber',                378.00, 'INR', '2026-03-15', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Electricity Board',  2150.00, 'INR', '2026-03-22', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   3000.00, 'INR', '2026-03-26', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual');

  -- ════════════════════ APRIL 2026 (current month) ═══════════════
  INSERT INTO public.documents (id, user_id, type, vendor_name, amount, currency, date, category_id, description, status, payment_method, extracted_data, category_source) VALUES
    (gen_random_uuid(), uid, 'receipt',  'BigBasket',          3150.00, 'INR', '2026-04-01', (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       'Groceries',       'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Zomato',              645.00, 'INR', '2026-04-03', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Airtel Fiber',       1499.00, 'INR', '2026-04-05', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       'Utilities',       'saved', 'Auto-debit', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Uber',                310.00, 'INR', '2026-04-07', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Amazon',             2199.00, 'INR', '2026-04-09', (SELECT cid FROM _cat_map WHERE name='Shopping' LIMIT 1),        'Shopping',        'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'invoice',  'Netflix',             649.00, 'INR', '2026-04-10', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   'Subscriptions',   'saved', 'Credit Card', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Swiggy',              478.00, 'INR', '2026-04-12', (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          'Dining',          'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Petrol Pump - HP',   2900.00, 'INR', '2026-04-14', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  'Transportation',  'saved', 'UPI', '{"source":"manual"}', 'manual'),
    (gen_random_uuid(), uid, 'receipt',  'Chai Point',          220.00, 'INR', '2026-04-16', (SELECT cid FROM _cat_map WHERE name='Food & Beverage' LIMIT 1), 'Food & Beverage', 'saved', 'Cash', '{"source":"manual"}', 'manual');

  -- ─── Step 5: Create transactions from documents ─────────────────
  INSERT INTO public.transactions (id, user_id, amount, currency, date, type, title, description, category_id, category_source, payment_method, source_type, source_document_id, effective_amount, status, account_id)
    SELECT gen_random_uuid(), d.user_id, d.amount, d.currency, d.date, 'expense', d.vendor_name, d.description, d.category_id, 'manual', d.payment_method, 'manual', d.id, d.amount, 'confirmed',
      CASE
        WHEN d.payment_method = 'Credit Card' THEN 'a0000001-0000-0000-0000-000000000003'::uuid
        WHEN d.payment_method = 'Cash'        THEN 'a0000001-0000-0000-0000-000000000004'::uuid
        ELSE 'a0000001-0000-0000-0000-000000000001'::uuid
      END
    FROM public.documents d WHERE d.user_id = uid;

  -- ─── Step 6: Income transactions (salary) ───────────────────────
  INSERT INTO public.transactions (user_id, amount, currency, date, type, title, description, source_type, effective_amount, status, account_id) VALUES
    (uid, 85000.00, 'INR', '2025-04-30', 'income', 'Salary - April',     'Monthly salary', 'manual', 85000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 85000.00, 'INR', '2025-05-31', 'income', 'Salary - May',       'Monthly salary', 'manual', 85000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 85000.00, 'INR', '2025-06-30', 'income', 'Salary - June',      'Monthly salary', 'manual', 85000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 85000.00, 'INR', '2025-07-31', 'income', 'Salary - July',      'Monthly salary', 'manual', 85000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 90000.00, 'INR', '2025-08-31', 'income', 'Salary - August',    'Monthly salary (raise)', 'manual', 90000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 90000.00, 'INR', '2025-09-30', 'income', 'Salary - September', 'Monthly salary', 'manual', 90000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 90000.00, 'INR', '2025-10-31', 'income', 'Salary - October',   'Monthly salary', 'manual', 90000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 90000.00, 'INR', '2025-11-30', 'income', 'Salary - November',  'Monthly salary', 'manual', 90000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 90000.00, 'INR', '2025-12-31', 'income', 'Salary - December',  'Monthly salary', 'manual', 90000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 95000.00, 'INR', '2026-01-31', 'income', 'Salary - January',   'Monthly salary (annual raise)', 'manual', 95000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 95000.00, 'INR', '2026-02-28', 'income', 'Salary - February',  'Monthly salary', 'manual', 95000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002'),
    (uid, 95000.00, 'INR', '2026-03-31', 'income', 'Salary - March',     'Monthly salary', 'manual', 95000.00, 'confirmed', 'a0000001-0000-0000-0000-000000000002');

  -- ─── Step 7: Lend & Borrow entries ──────────────────────────────
  INSERT INTO public.lend_borrow_entries (user_id, counterparty_name, amount, type, status, due_date, notes) VALUES
    (uid, 'Rahul',   5000.00, 'lent',     'pending',  '2025-06-15', 'Trip expenses'),
    (uid, 'Priya',   3000.00, 'lent',     'settled',  '2025-07-01', 'Dinner share'),
    (uid, 'Vikram',  8000.00, 'borrowed', 'pending',  '2025-09-01', 'Emergency cash'),
    (uid, 'Sneha',   2000.00, 'lent',     'pending',  '2025-10-15', 'Movie tickets + food'),
    (uid, 'Arjun',  12000.00, 'borrowed', 'settled',  '2025-12-01', 'Laptop repair'),
    (uid, 'Meera',   4500.00, 'lent',     'pending',  '2026-02-28', 'Shopping split'),
    (uid, 'Karthik', 6000.00, 'borrowed', 'pending',  '2026-04-30', 'Rent gap cover');

  -- ─── Step 8: Budgets (current month active) ────────────────────
  INSERT INTO public.budgets (user_id, name, category_id, amount, period, currency, is_active, start_date) VALUES
    (uid, 'Groceries',      (SELECT cid FROM _cat_map WHERE name='Groceries' LIMIT 1),       8000.00,  'monthly', 'INR', true, '2026-04-01'),
    (uid, 'Dining',         (SELECT cid FROM _cat_map WHERE name='Dining' LIMIT 1),          3000.00,  'monthly', 'INR', true, '2026-04-01'),
    (uid, 'Transportation', (SELECT cid FROM _cat_map WHERE name='Transportation' LIMIT 1),  5000.00,  'monthly', 'INR', true, '2026-04-01'),
    (uid, 'Utilities',      (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),       5000.00,  'monthly', 'INR', true, '2026-04-01'),
    (uid, 'Shopping',       (SELECT cid FROM _cat_map WHERE name='Shopping' LIMIT 1),        6000.00,  'monthly', 'INR', true, '2026-04-01'),
    (uid, 'Subscriptions',  (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1),   3000.00,  'monthly', 'INR', true, '2026-04-01'),
    (uid, 'Entertainment',  (SELECT cid FROM _cat_map WHERE name='Entertainment' LIMIT 1),   2000.00,  'monthly', 'INR', true, '2026-04-01');

  -- ─── Step 9: Recurring series ───────────────────────────────────
  INSERT INTO public.recurring_series (user_id, title, amount, currency, category_id, cadence, anchor_date, next_due, detection_source, is_active) VALUES
    (uid, 'Netflix',        649.00,  'INR', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1), 'monthly', '2025-04-15', '2026-05-15', 'manual', true),
    (uid, 'Airtel Fiber',  1499.00,  'INR', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),     'monthly', '2025-04-07', '2026-05-07', 'manual', true),
    (uid, 'Spotify',        119.00,  'INR', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1), 'monthly', '2025-05-07', '2026-05-07', 'manual', true),
    (uid, 'YouTube Premium', 129.00, 'INR', (SELECT cid FROM _cat_map WHERE name='Subscriptions' LIMIT 1), 'monthly', '2025-08-05', '2026-05-05', 'manual', true),
    (uid, 'Electricity',   2000.00,  'INR', (SELECT cid FROM _cat_map WHERE name='Utilities' LIMIT 1),     'monthly', '2025-04-22', '2026-05-22', 'manual', true);

  -- ─── Step 10: A few activity events ─────────────────────────────
  INSERT INTO public.activity_events (user_id, event_type, actor_user_id, summary, visibility) VALUES
    (uid, 'document_scanned',     uid, 'Scanned Swiggy receipt for ₹489',          'private'),
    (uid, 'budget_created',       uid, 'Created monthly Groceries budget (₹8,000)', 'private'),
    (uid, 'budget_exceeded',      uid, 'Shopping budget exceeded by ₹199',           'private'),
    (uid, 'lend_created',         uid, 'Lent ₹5,000 to Rahul',                      'private'),
    (uid, 'borrow_created',       uid, 'Borrowed ₹8,000 from Vikram',               'private'),
    (uid, 'recurring_detected',   uid, 'Detected Netflix as monthly recurring',      'private'),
    (uid, 'statement_imported',   uid, 'Imported HDFC statement (15 transactions)',   'private'),
    (uid, 'transaction_created',  uid, 'Added ₹95,000 salary for March',             'private');

  RAISE NOTICE 'Seed data complete for Manng (%). Documents, transactions, budgets, lend/borrow, recurring, and activity events inserted.', uid;
END $$;
