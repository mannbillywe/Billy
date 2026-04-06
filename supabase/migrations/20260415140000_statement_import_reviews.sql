-- Optional audit queue for parser/mapping issues and scanned-PDF placeholders.

create table if not exists public.statement_import_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  import_id uuid references public.statement_imports(id) on delete cascade,
  review_type text not null,
  payload jsonb not null default '{}'::jsonb,
  resolved boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists statement_import_reviews_user_idx
  on public.statement_import_reviews (user_id, created_at desc);
create index if not exists statement_import_reviews_import_idx
  on public.statement_import_reviews (import_id);

alter table public.statement_import_reviews enable row level security;

create policy "statement_import_reviews_select_own"
  on public.statement_import_reviews for select using (auth.uid() = user_id);
create policy "statement_import_reviews_insert_own"
  on public.statement_import_reviews for insert with check (auth.uid() = user_id);
create policy "statement_import_reviews_update_own"
  on public.statement_import_reviews for update using (auth.uid() = user_id);
create policy "statement_import_reviews_delete_own"
  on public.statement_import_reviews for delete using (auth.uid() = user_id);
