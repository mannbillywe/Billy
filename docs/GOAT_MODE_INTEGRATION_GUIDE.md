# Goat Mode - Integration Guide

> A complete reference for anyone wanting to bring the Goat Mode analytics
> backend into another app. Written from the `backup/pre-revert-apr-17`
> branch, where the full Phase 8 implementation lives.

---

## 1. What is Goat Mode?

Goat Mode is a **scope-aware financial analytics engine** that turns a user's
raw transactions, accounts, budgets, recurring series, and a handful of
declared inputs into a structured snapshot of:

- deterministic **metrics** (net worth, daily spend, budget pace, savings rate, ...)
- **forecasts** (7/30-day spend, end-of-month liquidity, goal trajectory, ...)
- **anomaly flags** (category spikes, recurring-bill jumps, liquidity floor breaches, ...)
- **risk scores** (budget overrun, missed payment, EF breach, ...)
- **recommendations** with stable fingerprints and an open/dismissed/snoozed lifecycle
- an optional **Gemini-phrased narrative** that is *validated* before persistence

Every output is **grounded** - the AI layer is never allowed to invent numbers,
entities, or reason codes that aren't already in the deterministic bundle.

The pipeline is built to **degrade gracefully**: any one layer (forecast,
anomaly, risk, AI) can fail without taking the job down. Failures are recorded
per-layer in `layer_errors` and the snapshot's status becomes `partial` rather
than `failed`.

---

## 2. High-level architecture

```
Flutter client
      |
      |  1. POST /goat-mode-trigger  (user JWT)
      v
Supabase Edge Function  (goat-mode-trigger)
      |
      |  - verifies JWT
      |  - derives user_id from session (never from body)
      |  - checks profiles.goat_mode == true
      |  - forwards to backend with shared secret (OIDC ID token on GCP)
      v
Cloud Run  /  Local FastAPI   (backend/app/goat)
      |
      |  2. Insert goat_mode_jobs row (status=queued)
      |  3. load_bundle()      -> GoatDataBundle
      |  4. compute_scope()    -> deterministic metrics
      |  5. soft-fail layers:  forecast / anomaly / risk
      |  6. recommendations.generate()
      |  7. soft-fail AI:      Gemini-phrased envelope + strict validator
      |  8. upsert snapshot + insert recs
      |  9. update job status + job_events
      v
Supabase DB   (goat_mode_*, read back via RLS)
      |
      v
Flutter client polls / reads the snapshot and recommendations
```

Two boundaries you'll care about:

- `supabase/functions/goat-mode-trigger/index.ts` - Deno edge function
- `backend/app/goat/` - FastAPI service (can also run as CLI)

---

## 3. HTTP surface

All routes are under `/goat-mode`. All writes require the shared backend secret.

| Verb | Path | Purpose |
|---|---|---|
| `POST` | `/goat-mode/run` | Create job, compute, persist, return `RunResponse` |
| `POST` | `/goat-mode/run-for-user` | **Dev-only** (`GOAT_ALLOW_DEV_ENDPOINTS=1`), defaults `user_id` to `GOAT_TEST_USER_ID` |
| `GET`  | `/goat-mode/jobs/{id}` | Fetch a `JobSummary` |
| `GET`  | `/goat-mode/latest/{user_id}?scope=overview` | Latest `SnapshotOut` for that scope |

### Request

```json
POST /goat-mode/run
X-Goat-Backend-Secret: <shared>

{
  "user_id": "uuid",
  "scope": "overview",              // overview|cashflow|budgets|recurring|debt|goals|full
  "range_start": "2026-03-01",      // optional; backend infers sensible window
  "range_end":   "2026-04-17",      // optional
  "trigger_source": "manual",       // manual|scheduled|post_event|system
  "dry_run": false                  // true = compute only, no DB writes
}
```

### Response (abridged shape)

