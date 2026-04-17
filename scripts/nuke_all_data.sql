-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Billy — NUKE ALL DATA                                                  ║
-- ║                                                                          ║
-- ║  DROPS every user-owned row in public.*, then DELETEs every auth.users  ║
-- ║  row so the next signup starts from a completely empty database.        ║
-- ║                                                                          ║
-- ║  ⚠  DESTRUCTIVE — data cannot be recovered. Run in Supabase SQL Editor  ║
-- ║     (service-role session). Intended for dev / staging resets only.     ║
-- ║                                                                          ║
-- ║  Preserves                                                              ║
-- ║  ---------                                                              ║
-- ║  • Schema (tables, constraints, policies, triggers, functions).         ║
-- ║  • public.app_api_keys rows (shared provider keys — comment out line    ║
-- ║    at the bottom of the TRUNCATE list to keep them).                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- 1. Drop every row in every per-user table.
--    TRUNCATE ... CASCADE handles any FK chain in one shot and is far faster
--    than a DELETE loop. `profiles` is last so the cascade drains before we
--    remove its referenced auth.users rows.
TRUNCATE TABLE
  public.activity_events,
  public.ai_suggestions,
  public.analytics_insight_snapshots,
  public.budget_periods,
  public.budgets,
  public.categories,
  public.connected_apps,
  public.contact_invitations,
  public.disputes,
  public.documents,
  public.expense_group_members,
  public.expense_groups,
  public.export_history,
  public.goat_goals,
  public.goat_mode_job_events,
  public.goat_mode_jobs,
  public.goat_mode_recommendations,
  public.goat_mode_snapshots,
  public.goat_obligations,
  public.goat_user_inputs,
  public.group_expense_participants,
  public.group_expenses,
  public.group_settlements,
  public.invoice_items,
  public.invoice_ocr_logs,
  public.invoice_processing_events,
  public.invoices,
  public.lend_borrow_entries,
  public.merchant_canonical,
  public.recurring_occurrences,
  public.recurring_series,
  public.recurring_suggestions,
  public.statement_import_rows,
  public.statement_imports,
  public.transactions,
  public.user_connections,
  public.user_usage_limits,
  public.accounts,
  public.profiles
  -- , public.app_api_keys   -- uncomment to also wipe shared provider keys
RESTART IDENTITY CASCADE;

-- 2. Remove every auth.users row. Supabase auth.* internal tables (identities,
--    sessions, refresh_tokens, mfa_factors, …) reference auth.users with
--    ON DELETE CASCADE, so a plain DELETE is enough.
DELETE FROM auth.users;

-- 3. Sanity check — expect every number to be zero.
DO $$
DECLARE
  n_users       int;
  n_profiles    int;
  n_docs        int;
  n_txns        int;
BEGIN
  SELECT count(*) INTO n_users    FROM auth.users;
  SELECT count(*) INTO n_profiles FROM public.profiles;
  SELECT count(*) INTO n_docs     FROM public.documents;
  SELECT count(*) INTO n_txns     FROM public.transactions;

  RAISE NOTICE 'auth.users=% profiles=% documents=% transactions=%',
    n_users, n_profiles, n_docs, n_txns;

  IF n_users + n_profiles + n_docs + n_txns <> 0 THEN
    RAISE EXCEPTION 'Nuke did not clear everything — aborting transaction.';
  END IF;
END $$;

COMMIT;
