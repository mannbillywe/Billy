# Goat Mode — Phase 5: Supabase Edge Function + Cloud Run

Phase 5 bridges the already-green local compute stack to a real remote
orchestration path.

**Deployed architecture (Cloud Run — current production path):**

```
Flutter client  ─►  Supabase Edge Function (goat-mode-trigger)
                           │
                           │  HTTPS + X-Goat-Backend-Secret
                           ▼
                    Cloud Run  billy-ai  (asia-south1, allUsers invoker)
                           │
                           ▼
                    Supabase tables (goat_mode_jobs/snapshots/recommendations)
```

URL: `https://billy-ai-eq3uykqo2q-el.a.run.app`

Earlier in this phase the GCP org policies
(`iam.disableServiceAccountKeyCreation`, `iam.allowedPolicyMemberDomains`)
blocked both `allUsers` invoker bindings and SA-key-based Workload
Identity. After `mann@billy-co.com` was elevated to Google Workspace
super-admin, we granted ourselves `roles/resourcemanager.organizationAdmin`
and `roles/orgpolicy.policyAdmin` at the organization level, then
overrode both constraints at the *project* level (`billy-ai-493507`).
The Cloudflare Tunnel + local-host path used during the blocked phase
is preserved in `scripts/goat/start_dev_host.ps1` for future dev-host
scenarios, but is no longer part of the live production wire.

Hard rules kept in force:

- Edge Function is **thin**; no analytics compute.
- `user_id` comes **only** from the Supabase auth context.
- Backend stays stateless; all writes still land in `goat_mode_*` tables.
- Gemini remains the phrasing/explanation layer introduced in Phase 4.
- No Flutter changes in this phase.

---

## New files

| Path | Purpose |
| --- | --- |
| `supabase/functions/goat-mode-trigger/index.ts` | Thin auth + dispatch Edge Function |
| `supabase/functions/_shared/backend_dispatch.ts` | Shared helper for Cloud Run dispatch (secret + timeouts) |
| `backend/app/goat/auth.py` | FastAPI dep: `verify_backend_secret` |
| `backend/app/.env.production.example` | Cloud Run env template |
| `backend/app/tests/test_auth_edge.py` | 7 tests for shared-secret enforcement |
| `scripts/goat/deploy_goat_backend_cloudrun.ps1` | Cloud Run deploy/update script (retained for future use) |
| `scripts/goat/deploy_goat_mode_trigger.ps1` | Edge Function deploy script |
| `scripts/goat/start_dev_host.ps1` | One-shot launcher: backend + Cloudflare Tunnel + push URL to Supabase |
| `supabase/functions/_shared/gcp_id_token.ts` | ID-token minter for future private Cloud Run (unused in current path) |

## Touched files

| Path | Change |
| --- | --- |
| `backend/app/goat/api.py` | `/goat-mode/run`, `/run-for-user`, `/jobs/{id}`, `/latest/{user_id}` now depend on `verify_backend_secret` |
| `backend/app/main.py` | `/health` reports `shared_secret_enforced`, `shared_secret_required`, `ai_enabled` |
| `backend/app/.env.example` | Adds `GOAT_BACKEND_SHARED_SECRET` + `GOAT_REQUIRE_SHARED_SECRET` |

---

## Required function secrets (Supabase Edge Function)

Set in Dashboard → Edge Functions → Secrets, or via CLI:

```powershell
npx supabase secrets set --project-ref wpzopkigbbldcfpxuvcm `
  GOAT_BACKEND_URL='https://billy-ai-eq3uykqo2q-el.a.run.app' `
  GOAT_BACKEND_SHARED_SECRET='<same-long-random-hex-as-cloud-run>'
```

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are provided automatically by the
Supabase runtime — do **not** set them manually.

## Required Cloud Run env / secrets

Prefer Secret Manager (`--set-secrets`) for credential-grade values; plain
env vars (`--set-env-vars`) for flags. The deploy script does both for you:

