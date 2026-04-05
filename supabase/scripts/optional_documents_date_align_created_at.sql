-- Optional: align documents.date with when the row was saved for very old invoice dates.
--
-- Problem this addresses: OCR often stores the vendor's invoice date in documents.date.
-- Dashboard "this week" and analytics used to look only at documents.date, so new scans
-- could show in all-time category totals but not in week / recent ranges.
--
-- The Flutter app now also considers created_at for those views. You usually do NOT need
-- this script. Use it only if you want documents.date itself updated for exports, SQL
-- reports, or third-party tools that only read documents.date.
--
-- Review the WHERE clause, then uncomment and run in Supabase SQL Editor.

-- update public.documents d
-- set
--   date = (d.created_at at time zone 'utc')::date,
--   updated_at = now()
-- where d.status is distinct from 'draft'
--   and d.date < ((d.created_at at time zone 'utc')::date - interval '90 days');

-- Optional: preview how many rows would change (safe to run as-is):
select count(*) as rows_that_would_align
from public.documents d
where d.status is distinct from 'draft'
  and d.date < ((d.created_at at time zone 'utc')::date - interval '90 days');
