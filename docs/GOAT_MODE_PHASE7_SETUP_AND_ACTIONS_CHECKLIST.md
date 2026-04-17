# Goat Mode — Phase 7: Setup + Recommendation Actions

**Status:** ✅ shipped on master
**Scope:** Close the product loop. Let users add/edit the Goat inputs, goals, and obligations
that power the analysis, and act on recommendations (dismiss / snooze / resolve) — all without
changing the analytics contract, compute pipeline, or global navigation shipped in Phases 1–6.
**Pre-reqs met:** Phase 6 (Flutter binding + first live surface) in place and working on device.

Phase 7 is the first version of Goat Mode that can be used repeatedly on a real account.
Until now, users could trigger a run and read the output; they couldn’t correct the inputs,
answer a missing-input prompt, or remove a stale recommendation. Phase 7 ships all three.

> **Design note.** Everything here is presentation-first. No new backend tables. No new
> Edge Functions. No change to recommendation dedupe / compute. We only use write paths
> that already pass RLS for the signed-in user.

---

## 1. Product loop we unlocked

Before Phase 7:
1. User opens Goat Mode.
2. Sees a snapshot + recommendations.
3. …can’t do anything with them except close the tab.

After Phase 7:
1. User opens Goat Mode.
2. Sees a snapshot + recommendations **and a visible “Your setup” card** showing what is set.
3. Taps “Improve this analysis” (or a missing-input prompt, or the setup card) → the right
   form sheet opens focused on that field. Saves locally scoped to their account.
4. Taps a recommendation’s **⋯** (or long-presses it) → dismiss, snooze 24h / 3d / 7d, or
   mark resolved. The recommendation disappears optimistically with rollback on error.
5. Opens the **Your setup** screen from the card → hub for inputs, goals, obligations, plus a
   single “Refresh analysis” CTA to rerun Goat Mode when ready.
6. Next run is measurably better because inputs improved.

---

## 2. Repo-aware write-path audit (step A)

We audited every write before coding anything. Audit lives alongside Phase-1 migration.

| Table | RLS in place? | Write path chosen | Why |
|---|---|---|---|
| `goat_user_inputs` | `SELECT/INSERT/UPDATE/DELETE WHERE auth.uid() = user_id` | **Direct client upsert** on `user_id` PK | One row per user; `upsert(onConflict: 'user_id')` is race-safe and simpler than a dedicated RPC. |
| `goat_goals` | Same full CRUD RLS | **Direct client insert/update/delete** scoped `.eq('user_id', uid)` | User-owned rows with no cross-user invariants. |
| `goat_obligations` | Same full CRUD RLS | **Direct client insert/update/delete** scoped `.eq('user_id', uid)` | Same as above. |
| `goat_mode_recommendations` | `SELECT + UPDATE WHERE auth.uid() = user_id` (INSERT/DELETE are backend-only) | **Direct client UPDATE** of `status` + `snoozed_until` only | Mirrors what the backend expects; dedupe invariants stay intact because the partial unique index is `(user_id, rec_fingerprint) WHERE status = 'open'` — moving a row out of `open` frees the fingerprint for the next compute pass. |

**Edge cases we confirmed:**
- `GoatSetupService` always injects `user_id` from `Supabase.instance.client.auth.currentUser?.id`.
  The client never trusts a `user_id` from a payload.
- `updated_at` is set server-locally (`DateTime.now().toUtc().toIso8601String()`); the tables
  do not rely on a DB trigger.
- Dismiss / snooze set `status` → `'dismissed'` / `'snoozed'`; `snoozed_until` is cleared on
  dismiss and on resolve. Moving a row back to `'open'` is **never** a client op.

**We did not need an Edge Function or an RPC for Phase 7.** All four write paths are safe
directly from the client under existing RLS.

---

## 3. New / modified Flutter files

**New**

