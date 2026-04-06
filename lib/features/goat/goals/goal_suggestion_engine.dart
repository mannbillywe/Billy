import '../finance/finance_repository.dart';
import '../recurring/recurring_repository.dart';
import 'goals_repository.dart';

/// Deterministic sinking-fund suggestions (no AI). Syncs rows into [goal_recommendations].
class GoalSuggestionEngine {
  GoalSuggestionEngine._();

  static Future<void> syncRecommendations() async {
    final series = await RecurringRepository.fetchSeries();
    for (final s in series) {
      final st = s['status'] as String? ?? '';
      if (st != 'active' && st != 'suggested') continue;
      final freq = s['frequency'] as String? ?? '';
      if (freq != 'yearly' && freq != 'quarterly') continue;
      final id = s['id'] as String?;
      final title = (s['title'] as String?)?.trim() ?? 'Bill';
      final amt = (s['expected_amount'] as num?)?.toDouble() ?? 0;
      if (id == null) continue;
      final key = 'recurring_series:$id';
      await GoalsRepository.ensurePendingRecommendation(
        suggestionKey: key,
        title: 'Sinking fund: $title',
        body: freq == 'yearly'
            ? 'Set aside monthly for this annual obligation.'
            : 'Set aside monthly for this quarterly obligation.',
        suggestionType: 'recurring_series',
        refTable: 'recurring_series',
        refId: id,
        suggestedTargetAmount: amt > 0 ? amt : null,
        payload: {'frequency': freq, 'series_title': title},
      );
    }

    final planned = await FinanceRepository.fetchPlannedEvents();
    for (final p in planned) {
      if ((p['direction'] as String?) != 'outflow') continue;
      final id = p['id'] as String?;
      if (id == null) continue;
      final title = (p['title'] as String?) ?? 'Planned expense';
      final amt = (p['amount'] as num?)?.toDouble() ?? 0;
      final key = 'planned_event:$id';
      await GoalsRepository.ensurePendingRecommendation(
        suggestionKey: key,
        title: 'Fund ahead: $title',
        body: 'Build a sinking fund before this planned outflow.',
        suggestionType: 'planned_event',
        refTable: 'planned_cashflow_events',
        refId: id,
        suggestedTargetAmount: amt > 0 ? amt : null,
        payload: {},
      );
    }

    await GoalsRepository.ensurePendingRecommendation(
      suggestionKey: 'emergency_fund:default',
      title: 'Start an emergency fund',
      body: 'A cash buffer reduces forecast risk when bills cluster before income.',
      suggestionType: 'emergency_fund',
      suggestedTargetAmount: null,
      payload: {},
    );
  }
}