```json
{
  "job_id":  "uuid-or-null-on-dry-run",
  "snapshot_id": "uuid-or-null-on-dry-run",
  "scope": "overview",
  "readiness_level": "L2",          // L1 | L2 | L3
  "snapshot_status": "completed",   // completed | partial | failed
  "data_fingerprint": "sha1-40",

  "coverage": {
    "coverage_score": 0.72,
    "readiness_level": "L2",
    "breakdown": {
      "transactions": 1.0, "accounts": 1.0, "budgets": 0.67,
      "recurring": 0.5, "income_declared": 1.0,
      "goals": 1.0, "obligations": 0.33
    },
    "inputs_used": ["transactions.range", "accounts.active", ...],
    "missing_inputs": [
      {
        "key": "budgets.any_active",
        "label": "No active budgets",
        "why": "Budget pace metrics and overrun risk need at least one budget.",
        "unlocks": ["budget_overrun_risk", "budget_pace_metrics"],
        "severity": "watch"
      }
    ],
    "unlockable_scopes": ["budgets"]
  },

  "payload": {
    "scope": "overview",
    "status": "completed",
    "readiness_level": "L2",
    "confidence": "medium",
    "metrics": [
      {
        "key": "net_worth",
        "value": 128450.00,
        "unit": "INR",
        "confidence": 0.9,
        "confidence_bucket": "high",
        "reason_codes": ["from_account_balances"],
        "inputs_used": ["accounts.active"],
        "inputs_missing": [],
        "detail": { "account_count": 3 }
      }
      // ... more metrics
    ],
    "narrative": { /* deterministic slots filled by recommendations phase */ }
  },

  "recommendation_count": 4,
  "recommendations": [
    {
      "kind": "budget_overrun",
      "severity": "warn",
      "priority": 72,
      "impact_score": 0.65,
      "effort_score": 0.2,
      "confidence": 0.8,
      "rec_fingerprint": "sha1-32",
      "entity_type": "budget",
      "entity_id": "uuid",
      "observation":    { "spent": 18200, "limit": 15000, "pace": 1.21 },
      "recommendation": { "action": "trim", "target_category_id": "uuid", "suggested_cut": 500 }
    }
  ],

  "forecast": {
    "version": "0.1.0",
    "generated_at": "2026-04-17T18:00:00Z",
    "disabled": false,
    "models_available": { "prophet": true, "ets": true, "sklearn": true },
    "targets": [
      {
        "target": "short_horizon_spend_30d",
        "status": "ok",
        "model_used": "ets",
        "fallback_used": false,
        "history_length": 94,
        "horizon_days": 30,
        "confidence": 0.71,
        "confidence_bucket": "high",
        "reason_codes": ["ets_fit_converged"],
        "insufficient_data_fields": [],
        "value":  { "p10": 28200, "p50": 31100, "p90": 34000 },
        "series": { "horizon_days": 30, "unit": "INR", "points": [ /* ForecastPoint[] */ ] }
      }
    ]
  },

  "anomalies": {
    "version": "0.1.0",
    "generated_at": "2026-04-17T18:00:00Z",
    "disabled": false,
    "methods_available": { "robust_mad": true, "isolation_forest": true },
    "items": [
      {
        "anomaly_type": "amount_spike_category",
        "method": "robust_mad",
        "severity": "watch",
        "score": 4.2,
        "confidence": 0.82,
        "confidence_bucket": "high",
        "reason_codes": ["mad_zscore_gt_3_5"],
        "entity_type": "category",
        "entity_id": "uuid",
        "window_start": "2026-04-10",
        "window_end":   "2026-04-17",
        "baseline":    { "median": 340, "mad": 60 },
        "observation": { "sum": 1820, "n": 3 },
        "explanation": "3 transactions in 'dining' total 1820 vs trailing median 340."
      }
    ]
  },

  "risk": {
    "version": "0.1.0",
    "generated_at": "2026-04-17T18:00:00Z",
    "disabled": false,
    "model_enabled": false,
    "scores": [
      {
        "target": "budget_overrun_risk",
        "method_used": "heuristic",
        "probability": 0.68,
        "severity": "warn",
        "confidence": 0.6,
        "confidence_bucket": "medium",
        "data_sufficient": true,
        "calibration_applied": false,
        "reason_codes": ["pace_above_1_2x"],
        "entity_type": "budget",
        "entity_id": "uuid",
        "features_used": ["pace", "days_remaining", "category_volatility"]
      }
    ]
  },

  "ai": {
    "version": "0.1.0",
    "generated_at": "2026-04-17T18:00:00Z",
    "mode": "real",                  // disabled | fake | real
    "model": "gemini-3-flash-preview",
    "ai_validated": true,
    "fallback_used": false,
    "reason_codes": [],
    "envelope": {
      "narrative_summary": "Your April spend is tracking ~12% above March ...",
      "pillars":   [ /* AIPillar[] */ ],
      "recommendation_phrasings":   [ /* AIRecommendationPhrasing[] */ ],
      "missing_input_prompts":      [ /* AIMissingInputPrompt[] */ ],
      "coaching":                   [ /* AICoachingNudge[] */ ],
      "follow_up_questions":        [ /* AIFollowUpQuestion[] */ ]
    },
    "validation": { "passed": true, "errors": [], "warnings": [] },
    "layer_statuses": { "forecast": "ok", "anomaly": "ok", "risk": "ok" },
    "model_versions": { "deterministic": "0.1.0", /* ... */ }
  },

  "layer_errors": {},                // { "forecast": "ValueError: ...", ... } if any soft-failed
  "dry_run": false,
  "model_versions": { /* versions.py */ }
}
```

