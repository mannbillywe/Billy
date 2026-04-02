-- Structured category provenance for analytics and audits.

alter table public.documents
  add column if not exists category_source text
  check (
    category_source is null
    or category_source in ('manual', 'ai', 'rule', 'legacy')
  );

comment on column public.documents.category_source is
  'manual = user UI; ai = OCR/extraction save; rule = name/id resolution or backfill; legacy = unknown pre-migration';

-- Existing rows with a category link but no source
update public.documents
set category_source = 'legacy'
where category_id is not null
  and category_source is null;

-- Rule-based: first comma segment of description matches a category name (global or same user)
update public.documents d
set
  category_id = m.cat_id,
  category_source = 'rule'
from (
  select distinct on (x.doc_id)
    x.doc_id,
    x.cat_id
  from (
    select
      d2.id as doc_id,
      c.id as cat_id,
      case when c.user_id is not distinct from d2.user_id then 0 else 1 end as pref
    from public.documents d2
    inner join public.categories c
      on trim(lower(split_part(coalesce(d2.description, ''), ',', 1))) = lower(trim(c.name))
      and (c.user_id is null or c.user_id = d2.user_id)
    where d2.category_id is null
      and coalesce(trim(d2.description), '') <> ''
  ) x
  order by x.doc_id, x.pref
) m
where d.id = m.doc_id;
