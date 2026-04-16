-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Clear ALL data for a single user UUID                             ║
-- ║  Paste your UUID below and run in Supabase SQL Editor.             ║
-- ║  ⚠  This is destructive — data cannot be recovered!               ║
-- ╚══════════════════════════════════════════════════════════════════════╝

DO $$
DECLARE
  uid uuid := 'PASTE-YOUR-UUID-HERE';
BEGIN

  DELETE FROM public.activity_events       WHERE user_id = uid;
  DELETE FROM public.recurring_series      WHERE user_id = uid;
  DELETE FROM public.budgets               WHERE user_id = uid;
  DELETE FROM public.lend_borrow_entries   WHERE user_id = uid;
  DELETE FROM public.transactions          WHERE user_id = uid;
  DELETE FROM public.documents             WHERE user_id = uid;
  DELETE FROM public.accounts              WHERE user_id = uid;
  DELETE FROM public.categories            WHERE user_id = uid;

  RAISE NOTICE 'All data cleared for user %', uid;

END $$;
