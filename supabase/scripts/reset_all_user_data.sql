-- ═══════════════════════════════════════════════════════════════════════════
-- BILLY: HARD RESET ALL APP DATA (KEEP ACCOUNTS)
--
-- What stays:
--   - auth.users (logins)
--   - public.profiles (rows stay; optional gemini key cleared below)
--   - public.app_api_keys (shared Gemini key)
--   - public.categories where user_id IS NULL (default catalog, if any)
--
-- What is removed:
--   - Documents, invoices, scans metadata, splits, exports, analytics cache,
--     usage counters, groups, connections, invitations, lend/borrow, etc.
--
-- NOT run automatically. Execute once in Supabase Dashboard → SQL Editor
-- as a privileged role (postgres / service role). Review before running.
--
-- After SQL: empty Storage bucket `invoice-files` (Dashboard → Storage)
-- or orphaned files remain until you delete them manually.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- Invoice pipeline (order: children → parents)
delete from public.invoice_processing_events;
delete from public.invoice_items;
delete from public.invoice_ocr_logs;
delete from public.invoices;

-- Group ledger
delete from public.group_expense_participants;
delete from public.group_expenses;
delete from public.group_settlements;

-- Personal + social financial rows (before documents / groups)
delete from public.lend_borrow_entries;
delete from public.documents;

-- Legacy splits module
delete from public.split_participants;
delete from public.splits;

delete from public.export_history;
delete from public.connected_apps;
delete from public.analytics_insight_snapshots;

-- Usage counters (re-created on next OCR/refresh via RPCs)
delete from public.user_usage_limits;

-- Groups & contacts (after nothing references groups)
delete from public.expense_group_members;
delete from public.expense_groups;
delete from public.user_connections;
delete from public.contact_invitations;

-- User-defined categories only (keep shared defaults)
delete from public.categories where user_id is not null;

-- Optional: clear per-user Gemini override if column exists
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'gemini_api_key'
  ) then
    execute 'update public.profiles set gemini_api_key = null where gemini_api_key is not null';
  end if;
end $$;

commit;

-- Verify (optional): counts should be 0 for app tables above (except profiles, categories defaults).