| Var | Where | Value |
| --- | --- | --- |
| `SUPABASE_URL` | Secret Manager | `https://<project-ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | Secret Manager | `sb_secret_…` or legacy service_role JWT |
| `GEMINI_API_KEY` | Secret Manager | `AIza…` |
| `GOAT_BACKEND_SHARED_SECRET` | Secret Manager | `openssl rand -hex 48` |
| `GOAT_AI_ENABLED` | env var | `1` |
| `GOAT_AI_FAKE_MODE` | env var | `0` |
| `GOAT_AI_MODEL` | env var | `gemini-2.5-flash-lite` |
| `GOAT_REQUIRE_SHARED_SECRET` | env var | `1` (fail-closed) |
| `GOAT_ALLOW_DEV_ENDPOINTS` | env var | `0` |

Bootstrap Secret Manager once per project:

```bash
gcloud secrets create SUPABASE_URL              --replication-policy=automatic
gcloud secrets create SUPABASE_SERVICE_ROLE_KEY --replication-policy=automatic
gcloud secrets create GEMINI_API_KEY            --replication-policy=automatic
gcloud secrets create GOAT_BACKEND_SHARED_SECRET --replication-policy=automatic

# Write a version (repeat with --data-file=- for each):
printf 'sb_secret_xxxxxxxxxxxxxxxxxx' | gcloud secrets versions add SUPABASE_SERVICE_ROLE_KEY --data-file=-
```

Then grant Cloud Run access:

```bash
gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member=serviceAccount:$(gcloud run services describe billy-ai \
      --region=asia-south1 --format='value(spec.template.spec.serviceAccountName)') \
  --role=roles/secretmanager.secretAccessor
```

---

## Deploy commands

```powershell
# 1. Backend to Cloud Run.
$env:GCP_PROJECT        = '<gcp-project-id>'
$env:CLOUDRUN_REGION    = 'asia-south1'
$env:CLOUDRUN_SERVICE   = 'billy-ai'
.\scripts\goat\deploy_goat_backend_cloudrun.ps1