| Path | Purpose |
|---|---|
| `lib/features/goat/models/goat_setup_models.dart` | Write-side view-models (`GoatUserInputs`, `GoatGoal`, `GoatObligation`) + enums (`GoatPayFrequency`, `GoatRiskTolerance`, `GoatTonePreference`, `GoatGoalType`, `GoatGoalStatus`, `GoatObligationType`, `GoatObligationCadence`, `GoatObligationStatus`). Enum wire tokens pinned to DB `check` constraints. `toInsert/Upsert/UpdatePayload` only emits non-null fields so PATCH-style saves never clobber server values. |
| `lib/features/goat/services/goat_setup_service.dart` | Supabase write binding for setup tables + recommendation lifecycle updates. Everything is user-scoped via RLS. Errors flow back as `GoatModeException` or raw Postgres errors. |
| `lib/features/goat/providers/goat_setup_providers.dart` | `AsyncNotifier` controllers: `GoatUserInputsController` (upsert), `GoatGoalsController` / `GoatObligationsController` (CRUD). Plus `GoatRecommendationActions` — a small helper that applies optimistic list updates on `goatModeControllerProvider` and rolls back on failure. |
| `lib/features/goat/widgets/goat_form_primitives.dart` | Reusable form atoms: `GoatSheetScaffold`, `GoatLabeledField`, `GoatChipPicker<T>`, `GoatDatePickerField`, `GoatPrimaryButton`, `GoatFormSectionHeader`. Shared validators: `goatValidateRequiredText`, `goatValidatePositiveAmount`, `goatValidateNonNegativeAmount`, `goatValidateIntRange`. |
| `lib/features/goat/widgets/goat_user_inputs_sheet.dart` | Bottom sheet for `goat_user_inputs`. Split into three compact sections — Income / Safety net / Preferences. Every field is optional. Supports `focusedKey` for contextual handoff from a missing-input prompt. |
| `lib/features/goat/widgets/goat_goal_sheet.dart` | Bottom sheet to create/edit a goal. Priority slider, date picker, status chip (edit only), and a guarded “Remove goal” action. |
| `lib/features/goat/widgets/goat_obligation_sheet.dart` | Bottom sheet to create/edit an obligation. Cadence + status chips, monthly / outstanding / interest fields, lender name. |
| `lib/features/goat/widgets/goat_rec_action_sheet.dart` | Sheet exposing **Dismiss / Snooze / Resolve** for a recommendation. Snooze opens a nested mini-sheet with **24h / 3 days / 7 days** presets. Uses `GoatRecommendationActions`. |
| `lib/features/goat/widgets/goat_setup_summary_card.dart` | Card on the main Goat Mode screen summarising `N of 5` core inputs + goal/obligation counts, with a calm CTA to the setup hub. |
| `lib/features/goat/screens/goat_setup_screen.dart` | “Your setup” hub. Inputs tile, Goals + Obligations sections, pull-to-refresh, and a sticky `_RerunBanner` that calls `goatModeControllerProvider.refresh()`. |
| `test/goat_setup_models_test.dart` | Pure-Dart tests: enum wire round-trips, payload shape, row parsing, clamping, `copyWith` semantics. |
| `test/goat_form_validators_test.dart` | Validator coverage: required / positive / non-negative / int-range, including edge cases around `required: false`, blanks, non-numeric, and bounds. |
| `test/goat_setup_screen_widget_test.dart` | Widget tests: empty vs populated setup, inputs tile → user-inputs sheet, goal tile → edit sheet with “Remove”. |

**Modified**

| Path | Change |
|---|---|
| `lib/features/goat/screens/goat_mode_screen.dart` | Wires `GoatSetupSummaryCard`, routes missing-input prompts into the correct setup sheet (by `key`), surfaces `showGoatRecActionSheet` from `GoatRecommendationCard` via `onActions` (⋯ button + long-press), and adds a “Your setup” entry in `_AppBar`. |
| `lib/features/goat/widgets/goat_recommendation_card.dart` | New optional `onActions` callback. Exposes a ⋯ icon and long-press on the card; both open the lifecycle sheet. |
| `lib/features/goat/providers/goat_mode_providers.dart` | Added `GoatModeController.setStateForActions(next)` so `GoatRecommendationActions` can apply optimistic updates + rollback without subclassing. Not a test-only hook. |
| `lib/features/goat/widgets/goat_readiness_strip.dart` | Tiny fix: replaced unused-parameter warning `(_, v, __)` → `(_, v, _)`. |
| `test/goat_mode_screen_widget_test.dart` | Stubbed the three new setup controllers in `_host`, added scroll-to-visible fixes for tests that relied on the pre-card layout, and updated the missing-input handoff assertion (we now open the real form, not the explanatory stub). |