The full Pydantic contracts live at `backend/app/goat/contracts.py`.

---

## 4. Database model

Seven tables, all with RLS (read-own, mutate-own where applicable). Backend
workers write with the **service role key** and bypass RLS.

| Table | Purpose | Lifecycle |
|---|---|---|
| `goat_mode_jobs` | One row per `/run` call; status `queued / running / succeeded / partial / failed / cancelled` | Updated by runner |
| `goat_mode_snapshots` | Computed payload per `(user, scope, data_fingerprint)` - unique index makes reruns idempotent | Upsert on fingerprint |
| `goat_mode_job_events` | Per-step audit (`dispatch / input_load / deterministic / forecast / anomaly / risk / recommendation / ai / persist / callback / teardown`) | Insert-only |
| `goat_mode_recommendations` | Independent lifecycle (`open / dismissed / snoozed / resolved / expired`), uniqued on `(user, rec_fingerprint) WHERE status = 'open'` | User flips status; backend inserts |
| `goat_user_inputs` | One row per user. Declared income, pay frequency, EF target, liquidity floor, tone preference, ... | User CRUD |
| `goat_goals` | User-declared goals (emergency fund / savings / travel / debt / investment) | User CRUD |
| `goat_obligations` | Declared recurring debts (EMI / rent / insurance / CC min) | User CRUD |

**Full DDL** for the 3 user-facing tables plus a working seed is at
`scripts/goat_user_inputs_with_seed.sql`. The compute tables (jobs / snapshots /
events / recommendations) come from `supabase/migrations/20260423120000_goat_mode_v1.sql`
on the backup branch.

**Fingerprint conventions:**

- `data_fingerprint = sha1( user_id | scope | range | sorted(counts) | sorted(updated_at_stamps) )` -> same input = same snapshot row (upsert).
- `rec_fingerprint = sha1( kind | keys... )` -> reruns never create duplicate open recommendations.

---

## 5. Processing pipeline (`runner.run_job`)

1. **Create `goat_mode_jobs` row** (unless `dry_run`). This guarantees a breadcrumb even for crashes.
2. **Load bundle** via `data_loader.load_bundle(user_id, scope, range_start, range_end)`. This fetches transactions (in-range + prior-range), accounts, budgets, recurring series, goat_user_inputs, goat_goals, goat_obligations, profile.
3. **Deterministic layer** (`deterministic.compute_scope`) builds the `ScopePayload` - metrics only, no ML.
4. **Coverage + readiness** (`missing_inputs.compute_coverage`) computes seven pillar scores and classifies `L1 / L2 / L3`.
5. **Soft-fail statistical layers** (each wrapped in `_soft_run`):
   - `forecasting.run_forecasting_layer(bundle)`
   - `anomaly.run_anomaly_layer(bundle, payload)`
   - `risk.run_risk_layer(bundle, payload, forecast)`
