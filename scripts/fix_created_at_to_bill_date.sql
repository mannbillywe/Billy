-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Fix created_at → match bill date for demo data                    ║
-- ║  Paste your UUID below and run in Supabase SQL Editor.             ║
-- ╚══════════════════════════════════════════════════════════════════════╝

UPDATE public.documents
SET    created_at = date::timestamptz
WHERE  user_id = 'f308f807-00eb-46ce-9468-63cd7c8d3c0f'
  AND  date IS NOT NULL;

UPDATE public.transactions
SET    created_at = date::timestamptz
WHERE  user_id = 'f308f807-00eb-46ce-9468-63cd7c8d3c0f'
  AND  date IS NOT NULL;
