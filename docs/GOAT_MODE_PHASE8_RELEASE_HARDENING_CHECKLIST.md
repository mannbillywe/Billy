# Goat Mode — Phase 8: Entitlement Hardening + Release Readiness

This document captures the decisions, implemented files, and operational
posture for the v1 release of Goat Mode.

---

## Can only users with `profiles.goat_mode = true` access Goat Mode?

**Yes, at every layer that can meaningfully act on Goat data** — with one
intentional nuance.

| Layer                       | Entitlement enforcement |
|-----------------------------|-------------------------|
| Flutter UI                  | Gated — non-entitled users see the "Goat Mode is rolling out" card. No setup/recommendation UI is reachable. |
| Flutter provider reads      | Gated — `goatModeControllerProvider` is only subscribed to for entitled users. No Supabase reads are issued otherwise. |
| Supabase Edge Function      | Gated — `goat-mode-trigger` short-circuits with `GOAT_MODE_NOT_ENABLED` (403) when `profiles.goat_mode != true`. |
| Backend (`/goat-mode/run*`) | Protected by the Edge ↔ Backend shared secret (`verify_backend_secret`). The Edge Function is the entitlement gatekeeper; the backend assumes pre-gated callers only. |
| Database (RLS)              | **WRITES gated** — INSERT / UPDATE / DELETE on `goat_user_inputs`, `goat_goals`, `goat_obligations`, `goat_mode_jobs` (insert), and UPDATE on `goat_mode_recommendations` now also require `profiles.goat_mode = true`. |

**Nuance — reads stay user-scoped, not entitlement-scoped.** If a user is
de-entitled later, they can still *read* their historical Goat rows through
RLS. This is intentional: compute never ran for a user that was never
entitled, so there is nothing to hide; and when we retroactively gate an
existing user we don't want their own data to silently vanish from their
session. All *writes* from that point forward are blocked.

---

## Final access model

Defence in depth, three layers:

1. **UI gate** (Flutter `goatModeEntitlementProvider`) — the user never sees
   Goat Mode UI unless entitled.
2. **Edge Function gate** (`goat-mode-trigger`) — even a crafted request
   cannot trigger Goat compute for a non-entitled user.
3. **DB entitlement gate on writes** (RLS migration `20260424090000_goat_mode_phase8_entitlement.sql`) — a non-entitled user who tries to
   insert/update/delete their own Goat rows directly against Supabase (via
   raw REST, a modified client, etc.) is rejected by PostgREST.

The compute backend (`runner.py` + `supabase_io.py`) uses the Supabase
service_role key, which bypasses RLS — it is *not* affected by the new
policies, so the existing compute flow is unchanged.

---

## Implemented / modified files

### New files

| Path | Purpose |
|------|---------|
| `supabase/migrations/20260424090000_goat_mode_phase8_entitlement.sql` | Adds the `public.goat_mode_enabled_for(uuid)` helper and tightens write-path RLS on all client-writable Goat tables. |
| `scripts/goat/verify_phase8_entitlement_rls.sql` | Diagnostic script to confirm the helper + policies landed correctly on a real Supabase project. Includes commented-out live write checks. |
| `backend/app/tests/test_phase8_dev_endpoint.py` | Backend tests covering the dev endpoint posture (default-off, requires shared secret even when on, env example stays safe). |
| `test/goat_mode_entitlement_widget_test.dart` | Flutter widget tests for the non-entitled UI state, provider-read suppression, and setup-screen deep-link fallback. |
| `docs/GOAT_MODE_PHASE8_RELEASE_HARDENING_CHECKLIST.md` | This document. |

### Modified files

