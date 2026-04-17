# Goat Mode — Phase 2 Local Backend Checklist

> **Scope:** Phase 2 only — the local Goat Mode backend (FastAPI) that reads
> a real user's Billy data from Supabase, runs the deterministic analytics
> layer, generates deterministic recommendations, and writes the results
> back into the Goat Mode v1 tables.
>
> Out of scope in this phase: Gemini, forecasting, anomaly ML, risk-scoring
> ML, Edge Function trigger, Flutter UI, and Cloud Run deployment.

---

## 1. Files added in this phase

Backend module:

```
backend/app/main.py                     (edited)
backend/app/requirements.txt            (edited — pinned versions, +python-dotenv)
backend/app/requirements-dev.txt        (new)
backend/app/.env.example                (new)
backend/app/goat/__init__.py            (new)
backend/app/goat/api.py                 (new)
backend/app/goat/cli.py                 (new)
backend/app/goat/contracts.py           (new)
backend/app/goat/data_loader.py         (new)
backend/app/goat/deterministic.py       (new)
backend/app/goat/fingerprints.py        (new)
backend/app/goat/missing_inputs.py      (new)
backend/app/goat/recommendations.py     (new)
backend/app/goat/runner.py              (new)
backend/app/goat/scoring.py             (new)
backend/app/goat/supabase_io.py         (new)
backend/app/goat/versions.py            (new)
```

Tests (run locally, no Supabase required):

```
backend/pytest.ini                      (new)
backend/app/tests/__init__.py           (new)
backend/app/tests/conftest.py           (new; FakeStore / FakeTable / bundles)
backend/app/tests/test_missing_inputs.py
backend/app/tests/test_deterministic.py
backend/app/tests/test_recommendations.py
backend/app/tests/test_fingerprints.py
backend/app/tests/test_runner.py
```

Real-user convenience SQL:

```
scripts/goat/set_goat_user_inputs.sql   (new — non-persona, for your real UUID)
```

Phase 2 does **not** create or modify any Supabase migration.

---

## 2. Environment variables

Copy `backend/app/.env.example` to `backend/app/.env` and fill in:

| Variable | Purpose |
| --- | --- |
| `SUPABASE_URL` | Trusted server URL. For local Supabase CLI, default is `http://127.0.0.1:54321`. |
| `SUPABASE_SERVICE_ROLE_KEY` | **Service role** key. Bypasses RLS by design — never ship this to a client. |
| `GOAT_ALLOW_DEV_ENDPOINTS` | Set to `1` to expose `POST /goat-mode/run-for-user`. Leave unset in production. |
| `GOAT_TEST_USER_ID` | Optional. Default UUID used by the CLI and `/run-for-user` when no `user_id` is passed. |
| `GEMINI_API_KEY` | Unused in Phase 2. Add in Phase 4. |

Retrieve the service role key from Supabase Studio (`Project Settings → API`)
or, for the local stack, from `supabase status`.

---

## 3. Install + run the backend locally

From the repo root:

```bash
cd backend/app
python -m venv .venv
# Windows:  .venv\Scripts\activate
# macOS/Linux:  source .venv/bin/activate
pip install -r requirements-dev.txt
```

Start the API:

```bash
uvicorn main:app --reload --port 8080
```

Health check:

```bash
curl http://localhost:8080/health
# → {"ok": true, "goat_mode": true, "supabase_url_present": true, ...}
```

---

## 4. Call Goat Mode for a real user UUID

### 4.1 Dry run via HTTP (recommended first)

```bash
curl -X POST http://localhost:8080/goat-mode/run \
  -H 'Content-Type: application/json' \
  -d '{
        "user_id": "f308f807-00eb-46ce-9468-63cd7c8d3c0f",
        "scope": "overview",
        "dry_run": true
      }' | jq
```

Returns the full computed payload, coverage, missing-inputs list, and
recommendations **without writing** to `goat_mode_*` tables.

### 4.2 Persistent run (writes job, snapshot, recommendations)

```bash
curl -X POST http://localhost:8080/goat-mode/run \
  -H 'Content-Type: application/json' \
  -d '{
        "user_id": "f308f807-00eb-46ce-9468-63cd7c8d3c0f",
        "scope": "full",
        "dry_run": false
      }' | jq '.job_id, .snapshot_id, .readiness_level, .recommendation_count'
```

### 4.3 Dev convenience endpoint

With `GOAT_ALLOW_DEV_ENDPOINTS=1` and `GOAT_TEST_USER_ID=<uuid>`:

```bash
curl -X POST http://localhost:8080/goat-mode/run-for-user \
  -H 'Content-Type: application/json' \
  -d '{"scope": "full"}' | jq
```

### 4.4 CLI (no server needed)

```bash
cd backend/app
python -m goat.cli run --user-id f308f807-00eb-46ce-9468-63cd7c8d3c0f \
                       --scope full --dry-run --pretty
```

### 4.5 Fetch the latest snapshot

```bash
curl http://localhost:8080/goat-mode/latest/f308f807-00eb-46ce-9468-63cd7c8d3c0f?scope=overview
```

### 4.6 Fetch a specific job

```bash
curl http://localhost:8080/goat-mode/jobs/<job-uuid-from-run-response>
```

