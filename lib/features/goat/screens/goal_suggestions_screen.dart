import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../providers/goat_cash_providers.dart';
import '../../../providers/goat_goals_providers.dart';
import '../../../providers/profile_provider.dart';
import '../goals/goal_suggestion_engine.dart';
import '../goals/goals_repository.dart';
import '../goals/goat_goal_sheets.dart';
import '../widgets/goat_premium_card.dart';

/// Full list of deterministic sinking-fund suggestions (accept / dismiss / customize).
class GoalSuggestionsScreen extends ConsumerWidget {
  const GoalSuggestionsScreen({super.key});

  static String _goalTypeForSuggestion(String? st) {
    switch (st) {
      case 'emergency_fund':
        return 'emergency_fund';
      case 'planned_event':
        return 'bill_buffer';
      case 'recurring_series':
      default:
        return 'sinking_fund';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    final async = ref.watch(goatGoalRecommendationsProvider);

    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Suggestions'),
        ),
        body: RefreshIndicator(
          color: GoatTokens.gold,
          onRefresh: () async {
            await GoalSuggestionEngine.syncRecommendations();
            ref.invalidate(goatGoalRecommendationsProvider);
          },
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
            error: (e, _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                Text('$e', style: TextStyle(color: GoatTokens.textMuted, height: 1.4)),
              ],
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'No pending suggestions. Add yearly or quarterly recurring bills, or planned outflows — then pull to refresh.',
                      style: TextStyle(color: GoatTokens.textMuted, height: 1.45),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                itemCount: rows.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final r = rows[i];
                  final id = r['id'] as String?;
                  final title = r['title'] as String? ?? 'Suggestion';
                  final body = r['body'] as String?;
                  final st = r['suggestion_type'] as String?;
                  final amt = (r['suggested_target_amount'] as num?)?.toDouble();
                  final sd = r['suggested_target_date'] as String?;
                  DateTime? td;
                  if (sd != null) td = DateTime.tryParse(sd);

                  return GoatPremiumCard(
                    accentBorder: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                        if (body != null && body.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(body, style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.4)),
                        ],
                        if (amt != null && amt > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Suggested target: ${AppCurrency.format(amt, currency)}',
                            style: TextStyle(color: GoatTokens.gold, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: id == null
                                  ? null
                                  : () async {
                                      await GoalsRepository.setRecommendationStatus(id, 'dismissed');
                                      ref.invalidate(goatGoalRecommendationsProvider);
                                    },
                              child: const Text('Dismiss'),
                            ),
                            OutlinedButton(
                              onPressed: id == null
                                  ? null
                                  : () {
                                      final gt = _goalTypeForSuggestion(st);
                                      showCreateGoalSheet(
                                        context,
                                        ref,
                                        prefill: CreateGoalPrefill(
                                          title: title,
                                          targetAmountText: amt != null && amt > 0 ? amt.toString() : '',
                                          goalType: gt,
                                          targetDate: td,
                                          forecastReserve: 'soft',
                                        ),
                                      );
                                    },
                              child: const Text('Customize'),
                            ),
                            FilledButton(
                              onPressed: id == null
                                  ? null
                                  : () async {
                                      try {
                                        await GoalsRepository.acceptRecommendationAsGoal(id);
                                        ref.invalidate(goatGoalRecommendationsProvider);
                                        ref.invalidate(goatGoalsProvider);
                                        ref.invalidate(goatGoalsSummaryProvider);
                                        ref.invalidate(goatGoalsForecastInputProvider);
                                        ref.invalidate(goatForecastProvider);
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(content: Text('Goal created from suggestion')),
                                          );
                                        }
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                                        }
                                      }
                                    },
                              child: const Text('Accept'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
