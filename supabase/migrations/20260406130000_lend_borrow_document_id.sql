-- Link lend/borrow entries to the document created from the same scan/invoice save (OCR flow).
alter table public.lend_borrow_entries
  add column if not exists document_id uuid references public.documents(id) on delete set null;

create index if not exists lend_borrow_document_id_idx
  on public.lend_borrow_entries(document_id)
  where document_id is not null;

comment on column public.lend_borrow_entries.document_id is
  'Optional: documents.id from the receipt/invoice save that recorded this lend/borrow (null for manual adds).';
