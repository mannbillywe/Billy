# Goat Mode — Local-First Implementation Plan (Phase 0)

> Companion to `GOAT_MODE_ANALYTICS_ARCHITECTURE.md` and
> `GOAT_MODE_DATA_MODEL_DRAFT.md`. V1 rule: dedicated data only.
>
> This document defines the build order, the local dev loop, the three sample
> users we'll verify against, and the test strategy — **before** any Cloud Run
> deployment.

---

## 1. Build order

Each step is independently reviewable. No step deploys to Cloud Run.

### Step 1 — Analytics contract approval

- **Artifacts.** The three design docs (`GOAT_MODE_ANALYTICS_ARCHITECTURE.md`,
  `GOAT_MODE_DATA_MODEL_DRAFT.md`, this file).
- **Gate.** Principal engineer sign-off on scopes, formulas, readiness levels,
  table shape, and local-test users.

### Step 2 — Schema / migration phase (local only)

- Create one new migration file:
  `supabase/migrations/<timestamp>_goat_mode_v1.sql` implementing every table
  in the data-model draft.
- Apply locally with `supabase db reset` (recreates the DB from all migrations
  and seed files).
- Verify RLS with `supabase db lint` and by running a small SQL test script
  under two different user contexts.
- **Do not** run this against the production project yet.

### Step 3 — Local backend implementation

The existing `backend/` FastAPI skeleton is the right home.

- **Structure.**

  ```text
  backend/
  ├── app/
  │   ├── main.py                     # existing; add /goat endpoints
  │   ├── goat/
  │   │   ├── __init__.py
  │   │   ├── api.py                  # FastAPI router: POST /goat/jobs, GET /goat/jobs/{id}, GET /goat/snapshot
  │   │   ├── pipeline.py             # orchestrator: load → compute → forecast → anomaly → risk → recommend → ai
  │   │   ├── data_loader.py          # one function per operational table, returns pandas DataFrames
  │   │   ├── deterministic.py        # §3.1 formulas (pure functions, unit-tested)
  │   │   ├── forecasting/
  │   │   │   ├── base.py             # Forecaster protocol, CI shape
  │   │   │   ├── baseline.py         # seasonal-naïve + rolling-median
  │   │   │   ├── ets.py              # statsmodels ETS
  │   │   │   └── prophet_adapter.py  # prophet fallback
  │   │   ├── anomaly.py              # MAD + IsolationForest + rule checks
  │   │   ├── risk/
  │   │   │   ├── budget_overrun.py   # logistic + CalibratedClassifierCV
  │   │   │   └── missed_payment.py
  │   │   ├── recommendations.py      # deterministic rec engine
  │   │   ├── ai_client.py            # gemini wrapper w/ structured-output validation
  │   │   ├── scoring.py              # FWB + coverage scorecards
  │   │   ├── contracts.py            # pydantic models for inputs/outputs
  │   │   ├── supabase_io.py          # service-role writes to goat_* tables
  │   │   └── versions.py             # model_versions constants
  │   └── requirements.txt            # already lists pandas, numpy, sklearn, statsmodels, prophet, google-genai, supabase
  └── Dockerfile                      # already targets Cloud Run
  ```

- **Endpoints.**
  - `POST /goat/jobs` — create a job row (service role), enqueue, return job id.
  - `GET /goat/jobs/{id}` — return status.
  - `GET /goat/snapshot?scope=full` — convenience read (mirrors what Flutter
    will do directly against Supabase).
- **Run locally.** `uvicorn main:app --reload --port 8080` at the root of
  `backend/app/`. For Docker parity: `docker build -t billy-goat-backend ./backend && docker run -p 8080:8080 --env-file .env billy-goat-backend`.
- **Secrets locally.** `.env` with `GEMINI_API_KEY`, `SUPABASE_URL`,
  `SUPABASE_SERVICE_ROLE_KEY` (local Supabase values from `supabase status`).

### Step 4 — Local fixtures and sample users

