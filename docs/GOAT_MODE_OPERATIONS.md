# GOAT Mode — Operations Guide

Short runbook for **granting access**, **running the backend** (monthly or on demand), and **what the app does with the results**. The user-facing UI never triggers compute; it only reads what the backend wrote.

---

## 1. Data model

Migration: `supabase/migrations/20260423120000_goat_mode_v1.sql` (idempotent).

Tables:

| Table | Purpose |
|---|---|
| `public.goat_mode_access` | Admin ledger: who is entitled, when, by whom, why. RLS prevents users from granting themselves access. |
| `public.profiles.goat_mode` | Boolean flag read by the Flutter client. **Kept in sync automatically** via the `goat_mode_access_sync_profile` trigger on `goat_mode_access`. |
| `public.goat_mode_jobs` | One row per compute run (queued / running / succeeded / failed). |
| `public.goat_mode_snapshots` | One row per successful run (per `scope`): metrics, coverage, forecasts, anomalies, risk, AI envelope. |
| `public.goat_mode_job_events` | Per-layer execution events (good for debugging a flaky run). |
| `public.goat_mode_recommendations` | Open recommendations, dedupe-keyed by fingerprint. |
| `public.goat_user_inputs` / `public.goat_goals` / `public.goat_obligations` | Optional user-provided inputs that unlock deeper layers (lifestyle, goals, EMI / obligations). |

RLS: users can only `SELECT` their own rows. Only the backend (via service role) can `INSERT/UPDATE` analysis.

---

## 2. Granting GOAT Mode to a user

Two equivalent ways — pick one.

### 2a. Paste-UUID SQL (preferred)

Edit `scripts/goat/grant_goat_mode_access.sql`, paste one or more UUIDs into the `uids` array, then run it against your Supabase project:

```sql
-- In Supabase SQL Editor
\i scripts/goat/grant_goat_mode_access.sql
```

The script upserts into `goat_mode_access`. The trigger updates `profiles.goat_mode = true` automatically, so the Flutter client picks up the change on the next profile refresh.

To revoke: `scripts/goat/revoke_goat_mode_access.sql` (same pattern — the trigger sets `profiles.goat_mode = false`).

### 2b. One-off manual flip

```sql
update public.profiles set goat_mode = true where id = '<uuid>';
```

Works fine, but bypasses the audit ledger. Prefer 2a for anything real.

---

## 3. Running the backend (wet run)

The analytics backend is the one at `C:\Users\mannt\Downloads\backend` (Docker). `C:\Users\mannt\Desktop\billy_con\backend` is intentionally ignored.

Script: `scripts/goat/run_goat_backend_docker.ps1`.

```powershell
# 1. Paste UUID(s) into the $UserIds array in the script.
# 2. Make sure C:\Users\mannt\Downloads\backend\app\.env has SUPABASE_URL and
#    SUPABASE_SERVICE_ROLE_KEY (the service role — not the anon key).
# 3. Run it:
.\scripts\goat\run_goat_backend_docker.ps1
```

What it does for every UUID you paste:

1. `docker build -t billy-goat-backend:latest` against the backend folder (skip with `-SkipBuild`).
2. `docker run --rm --env-file …\.env billy-goat-backend:latest python -m goat.cli run --user-id <uuid> --scope full --pretty` — **no `--dry-run`**, so results are written to Supabase.
3. Saves the raw JSON to `.tools\goat-runs\<timestamp>-<uuid>.json` for debugging.

