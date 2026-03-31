# Supabase Setup for Billy

## Run Migrations

1. Go to [Supabase Dashboard](https://supabase.com/dashboard) > your project
2. Open **SQL Editor** > **New Query**
3. Copy and run **each** file in order:
   - `migrations/20240318000000_initial_schema.sql`
   - `migrations/20240318000001_rls_policies.sql`

## Storage Buckets

Create these buckets in **Storage** > **New bucket**:

| Bucket   | Public | File size limit |
|----------|--------|-----------------|
| receipts | No     | 10 MB           |
| exports  | No     | 50 MB           |
| splits   | No     | 10 MB           |

Add RLS policies for each bucket so users can only access their own files (path: `user_id/*`).
