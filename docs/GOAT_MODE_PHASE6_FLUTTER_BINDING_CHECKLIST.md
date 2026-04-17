# Goat Mode — Phase 6: Flutter binding + first live UI

**Status:** ✅ shipped on master
**Scope:** Flutter binding + polling/status + first live Goat surface + UI/UX + motion pass.
**Pre-reqs met:** Phases 0–5 complete (schema, compute, forecast/anomaly/risk, AI layer, Edge Function + Cloud Run).

Phase 6 turns the approved remote orchestration path into the first live Goat Mode
experience inside Billy. Flutter now triggers the Supabase Edge Function, polls the
job row, and reads snapshot + recommendation rows. No analytics logic runs on the
client. No direct Cloud Run calls from the client.

---

## 1. Architecture (one page)

```
                                  ┌─────────────────────────────────────┐
                                  │          Supabase (Postgres)        │
                                  │ ┌─────────────┐  ┌────────────────┐ │
                                  │ │ goat_mode_* │  │ goat_mode_snap │ │
                                  │ │   _jobs     │  │    _shots      │ │
                                  │ └─────────────┘  └────────────────┘ │
                                  │ ┌─────────────────────────────────┐ │
                                  │ │ goat_mode_recommendations (RLS) │ │
                                  │ └─────────────────────────────────┘ │
                                  └────────────┬────────────────────────┘
                                               ▲
                                               │ RLS-scoped reads
                                               │
┌───────────────────────┐   1. invoke            │   4. poll jobs.id
│  Flutter (Billy app)  │────────────▶ ┌────────────────────────┐
│                       │              │  goat-mode-trigger     │
│  GoatModeController   │◀──────────── │  (Supabase Edge Fn)    │
│  (Riverpod Notifier)  │   2. job_id  └───────────┬────────────┘
│                       │                          │ 3. dispatch (+ shared secret)
│  GoatModeService      │                          ▼
│  (Supabase binding)   │              ┌────────────────────────┐
└───────────────────────┘              │ Cloud Run backend      │
                                       │ (writes with service_  │
                                       │  role key, bypass RLS) │
                                       └────────────────────────┘
```

Flutter never reaches Cloud Run directly. Flutter never computes analytics.

---

## 2. New / modified Flutter files

**New**

| Path | Purpose |
|---|---|
| `lib/features/goat/models/goat_models.dart` | View-models (`GoatJob`, `GoatSnapshot`, `GoatRecommendation`, `GoatAIView`, `GoatScope`, …). Row → model parsers are null-safe and enum-fallback-safe. |
| `lib/features/goat/services/goat_mode_service.dart` | Thin Supabase binding. Invokes the Edge Function (`goat-mode-trigger`) + reads `goat_mode_jobs` / `goat_mode_snapshots` / `goat_mode_recommendations`. Mirrors the hosted-web / `functions.invoke` split used by `AnalyticsInsightsService`. |
| `lib/features/goat/providers/goat_mode_providers.dart` | `GoatModeController` (`AsyncNotifier<GoatModeState>`) — owns refresh + polling lifecycle. Also `goatSelectedScopeProvider` (UI scope chip) and `goatModeEntitlementProvider` (derived from `profiles.goat_mode`). |
| `lib/features/goat/screens/goat_mode_screen.dart` | First live Goat Mode screen. Replaces the placeholder. |
| `lib/features/goat/widgets/goat_hero_card.dart` | Hero — narrative, status chip, refresh action, freshness label. |
| `lib/features/goat/widgets/goat_status_chip.dart` | Calm animated status pill (queued / running / succeeded / partial / failed / stale). |
| `lib/features/goat/widgets/goat_readiness_strip.dart` | Coverage/readiness summary with animated progress bar. |
| `lib/features/goat/widgets/goat_scope_switcher.dart` | Horizontal scope chips (overview / cashflow / budgets / recurring / debt / goals). |
| `lib/features/goat/widgets/goat_scope_detail.dart` | Per-scope top-N metric rows + "See all" bottom sheet. |
| `lib/features/goat/widgets/goat_recommendation_card.dart` | Expandable recommendation card with AI phrasing fallback. |
| `lib/features/goat/widgets/goat_missing_input_card.dart` | Unlock-framed missing-input prompt with sheet handoff. |
| `lib/features/goat/widgets/goat_ai_summary_card.dart` | Ambient AI narrative card (only renders if validated & non-empty). |
| `lib/features/goat/widgets/goat_empty_state.dart` | First-run invite + not-entitled state. |
| `lib/features/goat/widgets/goat_error_banner.dart` | Soft recoverable error banner with retry/dismiss. |
| `lib/features/goat/widgets/goat_skeleton.dart` | Dependency-free shimmer block (mirrors `billy_header._GoatModeButton` gradient sweep). |
| `test/goat_models_test.dart` | Row parser coverage (14 cases). |
| `test/goat_mode_state_test.dart` | `GoatModeState` immutability + copyWith semantics (5 cases). |
| `test/goat_mode_screen_widget_test.dart` | Widget smoke tests across 10 states. |

