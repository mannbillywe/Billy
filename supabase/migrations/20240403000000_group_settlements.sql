-- Record payments between group members; adjusts net balances in the app.

create table public.group_settlements (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.expense_groups(id) on delete cascade,
  payer_user_id uuid not null references public.profiles(id) on delete restrict,
  payee_user_id uuid not null references public.profiles(id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  note text,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (payer_user_id <> payee_user_id)
);

create index group_settlements_group_idx on public.group_settlements (group_id, created_at desc);

alter table public.group_settlements enable row level security;

drop policy if exists "gs_select" on public.group_settlements;
create policy "gs_select" on public.group_settlements for select using (
  exists (
    select 1
    from public.expense_group_members m
    where m.group_id = group_settlements.group_id
      and m.user_id = auth.uid()
  )
);

drop policy if exists "gs_insert" on public.group_settlements;
create policy "gs_insert" on public.group_settlements for insert with check (
  auth.uid() = payer_user_id
  and auth.uid() = created_by
  and exists (
    select 1 from public.expense_group_members m
    where m.group_id = group_settlements.group_id and m.user_id = payer_user_id
  )
  and exists (
    select 1 from public.expense_group_members m
    where m.group_id = group_settlements.group_id and m.user_id = payee_user_id
  )
);

drop policy if exists "gs_delete" on public.group_settlements;
create policy "gs_delete" on public.group_settlements for delete using (created_by = auth.uid());

comment on table public.group_settlements is 'Payer paid payee toward group balance; client adjusts net = expense_net[payer]-=amount, expense_net[payee]+=amount.';
