-- Optional link from group_expenses to documents (same scan save as vault row).

alter table public.group_expenses
  add column if not exists document_id uuid references public.documents(id) on delete set null;

create index if not exists group_expenses_document_id_idx on public.group_expenses (document_id);

comment on column public.group_expenses.document_id is
  'Optional documents.id from the receipt/invoice row created in the same save flow.';

drop function if exists public.create_group_expense(uuid, text, numeric, uuid, date, jsonb);

create or replace function public.create_group_expense(
  p_group_id uuid,
  p_title text,
  p_amount numeric,
  p_paid_by_user_id uuid,
  p_expense_date date,
  p_shares jsonb,
  p_document_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  eid uuid;
  sum_shares numeric;
  share_count int;
  distinct_users int;
begin
  if not exists (
    select 1 from public.expense_group_members m
    where m.group_id = p_group_id and m.user_id = auth.uid()
  ) then
    raise exception 'Not a group member';
  end if;

  if not exists (
    select 1 from public.expense_group_members m
    where m.group_id = p_group_id and m.user_id = p_paid_by_user_id
  ) then
    raise exception 'Payer is not a group member';
  end if;

  if p_document_id is not null then
    if not exists (
      select 1 from public.documents d
      where d.id = p_document_id and d.user_id = auth.uid()
    ) then
      raise exception 'Document not found or not owned';
    end if;
  end if;

  select count(*)::int, count(distinct user_id)::int, coalesce(sum(share_amount), 0)
  into share_count, distinct_users, sum_shares
  from jsonb_to_recordset(p_shares) as x(user_id uuid, share_amount numeric);

  if share_count = 0 then
    raise exception 'At least one share row is required';
  end if;

  if distinct_users <> share_count then
    raise exception 'Duplicate user in shares';
  end if;

  if abs(sum_shares - p_amount) > 0.01 then
    raise exception 'Share sum must equal expense amount';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_shares) as x(user_id uuid, share_amount numeric)
    where share_amount < 0
       or not exists (
         select 1 from public.expense_group_members m
         where m.group_id = p_group_id and m.user_id = x.user_id
       )
  ) then
    raise exception 'Invalid shares or user not in group';
  end if;

  insert into public.group_expenses (
    group_id, paid_by_user_id, title, amount, expense_date, created_by, document_id
  )
  values (
    p_group_id,
    p_paid_by_user_id,
    coalesce(nullif(trim(p_title), ''), 'Expense'),
    p_amount,
    coalesce(p_expense_date, (timezone('utc', now()))::date),
    auth.uid(),
    p_document_id
  )
  returning id into eid;

  insert into public.group_expense_participants (expense_id, user_id, share_amount)
  select eid, x.user_id, x.share_amount
  from jsonb_to_recordset(p_shares) as x(user_id uuid, share_amount numeric);

  return eid;
end;
$$;

grant execute on function public.create_group_expense(uuid, text, numeric, uuid, date, jsonb, uuid) to authenticated;