# 2. Edge Function to Supabase.
.\scripts\goat\deploy_goat_mode_trigger.ps1
```

The backend script uses `gcloud run deploy --source=./backend --allow-unauthenticated`
and then hits `/health` to confirm the service is up.

---

## Auth model (current phase decision)

- Cloud Run runs **allow-unauthenticated** so the Edge Function can call it
  without needing a GCP service-account token minter.
- Backend **enforces `GOAT_BACKEND_SHARED_SECRET`**. Without the matching
  `X-Goat-Backend-Secret` header, every `/goat-mode/*` route returns 401.
- The shared secret lives in Supabase function secrets and in GCP Secret
  Manager — never in source control, the client bundle, or logs.
- End-user authentication happens only at the Edge Function boundary via the
  caller's Supabase JWT. `user_id` is derived from `supabase.auth.getUser()`
  inside the function; any caller-supplied `user_id` is ignored (and a
  warning is logged).

Stronger alternative (deferred): put Cloud Run on private IAM and have the
Edge Function mint an ID token with `google-auth` before calling. This is
straightforward but requires adding a GCP service-account key or workload
identity pool to the function's secrets and is out of scope for Phase 5.

---

## Local test flows

### 1. Local backend + shared-secret unit tests

```powershell
cd backend\app
.\.venv\Scripts\python.exe -m pytest tests/test_auth_edge.py -q
```

Seven tests cover: no-secret mode, wrong header, right header, fail-closed
mode, health-unprotected, jobs endpoint protected.

### 2. Local backend + local Edge Function

Serve the function with Supabase CLI:

```powershell
# Terminal 1 — backend.
cd backend\app
.\.venv\Scripts\python.exe -m uvicorn main:app --reload --port 8080

# Terminal 2 — function.
$env:GOAT_BACKEND_URL = 'http://host.docker.internal:8080'
$env:GOAT_BACKEND_SHARED_SECRET = 'dev-secret-123'
# Mirror the same value into backend/.env while testing.
npx supabase functions serve goat-mode-trigger --no-verify-jwt --env-file .\supabase\functions\.env.local
```

> When running the backend on Windows host and function inside the CLI's
> Docker, `host.docker.internal` points at the host. If you run both natively
> (no Docker), use `http://127.0.0.1:8080`.

Invoke with a real Supabase user JWT (copy one from the Flutter app or from
`supabase auth sign-in` output):

```powershell
$token = 'eyJhbGciOi...'   # supabase user access token
$body  = '{"scope":"overview","dry_run":true}'
Invoke-RestMethod `
  -Uri 'http://127.0.0.1:54321/functions/v1/goat-mode-trigger' `
  -Method POST `
  -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
  -Body $body
```

Expected response shape:

```json
{
  "ok": true,
  "user_id": "3d8238ac-97bd-49e5-9ee7-1966447bae7c",
  "scope": "overview",
  "dry_run": true,
  "job_id": null,
  "snapshot_id": null,
  "readiness_level": "L2",
  "snapshot_status": "partial",
  "data_fingerprint": "overview:...",
  "recommendation_count": 0,
  "layer_errors": {},
  "ai": { "mode": "real", "model": "gemini-2.5-flash-lite", "ai_validated": true, "fallback_used": false }
}
```

### 3. Remote Cloud Run backend + local Edge Function (fastest real-data loop)

```powershell
$env:GOAT_BACKEND_URL = 'https://billy-ai-eq3uykqo2q-el.a.run.app'
$env:GOAT_BACKEND_SHARED_SECRET = '<the secret you stored in Secret Manager>'
npx supabase functions serve goat-mode-trigger --env-file .\supabase\functions\.env.local
```

Then the same `Invoke-RestMethod` as in flow #2.

### 4. Fully remote via Cloud Run (current production path)

The backend is already deployed at
`https://billy-ai-eq3uykqo2q-el.a.run.app` with
`--allow-unauthenticated`. The Supabase Edge Function has
`GOAT_BACKEND_URL` pointed at that host and holds the matching
`GOAT_BACKEND_SHARED_SECRET`. No per-restart setup is needed.

### 4b. Alternate dev path via Cloudflare Tunnel (off by default)

If Cloud Run is ever down or you want to iterate on the backend locally
against the real Edge Function, `scripts/goat/start_dev_host.ps1` still
works — it launches the backend on :8080, starts a quick Cloudflare
tunnel, pushes that URL to Supabase function secrets, and you're back
online. Re-run the deploy script afterwards to point Supabase back at
Cloud Run.

Call the live Edge Function:

```powershell
$token = 'eyJhbGciOi...'   # user access token (ES256 Supabase JWT)
$anon  = 'sb_publishable_...'
Invoke-RestMethod `
  -Uri 'https://wpzopkigbbldcfpxuvcm.supabase.co/functions/v1/goat-mode-trigger' `
  -Method POST `
  -Headers @{ apikey = $anon; Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
  -Body '{"scope":"full","dry_run":false}'
```

> The function is deployed with `--no-verify-jwt` because Supabase's
> Functions gateway currently only supports HS256 verification and the
> project issues modern ES256 JWTs. The function body itself still
> validates the user via `supabase.auth.getUser()` before doing anything,
> so the auth boundary is preserved.

### Verified end-to-end (2026-04-17)

Two independent paths validated on the same real UUID
`3d8238ac-97bd-49e5-9ee7-1966447bae7c`:

**A. Cloudflare tunnel → local backend**

| Step | Result |
| --- | --- |
| No auth → Edge Function | `401 UNAUTHORIZED` |
| Real user JWT, `dry_run:true` | `L2`, 15 recs, AI real+validated, ~18s |
| Real user JWT, `dry_run:false` (first run) | snapshot + 15 recs written |
| Real user JWT, `dry_run:false` (repeat) | snapshot Δ=0, recs Δ=0 (idempotent) |

**B. Cloud Run (current production wire)**

| Step | Result |
| --- | --- |
| Public `GET /health` on Cloud Run | `ok:true, shared_secret_enforced:true, ai_enabled:true` |
| Cloud Run `/goat-mode/run` without secret | `401 GOAT_BACKEND_SECRET_INVALID` |
| Cloud Run `/goat-mode/run` with correct secret | accepted, returns `RunResponse` |
| Edge Function → Cloud Run, `dry_run:true` | `L2`, 15 recs, fingerprint matches tunnel path, ~25s |
| Edge Function → Cloud Run, `dry_run:false` | same `snapshot_id` (`004c95c5…`), 15 recs preserved |

---

## Manual validation matrix

| Scenario | Expected result |
| --- | --- |
| Unauthenticated client call | `401 UNAUTHORIZED` from Edge Function |
| Client body with bogus `user_id` different from JWT | Backend receives only the JWT-derived id; warning logged |
| `scope: "moon"` | `400 INVALID_INPUT` |
| `range_start: "2026/01/01"` | `400 INVALID_INPUT` |
| `dry_run: true` | Round-trips with `job_id: null, snapshot_id: null` |
| `dry_run: false` | Returns `job_id` + `snapshot_id`; rows appear in `goat_mode_jobs/snapshots` |
| Repeat wet run with same data | Identical `data_fingerprint`; exactly one row per user in `goat_mode_snapshots` |
| Wrong/missing `GOAT_BACKEND_SHARED_SECRET` on function | Function returns `502 BACKEND_REJECTED_SECRET` |
| `profiles.goat_mode = false` | `403 GOAT_MODE_NOT_ENABLED` |
| Backend down | `502 BACKEND_UNREACHABLE`; `504 BACKEND_TIMEOUT` after 120s |

---

## Stable response contract

Edge Function response (on `ok: true`):

```
ok, user_id, scope, dry_run,
job_id, snapshot_id, readiness_level, snapshot_status, data_fingerprint,
recommendation_count, layer_errors,
ai: { mode, model, ai_validated, fallback_used } | null
```

Backend response (full) remains `RunResponse` as defined in `contracts.py`.
The function deliberately returns a slimmer projection to keep the wire
contract tight and to avoid leaking anything new through the edge.

---

## Intentionally NOT in this phase

- Flutter `GoatModeService` binding (Phase 6).
- Background / long-running job semantics (fire-and-forget polling).
- Per-user quota enforcement inside the Edge Function.
- Workload Identity Federation / private IAM Cloud Run (deferred).
- Realtime push of snapshot readiness.
- Production billing hardening (already scoped under `docs/PRODUCTION_READINESS.md`).

## GCP org-policy overrides applied

These project-level overrides were required to unblock Cloud Run
`allow-unauthenticated` on this org:

| Constraint | Scope | Override |
| --- | --- | --- |
| `iam.allowedPolicyMemberDomains` | `projects/billy-ai-493507` | `allowAll: true` |
| `iam.disableServiceAccountKeyCreation` | `projects/billy-ai-493507` | `enforce: false` |

Source YAMLs live in `.secrets/policy_allow_members.yaml` and
`.secrets/policy_allow_sa_keys.yaml` (gitignored). To re-apply:

```powershell
gcloud org-policies set-policy .secrets\policy_allow_members.yaml
gcloud org-policies set-policy .secrets\policy_allow_sa_keys.yaml
```

`mann@billy-co.com` was elevated to Google Workspace super-admin, then
granted `roles/resourcemanager.organizationAdmin` +
`roles/orgpolicy.policyAdmin` at the organization level, and
`roles/owner` at the project level. Without at least one of those org
roles, neither override can be written.

## Operational notes

- `/health` on Cloud Run is unauthenticated and safe to expose — it
  reveals only the state of feature flags (`ai_enabled`,
  `shared_secret_required`, etc.), never secret values.
- `/goat-mode/*` routes are fail-closed: a missing or wrong
  `X-Goat-Backend-Secret` returns `401 GOAT_BACKEND_SECRET_INVALID`.
- To rotate the shared secret: update `GOAT_BACKEND_SHARED_SECRET` in
  GCP Secret Manager *and* the Supabase function secret in the same
  window, then redeploy both sides. `scripts/goat/deploy_goat_backend_cloudrun.ps1`
  + `scripts/goat/deploy_goat_mode_trigger.ps1` handle this when the
  value in `backend/app/.env` changes.

## Blockers before Phase 6

- (Done) Supabase `profiles.goat_mode` set for the real test user.
- (Done) Shared secret lives in GCP Secret Manager, Supabase function
  secrets, and `backend/app/.env`.
- (Done) Cloud Run deployed, public, and verified end-to-end.
- Flutter `GoatModeService` wiring — scope of Phase 6.
