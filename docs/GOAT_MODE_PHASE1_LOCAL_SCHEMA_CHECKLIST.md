# Goat Mode — Phase 1 Local Schema Checklist

> Scope: **Phase 1 only** — local schema + fixture/seed scaffolding.
> No backend compute, Edge Function, or Flutter code is added in this phase.
> Follow `GOAT_MODE_ANALYTICS_ARCHITECTURE.md`, `GOAT_MODE_DATA_MODEL_DRAFT.md`,
> and `GOAT_MODE_LOCAL_FIRST_PLAN.md` for the broader context.

---

## 1. Files in this phase

| File | Purpose |
| --- | --- |
| `supabase/migrations/20260423120000_goat_mode_v1.sql` | Creates the 7 Goat Mode v1 tables, indexes, triggers, and RLS policies. |
| `scripts/goat/seed_goat_sparse.sql` | SPARSE persona (L1): feature flag + clean Goat rows only. |
| `scripts/goat/seed_goat_medium.sql` | MEDIUM persona (L2): `goat_user_inputs` + 1 emergency-fund goal. |
| `scripts/goat/seed_goat_rich.sql` | RICH persona (L3): full `goat_user_inputs` + 3 goals + 2 obligations. |
| `docs/GOAT_MODE_PHASE1_LOCAL_SCHEMA_CHECKLIST.md` | This document. |

All three seed scripts are **Goat-specific only**. Operational seed prerequisites
(transactions, accounts, budgets, recurring, lend_borrow, statement_imports) are
documented as `TODO [operational seed]` comments inside each script and will be
authored alongside Phase 2 backend tests.

---

## 2. Local commands (Billy + Supabase CLI workflow)

```bash
# From the repo root, with Docker running:

# 2.1 Apply everything fresh, including the new Goat v1 migration.
supabase db reset

# 2.2 Or, against an already-running local stack, push only new migrations.
supabase db push --local   # (CLI ≥ 1.180)
# or, as a fallback:
supabase db reset --no-seed

# 2.3 To run a single seed script against the local DB:
supabase db execute --local --file scripts/goat/seed_goat_sparse.sql
supabase db execute --local --file scripts/goat/seed_goat_medium.sql
supabase db execute --local --file scripts/goat/seed_goat_rich.sql
```

> **Before running the seeds:** open each file and paste the real
> `auth.users.id` for the corresponding persona (SPARSE / MEDIUM / RICH)
> into the `uid uuid := '…';` line. Personas can be created through the
> running Flutter app's sign-up flow or via Supabase Studio (`Authentication → Users → Add user`).

---

## 3. Verify tables exist

Run in `supabase db psql` or Studio SQL editor:

```sql
select table_name
  from information_schema.tables
 where table_schema = 'public'
   and table_name like 'goat_%'
 order by table_name;
```

Expected (7 rows):

```
goat_goals
goat_mode_job_events
goat_mode_jobs
goat_mode_recommendations
goat_mode_snapshots
goat_obligations
goat_user_inputs
```

### Verify idempotency indexes

```sql
select indexname
  from pg_indexes
 where schemaname = 'public'
   and indexname in (
     'goat_mode_snapshots_unique_fp',
     'goat_mode_recommendations_open_unique'
   );
```

Both must be present.

### Verify triggers

```sql
select event_object_table, trigger_name, action_statement
  from information_schema.triggers
 where event_object_schema = 'public'
   and event_object_table like 'goat_%'
 order by event_object_table, trigger_name;
```

Each mutable table (`goat_mode_jobs`, `goat_mode_snapshots`,
`goat_user_inputs`, `goat_goals`, `goat_obligations`,
`goat_mode_recommendations`) must have exactly one `…_touch_updated_at`
trigger calling `public.set_invoice_updated_at()`.
`goat_mode_job_events` is insert-only and has no trigger.

---

## 4. Verify RLS basically works

```sql
-- Every Goat table must report rowsecurity = true.
select relname, relrowsecurity
  from pg_class
 where relnamespace = 'public'::regnamespace
   and relname like 'goat_%'
 order by relname;
```

All seven rows must show `relrowsecurity = t`.

### Quick user-scope smoke test

With the local Supabase stack running:

1. Sign in as `goat_medium_user` through the Flutter app (or `supabase auth sign-in` with a matching JWT).
2. Run from a JWT-authenticated session:

   ```sql
   select user_id, monthly_income from public.goat_user_inputs;
   ```

   The authenticated user must see **only their own row**.

3. Sign in as a different user and re-run — it must return **zero rows**.

4. From the `anon` role (unauthenticated), the same query must return **zero rows**.

5. From the `service_role` (backend key), all rows are visible (RLS bypassed) — this is the expected behaviour for the Cloud Run worker.

Repeat spot checks against `goat_goals` and `goat_obligations` (full CRUD
allowed for the owner) and against `goat_mode_snapshots` /
`goat_mode_job_events` (select-only for the owner).

---

## 5. Reset & reseed

```bash
# Full reset of the local DB (drops everything and reapplies all migrations).
supabase db reset

# Re-run Goat-specific seeds (after pasting the three persona UUIDs):
supabase db execute --local --file scripts/goat/seed_goat_sparse.sql
supabase db execute --local --file scripts/goat/seed_goat_medium.sql
supabase db execute --local --file scripts/goat/seed_goat_rich.sql
```

Each seed script is idempotent: it deletes any prior Goat rows for that user
before inserting fresh fixture data, so re-runs converge to the same state.

---

## 6. Known blockers before Phase 2 backend work starts

1. **Persona UUIDs must be created manually.** The three personas are not
   auto-created in `auth.users`. Phase 2 will add a helper script or Edge
   Function to bootstrap them from the service_role key so tests can be
   run without hand-editing UUIDs.

2. **Operational seed data is deferred.** Each seed script carries
   `TODO [operational seed]` comments that describe the transactions,
   accounts, budgets, recurring series, and statement imports the
   persona needs in Phase 2. Without that operational data the
   deterministic layer will still run but coverage_score will look
   thin — that is expected and tested via the SPARSE persona.

3. **No automated backend code calls these tables yet.** The backend
   wiring (FastAPI service + Edge Function trigger) lands in Phase 2.
   Any writes to `goat_mode_jobs`, `goat_mode_snapshots`,
   `goat_mode_job_events`, or `goat_mode_recommendations` during Phase 1
   manual testing must be issued by a human using the `service_role`
   key, because no client-side insert/update policies are open for those
   tables by design.

4. **Recommendation open-dedupe depends on deterministic fingerprints.**
   The partial unique index
   `goat_mode_recommendations_open_unique(user_id, rec_fingerprint)
   where status = 'open'` requires the Phase 2 compute layer to
   generate stable `rec_fingerprint` values. Until that fingerprint
   contract is written, manual inserts for smoke testing should use
   different fingerprint strings to avoid false upsert conflicts.

5. **Risk output is expected to be feature-flagged in app code.**
   Nothing in the schema forces this; Phase 2 / Phase 3 must gate
   `risk_json` consumption behind a profile / remote-config flag until
   enough pooled calibration data exists.

6. **Realtime is intentionally not wired.** Flutter will poll
   `goat_mode_jobs` by `(user_id, status)` during Phase 2; do not add
   `supabase_realtime` publications for these tables in this phase.
