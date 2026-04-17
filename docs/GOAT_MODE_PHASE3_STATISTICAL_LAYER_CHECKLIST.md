# Goat Mode — Phase 3 Statistical Layer Checklist

Phase 3 extends the Phase 2 deterministic backend with three new layers — **forecast**, **anomaly**, **risk** — and adds a real-local-Supabase validation path. No Edge Functions, no Flutter, no Cloud Run deployment, no Gemini.

---

## 1. What shipped in Phase 3

### 1.1 New backend packages

| Path | Purpose |
| --- | --- |
| `backend/app/goat/forecasting/__init__.py` | Exports `run_forecasting_layer` |
| `backend/app/goat/forecasting/features.py` | Daily/monthly series extraction from `GoatDataBundle` |
| `backend/app/goat/forecasting/baselines.py` | stdlib-only baselines (`rolling_median`, `seasonal_naive`, `naive_mean`) with p10/p50/p90 bands |
| `backend/app/goat/forecasting/ets.py` | Guarded `statsmodels` ETS / Holt-Winters wrapper |
| `backend/app/goat/forecasting/prophet_model.py` | Guarded Prophet wrapper (`GOAT_USE_PROPHET=1` required) |
| `backend/app/goat/forecasting/policy.py` | Per-target model selection + the 6 target builders |
| `backend/app/goat/anomaly/__init__.py` | Exports `run_anomaly_layer` |
| `backend/app/goat/anomaly/robust.py` | `mad`, `robust_z`, `iqr_bounds` (stdlib only) |
| `backend/app/goat/anomaly/isoforest.py` | Guarded sklearn IsolationForest wrapper |
| `backend/app/goat/anomaly/detector.py` | Rule + robust-stat anomaly pipeline + optional IsolationForest fusion |
| `backend/app/goat/risk/__init__.py` | Exports `run_risk_layer` |
| `backend/app/goat/risk/heuristics.py` | Deterministic heuristics for all 5 risk targets |
| `backend/app/goat/risk/model.py` | Guarded Logistic Regression + `CalibratedClassifierCV` (flag-gated) |
| `backend/app/goat/risk/scorer.py` | Orchestrator that runs heuristics and optionally upgrades to calibrated probs |

### 1.2 Touched files

| Path | Change |
| --- | --- |
| `backend/app/main.py` | Explicit `backend/app/.env` load, `override=False` |
| `backend/app/goat/cli.py` | Explicit `.env` load, new `--print-layer` flag |
| `backend/app/goat/contracts.py` | Added `ForecastLayer`, `AnomalyLayer`, `RiskLayer`, `layer_errors`, literal unions |
| `backend/app/goat/versions.py` | Bumped `recommendations` → `0.2.0`; `forecast`/`anomaly`/`risk` → `0.1.0` |
| `backend/app/goat/supabase_io.py` | **Bug fix:** replaces Postgres-invalid `"now()"` literal with real UTC ISO timestamps in `create_job`/`update_job` |
| `backend/app/goat/runner.py` | Soft-fail orchestration; layered snapshot persistence; new `layer_errors` surface |
| `backend/app/goat/recommendations.py` | `_anomaly_recs`, `_risk_recs` — new recs grounded in statistical layers |

### 1.3 New scripts / tests / docs

| Path | Purpose |
| --- | --- |
| `scripts/goat/validate_real_supabase.py` | End-to-end validation (dry-run → wet run → idempotency) against a real local Supabase stack |
| `backend/app/tests/test_forecasting.py` | Baselines, policy selection, insufficient-history, JSON shape |
| `backend/app/tests/test_anomaly.py` | Robust stats, amount spike, recurring jump, duplicate patterns, sparse safety |
| `backend/app/tests/test_risk_and_soft_fail.py` | Heuristic correctness, gating, runner layered output, **runner soft-fail** |
| `backend/app/tests/test_integration_local_supabase.py` | Skipped-by-default real-stack integration test |

---

## 2. Model selection rules

All layers follow the same contract: **always produce something deterministic**, and only reach for statsmodels/Prophet/sklearn when data supports it.

### 2.1 Forecast (`forecasting/policy.py`)

| Target | History needed | Preferred | Fallback | Insufficient |
| --- | --- | --- | --- | --- |
| `short_horizon_spend_7d` | ≥ 14d | ETS if available | `rolling_median` → `naive_mean` | `status="insufficient_history"` |
| `short_horizon_spend_30d` | ≥ 21d | ETS | `seasonal_naive(7)` → `rolling_median` | same |
| `end_of_month_liquidity` | ≥ 21d cashflow | Net-cashflow ETS | `naive_mean(last 30d)` | same |
| `budget_overrun_trajectory` | active budget + ≥ 14d category spend | category `rolling_median` projection to period end | heuristic pace × remaining days | same |
| `emergency_fund_depletion_horizon` | declared target + 30d cashflow | deterministic runway math on ETS 30d spend forecast | naive 30d mean burn | `status="insufficient_data"` |
| `goal_completion_trajectory` | goal + declared contribution cadence | deterministic linear projection | n/a | `status="insufficient_data"` |

