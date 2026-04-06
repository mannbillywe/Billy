import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/goat/finance/cashflow_engine.dart';
import '../features/goat/goals/goal_engine.dart';
import '../features/goat/goals/goals_repository.dart';

/// Active goals + rules for forecast hard-reserve math.
class GoatGoalsForecastInput {
  const GoatGoalsForecastInput({required this.activeGoals, required this.rulesByGoalId});

  final List<Map<String, dynamic>> activeGoals;
  final Map<String, List<Map<String, dynamic>>> rulesByGoalId;
}

final goatGoalsForecastInputProvider = FutureProvider<GoatGoalsForecastInput>((ref) async {
  final all = await GoalsRepository.fetchGoals();
  final active = all.where((g) => (g['status'] as String?) == 'active').toList();
  final rules = <String, List<Map<String, dynamic>>>{};
  for (final g in active) {
    final id = g['id'] as String?;
    if (id == null) continue;
    rules[id] = await GoalsRepository.fetchRulesForGoal(id);
  }
  return GoatGoalsForecastInput(activeGoals: active, rulesByGoalId: rules);
});

final goatGoalsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return GoalsRepository.fetchGoals();
});

final goatGoalRecommendationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return GoalsRepository.fetchRecommendations(status: 'pending');
});

final goatGoalDetailProvider = FutureProvider.family<({Map<String, dynamic>? goal, List<Map<String, dynamic>> contribs, List<Map<String, dynamic>> rules}), String>(
  (ref, goalId) async {
    final goal = await GoalsRepository.fetchGoalById(goalId);
    final contribs = await GoalsRepository.fetchContributions(goalId);
    final rules = await GoalsRepository.fetchRulesForGoal(goalId);
    return (goal: goal, contribs: contribs, rules: rules);
  },
);

class GoalsSummary {
  const GoalsSummary({
    required this.totalSavedMinor,
    required this.totalMonthlyRequiredMinor,
    required this.onTrack,
    required this.behind,
    required this.ahead,
    required this.activeCount,
    required this.softReserveMonthlyMinor,
  });

  final int totalSavedMinor;
  final int totalMonthlyRequiredMinor;
  final int onTrack;
  final int behind;
  final int ahead;
  final int activeCount;
  final int softReserveMonthlyMinor;

  static GoalsSummary compute(List<Map<String, dynamic>> goals, Map<String, List<Map<String, dynamic>>> rulesByGoalId) {
    var saved = 0;
    var monthly = 0;
    var softM = 0;
    var ot = 0, be = 0, ah = 0;
    var active = 0;
    for (final g in goals) {
      if ((g['status'] as String?) != 'active') continue;
      active++;
      final id = g['id'] as String?;
      final rules = id != null ? (rulesByGoalId[id] ?? const <Map<String, dynamic>>[]) : const <Map<String, dynamic>>[];
      saved += CashflowMoneyLine.toMinor((g['current_amount'] as num?)?.toDouble() ?? 0);
      final pace = GoalEngine.computePace(g, rules: rules);
      monthly += pace.requiredMonthlyMinor;
      if ((g['forecast_reserve'] as String?) == 'soft') {
        softM += pace.requiredMonthlyMinor;
      }
      switch (pace.paceStatus) {
        case 'behind':
          be++;
          break;
        case 'ahead':
          ah++;
          break;
        case 'on_track':
          ot++;
          break;
        default:
          break;
      }
    }
    return GoalsSummary(
      totalSavedMinor: saved,
      totalMonthlyRequiredMinor: monthly,
      onTrack: ot,
      behind: be,
      ahead: ah,
      activeCount: active,
      softReserveMonthlyMinor: softM,
    );
  }
}

final goatGoalsSummaryProvider = FutureProvider<GoalsSummary>((ref) async {
  final all = await ref.watch(goatGoalsProvider.future);
  final active = all.where((g) => (g['status'] as String?) == 'active').toList();
  final rules = <String, List<Map<String, dynamic>>>{};
  for (final g in active) {
    final id = g['id'] as String?;
    if (id == null) continue;
    rules[id] = await GoalsRepository.fetchRulesForGoal(id);
  }
  return GoalsSummary.compute(active, rules);
});
