-- Disputes for group expenses, settlements, lend/borrow entries.

create table if not exists public.disputes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  entity_type text not null check (entity_type in ('group_expense','settlement','lend_borrow')),
  entity_id uuid not null,
  group_id uuid references public.expense_groups(id),
  transaction_id uuid references public.transactions(id),
  reason text not null,
  proposed_amount numeric(12,2),
  proposed_resolution text,
  status text not null default 'open' check (status in ('open','acknowledged','resolved','withdrawn')),
  resolved_by uuid references public.profiles(id),
  resolution_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index disputes_user_idx on public.disputes(user_id);
create index disputes_group_idx on public.disputes(group_id) where group_id is not null;
create index disputes_entity_idx on public.disputes(entity_type, entity_id);

alter table public.disputes enable row level security;
create policy "disputes_select" on public.disputes for select
  using (auth.uid() = user_id or (group_id is not null and public.user_is_expense_group_member(group_id)));
create policy "disputes_insert" on public.disputes for insert with check (auth.uid() = user_id);
create policy "disputes_update" on public.disputes for update
  using (auth.uid() = user_id or auth.uid() = resolved_by);

create trigger disputes_touch_updated_at
  before update on public.disputes
  for each row execute function set_invoice_updated_at();
