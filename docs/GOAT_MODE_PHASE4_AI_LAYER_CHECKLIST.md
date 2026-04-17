# Goat Mode — Phase 4: Gemini Explanation / Recommendation Phrasing Layer

Phase 4 adds a **strictly structured, heavily validated Gemini layer** on top of
the already-green deterministic + statistical stack. Gemini is demoted to a
phrasing/coaching role — it explains and wraps, it never decides.

If Gemini is disabled, errors, or fails grounding validation, the runner falls
back to a deterministic envelope with the exact same schema, so downstream
consumers (CLI, future Flutter UI, future Edge Function) don't care which path
produced the output.

---

## New files

| Path | Purpose |
| --- | --- |
| `backend/app/goat/ai/__init__.py` | Re-exports `run_ai_layer` |
| `backend/app/goat/ai/client.py` | Mode resolution + Gemini client wrapper (disabled / fake / real) |
| `backend/app/goat/ai/contracts.py` | _(contracts live in `goat/contracts.py` alongside the other layers — the `ai/contracts.py` split was rejected to avoid a circular import)_ |
| `backend/app/goat/ai/prompts.py` | Scope-aware prompt + input-bundle builder |
| `backend/app/goat/ai/validator.py` | Schema + grounding + numeric + safety checks |
| `backend/app/goat/ai/fallbacks.py` | Deterministic stand-in envelope |
| `backend/app/goat/ai/renderer.py` | Orchestrator — always returns a typed `AILayer` |
| `backend/app/tests/test_ai_layer.py` | 68 tests total, 15 new for AI layer |

## Touched files

| Path | Change |
| --- | --- |
| `backend/app/goat/contracts.py` | Added `GoatAIEnvelopeOut`, `AILayer`, `AIValidationReport`, `AIPillar`, `AIRecommendationPhrasing`, `AIMissingInputPrompt`, `AICoachingNudge`, `AIFollowUpQuestion`; `RunResponse.ai` field. |
| `backend/app/goat/runner.py` | AI layer runs inside `_soft_run` after deterministic recs; snapshot persists full `AILayer` dump + `ai_validated` flag. AI-only errors do **not** degrade `snapshot_status`. |
| `backend/app/goat/cli.py` | `--ai-mode {disabled\|fake\|real}`, `--print-layer` now accepts `ai`, `ai_envelope`, `ai_validation`. |
| `backend/app/goat/versions.py` | `"ai": "0.1.0"` (was `"inactive"`). |
| `backend/app/.env.example` | Documented `GOAT_AI_ENABLED`, `GOAT_AI_FAKE_MODE`, `GOAT_AI_MODEL`. |
| `backend/app/tests/test_risk_and_soft_fail.py` | Updated one persistence assertion to match the new `AILayer.layer_statuses` shape (was `ai_layer.layers`). |

---

## Env vars

| Var | Values | Effect |
| --- | --- | --- |
| `GOAT_AI_ENABLED` | `0` / `1` | Master switch. `0` → deterministic fallback, no Gemini call ever. |
| `GOAT_AI_FAKE_MODE` | `0` / `1` | With `GOAT_AI_ENABLED=1`: bypass network and use a deterministic stand-in envelope. Ideal for CI. |
| `GEMINI_API_KEY` | string | Required for real mode. If missing, `resolve_mode()` degrades to `disabled`. |
| `GOAT_AI_MODEL` | string | Override default `gemini-3-flash-preview`. |

Mode resolution (`ai/client.py::resolve_mode`):

```
GOAT_AI_ENABLED=0                → "disabled"
GOAT_AI_FAKE_MODE=1              → "fake"
no GEMINI_API_KEY                → "disabled"
google-genai not importable      → "disabled"
otherwise                        → "real"
```

---

## What Gemini CAN and CANNOT do

### CAN
- Summarise already-computed outputs into a `narrative_summary`.
- Emit per-pillar `observation` / `inference` pairs with `confidence` + `reason_codes`.
- Wrap **existing deterministic recommendations** with user-friendly phrasing.
- Phrase missing-input prompts.
- Produce short `coaching` nudges and `follow_up_questions`.

### CANNOT (validator will reject)
- Reference a `rec_fingerprint` that is not in the input bundle.
- Reference a `missing_inputs` key that is not in the input bundle.
- Use a pillar `reason_code` that does not exist in any metric / forecast /
  anomaly / risk / missing-input item from the input bundle. (Framework codes
  `readiness:L?` and `scope:*` are always accepted.)
- Include any 3+ digit number that is not in the input bundle JSON
  (prevents invented amounts, dates, counts).
- Give financial advice matching `buy stock *`, `invest in *`,
  `guaranteed returns`, `risk-free`, or tax-section advice.

Anything failing any rule → validator reports it, renderer falls back to
deterministic phrasing, `ai_validated=false`, `fallback_used=true`, and the
errors are preserved on `ai.validation.errors` for audit.

---

## Runner flow (Phase 4)

```
1. create/update goat_mode_jobs → running   (skipped in dry_run)
2. load data
3. compute coverage / missing inputs
4. deterministic analytics        → payload
5. forecast layer (soft-fail)
6. anomaly layer (soft-fail)
7. risk layer (soft-fail)
8. deterministic recommendations  → recs
9. build ai_input_bundle + prompt
10. route to disabled / fake / real client
11. validate raw → envelope OR fallback
12. persist snapshot (ai_layer = AILayer dump, ai_validated = envelope validity)
13. insert recommendations (dedupe unchanged)
14. write job_events
15. mark job succeeded / partial / failed
```

