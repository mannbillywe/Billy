-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Goat Mode — minimal setup inputs for an EXISTING real user          ║
-- ║  Not a seed persona. Use this on your own account.                   ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- Goat Mode will happily compute L1 output without any of this. Fill it in to
-- unlock savings-rate, runway, and debt-to-income math. All fields are optional
-- except user_id; nullable columns stay null if you don't provide a value.

DO $$
DECLARE
  -- ┌──────────────────────────────────────────────────────────────────┐
  -- │  PASTE YOUR REAL UUID BELOW (same one used in seed_manng_data.sql) │
  -- └──────────────────────────────────────────────────────────────────┘
  uid uuid := 'f308f807-00eb-46ce-9468-63cd7c8d3c0f';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = uid) THEN
    RAISE EXCEPTION
      'No profile for uid=%. Make sure the auth user exists first.', uid;
  END IF;

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
    tone_preference
  ) VALUES (
    uid,
    -- edit these to match reality
    NULL,     -- monthly_income (e.g. 95000)
    'INR',
    NULL,     -- pay_frequency  (weekly | biweekly | semimonthly | monthly | other)
    NULL,     -- salary_day     (1..31)
    NULL,     -- emergency_fund_target_months (e.g. 3)
    NULL,     -- liquidity_floor (e.g. 10000)
    NULL,     -- household_size
    NULL,     -- dependents
    NULL,     -- risk_tolerance (conservative | balanced | aggressive)
    NULL,     -- planning_horizon_months
    NULL      -- tone_preference (calm | direct | coaching)
  )
  ON CONFLICT (user_id) DO UPDATE SET
    monthly_income               = COALESCE(EXCLUDED.monthly_income,               public.goat_user_inputs.monthly_income),
    income_currency              = COALESCE(EXCLUDED.income_currency,              public.goat_user_inputs.income_currency),
    pay_frequency                = COALESCE(EXCLUDED.pay_frequency,                public.goat_user_inputs.pay_frequency),
    salary_day                   = COALESCE(EXCLUDED.salary_day,                   public.goat_user_inputs.salary_day),
    emergency_fund_target_months = COALESCE(EXCLUDED.emergency_fund_target_months, public.goat_user_inputs.emergency_fund_target_months),
    liquidity_floor              = COALESCE(EXCLUDED.liquidity_floor,              public.goat_user_inputs.liquidity_floor),
    household_size               = COALESCE(EXCLUDED.household_size,               public.goat_user_inputs.household_size),
    dependents                   = COALESCE(EXCLUDED.dependents,                   public.goat_user_inputs.dependents),
    risk_tolerance               = COALESCE(EXCLUDED.risk_tolerance,               public.goat_user_inputs.risk_tolerance),
    planning_horizon_months      = COALESCE(EXCLUDED.planning_horizon_months,      public.goat_user_inputs.planning_horizon_months),
    tone_preference              = COALESCE(EXCLUDED.tone_preference,              public.goat_user_inputs.tone_preference),
    updated_at                   = now();

  RAISE NOTICE 'goat_user_inputs upserted for user %', uid;
END $$;