---

## 4. Setup / edit UX strategy (step B)

We **did not** ship an onboarding wall. Phase 7’s UX is deliberately incremental and contextual:

- **Start from what’s already visible.** The Goat Mode screen now carries a `GoatSetupSummaryCard`
  above the “Top of mind” section. It shows coverage (`N of 5` core fields, goals, obligations)
  and a single CTA. It never nags, never blocks.
- **Missing-input prompts route to forms, not explanations.** In Phase 6 each `GoatMissingInputCard`
  opened a tiny explanatory bottom sheet with a **Got it** button. In Phase 7 tapping one opens
  the correct sheet, focused where it matters:
  - `monthly_income`, `liquidity_floor`, `emergency_fund_target_months`, `risk_tolerance`,
    `tone_preference`, `pay_frequency`, `planning_horizon_months` → `GoatUserInputsSheet(focusedKey: key)`.
  - keys starting with `goal_` → `GoatGoalSheet` (create).
  - keys starting with `obligation_` → `GoatObligationSheet` (create).
  - Anything else → generic `GoatUserInputsSheet`.
- **“Improve this analysis”.** That phrase is the single thread running through the setup card,
  the user-inputs sheet title, and the rerun banner. It sets the expectation that giving info
  is how the analysis gets better — nothing else.
- **Focused bottom sheets.** Every form is a `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)`.
  `GoatSheetScaffold` adds keyboard padding via `MediaQuery.viewInsets.bottom`, a drag handle,
  a section title, optional subtitle, and a persistent footer (primary CTA + delete action on edit).
- **Explain what fields unlock.** The user-inputs sheet has section headers (“Income / Safety net /
  Preferences”) and a helper under each input. The missing-input cards on the home screen still
  display `unlocks` and `why`.

---

## 5. Flutter forms implementation (step C)

All three sheets use the same pattern:

```
ConsumerStatefulWidget
  GlobalKey<FormState>
  TextEditingControllers for text fields
  plain state (enum / bool / int / DateTime?) for chips / slider / date
  hydrate-once from async provider.whenData(...)
  validator per field → TextFormField / helpers in goat_form_primitives
  _save(): validate → build immutable draft → provider.create/save
  success → Navigator.pop(true) + SnackBar
  failure → setState(_saving=false, _errorMsg=…)
```

**User inputs sheet (`goat_user_inputs`).** Monthly income (₹ prefix), pay frequency (chips),
salary day (1–31), emergency fund target (months suffix), liquidity floor (₹), household size,
dependents, risk tolerance (chips + helper), planning horizon months (1–60), tone preference
(chips + helper). All fields optional. Supports `focusedKey` to autofocus the right input.

**Goal sheet (`goat_goals`).** Goal type (chips), title (required, max 60), target amount
(> 0), saved so far (≥ 0), target date (optional), priority (slider, 1–5 with label), status
(chips, edit-only), delete confirmation dialog on edit.

**Obligation sheet (`goat_obligations`).** Type (chips), lender name (optional), current
outstanding (≥ 0), monthly due (≥ 0), due day (1–31), interest rate (≥ 0, max 100), cadence
(chips, default monthly), status (chips, edit-only), delete confirmation dialog on edit.

Input formatting is liberal on the way in, strict on the way out:
- Amount fields: `FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))`, parsed with
  `double.tryParse` after stripping commas.
- Integer fields: `FilteringTextInputFormatter.digitsOnly`, parsed with `int.tryParse`.

---

## 6. Supabase write implementation (step D)

