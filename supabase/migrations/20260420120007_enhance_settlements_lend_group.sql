-- Enhance existing tables to link into the canonical transactions ledger.

-- group_settlements: add confirmation flow + transaction link
alter table public.group_settlements
  add column if not exists status text not null default 'pending'
    check (status in ('pending','confirmed','rejected')),
  add column if not exists confirmed_at timestamptz,
  add column if not exists transaction_id uuid references public.transactions(id);

-- lend_borrow_entries: add transaction link
alter table public.lend_borrow_entries
  add column if not exists transaction_id uuid references public.transactions(id);

-- group_expenses: add transaction link
alter table public.group_expenses
  add column if not exists transaction_id uuid references public.transactions(id);

-- Indexes for the new FKs
create index if not exists group_settlements_txn_idx on public.group_settlements(transaction_id) where transaction_id is not null;
create index if not exists lend_borrow_txn_idx on public.lend_borrow_entries(transaction_id) where transaction_id is not null;
create index if not exists group_expenses_txn_idx on public.group_expenses(transaction_id) where transaction_id is not null;
