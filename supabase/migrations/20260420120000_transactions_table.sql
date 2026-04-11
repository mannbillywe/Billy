-- Canonical financial transaction ledger
-- Every financial event flows through this table.

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(12,2) not null,
  currency text not null default 'INR',
  date date not null,
  type text not null check (type in ('expense','income','transfer','lend','borrow','settlement_out','settlement_in','refund','recurring')),
  title text not null,
  description text,
  category_id uuid references public.categories(id),
  category_source text check (category_source in ('manual','ai','rule','import','legacy')),
  payment_method text,
  source_type text not null check (source_type in ('scan','manual','statement','group_split','settlement','recurring','linked_account','system')),
  source_document_id uuid references public.documents(id) on delete set null,
  source_import_id uuid,
  effective_amount numeric(12,2),
  group_id uuid references public.expense_groups(id) on delete set null,
  group_expense_id uuid,
  lend_borrow_id uuid,
  settlement_id uuid,
  status text not null default 'confirmed' check (status in ('draft','confirmed','pending','voided','disputed')),
  is_recurring boolean not null default false,
  recurring_series_id uuid,
  notes text,
  tags text[],
  extracted_data jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index transactions_user_id_idx on public.transactions(user_id);
create index transactions_date_idx on public.transactions(user_id, date desc);
create index transactions_type_idx on public.transactions(user_id, type);
create index transactions_source_doc_idx on public.transactions(source_document_id) where source_document_id is not null;
create index transactions_group_idx on public.transactions(group_id) where group_id is not null;
create index transactions_category_idx on public.transactions(category_id) where category_id is not null;
create index transactions_status_idx on public.transactions(user_id, status);

alter table public.transactions enable row level security;
create policy "txn_select" on public.transactions for select using (auth.uid() = user_id);
create policy "txn_insert" on public.transactions for insert with check (auth.uid() = user_id);
create policy "txn_update" on public.transactions for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "txn_delete" on public.transactions for delete using (auth.uid() = user_id);

create trigger transactions_touch_updated_at
  before update on public.transactions
  for each row execute function set_invoice_updated_at();