File: `lib/features/goat/services/goat_setup_service.dart`.

- `fetchUserInputs()` → single row by `user_id`, returns `GoatUserInputs.empty` if none yet.
- `upsertUserInputs(value)` → `.upsert(payload, onConflict: 'user_id').select().single()`.
  Only sends fields that are non-null (PATCH-style).
- `fetchGoals({includeInactive})` / `createGoal` / `updateGoal` / `deleteGoal` →
  `eq('user_id', uid)` on every filter. Updates and deletes also `.eq('id', id)`.
- `fetchObligations({includeInactive})` / `createObligation` / `updateObligation` /
  `deleteObligation` → same pattern.
- `dismissRecommendation(recId)` → `UPDATE goat_mode_recommendations SET status='dismissed',
  snoozed_until=null, updated_at=now() WHERE id=? AND user_id=?`.
- `snoozeRecommendation(recId, duration:)` → sets `status='snoozed'` and
  `snoozed_until = (now + duration).toUtc().toIso8601String()`.
- `resolveRecommendation(recId)` → `status='resolved'`.

Sign-out states throw `GoatModeException('Sign in to …', status: 401)` instead of sending
anonymous requests.

---

## 7. Recommendation actions (step E)

`GoatRecommendationActions` (in `goat_setup_providers.dart`) wraps each server call in
`_optimistic(recId, serverAction)`:

1. Read the current `GoatModeState` from `goatModeControllerProvider`.
2. Immediately emit a new state with the rec filtered out (`setStateForActions`). No
   `AsyncLoading` flash.
3. Await the server call.
4. On error, roll back to the pre-action state but carry an `errorMessage` on the state so the
   screen can surface a non-destructive banner. Rethrow so callers can also react.

`GoatRecommendationCard`’s new `onActions` callback drives the UI. The card exposes two
equivalent triggers:
- `InkResponse` with `Icons.more_horiz_rounded`, `Semantics(label: 'More actions')`.
- `InkWell.onLongPress` on the card.

`showGoatRecActionSheet(context, rec)` shows three `_ActionTile`s: **Dismiss**, **Snooze**,
**Mark resolved**. Snooze opens a nested sheet with `_SnoozePicker` presets (24h / 3d / 7d).
Each success shows a short `SnackBar`. Dedupe is untouched — we only move rows between
`open → dismissed / snoozed / resolved` which all free the `rec_fingerprint` partial-unique
slot for the next run.

---

## 8. UI / UX polish pass (step F)

- **Typography.** All screens lean on `BillyTheme` tokens (`emerald600`, `gray100`, `gray800`,
  `red500`, etc.). No raw `#HEX` colors outside the theme file.
- **Motion.** 180 ms `AnimatedContainer` on chip selection. 500 ms `TweenAnimationBuilder` on
  the inputs-card progress bar. No pulsing, no bouncy physics. `AnimatedSwitcher` on the
  primary button for spinner-vs-label.
- **Empty / loading / partial / success states.**
  - Empty: `_EmptyCard` with a leading icon, a title, a one-sentence body, and a filled CTA.
  - Loading (first fetch only): `_LoadingCard` with a 16×16 emerald spinner.
  - Partial (already in Phase 6): honored — Phase 7 never hides the partial stripe.
  - Success: floating `SnackBar` ("Goal added", "Setup saved", "Obligation updated", "Goal removed").
- **Perceived quality.** The Goat Mode screen reuses the existing hero + readiness + scope
  switcher. The setup card is the only new element and it’s additive, not intrusive.

---

## 9. Accessibility / usability hardening (step G)

- **Text scaling.** Every large string uses `fontSize` tokens in the 11.5–18 range; no fixed
  heights that would clip with `textScaleFactor > 1.0`.
- **Overflow.** All long strings use `maxLines + TextOverflow.ellipsis` where relevant
  (goal title, obligation lender, rec summary already had this from Phase 6).
