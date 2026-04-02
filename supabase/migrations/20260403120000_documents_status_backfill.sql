-- Ensure documents.status is never null for dashboard filters (draft vs saved).
update public.documents
set status = 'saved'
where status is null;

comment on column public.documents.status is 'saved | draft — drafts excluded from spend totals in app queries';