6. **Recommendations** (`recommendations.generate(...)`) deduplicated against `existing_open_fingerprints`.
7. **AI layer** (soft-fail): `ai.run_ai_layer(...)` builds a flat input bundle, calls Gemini (or the fake/disabled path), validates grounding, falls back to deterministic phrasing on any failure.
8. **Persist**:
   - Upsert `goat_mode_snapshots` by `data_fingerprint`.
   - Insert new rows into `goat_mode_recommendations`.
   - Update job row with `status`, `readiness_level`, `data_fingerprint`, `model_versions`, `finished_at`.
   - Bulk-insert job_events.

If any non-AI layer soft-fails, `snapshot_status` degrades from `completed` to
`partial`. An AI-only failure never degrades status - the deterministic layers
are always the source of truth.

---

## 6. Algorithms, layer by layer

### 6.1 Deterministic metrics (`deterministic.py`)

Pure math + stats over existing Billy data. Every metric carries
`confidence`, `confidence_bucket`, `reason_codes`, `inputs_used`,
`inputs_missing`, `detail`.

Representative metrics by scope:

- **overview**: `net_worth`, `daily_spend_avg`, `savings_rate`, `month_to_date_spend`
- **cashflow**: `inflow_window`, `outflow_window`, `net_flow`, `recurring_share`
- **budgets**: `budget_pace`, `overruns_count`, `headroom_by_category`
- **recurring**: `recurring_due_next_30d`, `recurring_drift_count`
- **debt**: `total_outstanding`, `monthly_debt_load`, `debt_to_income_proxy`
- **goals**: `goal_progress_pct`, `ef_months_current`, `ef_shortfall`

`_span_days`, `_sum_by_type`, `_income_total`, `_expense_total` are the
aggregation primitives. All dates are `date.isoformat()`; all amounts are
`float` with a currency fallback of `INR`.

### 6.2 Forecasting (`forecasting/`)

Six targets, each with its own minimum-history threshold and fallback chain:

```python
MIN_HISTORY = {
  "short_horizon_spend_7d":          14,
  "short_horizon_spend_30d":         21,
  "end_of_month_liquidity":          21,
  "budget_overrun_trajectory":        7,
  "emergency_fund_depletion_horizon":30,
  "goal_completion_trajectory":       0,   # deterministic on static inputs
}
```

**Model selection** (`policy.choose_spend_model`):

| Data (days) | Model | Notes |
|---|---|---|
| `< 14` | `none` | Emits `insufficient_history` target |
| `14..44` | `seasonal_naive` | day-of-week repeat |
| `45..89` | `ets` | Exponential smoothing (statsmodels) |
| `>= 90` | `prophet` | if `prophet` is importable |

Runs with automatic fallback: `prophet -> ets -> seasonal_naive -> rolling_median -> naive_mean`.

Each target emits:

```
ForecastTargetOut {
  target, status, model_used, fallback_used,
  history_length, horizon_days,
  confidence (0..1), confidence_bucket, reason_codes,
  insufficient_data_fields,
  entity_id, entity_label,
  value: { p10, p50, p90, ... },
  series: ForecastSeries { horizon_days, unit, points[] }
}
```

**No market / news / weather inputs.** The only future-known regressors are
internal: salary_day, recurring-series due dates.

### 6.3 Anomaly detection (`anomaly/`)

Two-stage pipeline, deterministic first, ML second:

