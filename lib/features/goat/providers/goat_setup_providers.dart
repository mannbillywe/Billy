import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goat_setup_models.dart';
import '../services/goat_setup_service.dart';
import 'goat_mode_providers.dart';

/// Owns the write-side cache for Goat Mode setup: user inputs, goals,
/// obligations, and recommendation lifecycle actions. Read-only snapshot/
/// job/recs state still lives on [goatModeControllerProvider]; after any
/// setup write that can materially change the snapshot we notify that
/// controller via `refreshOnDemand` so the UI shows the improvement CTA.

// ──────────────────────────────────────────────────────────────────────────
// goat_user_inputs
// ──────────────────────────────────────────────────────────────────────────

class GoatUserInputsController extends AsyncNotifier<GoatUserInputs> {
  @override
  Future<GoatUserInputs> build() async {
    final v = await GoatSetupService.fetchUserInputs();
    return v ?? GoatUserInputs.empty;
  }

  /// Save a merged version of the user inputs and refresh the local cache.
  /// Does not trigger a Goat Mode run — the screen offers that as a separate
  /// explicit CTA after a save (see `goatModeControllerProvider.refresh`).
  Future<GoatUserInputs> save(GoatUserInputs value) async {
    final merged = (state.valueOrNull ?? GoatUserInputs.empty).copyWith(
      monthlyIncome: value.monthlyIncome,
      incomeCurrency: value.incomeCurrency,
      payFrequency: value.payFrequency,
      salaryDay: value.salaryDay,
      emergencyFundTargetMonths: value.emergencyFundTargetMonths,
      liquidityFloor: value.liquidityFloor,
      householdSize: value.householdSize,
      dependents: value.dependents,
      riskTolerance: value.riskTolerance,
      planningHorizonMonths: value.planningHorizonMonths,
      tonePreference: value.tonePreference,
    );
    final saved = await GoatSetupService.upsertUserInputs(merged);
    state = AsyncData(saved);
    return saved;
  }
}

final goatUserInputsControllerProvider =
    AsyncNotifierProvider<GoatUserInputsController, GoatUserInputs>(
  GoatUserInputsController.new,
);

// ──────────────────────────────────────────────────────────────────────────
// goat_goals
// ──────────────────────────────────────────────────────────────────────────

class GoatGoalsController extends AsyncNotifier<List<GoatGoal>> {
  @override
  Future<List<GoatGoal>> build() async {
    return GoatSetupService.fetchGoals(includeInactive: true);
  }

  Future<GoatGoal> create(GoatGoal goal) async {
    final created = await GoatSetupService.createGoal(goal);
    final current = state.valueOrNull ?? const [];
    state = AsyncData([created, ...current]);
    return created;
  }

  Future<GoatGoal> save(GoatGoal goal) async {
    final updated = await GoatSetupService.updateGoal(goal);
    final current = state.valueOrNull ?? const [];
    state = AsyncData([
      for (final g in current)
        if (g.id == updated.id) updated else g
    ]);
    return updated;
  }

  Future<void> delete(String goalId) async {
    await GoatSetupService.deleteGoal(goalId);
    final current = state.valueOrNull ?? const [];
    state = AsyncData(current.where((g) => g.id != goalId).toList());
  }

  Future<void> refreshFromDb() async {
    state = const AsyncLoading<List<GoatGoal>>().copyWithPrevious(state);
    try {
      final v = await GoatSetupService.fetchGoals(includeInactive: true);
      state = AsyncData(v);
    } catch (e, st) {
      state = AsyncError<List<GoatGoal>>(e, st);
    }
  }
}

final goatGoalsControllerProvider =
    AsyncNotifierProvider<GoatGoalsController, List<GoatGoal>>(
  GoatGoalsController.new,
);

// ──────────────────────────────────────────────────────────────────────────
// goat_obligations
// ──────────────────────────────────────────────────────────────────────────

class GoatObligationsController extends AsyncNotifier<List<GoatObligation>> {
  @override
  Future<List<GoatObligation>> build() async {
    return GoatSetupService.fetchObligations(includeInactive: true);
  }

  Future<GoatObligation> create(GoatObligation o) async {
    final created = await GoatSetupService.createObligation(o);
    final current = state.valueOrNull ?? const [];
    state = AsyncData([created, ...current]);
    return created;
  }

  Future<GoatObligation> save(GoatObligation o) async {
    final updated = await GoatSetupService.updateObligation(o);
    final current = state.valueOrNull ?? const [];
    state = AsyncData([
      for (final x in current)
        if (x.id == updated.id) updated else x
    ]);
    return updated;
  }

  Future<void> delete(String obligationId) async {
    await GoatSetupService.deleteObligation(obligationId);
    final current = state.valueOrNull ?? const [];
    state = AsyncData(current.where((o) => o.id != obligationId).toList());
  }

  Future<void> refreshFromDb() async {
    state = const AsyncLoading<List<GoatObligation>>().copyWithPrevious(state);
    try {
      final v = await GoatSetupService.fetchObligations(includeInactive: true);
      state = AsyncData(v);
    } catch (e, st) {
      state = AsyncError<List<GoatObligation>>(e, st);
    }
  }
}

final goatObligationsControllerProvider =
    AsyncNotifierProvider<GoatObligationsController, List<GoatObligation>>(
  GoatObligationsController.new,
);

// ──────────────────────────────────────────────────────────────────────────
// Recommendation lifecycle actions
// ──────────────────────────────────────────────────────────────────────────
//
// Lives alongside `goatModeControllerProvider` so dismiss/snooze feel
// instantaneous: we optimistically remove the rec from the open list, then
// call Supabase; on failure we put it back and surface an error banner.

/// Handles dismiss/snooze/resolve on `goat_mode_recommendations` with safe
/// optimistic updates against [goatModeControllerProvider]'s cached list.
class GoatRecommendationActions {
  final Ref _ref;
  GoatRecommendationActions(this._ref);

  Future<void> dismiss(String recId) async {
    await _optimistic(recId, () => GoatSetupService.dismissRecommendation(recId));
  }

  Future<void> snooze(String recId, Duration duration) async {
    await _optimistic(
      recId,
      () => GoatSetupService.snoozeRecommendation(recId, duration: duration),
    );
  }

  Future<void> resolve(String recId) async {
    await _optimistic(recId, () => GoatSetupService.resolveRecommendation(recId));
  }

  Future<void> _optimistic(
    String recId,
    Future<void> Function() serverAction,
  ) async {
    final ctrl = _ref.read(goatModeControllerProvider.notifier);
    final before = _ref.read(goatModeControllerProvider).valueOrNull;
    if (before != null) {
      final next = before.copyWith(
        recommendations:
            before.recommendations.where((r) => r.id != recId).toList(),
        errorMessage: null,
      );
      ctrl.setStateForActions(next);
    }

    try {
      await serverAction();
    } catch (e) {
      if (kDebugMode) debugPrint('[GOAT] rec action error: $e');
      if (before != null) {
        ctrl.setStateForActions(before.copyWith(
          errorMessage: 'Couldn\'t update this recommendation — try again.',
        ));
      }
      rethrow;
    }
  }
}

final goatRecommendationActionsProvider =
    Provider<GoatRecommendationActions>((ref) {
  return GoatRecommendationActions(ref);
});