- **Keyboard avoidance.** `GoatSheetScaffold` wraps content in a `SafeArea(top:false)` + a
  `Padding` using `MediaQuery.viewInsets.bottom`; content scrolls inside a `Flexible +
  SingleChildScrollView`. Bottom sheets are `isScrollControlled: true` + `useSafeArea: true`.
- **Tap targets.** `TextButton` / `FilledButton` minimum size ≥ 32×32. Chip picker items have
  14×9 padding + hit area via `InkWell`. The recommendation card’s new ⋯ button uses a 36×36
  `InkResponse` with visible focus ring.
- **Screen readers.**
  - ⋯ button: `Semantics(label: 'More actions', button: true)`.
  - Snooze / dismiss / resolve tiles: `Semantics` label equals the action label.
  - All form fields rely on the default `TextFormField` semantics (label read via
    `decoration.hintText`) and the leading `_FieldLabel` text which is reachable in order.
- **Reduced motion.** The only non-trivial animations are 180 ms chip transitions and a
  500 ms progress tween; they’re short and don’t flash. We deliberately avoided infinite or
  oscillating animations on setup surfaces.
- **Color contrast.** Primary: `emerald600` on white (> 4.5:1). Error: `red500` on white.
  Disabled primary: `emerald100` with white text — used only while saving, which is
  transient.

---

## 10. Refresh / state integration after edits (step H)

Rule we followed: **don’t auto-rerun compute.** Compute has a cost, and forcing a rerun after
every field edit would spam the pipeline and make the UI feel unpredictable. Instead:

- Setup controllers optimistically update their local list / map after every write so the UI
  reflects the change before Supabase round-trips back.
- `GoatSetupScreen` has a sticky `_RerunBanner` (“Refresh analysis when ready”) bound to
  `goatModeControllerProvider.refresh()`. Disabled while `isRefreshing == true`.
- `GoatModeScreen`’s existing hero refresh button still works and is now the primary trigger.
- `GoatSetupScreen._postSetupSave(ref)` is deliberately a no-op hook, reserved for future
  telemetry (e.g. nudging the rerun banner once `N ≥ 3` fields changed).

---

## 11. Tests / validation (step I)

Ran `flutter test` — **96 tests pass**, including:

- `test/goat_setup_models_test.dart` — 19 tests. Enum wire round-trips, payload shape (PATCH
  omission rules), `filledCoreCount` weighting, `hasAnyValue`, date serialization, `copyWith`
  semantics, unknown-enum fallbacks.
- `test/goat_form_validators_test.dart` — 17 tests. Required / positive / non-negative /
  int-range, including `required: false`, blank handling, non-numeric, max bounds, decimals,
  and boundary integers.
- `test/goat_setup_screen_widget_test.dart` — 4 widget tests. Empty state (inputs tile + both
  empty cards + rerun banner), populated state (goal + obligation tiles with progress +
  counts), inputs tile → user-inputs sheet, goal tile → edit sheet with “Remove goal”.
- `test/goat_mode_screen_widget_test.dart` — all 10 pre-existing Phase 6 screen tests kept
  green. Updates:
  - `_host` now overrides the three new setup controllers with stubs (`_StubUserInputs`,
    `_StubGoals`, `_StubObligations`) so the screen renders without Supabase.
  - Tests that relied on the pre-setup-card layout use `dragUntilVisible` (scoped to the
    vertical `ListView`, since the scope switcher is also a `ListView`) + `ensureVisible`
    before tapping — the new card shifts content down ~110px in the 600px test viewport.
  - The missing-input handoff assertion now expects the real **Save setup** CTA (the Phase 6
    explanatory **Got it** stub has been replaced).

Coverage we deliberately did **not** add:
- `GoatSetupService` network tests. Static methods hit `Supabase.instance.client` directly;
  mocking them cleanly requires a refactor to inject a client. We rely on the model tests
  (payload shape + row parse) + manual QA against a real Supabase for this release.
- `GoatRecommendationActions` optimistic-rollback tests. Same reason — the server leg calls
  the static service. Manual QA steps below cover it.

**Lints.** `flutter analyze` stayed clean for every new file. No new warnings.