- Seed data lives in **`supabase/seed.sql`** (picked up by `supabase db reset`)
  for the base (profiles, categories, one user).
- Three user-specific scripts under **`scripts/goat/`**:
  - `seed_goat_sparse.sql`
  - `seed_goat_medium.sql`
  - `seed_goat_rich.sql`
- Each script truncates only its own user's rows and re-populates them (safe
  to re-run). Timestamps are computed relative to `now()` so the dataset
  always looks "today-relative".
- Existing `scripts/seed_manng_data.sql` is a good pattern; Goat scripts reuse
  the same structural style (transactions, budgets, recurring_series, etc.).

### Step 5 — Local Supabase integration

- `supabase start` brings up Postgres + Auth + Storage + Edge Functions +
  Studio at `http://localhost:54323`.
- `supabase db reset` re-applies all migrations and seeds.
- The FastAPI backend points at `SUPABASE_URL=http://localhost:54321` and
  uses the **service role key** from `supabase status`.
- Verify: `curl -X POST http://localhost:8080/goat/jobs -H 'Content-Type: application/json' -d '{"user_id":"...","scope":"full"}'` inserts a `goat_mode_jobs` row, runs the pipeline, and writes a `goat_mode_snapshots` row visible in Studio.

### Step 6 — Local Edge Function trigger

- Add a new Edge Function `supabase/functions/goat-mode-trigger/index.ts` whose
  sole job is: authenticate the caller, insert a `goat_mode_jobs` row under
  the user's JWT, and `fetch()` the Cloud Run URL (`GOAT_BACKEND_URL`) to kick
  compute. The Edge Function only forwards `(user_id, scope, job_id)`; it
  does not compute anything. Why: we want Flutter → Supabase Edge Function →
  backend, consistent with the existing `analytics-insights` / `process-invoice`
  pattern.
- Serve locally with `supabase functions serve goat-mode-trigger --env-file
  ./supabase/functions/.env.local`.
- Test: `curl -X POST http://localhost:54321/functions/v1/goat-mode-trigger -H "Authorization: Bearer <jwt>" -d '{"scope":"full"}'`.

### Step 7 — Local Flutter integration

- Add `lib/features/goat/services/goat_mode_service.dart` (thin wrapper: invokes
  Edge Function, reads `goat_mode_jobs` + `goat_mode_snapshots` + `goat_mode_recommendations` via
  `SupabaseService` helpers).
- Add `lib/features/goat/providers/goat_mode_provider.dart` (Riverpod
  `Notifier` pattern, mirroring `AnalyticsInsightsNotifier`):
  - `loadCached()` — reads latest `scope='full'` snapshot.
  - `refresh()` — invokes Edge Function, polls `goat_mode_jobs` until
    terminal, then reloads snapshot.
- Replace (or gate) `GoatModePlaceholderScreen` behind a compile-time flag
  while the v1 UI is built in a parallel Pull Request. The placeholder remains
  the fallback until the new screen is ready.
- Run Flutter locally against local Supabase: `flutter run --dart-define=SUPABASE_URL=http://localhost:54321 --dart-define=SUPABASE_ANON_KEY=<local_anon>`.

### Step 8 — Cloud Run deployment (only after local validation)

- Build & push the backend image: `gcloud builds submit --tag <region>-docker.pkg.dev/<project>/billy/goat-backend:<sha> ./backend`.
- Deploy: `gcloud run deploy billy-goat-backend --image ... --region <r> --set-env-vars SUPABASE_URL=...,GEMINI_API_KEY=... --set-secrets SUPABASE_SERVICE_ROLE_KEY=...`.
- Update the Edge Function's `GOAT_BACKEND_URL` secret to the Cloud Run URL.
- **Gate.** All three sample users have passing local validations + a dry-run
  in the remote staging project (not prod). Smoke tests confirmed against
  staging before prod switch.

---

## 2. Local test strategy — the three sample users

Each user exists in a local Supabase instance under a distinct `auth.users`
id, with a deterministic UUID embedded in each seed script.

