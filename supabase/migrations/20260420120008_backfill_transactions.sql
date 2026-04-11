-- Backfill canonical transactions from existing documents, group_expenses, and lend_borrow_entries.

-- Phase 1: documents → transactions
insert into public.transactions (
  user_id, amount, currency, date, type, title, description,
  category_id, category_source, source_type, source_document_id,
  effective_amount, status, extracted_data, created_at, updated_at
)
select
  d.user_id,
  d.amount,
  coalesce(d.currency, 'INR'),
  d.date::date,
  'expense',
  coalesce(d.vendor_name, 'Expense'),
  d.description,
  d.category_id,
  d.category_source,
  case
    when d.extracted_data->>'invoice_id' is not null then 'scan'
    else 'manual'
  end,
  d.id,
  d.amount,
  case d.status when 'draft' then 'draft' else 'confirmed' end,
  d.extracted_data,
  d.created_at,
  d.updated_at
from public.documents d
where not exists (
  select 1 from public.transactions t where t.source_document_id = d.id
);

-- Phase 2: link group_expenses to transactions via shared document_id
update public.group_expenses ge
set transaction_id = t.id
from public.transactions t
where t.source_document_id = ge.document_id
  and ge.document_id is not null
  and ge.transaction_id is null;

-- Phase 3: link lend_borrow_entries to transactions via shared document_id
update public.lend_borrow_entries lb
set transaction_id = t.id
from public.transactions t
where t.source_document_id = lb.document_id
  and lb.document_id is not null
  and lb.transaction_id is null;

-- Phase 4: create transactions for group_expenses without document links
insert into public.transactions (
  user_id, amount, currency, date, type, title,
  source_type, group_id, group_expense_id, effective_amount,
  status, created_at
)
select
  ge.paid_by_user_id,
  ge.amount,
  'INR',
  ge.expense_date,
  'expense',
  ge.title,
  'group_split',
  ge.group_id,
  ge.id,
  coalesce(
    (select gep.share_amount from public.group_expense_participants gep
     where gep.expense_id = ge.id and gep.user_id = ge.paid_by_user_id),
    ge.amount
  ),
  'confirmed',
  ge.created_at
from public.group_expenses ge
where ge.transaction_id is null
  and ge.document_id is null;

-- Link back the new transactions
update public.group_expenses ge
set transaction_id = t.id
from public.transactions t
where t.group_expense_id = ge.id
  and ge.transaction_id is null;

-- Phase 5: create transactions for lend_borrow_entries without document links
insert into public.transactions (
  user_id, amount, currency, date, type, title,
  source_type, lend_borrow_id, effective_amount, status, created_at
)
select
  lb.user_id,
  lb.amount,
  'INR',
  lb.created_at::date,
  case lb.type when 'lent' then 'lend' else 'borrow' end,
  coalesce(lb.counterparty_name, 'IOU'),
  'manual',
  lb.id,
  0,
  'confirmed',
  lb.created_at
from public.lend_borrow_entries lb
where lb.transaction_id is null
  and lb.document_id is null;

-- Link back
update public.lend_borrow_entries lb
set transaction_id = t.id
from public.transactions t
where t.lend_borrow_id = lb.id
  and lb.transaction_id is null;