---

## 12. Manual QA steps

Run on a real Supabase-connected build (dev or staging) after signing in as a user with
`profiles.goat_mode = true`:

1. **Empty account.**
   1. Install fresh / nuke `goat_user_inputs`, `goat_goals`, `goat_obligations` for the user.
   2. Open Goat Mode → verify the setup summary card shows `0 of 5`, and “Goals · 0 /
      Obligations · 0”. Tap it → `GoatSetupScreen` opens with both empty cards and the
      refresh banner at the bottom.
2. **Save inputs.**
   1. In `GoatSetupScreen` tap the “Your inputs” tile.
   2. Fill monthly income, pay frequency, emergency fund target, risk tolerance, tone.
   3. Save → SnackBar “Setup saved”. Return → counter reads `5 of 5`.
3. **Create a goal.**
   1. In `GoatSetupScreen` tap **Add** next to Goals.
   2. Pick type `Emergency fund`, title “Buffer”, target ₹ 90000, saved ₹ 45000, priority top.
   3. Save → SnackBar “Goal added”, list shows one row with 50% progress.
4. **Edit a goal.**
   1. Tap the goal tile → sheet title is “Edit goal”, **Remove goal** is visible.
   2. Change priority, save → SnackBar “Goal updated”.
   3. Tap **Remove goal** → confirm → SnackBar “Goal removed”, list back to empty.
5. **Create an obligation.**
   1. **Add** next to Obligations → type EMI, lender “Acme Bank”, monthly ₹ 15000, due day 5.
   2. Save → SnackBar “Obligation added”.
6. **Missing-input handoff.**
   1. If the current snapshot has a `monthly_income` missing-input, open Goat Mode.
   2. In **Unlock more** tap “Tell us your monthly income” → user-inputs sheet opens with
      the income field focused.
7. **Dismiss a recommendation.**
   1. Long-press a recommendation card, or tap ⋯.
   2. Choose **Dismiss** → card disappears immediately; SnackBar confirms.
   3. Pull-to-refresh or reopen → the card does not return for the current fingerprint.
8. **Snooze a recommendation.**
   1. Open the actions sheet → **Snooze** → **3 days**.
   2. Card disappears; next run or refetch should keep it hidden until `snoozed_until`.
9. **Resolve.**
   1. Actions sheet → **Mark resolved** → SnackBar.
10. **Rerun after edits.**
    1. From `GoatSetupScreen` tap **Refresh**.
    2. Verify the home screen picks up the new snapshot with changed metrics / recs.
11. **Accessibility smoke.**
    1. Bump device text size to 200%. Open each sheet. No clipped content, no locked-off CTAs.
    2. Enable TalkBack / VoiceOver. Swipe the actions sheet — Dismiss / Snooze / Mark resolved
       each read their full label.
12. **Sign-out safety.**
    1. Sign out mid-session. Attempt a setup save → we catch the 401 and surface the inline
      error message in the sheet footer; no crash.

---

## 13. Known non-goals / deliberately out of scope

- No auto-rerun of Goat Mode after a setup save. Explicit rerun only.
- No multi-step onboarding. Setup is always contextual, one sheet at a time.
- No undo for dismiss / snooze (v1). The backend regenerates the recommendation on the next
  run if still relevant; the partial-unique-on-`open` index makes that safe.
- No schema changes, no new Edge Functions. All reads/writes already existed behind RLS.
- No changes to global navigation. Setup is reached from the Goat Mode screen only.

---

## 14. Next steps (post-Phase 7 ideas)

- Surface a subtle nudge on the rerun banner once `filledCoreCount` increases since the last
  snapshot (“3 new fields since your last run”).
- Add a tiny “why this unlocks” tooltip per input in `GoatUserInputsSheet`.
- Extend `GoatRecommendationActions` with “undo snooze” for the last action in the current
  session (client-only, no server state change required).
- Consider generated analytics events (`goat_setup_opened`, `goat_input_saved`,
  `goat_rec_dismissed`) for funnel analysis once telemetry lands.