### 2.1 Sparse-data user — `goat_sparse_user_uuid`

- **Source data.**
  - 12 confirmed `transactions` over the last 18 days, all type `expense`,
    three categories, one vendor repeated twice.
  - 0 accounts.
  - 0 budgets.
  - 0 `recurring_series` (so `recurring_suggestions` can be generated only
    from those 12 transactions — nothing will qualify).
  - 0 lend/borrow.
  - 0 statement imports.
  - 0 `goat_user_inputs` row (opted out of setup).
  - `profiles.goat_mode = true`.

- **Expected Goat Mode output (scope=`full`).**
  - `readiness_level = L1`.
  - `coverage_score ≈ 8` (tx density partial, no budgets/income/accounts).
  - `well_being_score` returned with `partial=true` (liquidity pillar withheld; savings pillar withheld).
  - `overview.total_spend` present; `overview.savings_rate = null`.
  - `cashflow.forecast = null` with reason `insufficient_history` (< 30 d).
  - `budgets.status = 'empty'`.
  - `recurring.status = 'sparse'`.
  - `debt.scope_state = 'empty'`.
  - `goals.scope_state = 'empty'`.
  - `anomalies = []` (below IsolationForest minimum; MAD may surface 0–1
    entries depending on variance).
  - `risks = []`.
  - `recommendations` — exactly one of kind `missing_input` top of list
    (income), plus possibly `uncategorized_cleanup` if applicable. No
    forecast-derived recs.

- **UI should say.** Hero "We can't score you yet — add a few things so we
  can." Top missing-inputs card lists income, first account, first budget.
  The scope chips are visible but tapping them leads to empty-state screens
  (still clean and productive, not errors).

- **Recommendations that MUST appear.**
  - `missing_input` for `monthly_income`.
  - `missing_input` for first account balance (if any accounts row exists but
    without balance).

- **Recommendations that MUST NOT appear.**
  - Any forecast-based liquidity warning.
  - Any budget-overrun or missed-payment recommendation.
  - Any AI-generated claim that contains a number not in the deterministic
    payload.

### 2.2 Medium-data user — `goat_medium_user_uuid`

- **Source data.**
  - 180 days of `transactions` (~220 rows): 1 monthly income (₹65,000), mixed
    expense categories, ~25 % weekend-heavy spend, 1 real recurring pattern
    (monthly OTT).
  - 2 `accounts` (1 savings, 1 credit card), balances updated 3 d ago.
  - 2 `budgets` (Food monthly ₹8,000, Transport monthly ₹4,000) + their
    current + previous 2 `budget_periods`. Food has a mild overrun pattern
    (hits 108–112 % twice).
  - 1 `recurring_series` (OTT ₹499 monthly) + 4 confirmed occurrences.
  - 2 `lend_borrow_entries` (one pending, one settled).
  - 0 statement imports.
  - `goat_user_inputs`: `monthly_income=65000`, `income_cadence=monthly`,
    `salary_day_of_month=1`, `emergency_fund_target_months=3`,
    `planning_horizon_days=30`.
  - 1 `goat_goal` (Emergency fund, target ₹150k, current ₹45k).

- **Expected output (scope=`full`).**
  - `readiness_level = L2`.
  - `coverage_score ≈ 60`.
  - `well_being_score ≈ 55–65` with all pillars present.
  - `cashflow.forecast` filled: ETS fit, 30-day horizon, with CI. MAPE on
    held-out fold printed in `deterministic.forecasts.cashflow.backtest_mape`.
  - `budgets.Food.overrun_prob ≥ 0.5` (calibration valid), `pace_index ≥ 1.1`.
  - `recurring.monthly_total = 499`, one series visible, one suggestion may be
    generated for any pattern the detector finds.
  - `anomalies`: 0–2 entries at most (the data is intentionally tame).
  - `risks.budget_overrun` present for Food.
  - `goals.emergency_fund`: pace from trailing contributions, completion-date
    band.
  - `recommendations`: includes `budget_overrun` for Food, `goal_shortfall` if
    pace < required, `missing_input` for any remaining low-cost prompts
    (e.g. liquidity_floor).