- **Stage 1 - robust/rule-based** (`robust.py`):
  - `amount_spike_category` - MAD z-score (`> 3.5`) per category vs trailing window
  - `recurring_bill_jump` - > 30% above trailing median for a recurring series
  - `budget_pace_acceleration` - pace > 1.6x expected
  - `low_liquidity_pattern` - cash-months < 1.0
  - `duplicate_like_pattern` - same amount within 2-day window
- **Stage 2 - IsolationForest** (`isoforest.py`, sklearn):
  - Runs only when history >= 60 days AND sklearn is importable
  - Suppressed when deterministic evidence is weak (avoids noisy alerts on thin data)

Whole layer suppressed below `MIN_HIST_DAYS = 14` days with reason
`insufficient_history`. Output items carry `method`, `baseline`, `observation`,
`explanation`, and a severity in `info / watch / warn / critical`.

### 6.4 Risk scoring (`risk/`)

Five targets, heuristic-by-default, with an optional model upgrade path:

```
budget_overrun_risk
missed_payment_risk
short_term_liquidity_stress_risk
emergency_fund_breach_risk
goal_shortfall_risk
```

**Heuristics** (`risk/heuristics.py`) produce a `RiskScore` with
`method_used="heuristic"`, `probability`, `severity`, `features_used`, and
`reason_codes`. Each heuristic can say `data_sufficient=false` and list
`insufficient_data_fields` instead of producing a probability.

**Model upgrade** (`risk/model.py`) is feature-flagged. When
`is_enabled()` returns true, the scorer replaces heuristic `budget_overrun_risk`
rows with a calibrated logistic regression prediction (`method_used =
"logreg_calibrated"`), keeping the heuristic probability in `detail.heuristic_probability`
for audit.

Severity thresholds: `p < 0.25 -> info`, `< 0.5 -> watch`, `< 0.75 -> warn`, else `critical`.

### 6.5 Recommendations (`recommendations.py`)

Deterministic template-based engine. Each rec has:

```
kind            (RecKind enum - budget_overrun / anomaly_review / liquidity_warning / ...)
severity        (info|watch|warn|critical)
priority        0..100  (used for sort + UI badge)
impact_score    0..1
effort_score    0..1
confidence      0..1
rec_fingerprint sha1-32, stable across runs
entity_type     "budget" | "account" | "category" | ...
entity_id       uuid or free-form id
observation     { /* facts */ }
recommendation  { /* suggested action + parameters */ }
```

Generators include: `_missing_input_recs`, `_budget_overrun_recs`,
`_liquidity_warning_recs`, `_goal_shortfall_recs`, `_recurring_drift_recs`,
`_duplicate_cluster_recs`, `_anomaly_review_recs`, plus a missed-payment-risk
passthrough from the risk layer.

**Idempotency via fingerprints:** the runner passes
`existing_open_fingerprints` from `sb.list_open_recommendation_fingerprints`
and the engine skips anything already open. Flipping a rec to
`dismissed / resolved / expired` frees its fingerprint so a future compute can
re-surface it.

### 6.6 AI layer (`ai/`)

Gemini does **phrasing only**. It never produces numbers or entity IDs that
aren't in the input bundle - the validator hard-rejects those.

Files and roles:

- `ai/client.py` - resolves mode (`disabled / fake / real`) from env, builds the
  Gemini client, enforces a 25s per-call deadline, returns a `RawAIResult`.
- `ai/prompts.py` - `build_ai_input_bundle(...)` (flat dict, the source of
  truth for grounding checks) and `build_prompt(...)` (the actual string).
  Clips recs to 12, anomalies to 8, forecast targets to 6, risk targets to 5.
- `ai/validator.py` - runs 6 checks (shape / rec_fingerprint set / input_key
  set / reason_codes set / no hallucinated digits / no prohibited advice
  patterns) and returns an `AIValidationReport`. Never raises.
- `ai/fallbacks.py` - builds a deterministic `GoatAIEnvelopeOut` when AI is
  disabled, falls back, or fails validation.
- `ai/renderer.py` - orchestrator, always returns a typed `AILayer`.