---

## 5. Populate setup inputs for a real user

Goat Mode will happily produce L1 output from operational data alone. To unlock
L2/L3 analytics (savings rate, runway, DTI, goal pacing):

1. Open `scripts/goat/set_goat_user_inputs.sql`.
2. Paste your real Supabase `auth.users.id` into the `uid` line.
3. Edit the NULL values to reality (monthly income, salary day, emergency-fund
   target, liquidity floor, …). Any field you leave NULL stays NULL in the DB.
4. Run:

   ```bash
   supabase db execute --local --file scripts/goat/set_goat_user_inputs.sql
   ```

Optionally insert goals / obligations straight into `public.goat_goals` and
`public.goat_obligations` via Studio to exercise the `goals` / `debt` scopes.

---

## 6. Inspect the data Goat wrote

```sql
-- Most recent job for the user
select id, scope, status, readiness_level, data_fingerprint, created_at
  from public.goat_mode_jobs
 where user_id = 'f308f807-00eb-46ce-9468-63cd7c8d3c0f'
 order by created_at desc
 limit 5;

-- Latest snapshot per scope
select scope, readiness_level, snapshot_status, generated_at,
       coverage_json->'coverage_score' as coverage_score
  from public.goat_mode_snapshots
 where user_id = 'f308f807-00eb-46ce-9468-63cd7c8d3c0f'
 order by generated_at desc;

-- Open recommendations by priority
select recommendation_kind, severity, priority, rec_fingerprint,
       observation_json->>'field' as missing_field,
       recommendation_json->>'headline' as headline
  from public.goat_mode_recommendations
 where user_id = 'f308f807-00eb-46ce-9468-63cd7c8d3c0f'
   and status = 'open'
 order by priority desc;

-- Job event timeline
select step, status, severity, message, created_at
  from public.goat_mode_job_events
 where user_id = 'f308f807-00eb-46ce-9468-63cd7c8d3c0f'
 order by created_at;
```

---

## 7. Run the test suite

```bash
cd backend
python -m pytest app/tests/ -v
```

All 26 tests exercise:

- missing-input detection across L1 / L2 / L3
- deterministic formulas (overview, cashflow, budgets, recurring, debt, goals, full)
- recommendation fingerprint stability and in-run dedupe
- full runner lifecycle against an in-memory Supabase fake
- snapshot idempotency on the same `data_fingerprint`
- re-run suppression: open recommendations are not duplicated

No live Supabase is touched by the test suite; `supabase-py` itself does not
need to be installed to run tests.

---

## 8. What is intentionally NOT implemented in Phase 2

- **Forecasting** (`forecast_json` is written as `{}` always).
- **Anomaly ML** (`anomalies_json` is `{}`; `IsolationForest` / MAD-based
  anomaly layer deferred to Phase 4).
- **Risk scoring** (`risk_json` is `{}`; calibrated probability models
  deferred until enough labelled data exists).
- **Gemini** (`ai_layer` only stores `model_versions`; `ai_validated = false`).
- **Edge Function** (`supabase/functions/goat-mode-trigger`). The backend runs
  directly; no Supabase JWT forwarding yet.
- **Flutter UI** (nothing reads these snapshots yet from the app).
- **Cloud Run deployment** (`Dockerfile` is kept intact and works, but no
  deployment is performed).
- **Realtime publications** (Flutter will poll `goat_mode_jobs` in Phase 3).

Each of these slots is already carved out in the schema / contract so adding
them is additive, not a rewrite.

---

## 9. Known blockers / watch-outs before Phase 3 starts

1. **Service-role key handling.** The backend holds the full service role key
   for every Goat run. Phase 3 must introduce JWT forwarding from the Edge
   Function so the backend can honour RLS for reads that originate from a
   specific user session, instead of broadly impersonating users.
2. **Snapshot size.** `goat_mode_snapshots.metrics_json` is a flat list of
   `Metric` objects. For L3 users with many budgets this can grow; adding a
   Postgres TOAST compression hint is fine for v1, but Phase 4 should trim
   fields not needed by the UI.
3. **Budget-overrun threshold is a heuristic.** `utilization > pace + 0.15`
   works well for monthly cadences but becomes noisy on weekly budgets. Phase
   4 should tune per cadence and per history length.
4. **Trend delta needs 60+ days of paired data.** For new users, the
   `spend_trend_delta` metric returns `null` with a clear reason code — that's
   the correct behaviour, but Phase 3 UI must render "not enough history yet"
   cleanly.
5. **No pagination cap on transactions read.** The `fetch_transactions` helper
   pages through arbitrarily many rows. For extreme users (>50k tx) this
   should be capped and the snapshot should carry a `truncated` flag. Not a
   Phase 2 concern.
6. **Recommendation update flow.** Phase 1 migration allows the owner to
   update any column on `goat_mode_recommendations`. Phase 3 should add a
   `goat_recommendation_transition(rec_id, new_status, snoozed_until)` RPC
   and tighten the RLS policy.
7. **Prophet/statsmodels not actually used.** They ship in `requirements.txt`
   for Phase 4 forecasting. Keep them pinned so the image stays reproducible,
   even though Phase 2 doesn't import them.