- **UI should say.** Hero FWB with a meaningful pillar breakdown. Food budget
  badge flagged warn. One or two recs on the default screen. Forecast chart
  in the Cashflow scope detail. Recurring shows 1 series + 0-or-more
  suggestions.

- **Recs MUST appear.**
  - `budget_overrun` for Food with body referencing its pace index.
  - `goal_shortfall` if the computed pace < required (when we seed pace
    below required).

- **Recs MUST NOT appear.**
  - Any liquidity warning (balances healthy).
  - Any missed-payment risk (no declared obligations).
  - Any anomaly alert for data below the rank threshold.

### 2.3 Rich-data user — `goat_rich_user_uuid`

- **Source data.**
  - 12 months of `transactions` (~1,200 rows), 3 income streams (1 regular
    payroll + 2 occasional), 9 categories, multiple merchants, plausible
    seasonality (dec/jan spike).
  - 3 statement imports with ~120 rows each, most matched, 2 disputes open.
  - 4 `accounts` (2 savings, 1 checking, 1 credit card) with monthly balance
    updates (synthetic history across 12 months where we care about
    balance-trend; current balances are fresh).
  - 5 `budgets` (Food, Transport, Entertainment, Utilities, Shopping) +
    at least 3 prior periods each to train the overrun-risk model.
  - 4 `recurring_series` + 1 pending `recurring_suggestion`.
  - 4 `lend_borrow_entries` (2 pending, 1 overdue, 1 settled).
  - `goat_user_inputs`: full (income + emergency fund + household + planning
    horizon + liquidity_floor).
  - 3 `goat_goals` (emergency fund, vacation, laptop).
  - 2 `goat_obligations` (EMI + credit-card min payment).

- **Expected output.**
  - `readiness_level = L3`.
  - `coverage_score ≥ 85`.
  - `well_being_score ≈ 60–80`.
  - `cashflow.forecast`: 30 d ETS + 90 d Prophet fallback (or ETS if it wins
    backtest), CI bands present. skforecast shadow result logged in
    `goat_mode_job_events` but not surfaced.
  - `budgets.*.overrun_prob` calibrated (isotonic with enough samples across
    users once combined; for a single-user seed we use the pooled model).
  - `recurring`: 4 series + at least 1 suggestion + 1 amount-drift detection.
  - `anomalies`: 2–5 entries ranked.
  - `risks.missed_payment` for the EMI obligation; `risks.liquidity_stress`
    small but nonzero.
  - `goals`: all three present with pace + projection + shortfall.
  - `recommendations`: at least one per severity tier appears across the full
    set (`critical` only if a real liquidity breach was engineered into the
    seed).

- **UI should say.** Full experience: hero FWB with strong pillars, 3 ranked
  recs on default screen, all scope chips populated, forecast chart with
  shaded band in Cashflow detail, anomaly list in Cashflow/Scan detail,
  missed-payment rec visible in Debt.

- **Recs MUST appear.**
  - `budget_overrun` for whichever budget is trending (seed one on purpose).
  - `missed_payment_risk` for the EMI if its `due_date` falls in the horizon.
  - `recurring_drift` for the seeded amount change.
  - `goal_shortfall` for at least one goal (seed one below required pace).

- **Recs MUST NOT appear.**
  - Any claim referencing a number not produced by the pipeline.
  - Anomaly alerts for the top-merchant regular spend (guard the ranker).

---

## 3. What can be tested without Gemini

All of this is mocked / skipped:

- Unit tests on `deterministic.py` (pure-function formulas) for each metric in
  §3.1 of the architecture doc. Include edge cases: zero denominators, 1-row
  histories, all-same-day transactions, all-zero amounts.
- Unit tests on `forecasting/baseline.py` against synthetic series: constant,
  linear trend, weekly sinusoid + noise.