**Default model:** `gemini-3-flash-preview` (override with `GOAT_AI_MODEL`).
See `.cursor/skills/gemini-api-dev/SKILL.md` for current model picks.

**Grounded output contract** (`GoatAIEnvelopeOut`):

```
narrative_summary         (<= 600 chars)
pillars[]                 AIPillar     (observation / inference / confidence / reason_codes)
recommendation_phrasings[] AIRecommendationPhrasing (wraps an existing rec by rec_fingerprint)
missing_input_prompts[]   AIMissingInputPrompt      (wraps an existing missing input key)
coaching[]                AICoachingNudge
follow_up_questions[]     AIFollowUpQuestion
```

### 6.7 Readiness classification (`missing_inputs.py`)

Seven coverage pillars, each 0..1:

| Pillar | Saturates at |
|---|---|
| `transactions` | 60 tx across window + prior |
| `accounts` | 2 active |
| `budgets` | 3 active |
| `recurring` | (see source) |
| `income_declared` | 1 if `goat_user_inputs.monthly_income` is set |
| `goals` | any active goat_goals |
| `obligations` | any active goat_obligations |

The weighted average becomes `coverage_score`. Classification:

- `L1` - operational data only; deterministic metrics usable, forecast/risk suppressed
- `L2` - + declared income, salary_day, EF target; unlocks budget/risk/forecast
- `L3` - + budgets/recurring/accounts/statements fully populated; highest confidence

`MissingInput { key, label, why, unlocks, severity }` is attached to the
coverage summary so the UI can render an "ask only what's missing" form.

---

## 7. Edge function (`goat-mode-trigger`)

Responsibilities, in order:

1. CORS preflight handling, 405 on non-POST, 413 on body > 64 KB.
2. Reject if no `Authorization` header (401 `UNAUTHORIZED`).
3. Build a Supabase client with the caller's JWT, call `auth.getUser()`.
4. Parse body, validate `scope` (allow-list of 7 values) and ISO dates.
5. **Security invariant**: any `user_id` in the body is **ignored**; the
   user id always comes from `auth.getUser()`. A mismatch is logged.
6. Entitlement gate: reject with 403 `GOAT_MODE_NOT_ENABLED` if
   `profiles.goat_mode !== true`. Uses the **user-scoped** client so RLS applies.
7. `dispatchGoatBackend(...)` (in `_shared/backend_dispatch.ts`) attaches the
   shared secret. On Cloud Run it additionally mints a GCP-signed OIDC ID
   token via `_shared/gcp_id_token.ts`.
8. Return a trimmed client-safe response: `{ ok, user_id, scope, dry_run,
   job_id, snapshot_id, readiness_level, snapshot_status, data_fingerprint,
   recommendation_count, layer_errors, ai: { mode, model, ai_validated,
   fallback_used } }`.

A Safari-friendly Vercel proxy is available at `web/api/goat-mode-trigger.js`.

---

## 8. Environment / configuration

### Backend (`backend/app/goat/`)

| Var | Purpose | Default |
|---|---|---|
| `SUPABASE_URL` | Project URL | **required** |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key (bypasses RLS for writes) | **required** |
| `GOAT_BACKEND_SHARED_SECRET` | Must match the edge function's secret | **required** |
| `GOAT_ALLOW_DEV_ENDPOINTS` | `1` to expose `/run-for-user` | `0` |
| `GOAT_TEST_USER_ID` | Fallback user for dev endpoint | unset |
| `GOAT_AI_ENABLED` | `1` to call Gemini at all | `0` |
| `GOAT_AI_FAKE_MODE` | `1` to short-circuit with a canned fake envelope | `0` |
| `GOAT_AI_MODEL` | Override the default Gemini model | `gemini-3-flash-preview` |
| `GEMINI_API_KEY` | Required for `real` mode | unset |

### Edge function

| Var | Purpose |
|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Build the user-scoped client |
| `GOAT_BACKEND_URL` | Cloud Run / local FastAPI base URL |
| `GOAT_BACKEND_SHARED_SECRET` | Matches backend |
| `GCP_SERVICE_ACCOUNT_JSON` | For OIDC on Cloud Run (optional on local) |

