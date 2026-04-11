-- Bank/card statement file import tracking.

create table if not exists public.statement_imports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  file_path text not null,
  file_name text not null,
  mime_type text,
  source_type text not null default 'upload' check (source_type in ('upload','email','api')),
  account_name text,
  account_type text,
  institution_name text,
  statement_period_start date,
  statement_period_end date,
  status text not null default 'uploaded' check (status in ('uploaded','processing','review','completed','failed')),
  row_count integer,
  imported_count integer default 0,
  skipped_count integer default 0,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index statement_imports_user_idx on public.statement_imports(user_id, created_at desc);

alter table public.statement_imports enable row level security;
create policy "si_select" on public.statement_imports for select using (auth.uid() = user_id);
create policy "si_insert" on public.statement_imports for insert with check (auth.uid() = user_id);
create policy "si_update" on public.statement_imports for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "si_delete" on public.statement_imports for delete using (auth.uid() = user_id);

create trigger statement_imports_touch_updated_at
  before update on public.statement_imports
  for each row execute function set_invoice_updated_at();