**AI-only failures do not degrade `snapshot_status`**. If an AI call blows up
inside `_soft_run`, `layer_errors["ai"]` is recorded and the snapshot stays
`completed` / `partial` based on the other layers. The deterministic layers
are still the source of truth; Gemini is only the phrasing layer.

---

## Real local test commands

From `backend/app/` with `.venv` activated and `backend/app/.env` populated:

### 1) Deterministic-only (no Gemini call at all)

```powershell
$env:PYTHONIOENCODING="utf-8"
.\.venv\Scripts\python.exe -m goat.cli run `
  --user-id 3d8238ac-97bd-49e5-9ee7-1966447bae7c `
  --scope full --dry-run `
  --ai-mode disabled `
  --print-layer ai --pretty
```

Expect: `mode=disabled`, `fallback_used=true`, `ai_validated=false`,
`reason_codes=["ai_disabled_or_key_missing"]`, full fallback envelope.

### 2) Fake AI (deterministic stand-in, no network)

```powershell
.\.venv\Scripts\python.exe -m goat.cli run `
  --user-id 3d8238ac-97bd-49e5-9ee7-1966447bae7c `
  --scope full --dry-run `
  --ai-mode fake `
  --print-layer ai_envelope --pretty
```

Expect: `mode=fake`, `ai_validated=true`, envelope shape-compatible with real
Gemini output. Ideal for CI.

### 3) Real Gemini (smoke test)

```powershell
.\.venv\Scripts\python.exe -m goat.cli run `
  --user-id 3d8238ac-97bd-49e5-9ee7-1966447bae7c `
  --scope overview --dry-run `
  --ai-mode real `
  --print-layer ai --pretty
```

Outcomes:
- **Happy path** → `mode=real`, `ai_validated=true`, envelope grounded in data.
- **Key expired / quota hit** → `mode=real`, `ai_validated=false`,
  `fallback_used=true`, `reason_codes` contains `gemini_call_failed`
  and the API error summary. Job still completes.
- **Malformed JSON or ungrounded numbers** → `fallback_used=true`,
  `validation.errors` lists the exact rule violated (`ungrounded_digits:*`,
  `rec_fingerprint_not_in_input:*`, `prohibited_advice:*`, …).

### 4) Inspect just the validation report

```powershell
.\.venv\Scripts\python.exe -m goat.cli run `
  --user-id <uuid> --scope full --dry-run `
  --ai-mode real --print-layer ai_validation --pretty
```

### 5) Wet run (persists ai_layer to goat_mode_snapshots)

Remove `--dry-run`. The snapshot will contain:
- `ai_layer` → full `AILayer` dump (version, mode, reason_codes, envelope, validation, layer_statuses)
- `ai_validated` → boolean, matches `ai_layer.ai_validated`

---

## Tests

From `backend/app/`:

```powershell
$env:PYTHONIOENCODING="utf-8"
.\.venv\Scripts\python.exe -m pytest
```

Expected: **68 passed, 2 skipped** (the 2 skipped require
`GOAT_INTEGRATION=1` + a live local Supabase stack + `GOAT_TEST_USER_ID`).

New AI-layer tests cover:
- Mode resolution (disabled / fake / real, missing key edge case).
- Pydantic schema validation (narrative length cap).
- Validator happy path.
- Validator rejects unknown `rec_fingerprint`, unknown `input_key`,
  ungrounded numbers ≥ 3 digits, prohibited-advice patterns.
- Fallback envelope shape (copies missing-input prompts + phrasings).
- Renderer disabled path → fallback.
- Renderer fake path → grounded + validated.
- Renderer real path with simulated malformed JSON → fallback.
- Renderer real path with simulated ungrounded digits → fallback, real errors
  preserved (not overwritten by fallback stub).
- Runner surfaces `AILayer` on the response.
- Runner soft-fails gracefully when `run_ai_layer` itself raises;
  `resp.layer_errors == {"ai"}`, no non-AI error leakage.
- Wet run persists `ai_layer.mode`, `ai_layer.fallback_used`,
  and `ai_layer.envelope` into `goat_mode_snapshots`.

---

## Intentionally NOT implemented in Phase 4

- No Edge Function trigger (still Phase 5).
- No Flutter Goat Mode UI (still Phase 5/6).
- No Cloud Run deployment.
- No Gemini function-calling / tool-calling — the model is a pure
  structured-JSON responder.
- No SHAP / explainer — covered by deterministic `reason_codes`.
- No vector memory / RAG — we explicitly don't want Gemini pulling context
  outside the computed bundle.
- No user-facing streaming — batch JSON only.

## Known blockers before Phase 5

1. **Gemini key lifecycle.** Phase 4 surfaces `gemini_call_failed` reasons
   clearly; before wiring the Edge Function trigger, the key used by the
   server (and its rotation policy) needs to be decided and stored safely.
2. **Flutter render contract.** The `AILayer` shape is stable and typed
   (`GoatAIEnvelopeOut`), but UI-specific display rules (how to group
   pillars, urgency colours, drill-down affordances) still need design
   pass before Phase 5 Flutter work.
3. **Edge Function orchestration.** Phase 5 will move job creation to the
   Edge Function, which means the worker will need to read the same env
   flags (`GOAT_AI_ENABLED`, `GEMINI_API_KEY`) from whatever secrets store
   Supabase uses — the CLI path already validates the shape.
4. **Fake-mode coverage in CI.** Fake mode is production-safe today but we
   have no CI runner yet — this is a Phase 5+ infra task.

## Minimal Phase 3 doc update

No changes to Phase 3 checklist were required. The AI layer lives on top
of the statistical layer and its activation does not change the Phase 3
output shapes — only adds `RunResponse.ai` alongside the existing
`forecast`, `anomalies`, and `risk` blocks.