### Version map (`versions.py`)

```json
{
  "deterministic": "0.1.0",
  "recommendations": "0.2.0",
  "missing_inputs": "0.1.0",
  "forecast": "0.1.0",
  "anomaly": "0.1.0",
  "risk": "0.1.0",
  "ai": "0.1.0"
}
```

Written into `goat_mode_jobs.model_versions` and `goat_mode_snapshots.ai_layer.model_versions`
so downstream consumers can tell which code produced a row.

---

## 9. How to integrate into a new app

The steps below assume you have a Supabase project and a user table you want
Goat Mode to sit alongside. Everything is reusable as-is; the main
Billy-isms to watch are the assumed column names on `transactions`, `accounts`,
`budgets`, and `recurring_series`.

1. **Copy the database schema.**
   - Compute tables: run `supabase/migrations/20260423120000_goat_mode_v1.sql`
     and `20260424090000_goat_mode_phase8_entitlement.sql` from the backup branch.
   - User-input tables + seed: run `scripts/goat_user_inputs_with_seed.sql`.
   - Ensure `profiles(id)`, `accounts(id)`, `recurring_series(id)` exist in the
     target project; foreign keys depend on them. Rename or drop FKs if your
     target schema differs.

2. **Drop in the backend.**
   - Copy `backend/app/goat/` (and its `__init__.py`) into your FastAPI app.
   - Mount the router: `app.include_router(goat.api.router)`.
   - Install deps: `pydantic`, `fastapi`, `supabase-py`, `httpx`. Optional but
     recommended: `statsmodels` (ETS), `prophet`, `scikit-learn` (IsolationForest +
     logistic regression), `google-genai`.

3. **Adapt the data loader** (`backend/app/goat/data_loader.py`).
   - This is the one place that reads your operational tables. Columns the
     loader touches include:
     - `transactions.{amount, type, transaction_date, category_id, account_id, updated_at}`
     - `accounts.{current_balance, is_active, is_asset, currency}`
     - `budgets.{period_start, period_end, limit_amount, category_id, is_active}`
     - `recurring_series.{next_occurrence_date, amount, is_active}`
   - If your shape differs, translate there rather than in the deterministic
     module - it keeps the compute code intact.

4. **Deploy the edge function.**
   - Copy `supabase/functions/goat-mode-trigger/` and `supabase/functions/_shared/`
     from the backup branch.
   - `supabase functions deploy goat-mode-trigger`.
   - Set the secrets: `supabase secrets set GOAT_BACKEND_URL=... GOAT_BACKEND_SHARED_SECRET=...`.

5. **Wire entitlement.**
   - Add a `goat_mode boolean not null default false` column to your
     `profiles` table (see `20260422120000_profiles_goat_mode_flag.sql`).
   - Flip it to `true` for beta users via a privileged backend.

6. **Expose the client.**
   - The Flutter client is at `lib/features/goat/services/goat_mode_service.dart`
     (edge-function call) and `lib/features/goat/providers/goat_mode_providers.dart`
     (polling loop + latest-snapshot stream).
   - For a non-Flutter app: POST the JWT to the edge function, parse the
     abridged response, then query `goat_mode_snapshots` and
     `goat_mode_recommendations` directly under RLS.

7. **Turn AI on when ready.**
   - Start with `GOAT_AI_ENABLED=0` (everything works; `ai.mode = "disabled"`).
   - Flip `GOAT_AI_FAKE_MODE=1` to exercise the validator + fallback plumbing
     without spending tokens.
   - Set `GOAT_AI_ENABLED=1 GEMINI_API_KEY=...` for production.

---

## 10. Trade-offs and gotchas

- **Input-only fingerprints.** `data_fingerprint` is built from counts +
  per-table max `updated_at`. Bulk-editing transactions without touching
  `updated_at` won't bump the fingerprint; a fresh compute will upsert into
  the same snapshot row. This is by design but is worth knowing.

