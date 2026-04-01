-- Shared group expenses: ledger rows + per-user shares; atomic create via RPC.

-- Co-members can see each other's display names (for payer / split UI).
drop policy if exists "profiles_select_group_members" on public.profiles;
create policy "profiles_select_group_members" on public.profiles for select using (
  exists (
    select 1
    from public.expense_group_members m1
    join public.expense_group_members m2 on m1.group_id = m2.group_id
    where m1.user_id = auth.uid()
      and m2.user_id = profiles.id
  )
);

create table public.group_expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.expense_groups(id) on delete cascade,
  paid_by_user_id uuid not null references public.profiles(id) on delete restrict,
  title text not null default 'Expense',
  amount numeric(12, 2) not null check (amount > 0),
  expense_date date not null default (timezone('utc', now()))::date,
  notes text,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index group_expenses_group_id_idx on public.group_expenses (group_id desc);
create index group_expenses_expense_date_idx on public.group_expenses (expense_date desc);

create table public.group_expense_participants (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.group_expenses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  share_amount numeric(12, 2) not null check (share_amount >= 0),
  unique (expense_id, user_id)
);

create index group_expense_participants_expense_idx on public.group_expense_participants (expense_id);

alter table public.group_expenses enable row level security;
alter table public.group_expense_participants enable row level security;

drop policy if exists "ge_select" on public.group_expenses;
create policy "ge_select" on public.group_expenses for select using (
  exists (
    select 1
    from public.expense_group_members m
    where m.group_id = group_expenses.group_id
      and m.user_id = auth.uid()
  )
);

drop policy if exists "ge_update" on public.group_expenses;
create policy "ge_update" on public.group_expenses for update
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

drop policy if exists "ge_delete" on public.group_expenses;
create policy "ge_delete" on public.group_expenses for delete using (created_by = auth.uid());

-- Direct client inserts denied; use create_group_expense RPC (security definer).
drop policy if exists "ge_insert" on public.group_expenses;
create policy "ge_insert" on public.group_expenses for insert with check (false);

drop policy if exists "gep_select" on public.group_expense_participants;
create policy "gep_select" on public.group_expense_participants for select using (
  exists (
    select 1
    from public.group_expenses ge
    join public.expense_group_members m on m.group_id = ge.group_id and m.user_id = auth.uid()
    where ge.id = group_expense_participants.expense_id
  )
);
-- No insert/update/delete policies: participants rows are written only by RPC.

comment on table public.group_expenses is 'Group-scoped expenses; amounts split via group_expense_participants.';
comment on column public.group_expense_participants.share_amount is 'This user''s share of the expense total; sum per expense equals group_expenses.amount.';

create or replace function public.create_group_expense(
  p_group_id uuid,
  p_title text,
  p_amount numeric,
  p_paid_by_user_id uuid,
  p_expense_date date,
  p_shares jsonb
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
    group_id, paid_by_user_id, title, amount, expense_date, created_by
  )
  values (
    p_group_id,
    p_paid_by_user_id,
    coalesce(nullif(trim(p_title), ''), 'Expense'),
    p_amount,
    coalesce(p_expense_date, (timezone('utc', now()))::date),
    auth.uid()
  )
  returning id into eid;

  insert into public.group_expense_participants (expense_id, user_id, share_amount)
  select eid, x.user_id, x.share_amount
  from jsonb_to_recordset(p_shares) as x(user_id uuid, share_amount numeric);

  return eid;
end;
$$;

grant execute on function public.create_group_expense(uuid, text, numeric, uuid, date, jsonb) to authenticated;
