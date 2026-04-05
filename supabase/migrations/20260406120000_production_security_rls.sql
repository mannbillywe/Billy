-- Production security (PRODUCTION_READINESS.md A2, A5, A7)
-- P0: documents WITH CHECK, app_api_keys lockdown, user_usage_limits no direct UPDATE,
--     lend_borrow explicit WITH CHECK, input length / amount guards.

-- ─── app_api_keys: no authenticated reads of secrets ─────────────────
drop policy if exists "Authenticated users can read active keys" on public.app_api_keys;

-- get_api_key() would leak secrets if callable by clients — restrict to service_role only
revoke all on function public.get_api_key(text) from public;
revoke all on function public.get_api_key(text) from anon;
revoke all on function public.get_api_key(text) from authenticated;
grant execute on function public.get_api_key(text) to service_role;

create or replace function public.has_shared_api_key(p_provider text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.app_api_keys
    where provider = p_provider and is_active = true
  );
$$;

grant execute on function public.has_shared_api_key(text) to authenticated;

-- ─── user_usage_limits: read-only for users; mutations via SECURITY DEFINER RPCs only ─
drop policy if exists "Users can update own counters" on public.user_usage_limits;

-- ─── documents: replace FOR ALL with explicit policies + WITH CHECK ────────────────
drop policy if exists "Users can manage own documents" on public.documents;
drop policy if exists "documents_select_own" on public.documents;
drop policy if exists "documents_insert_own" on public.documents;
drop policy if exists "documents_update_own" on public.documents;
drop policy if exists "documents_delete_own" on public.documents;

create policy "documents_select_own"
  on public.documents for select
  to authenticated
  using (auth.uid() = user_id);

create policy "documents_insert_own"
  on public.documents for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "documents_update_own"
  on public.documents for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "documents_delete_own"
  on public.documents for delete
  to authenticated
  using (auth.uid() = user_id);

-- ─── lend_borrow: explicit WITH CHECK (mirrors USING; satisfies RLS audit tools) ────
drop policy if exists "lb_update" on public.lend_borrow_entries;
create policy "lb_update" on public.lend_borrow_entries for update
  using (auth.uid() = user_id or auth.uid() = counterparty_user_id)
  with check (auth.uid() = user_id or auth.uid() = counterparty_user_id);

-- ─── splits / connected_apps / export_history: FOR ALL → explicit + WITH CHECK ─────
drop policy if exists "Users can manage own splits" on public.splits;
drop policy if exists "splits_select_own" on public.splits;
drop policy if exists "splits_insert_own" on public.splits;
drop policy if exists "splits_update_own" on public.splits;
drop policy if exists "splits_delete_own" on public.splits;
create policy "splits_select_own" on public.splits for select to authenticated
  using (auth.uid() = user_id);
create policy "splits_insert_own" on public.splits for insert to authenticated
  with check (auth.uid() = user_id);
create policy "splits_update_own" on public.splits for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "splits_delete_own" on public.splits for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can manage own split participants" on public.split_participants;
drop policy if exists "split_participants_select_own" on public.split_participants;
drop policy if exists "split_participants_insert_own" on public.split_participants;
drop policy if exists "split_participants_update_own" on public.split_participants;
drop policy if exists "split_participants_delete_own" on public.split_participants;
create policy "split_participants_select_own" on public.split_participants for select to authenticated
  using (exists (select 1 from public.splits s where s.id = split_id and s.user_id = auth.uid()));
create policy "split_participants_insert_own" on public.split_participants for insert to authenticated
  with check (exists (select 1 from public.splits s where s.id = split_id and s.user_id = auth.uid()));
create policy "split_participants_update_own" on public.split_participants for update to authenticated
  using (exists (select 1 from public.splits s where s.id = split_id and s.user_id = auth.uid()))
  with check (exists (select 1 from public.splits s where s.id = split_id and s.user_id = auth.uid()));
create policy "split_participants_delete_own" on public.split_participants for delete to authenticated
  using (exists (select 1 from public.splits s where s.id = split_id and s.user_id = auth.uid()));

drop policy if exists "Users can manage own connected apps" on public.connected_apps;
drop policy if exists "connected_apps_select_own" on public.connected_apps;
drop policy if exists "connected_apps_insert_own" on public.connected_apps;
drop policy if exists "connected_apps_update_own" on public.connected_apps;
drop policy if exists "connected_apps_delete_own" on public.connected_apps;
create policy "connected_apps_select_own" on public.connected_apps for select to authenticated
  using (auth.uid() = user_id);
create policy "connected_apps_insert_own" on public.connected_apps for insert to authenticated
  with check (auth.uid() = user_id);
create policy "connected_apps_update_own" on public.connected_apps for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "connected_apps_delete_own" on public.connected_apps for delete to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can manage own export history" on public.export_history;
drop policy if exists "export_history_select_own" on public.export_history;
drop policy if exists "export_history_insert_own" on public.export_history;
drop policy if exists "export_history_update_own" on public.export_history;
drop policy if exists "export_history_delete_own" on public.export_history;
create policy "export_history_select_own" on public.export_history for select to authenticated
  using (auth.uid() = user_id);
create policy "export_history_insert_own" on public.export_history for insert to authenticated
  with check (auth.uid() = user_id);
create policy "export_history_update_own" on public.export_history for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "export_history_delete_own" on public.export_history for delete to authenticated
  using (auth.uid() = user_id);

-- ─── A5: column constraints (safe lengths / amount bounds) ─────────────────────────
alter table public.documents
  drop constraint if exists documents_vendor_name_length,
  drop constraint if exists documents_description_length,
  drop constraint if exists documents_amount_range;

alter table public.documents
  add constraint documents_vendor_name_length check (vendor_name is null or length(vendor_name) <= 500),
  add constraint documents_description_length check (description is null or length(description) <= 2000),
  add constraint documents_amount_range check (amount >= 0 and amount <= 9999999999.99);

alter table public.lend_borrow_entries
  drop constraint if exists lbe_counterparty_name_length,
  drop constraint if exists lbe_notes_length,
  drop constraint if exists lbe_amount_range;

alter table public.lend_borrow_entries
  add constraint lbe_counterparty_name_length check (length(counterparty_name) <= 200),
  add constraint lbe_notes_length check (notes is null or length(notes) <= 2000),
  add constraint lbe_amount_range check (amount > 0 and amount <= 9999999999.99);

alter table public.profiles
  drop constraint if exists profiles_display_name_length;

alter table public.profiles
  add constraint profiles_display_name_length check (display_name is null or length(display_name) <= 200);