**Modified**

| Path | Change |
|---|---|
| `lib/app/layout_shell.dart` | Swaps `GoatModePlaceholderScreen` import + push target for `GoatModeScreen`. No navigation structure change. |

**Deleted**

| Path |
|---|
| `lib/features/goat/goat_mode_placeholder_screen.dart` |

---

## 3. Data flow

### 3.1 Trigger
`GoatModeService.triggerRefresh(scope, rangeStart?, rangeEnd?, dryRun?)`:
- mobile / localhost-web → `client.functions.invoke('goat-mode-trigger', body)`
- hosted web (Vercel) → `POST ${origin}/api/goat-mode-trigger` with `Authorization: Bearer <access_token>` + `apikey: <anon>`

`user_id` is **never** sent from the client — the Edge Function derives it from the JWT.
`scope` defaults to `full` so every trigger produces a merged snapshot covering every pillar
(the UI's own scope chip only re-renders from this single snapshot; it does not re-trigger).

### 3.2 Reads (RLS-scoped)
| Row | Table | Select |
|---|---|---|
| latest job | `goat_mode_jobs` | `order(created_at desc) limit 1` |
| job by id | `goat_mode_jobs` | `eq(id, <job_id>)` |
| latest snapshot | `goat_mode_snapshots` | `eq(scope, 'full') order(generated_at desc) limit 1` |
| open recommendations | `goat_mode_recommendations` | `eq(status, 'open') order(priority desc, created_at desc) limit 20` |

RLS scopes every select to `auth.uid() = user_id`, so the client cannot leak.

### 3.3 Polling

Implemented in `GoatModeController._pollJob`:
- **initial delay:** 600 ms (feels snappy for quick-finish jobs)
- **interval:** 2 s
- **max total:** 120 s, then surface a soft "taking longer than usual" state + retry CTA

The loop:
1. `GoatModeService.fetchJobById(jobId)`
2. update `state.latestJob` every tick so the chip animates
3. when `job.status.isTerminal` → re-read snapshot + recs once, clear `isRefreshing`
4. if `failed` → surface the backend `error_message` (if any) in the error banner
5. on timeout → keep the current snapshot, flag `pollingTimedOut`, offer retry

Safety:
- every loop checks a `_refreshGen` counter; any new refresh invalidates stale loops
- `ref.onDispose` cancels the timer when the screen is popped

### 3.4 Scope chip behaviour
Scope chips are UI-only — `goatSelectedScopeProvider` just re-renders `GoatScopeDetailCard`
against the same snapshot. Switching scope is instant and does not hit Supabase.

---

## 4. UI / UX intent

### Layout order (top → bottom)
1. **Hero** — 3-second answer. Narrative line + status chip + refresh action.
2. **Readiness strip** — how deep the analysis is right now (coverage_score + readiness level).
3. **Error banner** (only if present).
4. **Partial stripe** (only if `snapshot_status = partial`).
5. **AI narrative card** (only if `ai_validated = true` AND envelope has content).
6. **Top of mind** — top 3 recommendations; rest behind a "See all" bottom sheet.
7. **Unlock more** — up to 2 highest-value missing inputs.
8. **Explore by pillar** — scope chips + scope detail card.

### Design principles honoured
- **Summary-first:** the first screenful is narrative + status + readiness, not a dashboard dump.
- **Progressive disclosure:** recommendation bodies cap at 2 lines; expand to show *Why this matters*.
- **Calm semantics:** even `failed` is soft red + recoverable CTA. No dead ends.
- **Grounded AI:** AI phrasing is keyed by `rec_fingerprint` and overlays deterministic recommendations. If AI is missing/invalidated, deterministic copy shows — the user never sees "fake mode" / validator state.
- **Never blank:** while refreshing, the old snapshot stays on screen; the hero chip softly pulses instead.
- **Never scary:** partial / missing-input / empty states are framed as "getting better" unlocks, not setup errors.

### Readability ladder
- **3-second scan:** status pill + one hero sentence answer "am I okay?"
- **10-second scan:** readiness strip + titles of top recs
- **Deeper read:** tap any rec to reveal its *Why this matters* block grounded in `observation_json`

### Copy system
- section headers: *Top of mind*, *Unlock more*, *Explore by pillar*, *What this means*
- card secondaries: *Why this matters*, *Unlocks*
- status chip: *Up to date*, *Analyzing…*, *Starting…*, *Partial*, *Failed*, *Stale*

No jargon in default surface. Raw `reason_codes`, `rec_fingerprint`, AI `mode` /
`validator` state never reach the user.

---

## 5. Motion pass

| Element | Motion | Duration | Intent |
|---|---|---|---|
| Status chip | `AnimatedContainer` colour + pulsing dot | 220 ms | Confirm state transition |
| Hero narrative line | `AnimatedSwitcher` keyed on text | 260 ms | Smooth handoff when AI/deterministic copy swaps |
| Readiness progress | `TweenAnimationBuilder` on value | 650 ms ease-out-cubic | Feels like filling up, not snapping |
| Recommendation expand | `AnimatedSize` + `AnimatedRotation` on chevron | 220 ms | Reveal reasoning without jank |
| Scope detail swap | `AnimatedSwitcher` + `SizeTransition + FadeTransition` | 240 ms | Guide eye without shuffling the whole screen |
| Scope chip selection | `AnimatedContainer` colour/border | 220 ms | Confirms tap |
| Refresh button | `AnimatedContainer` opacity | 220 ms | Signals "waiting for backend" without flicker |
| Loading state | Gradient-sweep shimmer box | 1400 ms loop | Premium placeholder without a shimmer dep |
| Body → live | Outer `AnimatedSwitcher` between loading / error / data / empty | 280 ms | Emotional continuity across state changes |

All durations are crisp, not slow. Nothing is decorative — every motion confirms
a state change, reveals new info, or softens a transition.

Accessibility: the app does not yet expose a reduced-motion flag; once one is
introduced (system-wide), the shimmer + pulsing dot are the only loop animations
that would need to be suppressed.

---

## 6. State matrix

| State | Trigger | UI |
|---|---|---|
| **Not entitled** | `profiles.goat_mode != true` | Calm "rolling out" card. No refresh. |
| **First run** | no snapshot, no job | First-run CTA card ("Run my first analysis"). |
| **Loading** | `AsyncLoading` during initial build | Shimmer skeleton. |
| **Refreshing w/ snapshot** | old snapshot present, new run in flight | Hero chip pulses; screen stays live. |
| **Refreshing no snapshot** | first-run in flight | CTA button spinner; other sections hidden. |
| **Completed** | `job.status = succeeded` | Snapshot + recs fully rendered. |
| **Partial** | `snapshot_status = partial` | Soft amber *partial read* stripe + whatever metrics exist. |
| **Failed** | `job.status = failed` | Snapshot preserved if any, error banner with retry. |
| **Polling timeout** | >120 s | Error banner "taking longer than usual", retry CTA. Snapshot preserved. |
| **Empty pillar** | `metrics_json[scope]` empty | "Not enough for X yet — add a bit more data." |

---

## 7. Test / QA

### Automated (56 total; 29 new in Phase 6)

```
$ flutter test
… All tests passed!
```

New:
- `test/goat_models_test.dart` — 14 row-parser cases (scope/status/readiness/job/snapshot/rec/AI envelope)
- `test/goat_mode_state_test.dart` — 5 immutability / copyWith cases
- `test/goat_mode_screen_widget_test.dart` — 10 widget smoke tests (first-run, live surface, recommendations list + expand, missing-input + sheet, scope switch, partial stripe, error state, not-entitled)

### Manual QA (real signed-in user against production)

Pre-flight:
- [ ] User's `profiles.goat_mode = true` in Supabase
- [ ] Cloud Run service healthy: `curl https://billy-ai-eq3uykqo2q-el.a.run.app/health`
- [ ] Supabase Edge Function secret `GOAT_BACKEND_URL` points to Cloud Run
- [ ] Supabase Edge Function deployed with `--no-verify-jwt` (known constraint — asymmetric JWTs, function internally calls `auth.getUser()`)

Happy path:
1. Sign in → tap GOAT button in header → first-run card appears
2. Tap "Run my first analysis" → chip shows *Starting…* then *Analyzing…*
3. Within ~60 s, hero flips to *Up to date*, readiness strip animates to real coverage
4. Top of mind renders 1–3 recommendations; tap one → *Why this matters* expands
5. Switch scope to Cashflow → detail card swaps with fade+expand
6. Tap "See all" in a 4+ recommendation run → modal with full list scrolls
7. Pull down → reloads from DB without re-triggering a run
8. Tap refresh again with an existing snapshot → old snapshot remains visible while new run is in-flight

Stress:
- [ ] Kill the phone's network mid-run → error banner appears, retry works after re-connecting
- [ ] Trigger twice in quick succession → only the newest run reflects in UI (`_refreshGen` guards)
- [ ] Sign out mid-run → no crash, no lingering timer (verified via `ref.onDispose`)
- [ ] Load a user with sparse data → partial stripe shows, missing-input unlocks render, retry still works

Performance:
- [ ] First-render to snapshot paint ≤ 1 frame after DB read lands
- [ ] Scope swap ≤ 240 ms, no layout jank
- [ ] No timers leak when popping back to the shell (verified with DevTools Timeline)

---

## 8. Intentionally deferred to later phases

| Deferred | Why | Phase |
|---|---|---|
| Editing `goat_user_inputs` / `goat_goals` / `goat_obligations` in-app | Phase 6 only renders the *unlock handoff* bottom sheet. Real editing forms are a meaningful surface of their own. | Phase 7 |
| Recommendation dismiss / snooze | Schema supports it but the backend has no write path yet; status changes would desync. | Phase 7 |
| Background refresh (periodic / push) | v1 is polling-based by spec — much simpler. | Later |
| Supabase Realtime for job progress | Not needed at this polling cadence; would add complexity without a clear user-visible win. | Later |
| Per-pillar deep-dive screens (e.g. anomaly explorer, forecast chart) | Phase 6 caps detail at 4 metrics + bottom-sheet "See all". | Later |
| Reduced-motion handling | App-wide pattern doesn't exist yet. Shimmer + pulsing dot are the only loops to suppress. | When a global a11y pass lands |
| Analytics events / instrumentation | No existing Billy pattern to mirror; adding it here would be a parallel track. | Later |

---

## 9. How it plugs into the broader Goat docs

- [Phase 0 — Approved data model](./GOAT_MODE_PHASE0_DATA_MODEL.md) — `goat_mode_jobs`, `goat_mode_snapshots`, `goat_mode_recommendations` shapes consumed here.
- [Phase 3 — Forecast / anomaly / risk](./GOAT_MODE_PHASE3_LAYERS.md) — populates `forecast_json` / `anomalies_json` / `risk_json` which Phase 6 does not render inline yet (reserved for deep-dive screens).
- [Phase 4 — AI layer](./GOAT_MODE_PHASE4_AI_LAYER.md) — `ai_layer.envelope.recommendation_phrasings` is keyed by `rec_fingerprint` exactly because Phase 6 overlays AI phrasing on top of deterministic recs.
- [Phase 5 — Edge Function + Cloud Run](./GOAT_MODE_PHASE5_EDGE_AND_CLOUDRUN_CHECKLIST.md) — the remote orchestration path Phase 6 binds against; dual validation path (Cloud Run primary) unchanged.