| Path | Change |
|------|--------|
| `backend/app/goat/api.py` | Hardened `_dev_endpoints_enabled()` helper (only `"1"` / `"true"` enable it), added a warning log on every dev-endpoint hit so accidental prod enablement is visible, tightened docstring. |
| `backend/app/.env.example` | `GOAT_ALLOW_DEV_ENDPOINTS` default flipped to `0` with an explicit production-safety comment. `GOAT_REQUIRE_SHARED_SECRET` comment now recommends `1` for prod. |
| `lib/features/goat/screens/goat_mode_screen.dart` | `goatModeControllerProvider` is only watched when entitled — avoids Supabase round-trips for non-entitled users. |
| `lib/features/goat/screens/goat_setup_screen.dart` | Belt-and-suspenders: non-entitled users who somehow reach the setup screen fall back to the rollout card instead of seeing an empty form they couldn't save anyway. |
| `test/goat_setup_screen_widget_test.dart` | Added `entitled: true` override to the test host to match the new screen contract. |
| `.gitignore` | Ignores `backend/app/wet-run-ai.json` and any `*.wet-run.json` local debug dumps. |

---

## Production env defaults

Recommended Cloud Run / production environment:

```
GOAT_BACKEND_SHARED_SECRET=<long random hex, generated with openssl rand -hex 48>
GOAT_REQUIRE_SHARED_SECRET=1
GOAT_ALLOW_DEV_ENDPOINTS=0    # or unset entirely
GOAT_TEST_USER_ID=            # MUST be empty in production
GOAT_AI_ENABLED=1
GOAT_AI_FAKE_MODE=0
SUPABASE_URL=<prod supabase url>
SUPABASE_SERVICE_ROLE_KEY=<prod service-role JWT>
GEMINI_API_KEY=<prod api key>
```

Full template in `backend/app/.env.production.example`.

### Dev-only flags and how they are disabled in production

| Flag | Safe default | Disabled in prod by |
|------|--------------|---------------------|
| `GOAT_ALLOW_DEV_ENDPOINTS` | `0` (env example, `_dev_endpoints_enabled()`) | Unset or `0`. `/run-for-user` returns 404 in that case. |
| `GOAT_AI_FAKE_MODE` | `0` | Production must set to `0` or leave unset. |
| `GOAT_TEST_USER_ID` | empty | Never configure in Cloud Run. |
| `GOAT_AI_ENABLED` | `0` (example) / `1` (prod) | Explicitly set per env. |

---

## Manual QA checklist

Run through this on a real Supabase project + deployed Cloud Run before
enabling Goat Mode for new user waves.

### Non-entitled user
- [ ] Log in as a user with `profiles.goat_mode = false`.
- [ ] Open Goat Mode from the header — the rollout card appears.
- [ ] Devtools shows no network calls to `goat_mode_jobs`, `goat_mode_snapshots`, `goat_mode_recommendations`, or `goat-mode-trigger`.
- [ ] Attempting a direct REST insert into `goat_goals` (with the user JWT) via curl fails with 403 / RLS violation.
- [ ] Toggle `profiles.goat_mode = true` in Supabase → refresh → the first-run state renders.

### Entitled user — happy path
- [ ] "Run my first analysis" triggers a job, readiness strip progresses, recommendations land.
- [ ] Setup forms (inputs / goal / obligation) save successfully.
- [ ] Dismiss / Snooze / Resolve on a recommendation updates immediately and persists after reload.
- [ ] Pull-to-refresh works on both the main screen and the setup screen.

### Entitled user — edge cases
- [ ] Force a backend 500 (stop Cloud Run) and confirm the error banner appears with a retry CTA.
- [ ] Cold-start a new user (no transactions) and confirm the readiness strip is calm and the missing-input card lists the right items.

### Backend / infra
- [ ] `GET /health` reports `shared_secret_enforced: true` and `shared_secret_required: true` in production.
- [ ] `POST /goat-mode/run-for-user` returns 404 in production.
- [ ] `POST /goat-mode/run` without the shared-secret header returns 401.

### DB policies (one-time)
- [ ] Run `scripts/goat/verify_phase8_entitlement_rls.sql` against the live project and confirm every row in the second SELECT shows `qual_has_entitlement` or `check_has_entitlement = true`.

