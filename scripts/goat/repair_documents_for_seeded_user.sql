-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  Goat Mode — DOCUMENT REPAIR for the seeded demo user                     ║
-- ║  Target user: 3d8238ac-97bd-49e5-9ee7-1966447bae7c                        ║
-- ║                                                                           ║
-- ║  Why                                                                      ║
-- ║  ---                                                                      ║
-- ║  The earlier version of seed_user_3d8238ac.sql deleted rows in            ║
-- ║  public.documents but only re-populated public.transactions. The          ║
-- ║  Goat Mode compute layer reads transactions; the rest of Billy            ║
-- ║  (dashboard spend cards, analytics totals, spend-trend charts,            ║
-- ║  category breakdown, savings tips) reads public.documents via             ║
-- ║  SupabaseService.fetchDocuments(). Result: every pre-Goat widget          ║
-- ║  rendered zero math on the seeded account.                                ║
-- ║                                                                           ║
-- ║  This script is idempotent and NON-DESTRUCTIVE: it inserts one            ║
-- ║  document row per seeded expense transaction that does not already        ║
-- ║  have a corresponding document (keyed on                                  ║
-- ║  extracted_data.source_transaction_id). Running it twice does             ║
-- ║  nothing the second time; it never deletes or updates existing rows.      ║
-- ║                                                                           ║
-- ║  Run                                                                      ║
-- ║  ---                                                                      ║
-- ║    Paste into Supabase SQL Editor (use service-role session), OR:         ║
-- ║    psql "$DATABASE_URL" -f scripts/goat/repair_documents_for_seeded_user.sql
-- ╚═══════════════════════════════════════════════════════════════════════════╝

DO $$
DECLARE
  uid         uuid := '3d8238ac-97bd-49e5-9ee7-1966447bae7c';
  inserted    int;
  before_cnt  int;
  after_cnt   int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = uid) THEN
    RAISE EXCEPTION
      'No profiles row for %. Sign the user up first, then rerun.', uid;
  END IF;

  SELECT count(*) INTO before_cnt FROM public.documents WHERE user_id = uid;

  WITH missing AS (
    SELECT t.*
    FROM public.transactions t
    LEFT JOIN public.documents d
      ON  d.user_id = t.user_id
      AND d.extracted_data ->> 'source_transaction_id' = t.id::text
    WHERE t.user_id = uid
      AND t.type    = 'expense'
      AND d.id IS NULL
  )
  INSERT INTO public.documents
    (user_id, type, vendor_name, amount, currency, tax_amount, date,
     category_id, description, payment_method, status, extracted_data)
  SELECT
    m.user_id,
    'receipt',
    m.title,
    m.amount,
    m.currency,
    0,
    m.date,
    m.category_id,
    m.description,
    m.payment_method,
    'saved',
    jsonb_build_object(
      'seeded_by',             'repair_documents_for_seeded_user.sql',
      'source_transaction_id', m.id,
      'synthetic',             true
    )
  FROM missing m;

  GET DIAGNOSTICS inserted = ROW_COUNT;
  SELECT count(*) INTO after_cnt FROM public.documents WHERE user_id = uid;

  RAISE NOTICE '── Document repair ──';
  RAISE NOTICE 'user               : %', uid;
  RAISE NOTICE 'documents (before) : %', before_cnt;
  RAISE NOTICE 'rows inserted      : %', inserted;
  RAISE NOTICE 'documents (after)  : %', after_cnt;
  RAISE NOTICE '── Re-open the dashboard; pre-Goat spend math should now render. ──';
END $$;
