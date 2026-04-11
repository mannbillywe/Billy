-- Destructive: removes GOAT workspace schema (statements, goals, recurring center, forecast inputs, setup chat, dashboard prefs)
-- and profile/documents columns added for GOAT. Run only if you intend to drop this data permanently.

-- ─── Storage: statement uploads ───────────────────────────────────
drop policy if exists "statement_files_delete_own" on storage.objects;
drop policy if exists "statement_files_update_own" on storage.objects;
drop policy if exists "statement_files_insert_own" on storage.objects;
drop policy if exists "statement_files_select_own" on storage.objects;

-- Storage bucket data must be removed via the Supabase Storage API / dashboard.
-- Direct DELETE from storage tables is blocked by Supabase.

-- ─── Tables (dependency order) ───────────────────────────────────
drop table if exists public.goat_dashboard_preferences cascade;
drop table if exists public.goat_setup_drafts cascade;
drop table if exists public.goat_setup_state cascade;

drop table if exists public.statement_row_reviews cascade;
drop table if exists public.statement_raw_extractions cascade;
drop table if exists public.statement_import_reviews cascade;
drop table if exists public.statement_document_links cascade;
drop table if exists public.canonical_financial_events cascade;
drop table if exists public.statement_transactions cascade;
drop table if exists public.statement_transactions_raw cascade;
drop table if exists public.statement_imports cascade;
drop table if exists public.statement_accounts cascade;

drop table if exists public.goal_contributions cascade;
drop table if exists public.goal_rules cascade;
drop table if exists public.goal_recommendations cascade;
drop table if exists public.goals cascade;

drop table if exists public.recurring_notification_rules cascade;
drop table if exists public.recurring_change_events cascade;
drop table if exists public.recurring_occurrences cascade;
drop table if exists public.recurring_series cascade;

drop table if exists public.account_balance_snapshots cascade;
drop table if exists public.financial_accounts cascade;
drop table if exists public.cashflow_forecast_snapshots cascade;
drop table if exists public.cashflow_scenarios cascade;
drop table if exists public.income_streams cascade;
drop table if exists public.planned_cashflow_events cascade;

-- ─── Functions (triggers above are dropped with tables) ─────────
drop function if exists public.goat_setup_reserve_ai_slot(uuid);
drop function if exists public.goat_setup_release_ai_slot(uuid);
drop function if exists public.goat_setup_touch_updated_at();
drop function if exists public.goat_dashboard_prefs_touch_updated_at();
drop function if exists public.goat_statements_touch_updated_at();
drop function if exists public.goat_goals_touch_updated_at();
drop function if exists public.goat_finance_touch_updated_at();
drop function if exists public.recurring_touch_updated_at();

-- ─── profiles / documents columns ────────────────────────────────
alter table public.profiles drop constraint if exists profiles_goat_analysis_lens_check;
alter table public.profiles drop column if exists goat_analysis_lens;
alter table public.profiles drop column if exists goat;

alter table public.documents drop column if exists exclude_from_goat_smart_analytics;

comment on table public.app_api_keys is
  'Shared keys for Edge Functions: provider gemini (default OCR + analytics).';