- ETS/Prophet smoke tests: given a canned 90-d series, assert MAPE < threshold
  and CI shape.
- Anomaly detector:
  - MAD on synthetic spikes.
  - IsolationForest score ordering on planted anomalies vs normals.
- Risk models:
  - Logistic overrun model on synthetic labelled frames.
  - CalibratedClassifierCV Brier-score delta ≥ 0.01 vs uncalibrated.
- Recommendation engine:
  - Given a fixed snapshot, rec fingerprint is stable.
  - Dismiss + re-run within 7 d does **not** re-surface.
  - Dedupe unique constraint works.
- Snapshot idempotency:
  - Same input fingerprint + no seed change → second run produces identical
    snapshot (UNIQUE enforces upsert).

## 4. What can be tested with mocked Gemini

- `ai_client.py` has a `FAKE_MODE=true` switch that returns canned structured
  JSON. All AI validation rules are then exercised:
  - Reject if any number appears in `narrative` that's not in the input
    payload.
  - Reject if `rec_id` is unknown.
  - Fall back to deterministic templates on rejection, and mark
    `snapshot.ai_validated = false`.
- End-to-end test: hit `/goat/jobs` for each sample user in `FAKE_MODE=true`,
  assert the full DB state matches the expectations in §2.

## 5. What can be tested end-to-end locally (no Cloud Run)

- `flutter run` against local Supabase + local FastAPI (+ mocked Gemini).
- Refresh flow: default → refresh → loading → snapshot rendered.
- Scope drill-down on all three sample users.
- Offline / degraded path: kill the FastAPI process and verify Flutter still
  shows the last cached snapshot plus a staleness banner.
- RLS assertion: sign in as `goat_medium_user` and attempt a direct Supabase
  select for `goat_mode_snapshots` with a WHERE clause targeting the
  `goat_rich_user` id → must return 0 rows.
- Usage limits: confirm `increment_refresh_count` behaviour still gates the
  "refresh" button for Goat Mode (reuse existing `user_usage_limits`
  infrastructure).

## 6. Cloud Run handoff gate

Do **not** deploy to Cloud Run until:

1. All three sample users pass the §2 expectations (machine-checked).
2. `FAKE_MODE=true` AI tests pass.
3. One real-Gemini smoke test passes locally (one user, one scope) with the
   structured-output validator enabled.
4. `supabase db reset` from a clean checkout completes without error and
   reproduces the same snapshots.
5. A checklist review of the RLS policies under two user contexts.
6. Sentry integration wired for the FastAPI process (reuse Billy's existing
   Sentry setup pattern from Flutter's `--dart-define=SENTRY_DSN`).

Only after this gate do we `gcloud run deploy`, point the Edge Function's
`GOAT_BACKEND_URL` at the Cloud Run URL, and flip a per-user rollout using
`profiles.goat_mode`.

---

## 7. Local dev one-liner (reference)

Once the phase-1 code is landed, a developer should be able to do:

```bash
# 1. Local Supabase
npx supabase start
npx supabase db reset   # applies all migrations + supabase/seed.sql
psql "$DATABASE_URL" -f scripts/goat/seed_goat_sparse.sql
psql "$DATABASE_URL" -f scripts/goat/seed_goat_medium.sql
psql "$DATABASE_URL" -f scripts/goat/seed_goat_rich.sql

# 2. Local backend
cd backend && uvicorn app.main:app --reload --port 8080

# 3. Local Edge Function trigger
supabase functions serve goat-mode-trigger --env-file ./supabase/functions/.env.local

# 4. Flutter against local stack
flutter run \
  --dart-define=SUPABASE_URL=http://localhost:54321 \
  --dart-define=SUPABASE_ANON_KEY=<local_anon> \
  --dart-define=GOAT_BACKEND_URL=http://localhost:8080
```

No step touches production. No step requires Cloud Run. Gemini stays optional
via `FAKE_MODE` until the final smoke test.
