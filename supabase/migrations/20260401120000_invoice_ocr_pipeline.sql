-- Invoice OCR pipeline: Storage + Edge Function (Gemini) + structured tables
-- Bucket: invoice-files — paths: {user_id}/yyyy/mm/{invoice_id}/{filename}

create or replace function public.set_invoice_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ─── invoices ─────────────────────────────────────────────────────────────
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  group_id uuid references public.expense_groups(id) on delete set null,
  file_path text not null,
  file_name text,
  mime_type text,
  status text not null default 'uploaded'
    check (status in ('uploaded', 'processing', 'completed', 'failed', 'reviewed', 'confirmed')),
  source text,
  ocr_provider text,
  document_type text,
  vendor_name text,
  vendor_gstin text,
  invoice_number text,
  invoice_date date,
  due_date date,
  subtotal numeric(14,2),
  cgst numeric(14,2),
  sgst numeric(14,2),
  igst numeric(14,2),
  cess numeric(14,2),
  discount numeric(14,2),
  total_tax numeric(14,2),
  total numeric(14,2),
  currency text default 'INR',
  payment_status text,
  raw_text text,
  confidence numeric(6,4),
  review_required boolean not null default true,
  processing_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists invoices_user_id_idx on public.invoices(user_id);
create index if not exists invoices_user_status_idx on public.invoices(user_id, status);
create index if not exists invoices_created_at_idx on public.invoices(created_at desc);

drop trigger if exists invoices_updated_at on public.invoices;
create trigger invoices_updated_at
  before update on public.invoices
  for each row execute procedure public.set_invoice_updated_at();

-- ─── invoice_items ────────────────────────────────────────────────────────
create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_user_id uuid references public.profiles(id) on delete set null,
  description text,
  quantity numeric(14,4),
  unit_price numeric(14,4),
  amount numeric(14,2),
  tax_percent numeric(8,4),
  tax_amount numeric(14,2),
  item_code text,
  category text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists invoice_items_invoice_id_idx on public.invoice_items(invoice_id);
create index if not exists invoice_items_user_id_idx on public.invoice_items(user_id);

drop trigger if exists invoice_items_updated_at on public.invoice_items;
create trigger invoice_items_updated_at
  before update on public.invoice_items
  for each row execute procedure public.set_invoice_updated_at();

-- ─── invoice_ocr_logs ─────────────────────────────────────────────────────
create table if not exists public.invoice_ocr_logs (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid references public.invoices(id) on delete set null,
  user_id uuid references public.profiles(id) on delete set null,
  request_payload jsonb,
  response_payload jsonb,
  normalized_payload jsonb,
  status text not null,
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists invoice_ocr_logs_invoice_id_idx on public.invoice_ocr_logs(invoice_id);
create index if not exists invoice_ocr_logs_user_id_idx on public.invoice_ocr_logs(user_id);

-- ─── invoice_processing_events (timeline) ───────────────────────────────
create table if not exists public.invoice_processing_events (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  step text not null,
  detail jsonb,
  created_at timestamptz not null default now()
);

create index if not exists invoice_processing_events_invoice_idx on public.invoice_processing_events(invoice_id, created_at);

-- ─── RLS ─────────────────────────────────────────────────────────────────
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
alter table public.invoice_ocr_logs enable row level security;
alter table public.invoice_processing_events enable row level security;

drop policy if exists "invoices_select_own" on public.invoices;
create policy "invoices_select_own" on public.invoices
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "invoices_insert_own" on public.invoices;
create policy "invoices_insert_own" on public.invoices
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and (
      group_id is null
      or exists (
        select 1 from public.expense_group_members egm
        where egm.group_id = invoices.group_id and egm.user_id = auth.uid()
      )
    )
  );

drop policy if exists "invoices_update_own" on public.invoices;
create policy "invoices_update_own" on public.invoices
  for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and (
      group_id is null
      or exists (
        select 1 from public.expense_group_members egm
        where egm.group_id = invoices.group_id and egm.user_id = auth.uid()
      )
    )
  );

drop policy if exists "invoices_delete_own" on public.invoices;
create policy "invoices_delete_own" on public.invoices
  for delete to authenticated
  using (user_id = auth.uid());

drop policy if exists "invoice_items_all_own" on public.invoice_items;
create policy "invoice_items_all_own" on public.invoice_items
  for all to authenticated
  using (
    user_id = auth.uid()
    and exists (select 1 from public.invoices i where i.id = invoice_items.invoice_id and i.user_id = auth.uid())
  )
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.invoices i where i.id = invoice_items.invoice_id and i.user_id = auth.uid())
  );

drop policy if exists "invoice_ocr_logs_select_own" on public.invoice_ocr_logs;
create policy "invoice_ocr_logs_select_own" on public.invoice_ocr_logs
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "invoice_ocr_logs_insert_own" on public.invoice_ocr_logs;
create policy "invoice_ocr_logs_insert_own" on public.invoice_ocr_logs
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "invoice_events_select_own" on public.invoice_processing_events;
create policy "invoice_events_select_own" on public.invoice_processing_events
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "invoice_events_insert_own" on public.invoice_processing_events;
create policy "invoice_events_insert_own" on public.invoice_processing_events
  for insert to authenticated
  with check (user_id = auth.uid());

-- ─── Storage bucket ───────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'invoice-files',
  'invoice-files',
  false,
  16777216,
  array['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "invoice_files_insert_own" on storage.objects;
create policy "invoice_files_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'invoice-files'
    and split_part(name, '/', 1) = auth.uid()::text
  );

drop policy if exists "invoice_files_select_own" on storage.objects;
create policy "invoice_files_select_own" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'invoice-files'
    and split_part(name, '/', 1) = auth.uid()::text
  );

drop policy if exists "invoice_files_update_own" on storage.objects;
create policy "invoice_files_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'invoice-files'
    and split_part(name, '/', 1) = auth.uid()::text
  );

drop policy if exists "invoice_files_delete_own" on storage.objects;
create policy "invoice_files_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'invoice-files'
    and split_part(name, '/', 1) = auth.uid()::text
  );