---

## Secret rotation note

The Edge Function ↔ Backend shared secret (`GOAT_BACKEND_SHARED_SECRET`)
lives in **two** places and must be rotated in lockstep:

1. Supabase function secrets (`supabase secrets set GOAT_BACKEND_SHARED_SECRET=...`).
2. Cloud Run service env (`gcloud run services update ... --update-env-vars`, or Secret Manager).

To rotate:

1. Generate a new value: `openssl rand -hex 48`.
2. Update Cloud Run first (it will accept both during rollout only if you
   run a transient dual-secret build; for simplicity just accept a brief
   window of failed triggers while #3 catches up).
3. Update Supabase function secret.
4. Verify with one `/goat-mode-trigger` call from a signed-in user.

Rotate the Supabase service-role key and Gemini API key on their own
cadences — they are independent of the shared secret.

---

## Rollback guidance

### Rolling back the Phase 8 RLS change

If the new RLS policies cause an unexpected regression for entitled users:

```sql
-- Minimal rollback: revert the write-path policies to user-scope only.
drop policy if exists goat_user_inputs_insert on public.goat_user_inputs;
create policy goat_user_inputs_insert on public.goat_user_inputs
  for insert with check (auth.uid() = user_id);

-- Repeat for update/delete on goat_user_inputs, goat_goals, goat_obligations,
-- goat_mode_jobs (insert), and goat_mode_recommendations (update).
-- The helper function `public.goat_mode_enabled_for` can stay — it's unused
-- once the policies drop it.
```

A reverse migration can be added if needed; intentionally not included here
so we don't ship a rollback that's easy to apply by accident.

### Rolling back the Flutter entitlement changes

The screen-level fallbacks and "skip reads when not entitled" change are
pure optimizations — reverting them is safe but unnecessary. Just redeploy
the previous web build (`vercel rollback`) or revert the commit.

### Rolling back the dev-endpoint posture

If a local workflow truly needs `/goat-mode/run-for-user`, set
`GOAT_ALLOW_DEV_ENDPOINTS=1` in the local `.env`. Do **not** revert the
default in `.env.example`.

---

## Known remaining caveats

- **SELECT RLS is not entitlement-scoped** on any Goat table. This is
  deliberate (see nuance above). If the product ever requires "hide all
  Goat data from de-entitled users," extend the same `goat_mode_enabled_for`
  predicate to the SELECT policies in a follow-up migration.
- The backend still behaves as "local-dev mode" when `GOAT_BACKEND_SHARED_SECRET` is unset. In production `GOAT_REQUIRE_SHARED_SECRET=1`
  turns that into fail-closed 503 — make sure the Cloud Run env sets both.
- The Edge Function fetches `profiles.goat_mode` using the caller's JWT, so
  an outage or RLS-breaking change on `profiles` would surface as the Edge
  Function treating the user as *entitled* (it only blocks on an explicit
  `goat_mode !== true`, not on a missing row). The DB-level write gate
  catches this belt-and-suspenders via `goat_mode_enabled_for`.
- Recommendation actions surface a generic "Couldn't update this
  recommendation — try again." on failure. The RLS denial code path is
  included here; if we ever want to distinguish "not entitled anymore" from
  "transient error" we'd need a dedicated 403 handler.

---

## Light telemetry added

- Backend: `log.warning(...)` on every hit to `/goat-mode/run-for-user` so
  any accidental production enablement is immediately visible in Cloud Run
  logs.
- Edge Function: `console.warn(...)` on caller-supplied `user_id`
  impersonation attempts and `console.error(...)` on profile-lookup failure
  (pre-existing, preserved).
- Flutter: `debugPrint('[GOAT] ...')` for profile / goat_mode reads and
  recommendation action failures (pre-existing, preserved).

No full analytics pipeline was added in this phase.
