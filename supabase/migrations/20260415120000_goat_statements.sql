-- GOAT Statements: ingestion, normalized txns, document links, canonical events, storage bucket.

-- ─── profiles: analysis lens (GOAT-wide) ───────────────────────────
alter table public.profiles
  add column if not exists goat_analysis_lens text not null default 'smart';

alter table public.profiles
  drop constraint if exists profiles_goat_analysis_lens_check;

alter table public.profiles
  add constraint profiles_goat_analysis_lens_check
  check (goat_analysis_lens in ('smart','statements_only','ocr_only','combined_raw'));

comment on column public.profiles.goat_analysis_lens is
  'GOAT analysis lens: smart (deduped), statements_only, ocr_only (bills/receipts), combined_raw (may double-count).';

-- ─── documents: exclude from Smart lens when linked as stmt duplicate ─
alter table public.documents
  add column if not exists exclude_from_goat_smart_analytics boolean not null default false;

comment on column public.documents.exclude_from_goat_smart_analytics is
  'When true, Smart lens skips this row in merged spend (statement txn is primary).';

-- ─── statement_imports ────────────────────────────────────────────
create table if not exists public.statement_imports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_type text not null check (source_type in (
    'pdf_digital','pdf_scanned','csv','xls','xlsx'
  )),
  file_name text not null,
  storage_path text not null,
  file_hash text not null,
  import_status text not null default 'uploaded' check (import_status in (
    'uploaded','processing','parsed','needs_review','imported','failed','archived'
  )),
  detected_institution text,
  detected_account_name text,
  detected_account_mask text,
  statement_start_date date,
  statement_end_date date,
  transaction_count int not null default 0,
  parse_confidence numeric(5,2),
  import_mode text not null default 'smart' check (import_mode in (
    'smart','statements_only','keep_separate'
  )),
  lens_override text check (lens_override is null or lens_override in (
    'smart','statements_only','ocr_only','combined_raw'
  )),
  parser_version text,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists statement_imports_user_created_idx
  on public.statement_imports (user_id, created_at desc);

-- ─── statement_accounts ───────────────────────────────────────────
create table if not exists public.statement_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  institution_name text,
  account_name text not null,
  account_type text not null check (account_type in (
    'bank','credit_card','wallet','loan','other'
  )),
  account_mask text,
  currency text not null default 'INR',
  source text not null default 'statement_import' check (source in (
    'statement_import','manual','aggregated'
  )),
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists statement_accounts_user_idx
  on public.statement_accounts (user_id);