**Prophet is optional.** Enable with `GOAT_USE_PROPHET=1` and `pip install prophet`. Never promoted over ETS automatically — only tried when ETS fails and history length justifies it.

### 2.2 Anomaly (`anomaly/detector.py`)

Two-stage:

1. **Deterministic / robust stats** — always runs when window ≥ 14d:
   - `amount_spike_category`: robust-z ≥ **3.5** vs trailing 60d, same category.
   - `recurring_bill_jump`: latest occurrence > **+40%** vs trailing median of prior paid occurrences.
   - `budget_pace_acceleration`: current-window daily rate > **1.6×** prior window; requires active period.
   - `low_liquidity_pattern`: earliest liquid balance < **30d trailing-median spend**.
   - `duplicate_like_pattern`: ≥ **3** near-identical (same day, same category, same amount ± 1%) txns.
   - `noisy_import_cluster`: > **25%** of in-range txns are uncategorized.
2. **Unsupervised model (optional)**: `IsolationForest` when ≥ **45 days** of daily spend are present and sklearn installed. Only used to _boost severity_ on items already flagged deterministically; we never surface an ML-only anomaly in v1.

Severity map: `score < 3 → info`, `< 4.5 → watch`, `≥ 4.5 → warn`.

### 2.3 Risk (`risk/scorer.py`)

Deterministic heuristics are **always** the baseline, **always** emitted, and **always** labelled `method_used="heuristic"`.

Model-based upgrade (`budget_overrun_risk` only in v1) is gated by **all** of:

- `GOAT_RISK_MODEL_ENABLED=1`
- `scikit-learn` installed
- `data_sufficient=true` (≥ 6 completed budget periods with spend + overrun label)
- `CalibratedClassifierCV` convergence

When enabled and valid, `method_used="logreg_calibrated"` and `probability` replaces the heuristic value. Reason codes record `feature_importances` via coefficients. Otherwise we return heuristic-only and mark `calibration_status="skipped"`.

Risk targets always included: `budget_overrun_risk`, `missed_payment_risk`, `short_term_liquidity_stress_risk`, `emergency_fund_breach_risk`, `goal_shortfall_risk`. Missing prerequisites → `method_used="suppressed"` + `data_sufficient=false`.

---

## 3. Minimum-history thresholds (summary)

| Layer | Feature | Min rows |
| --- | --- | --- |
| Forecast | Daily spend series | 14 |
| Forecast | Monthly cashflow | 3 |
| Forecast | Category spend | 14 |
| Anomaly | Deterministic rules | 14d window |
| Anomaly | IsolationForest path | 45d daily spend + sklearn |
| Risk | LogReg calibrated | 6 completed budget periods |

Everything below threshold returns `insufficient_history` / `data_sufficient=false` with reason codes — never a silent or fake number.

---

## 4. Local commands

From the repo root:

```powershell
cd backend/app
.\.venv\Scripts\activate
pip install -r requirements-dev.txt      # base deps (no Prophet/sklearn needed)
# Optional statistical upgrades:
pip install statsmodels scikit-learn     # ETS + IsolationForest + LogReg
pip install prophet                      # only if you also set GOAT_USE_PROPHET=1

# Make sure backend/app/.env has real service_role key (NOT the anon JWT).
uvicorn main:app --reload --port 8080
```

### 4.1 Dry-run full (no writes)

```powershell
$body = @{ user_id = "3d8238ac-97bd-49e5-9ee7-1966447bae7c"; scope = "full"; dry_run = $true } | ConvertTo-Json
Invoke-RestMethod -Uri http://localhost:8080/goat-mode/run -Method Post -ContentType "application/json" -Body $body | ConvertTo-Json -Depth 12
```

### 4.2 Wet run (persists job + snapshot + recs)

```powershell
$body = @{ user_id = "3d8238ac-97bd-49e5-9ee7-1966447bae7c"; scope = "full"; dry_run = $false } | ConvertTo-Json
Invoke-RestMethod -Uri http://localhost:8080/goat-mode/run -Method Post -ContentType "application/json" -Body $body |
  Select-Object job_id, snapshot_id, readiness_level, snapshot_status, recommendation_count, layer_errors
```

### 4.3 CLI with per-layer inspection

```powershell
# Print only the forecast layer:
python -m goat.cli run --user-id 3d8238ac-97bd-49e5-9ee7-1966447bae7c --scope full --dry-run --pretty --print-layer forecast

# Print only anomalies / risk / recommendations / coverage:
python -m goat.cli run --user-id 3d8238ac-97bd-49e5-9ee7-1966447bae7c --scope full --dry-run --pretty --print-layer anomaly
python -m goat.cli run --user-id 3d8238ac-97bd-49e5-9ee7-1966447bae7c --scope full --dry-run --pretty --print-layer risk
```

### 4.4 Real-stack validation script

