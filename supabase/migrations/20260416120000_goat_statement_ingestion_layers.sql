-- Align GOAT statement ingestion with 3-layer model (raw → parsed → normalized).
-- Maps to product spec: raw extractions + header fields + row reviews + txn extensions.
-- Existing tables remain: statement_imports ≈ upload+job, statement_transactions_raw = parsed rows,
-- statement_transactions = normalized, statement_import_reviews = import-level queue,
-- statement_document_links, canonical_financial_events, statement_accounts.

-- ─── statement_imports: pipeline + header summary fields ───────────
alter table public.statement_imports
  add column if not exists mime_type text,
  add column if not exists source_hint text,
  add column if not exists document_family text,
  add column if not exists opening_balance numeric(14,2),
  add column if not exists closing_balance numeric(14,2),
  add column if not exists total_debit numeric(14,2),
  add column if not exists total_credit numeric(14,2),
  add column if not exists account_holder_name text,
  add column if not exists has_running_balance boolean,
  add column if not exists amount_representation text,
  add column if not exists extractor_version text,
  add column if not exists ai_model_last text;

comment on column public.statement_imports.document_family is
  'Product classification: bank_statement, credit_card_statement, wallet_statement, loan_statement, payment_receipt, upi_receipt, account_export_csv, passbook_scan, unknown_financial_document, etc.';
comment on column public.statement_imports.source_hint is
  'User-selected hint at upload (bank, card, wallet, upi, auto).';

alter table public.statement_imports
  drop constraint if exists statement_imports_import_status_check;

alter table public.statement_imports
  add constraint statement_imports_import_status_check
  check (import_status in (
    'uploaded',
    'extracting',
    'classifying',
    'parsing',
    'validating',
    'processing',
    'parsed',
    'needs_review',
    'imported',
    'failed',
    'archived'
  ));

-- ─── Layer 1: full raw extraction blob per import (separate from per-row raw_payload) ─
create table if not exists public.statement_raw_extractions (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.statement_imports(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  raw_text text,
  raw_tables jsonb,
  ocr_json jsonb,
  page_count int,
  extraction_meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists statement_raw_extractions_import_idx
  on public.statement_raw_extractions (import_id);

alter table public.statement_raw_extractions enable row level security;

create policy "statement_raw_extractions_select_own"
  on public.statement_raw_extractions for select using (auth.uid() = user_id);
create policy "statement_raw_extractions_insert_own"
  on public.statement_raw_extractions for insert with check (auth.uid() = user_id);
create policy "statement_raw_extractions_delete_own"
  on public.statement_raw_extractions for delete using (auth.uid() = user_id);

-- ─── Row-level review queue (uncertain rows / fields) ───────────────
create table if not exists public.statement_row_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  import_id uuid not null references public.statement_imports(id) on delete cascade,
  statement_transaction_id uuid references public.statement_transactions(id) on delete cascade,
  row_index int not null default -1,
  issue_type text not null,
  issue_message text not null,
  suggested_fix jsonb not null default '{}'::jsonb,
  review_status text not null default 'open' check (review_status in ('open','resolved','ignored')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists statement_row_reviews_user_idx
  on public.statement_row_reviews (user_id, created_at desc);
create index if not exists statement_row_reviews_import_idx
  on public.statement_row_reviews (import_id);

alter table public.statement_row_reviews enable row level security;

create policy "statement_row_reviews_select_own"
  on public.statement_row_reviews for select using (auth.uid() = user_id);
create policy "statement_row_reviews_insert_own"
  on public.statement_row_reviews for insert with check (auth.uid() = user_id);
create policy "statement_row_reviews_update_own"
  on public.statement_row_reviews for update using (auth.uid() = user_id);
create policy "statement_row_reviews_delete_own"
  on public.statement_row_reviews for delete using (auth.uid() = user_id);

-- ─── statement_transactions: normalized layer extensions ────────────
alter table public.statement_transactions
  add column if not exists cheque_number text,
  add column if not exists counterparty_name text,
  add column if not exists payment_channel text,
  add column if not exists category_primary text,
  add column if not exists category_secondary text,
  add column if not exists is_internal_transfer boolean not null default false,
  add column if not exists is_salary boolean not null default false,
  add column if not exists is_emi boolean not null default false,
  add column if not exists is_cash_withdrawal boolean not null default false,
  add column if not exists raw_row_text text;

-- ─── statement_accounts: forecast toggle ───────────────────────────
alter table public.statement_accounts
  add column if not exists include_in_forecast boolean not null default true;

comment on column public.statement_accounts.include_in_forecast is
  'When false, statement-derived debits from this account can be excluded from horizon forecast (future client use).';

-- Allow image-based uploads (UPI/screenshot) stored as statement-files; parsing may defer to OCR/AI.
alter table public.statement_imports
  drop constraint if exists statement_imports_source_type_check;

alter table public.statement_imports
  add constraint statement_imports_source_type_check
  check (source_type in (
    'pdf_digital','pdf_scanned','csv','xls','xlsx','image'
  ));