Scope `full` is the richest payload and is what the Flutter client prefers (falls back to `overview` if that's all that exists).

### Scheduling

Run this monthly (or ad-hoc after onboarding a new user) from a box with Docker Desktop. There is no in-app trigger by design.

---

## 4. How the Flutter client reads the data

| Layer | File |
|---|---|
| Models (read-only) | `lib/features/goat/models/goat_models.dart` |
| Supabase read service | `lib/features/goat/services/goat_mode_service.dart` |
| Riverpod providers | `lib/features/goat/providers/goat_providers.dart` |
| Dashboard (tabs) | `lib/features/goat/screens/goat_mode_screen.dart` |
| Tab bodies | `lib/features/goat/widgets/goat_mode_tab_pages.dart` |
| Section widgets | `lib/features/goat/widgets/goat_sections.dart` |

**Sample CLI / API shape** (trimmed): `docs/samples/goat_cli_run_response.sample.json` — mirrors what `python -m goat.cli run --pretty` prints and what gets folded into `goat_mode_snapshots` JSONB columns.

### Dashboard tabs (v2 layout)

| Tab | What it shows |
|---|---|
| **Overview** | Hero, coverage/score row, metric highlights, AI pillars (when enabled). |
| **Actions** | Open recommendations, unlockable scopes from coverage, missing inputs, coaching nudges. |
| **Trends** | Forecast targets (`forecast_json.targets`). |
| **Safety** | Risk + anomaly watchouts (deduped vs priority recs). |
| **Run log** | Footer metadata, recommendation counts by severity/kind, `layer_errors` from `summary_json`, recent rows from `goat_mode_jobs`. |

Flow:

1. `profileProvider` → `profileGoatModeEnabled(profile)` decides whether `BillyHeader` shows the GOAT Mode button. Ineligible users see *no* new UI.
2. Tapping the button pushes `GoatModeScreen` from `layout_shell.dart`.
3. `GoatModeScreen` watches:
   - `goatLatestSnapshotProvider` — most recent `goat_mode_snapshots` row (prefers scope `full`).
   - `goatPreviousSnapshotProvider` — second-most-recent, same scope, for "vs last run" comparisons.
   - `goatOpenRecommendationsProvider` — `goat_mode_recommendations` where `status in ('open','snoozed')`.
   - `goatRecentJobsProvider` — recent `goat_mode_jobs` for the Run log tab.
4. Each tab renders only what belongs there; empty tabs show a short explanation instead of a blank page.
5. Pull-to-refresh re-fetches. Dismiss on a priority card flips `status = 'dismissed'` via RLS-safe update.

Graceful states:

- **No snapshot yet** → `_GoatEmpty` (explains the backend writes in the background, no action needed).
- **Fetch error** → `_GoatError` (no stack, just a friendly card).
- **Partial snapshot / layer errors** → still renders; `GoatFooterMeta` surfaces "Partial snapshot" and AI validation status.
- **AI disabled** → `snapshot.ai.mode == 'disabled'` → the AI-specific sections (`Insights`, `Coaching`) hide themselves; deterministic sections still render.

---

## 5. Checklist for a brand-new user

1. Make sure `public.profiles` has a row for the user (normal signup does this).
2. `scripts/goat/grant_goat_mode_access.sql` with their UUID → Flutter shows the button.
3. `scripts/goat/run_goat_backend_docker.ps1` with their UUID → Flutter shows the full analysis.
4. (Optional) Ask the user to fill `goat_user_inputs` / `goat_goals` / `goat_obligations` for higher readiness (`L2` → `L3`).

---

## 6. What I assumed about the schema

- `goat_mode_snapshots` has the JSONB columns documented in `docs/GOAT_MODE_INTEGRATION_GUIDE.md` §5 (`metrics_json`, `forecast_json`, `anomalies_json`, `risk_json`, `ai_layer`, `summary_json`, `coverage_json`, `recommendations_summary_json`). The model parser is forgiving and tolerates missing keys.
- `goat_mode_recommendations` has `status` in `('open','snoozed','dismissed','resolved','expired')` and exposes `recommendation_json` + `observation_json` JSONB blobs.
- `ai_layer.mode` is one of `disabled | fake | real`; `ai_layer.envelope.pillars[*].confidence` is a bucket string.
- If the backend skips a layer (e.g. no AI key), the snapshot row still exists with `snapshot_status = 'partial'` and `layer_errors` populated; the app handles that cleanly.
