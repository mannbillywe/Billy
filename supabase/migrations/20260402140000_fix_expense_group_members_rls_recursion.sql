-- expense_group_members.egm_select used a self-referential EXISTS on the same table,
-- which causes infinite recursion (42P17) when other policies (e.g. invoices, profiles)
-- query membership. Use a SECURITY DEFINER helper so the membership check bypasses RLS.

create or replace function public.user_is_expense_group_member(_group_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.expense_group_members m
    where m.group_id = _group_id
      and m.user_id = (select auth.uid())
  );
$$;

comment on function public.user_is_expense_group_member(uuid) is
  'RLS-safe membership check; avoids recursive policies on expense_group_members.';

revoke all on function public.user_is_expense_group_member(uuid) from public;
grant execute on function public.user_is_expense_group_member(uuid) to authenticated;
grant execute on function public.user_is_expense_group_member(uuid) to service_role;

drop policy if exists "egm_select" on public.expense_group_members;
create policy "egm_select" on public.expense_group_members for select using (
  public.user_is_expense_group_member(group_id)
);
