-- AI expense taxonomy for the whole bill (separate from document_type / receipt shape).

alter table public.invoices
  add column if not exists expense_category text;

comment on column public.invoices.expense_category is
  'Primary expense category from OCR (e.g. Food & Dining). document_type stays receipt/invoice shape.';