-- ─── statement_transactions_raw ───────────────────────────────────
create table if not exists public.statement_transactions_raw (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.statement_imports(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  row_index int not null,
  raw_payload jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists statement_txn_raw_import_idx
  on public.statement_transactions_raw (import_id);

-- ─── statement_transactions ───────────────────────────────────────
create table if not exists public.statement_transactions (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.statement_imports(id) on delete cascade,
  account_id uuid references public.statement_accounts(id) on delete set null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  txn_date date not null,
  post_date date,
  value_date date,
  description_raw text not null,
  description_clean text,
  merchant_normalized text,
  reference_no text,
  amount numeric(14,2) not null,
  direction text not null check (direction in ('debit','credit')),
  signed_amount numeric(14,2) not null,
  balance numeric(14,2),
  currency text not null default 'INR',
  txn_type text check (txn_type is null or txn_type in (
    'purchase','atm','transfer','fee','interest','refund','income','payment','emi','subscription','cash','other'
  )),
  category_id uuid references public.categories(id) on delete set null,
  status text not null default 'active' check (status in (
    'active','duplicate','reversed','ignored','needs_review'
  )),
  unique_fingerprint text,
  confidence numeric(5,2),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists statement_transactions_user_date_idx
  on public.statement_transactions (user_id, txn_date);
create index if not exists statement_transactions_account_date_idx
  on public.statement_transactions (account_id, txn_date);
create index if not exists statement_transactions_fingerprint_idx
  on public.statement_transactions (user_id, unique_fingerprint);

-- ─── statement_document_links ───────────────────────────────────────
create table if not exists public.statement_document_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  statement_transaction_id uuid not null references public.statement_transactions(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  match_type text not null check (match_type in ('exact','high_confidence','possible','manual')),
  link_role text not null default 'duplicate_evidence' check (link_role in (
    'duplicate_evidence','supporting_receipt','partial_match'
  )),
  score numeric(5,2) not null,
  is_excluded_from_double_count boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists statement_doc_links_user_stmt_idx
  on public.statement_document_links (user_id, statement_transaction_id);
create index if not exists statement_doc_links_user_doc_idx
  on public.statement_document_links (user_id, document_id);

-- ─── canonical_financial_events ───────────────────────────────────
create table if not exists public.canonical_financial_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary_source text not null check (primary_source in ('statement','document','manual')),
  primary_statement_transaction_id uuid references public.statement_transactions(id) on delete cascade,
  primary_document_id uuid references public.documents(id) on delete set null,
  event_date date not null,
  merchant_name text,
  amount numeric(14,2) not null,
  signed_amount numeric(14,2) not null,
  direction text not null check (direction in ('debit','credit')),
  currency text not null default 'INR',
  category_id uuid references public.categories(id) on delete set null,
  account_id uuid references public.statement_accounts(id) on delete set null,
  dedupe_status text not null default 'resolved' check (dedupe_status in (
    'resolved','needs_review','manual_override'
  )),
  analysis_scope text not null default 'goat' check (analysis_scope in ('goat','legacy','both')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists canonical_events_user_date_idx
  on public.canonical_financial_events (user_id, event_date);

-- ─── updated_at triggers (match GOAT goals style) ─────────────────
create or replace function public.goat_statements_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists statement_imports_touch_updated_at on public.statement_imports;
create trigger statement_imports_touch_updated_at
  before update on public.statement_imports
  for each row execute procedure public.goat_statements_touch_updated_at();

drop trigger if exists statement_accounts_touch_updated_at on public.statement_accounts;
create trigger statement_accounts_touch_updated_at
  before update on public.statement_accounts
  for each row execute procedure public.goat_statements_touch_updated_at();

drop trigger if exists statement_transactions_touch_updated_at on public.statement_transactions;
create trigger statement_transactions_touch_updated_at
  before update on public.statement_transactions
  for each row execute procedure public.goat_statements_touch_updated_at();

drop trigger if exists canonical_financial_events_touch_updated_at on public.canonical_financial_events;
create trigger canonical_financial_events_touch_updated_at
  before update on public.canonical_financial_events
  for each row execute procedure public.goat_statements_touch_updated_at();

-- ─── RLS ───────────────────────────────────────────────────────────
alter table public.statement_imports enable row level security;
alter table public.statement_accounts enable row level security;
alter table public.statement_transactions_raw enable row level security;
alter table public.statement_transactions enable row level security;
alter table public.statement_document_links enable row level security;
alter table public.canonical_financial_events enable row level security;

create policy "statement_imports_select_own" on public.statement_imports
  for select using (auth.uid() = user_id);
create policy "statement_imports_insert_own" on public.statement_imports
  for insert with check (auth.uid() = user_id);
create policy "statement_imports_update_own" on public.statement_imports
  for update using (auth.uid() = user_id);
create policy "statement_imports_delete_own" on public.statement_imports
  for delete using (auth.uid() = user_id);

create policy "statement_accounts_select_own" on public.statement_accounts
  for select using (auth.uid() = user_id);
create policy "statement_accounts_insert_own" on public.statement_accounts
  for insert with check (auth.uid() = user_id);
create policy "statement_accounts_update_own" on public.statement_accounts
  for update using (auth.uid() = user_id);
create policy "statement_accounts_delete_own" on public.statement_accounts
  for delete using (auth.uid() = user_id);

create policy "statement_txn_raw_select_own" on public.statement_transactions_raw
  for select using (auth.uid() = user_id);
create policy "statement_txn_raw_insert_own" on public.statement_transactions_raw
  for insert with check (auth.uid() = user_id);
create policy "statement_txn_raw_delete_own" on public.statement_transactions_raw
  for delete using (auth.uid() = user_id);

create policy "statement_txn_select_own" on public.statement_transactions
  for select using (auth.uid() = user_id);
create policy "statement_txn_insert_own" on public.statement_transactions
  for insert with check (auth.uid() = user_id);
create policy "statement_txn_update_own" on public.statement_transactions
  for update using (auth.uid() = user_id);
create policy "statement_txn_delete_own" on public.statement_transactions
  for delete using (auth.uid() = user_id);

create policy "statement_doc_links_select_own" on public.statement_document_links
  for select using (auth.uid() = user_id);
create policy "statement_doc_links_insert_own" on public.statement_document_links
  for insert with check (auth.uid() = user_id);
create policy "statement_doc_links_update_own" on public.statement_document_links
  for update using (auth.uid() = user_id);
create policy "statement_doc_links_delete_own" on public.statement_document_links
  for delete using (auth.uid() = user_id);

create policy "canonical_events_select_own" on public.canonical_financial_events
  for select using (auth.uid() = user_id);
create policy "canonical_events_insert_own" on public.canonical_financial_events
  for insert with check (auth.uid() = user_id);
create policy "canonical_events_update_own" on public.canonical_financial_events
  for update using (auth.uid() = user_id);
create policy "canonical_events_delete_own" on public.canonical_financial_events
  for delete using (auth.uid() = user_id);

-- ─── Storage bucket (private) ──────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit)
values ('statement-files', 'statement-files', false, 15728640)
on conflict (id) do update set file_size_limit = excluded.file_size_limit;

-- Path: {uid}/statements/{yyyy}/{mm}/{import_id}/{file_name}
drop policy if exists "statement_files_select_own" on storage.objects;
drop policy if exists "statement_files_insert_own" on storage.objects;
drop policy if exists "statement_files_update_own" on storage.objects;
drop policy if exists "statement_files_delete_own" on storage.objects;

create policy "statement_files_select_own"
  on storage.objects for select
  using (
    bucket_id = 'statement-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "statement_files_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'statement-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "statement_files_update_own"
  on storage.objects for update
  using (
    bucket_id = 'statement-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "statement_files_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'statement-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