```powershell
$env:SUPABASE_URL        = "http://127.0.0.1:54321"      # or your cloud URL
$env:SUPABASE_SERVICE_ROLE_KEY = "<real-service-role-jwt>"
$env:GOAT_TEST_USER_ID   = "3d8238ac-97bd-49e5-9ee7-1966447bae7c"
python scripts/goat/validate_real_supabase.py
```

The script runs three scenarios in sequence:

1. **Dry-run** — reads, no writes, prints coverage/readiness.
2. **Wet run** — writes job, snapshot, recs; prints IDs.
3. **Idempotency** — re-runs wet run, asserts snapshot `upsert` on `(user_id, scope, data_fingerprint)` does not insert duplicates, and that rec `rec_fingerprint` dedupe holds.

### 4.5 Integration tests

```powershell
$env:GOAT_INTEGRATION = "1"
$env:SUPABASE_URL = "..."; $env:SUPABASE_SERVICE_ROLE_KEY = "..."; $env:GOAT_TEST_USER_ID = "..."
pytest -q tests/test_integration_local_supabase.py -s
```

They auto-skip when any of those env vars are missing.

---

## 5. Interpreting `insufficient_data`

When a layer emits `insufficient_history` / `data_sufficient=false`:

- The layer still returns a **typed, shaped** object — clients never see `null` fields they expect.
- `reason_codes` always explain which input was missing (e.g. `goat_user_inputs.emergency_fund_target_months`, `daily_spend<14`, `no_active_budget_period`).
- `recommendations` will steer the user toward the missing input rather than fabricating a financial claim.
- UI should render a neutral "Not enough data yet" card, _not_ an error.

This is the contract: **degraded output is a feature, not a failure.**

---

## 6. Soft-fail orchestration

`runner._soft_run` wraps every statistical layer. On exception:

- The layer's field on `RunResponse` (`forecast`/`anomalies`/`risk`) stays `None`.
- `layer_errors[<layer>]` records the short message.
- `snapshot_status` degrades to `"partial"`.
- The job still completes; Phase 2 deterministic output is unaffected.
- Snapshot `ai_layer.layers[<layer>]` records `"error:<message>"` for audit.

Covered by `test_runner_soft_fail_does_not_crash`.

---

## 7. Intentionally NOT in Phase 3

- **Gemini** — no LLM calls, no narratives, no AI recommendations.
- **Edge Functions** — no Supabase Functions code, no triggers, no cron.
- **Flutter UI** — backend-only phase. UI wiring happens in a later phase.
- **Cloud Run** — still local-first. Deployment comes after UI integration.
- **External data** — dedicated-data-only. No market, weather, news, or macro signals.
- **SHAP / full explainability UI** — logistic coefficients are captured as reason codes, but SHAP integration is deferred.
- **Goal shortfall model-based probability** — heuristic only in v1.
- **Anomaly dismissal persistence** — anomaly items are computed per-run; dismissal reuses Phase 2's existing `ai_suggestions` pattern as a future hook.

---

## 8. Known blockers before Phase 4

1. **Env hygiene:** `SUPABASE_SERVICE_ROLE_KEY` must be the real service-role JWT. The anon JWT still respects RLS, yielding 0 rows for server-side reads. `main.py` and `cli.py` now pin to `backend/app/.env` — but we still depend on operators filling in the right secret.
2. **Optional deps drift:** If ops enable ETS/Prophet/sklearn on some environments but not others, outputs will vary. Pin versions in `requirements-prod.txt` before any Cloud Run push.
3. **Prophet footprint:** Prophet pulls in `cmdstanpy`/`pystan`; heavy in containers. Keep `GOAT_USE_PROPHET=0` by default.
4. **Anomaly false-positive tuning:** Thresholds (3.5 z-score, +40% recurring jump) are conservative but not yet tuned against labelled Billy data. Needs a feedback loop once UI dismissals land.
5. **Risk calibration data:** Model path requires ≥ 6 completed budget periods per user; most real users won't qualify yet. Heuristic is the de-facto path for v1.
6. **Schema untouched:** All Phase 3 outputs live inside existing `goat_mode_snapshots.{forecast,anomalies,risk}_json` + `ai_layer` columns. No migration needed; confirmed applied.

---

## 9. Contract stability

`RunResponse` now always includes:

```json
{
  "job_id": "...",
  "snapshot_id": "...",
  "snapshot_status": "complete | partial | failed",
  "coverage": { ... },
  "payload": { ... },
  "forecast":   { "targets": [...], "model_versions": {...}, "generated_at": "..." } | null,
  "anomalies":  { "items": [...], "disabled": false, "reason_codes": [...] } | null,
  "risk":       { "scores": [...], "model_enabled": false, ... } | null,
  "recommendations": [ ... ],
  "layer_errors": { "anomaly": "..." },
  "model_versions": { "forecast": "0.1.0", "anomaly": "0.1.0", "risk": "0.1.0", ... },
  "dry_run": true | false
}
```

Any Phase 4 addition (Gemini, Edge Function, Flutter) must preserve this shape.