- **Prophet / ETS are optional.** If neither is importable, every target falls
  back to `seasonal_naive` or `rolling_median`. The `forecast.models_available`
  flag tells the client what actually ran.

- **IsolationForest is gated.** It only runs when you have 60+ days of spend
  and sklearn is installed. Below that, anomalies are purely robust/rule-based.

- **Risk model is off by default.** `risk.model.is_enabled()` must return true
  (env flag + calibrated model artefacts on disk) before calibrated scores
  replace heuristic ones. The heuristic path always runs.

- **AI is append-only.** A failing AI layer never blocks persistence - the
  deterministic snapshot lands regardless. The validator's rejection count is
  surfaced via `ai.validation.errors`. Investigate false negatives by reading
  the rejected envelope from the `job_events.detail` payload.

- **Recommendations don't delete.** Users flip status. If you need to forget
  a fingerprint permanently, write `status = 'expired'` (not `DELETE`).

- **Profile column `preferred_currency`.** The deterministic layer reads it
  from `bundle.profile.preferred_currency`; if you don't have that column, the
  unit fallback is `INR`. Change that default in `deterministic.py` for
  non-INR deployments.

---

## 11. Files at a glance

```
backend/app/goat/
  api.py                 HTTP routes, auth dependency
  auth.py                shared-secret verifier
  cli.py                 `python -m app.goat.cli run ...`
  contracts.py           all Pydantic models (the wire contract)
  data_loader.py         reads operational tables -> GoatDataBundle
  deterministic.py       metrics per scope
  fingerprints.py        data + rec fingerprint helpers
  missing_inputs.py      coverage pillars + L1/L2/L3
  recommendations.py     deterministic rec generators
  runner.py              orchestrator (soft-fail layers, persists)
  scoring.py             bucketing + utility math
  supabase_io.py         Supabase writes (service-role)
  versions.py            MODEL_VERSIONS
  forecasting/
    policy.py            per-target selection + fallback chain
    baselines.py         seasonal_naive, rolling_median, naive_mean
    ets.py               ETS via statsmodels (optional)
    prophet_model.py     Prophet (optional)
    features.py          future-known regressors
  anomaly/
    detector.py          stage 1/2 orchestrator
    robust.py            MAD / rule-based detectors
    isoforest.py         sklearn IsolationForest (optional)
  risk/
    scorer.py            layer entrypoint
    heuristics.py        5 heuristic scorers
    model.py             calibrated logistic regression (feature-flagged)
  ai/
    client.py            disabled / fake / real router
    prompts.py           input bundle + prompt builder
    renderer.py          layer entrypoint
    validator.py         6 grounding checks
    fallbacks.py         deterministic phrasing

supabase/functions/
  goat-mode-trigger/index.ts    edge function
  _shared/backend_dispatch.ts   shared-secret + GCP OIDC dispatch
  _shared/cors.ts
  _shared/gcp_id_token.ts

scripts/
  goat_user_inputs_with_seed.sql   user-input tables + seed data
  cleanup_goat_mode_v1.sql         drop everything if rolling back
  goat/
    deploy_goat_backend_cloudrun.ps1
    deploy_goat_mode_trigger.ps1
    run-local.ps1
    seed_goat_rich.sql / medium / sparse

docs/
  GOAT_MODE_ANALYTICS_ARCHITECTURE.md
  GOAT_MODE_DATA_MODEL_DRAFT.md
  GOAT_MODE_LOCAL_FIRST_PLAN.md
  GOAT_MODE_PHASE1..8_CHECKLIST.md
  GOAT_MODE_INTEGRATION_GUIDE.md   <- you are here
```

All of those files live on the `backup/pre-revert-apr-17` branch; `main` was
rolled back to the April-16 state. To retrieve any file:

```bash
git show backup/pre-revert-apr-17:<path> > <local-name>
```

Or cherry-pick commit `f6127df` (Goat Mode v1) on top of the target branch.
