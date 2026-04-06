import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../providers/goat_cash_providers.dart';
import '../../../providers/goat_goals_providers.dart';
import '../../../providers/profile_provider.dart';
import '../finance/cashflow_engine.dart';
import '../goals/goal_engine.dart';
import '../goals/goals_repository.dart';
import '../goals/goat_goal_sheets.dart';
import '../widgets/goat_premium_card.dart';

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  static String _paceLabel(String s) {
    switch (s) {
      case 'behind':
        return 'Behind';
      case 'ahead':
        return 'Ahead';
      case 'on_track':
        return 'On track';
      default:
        return '—';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    final async = ref.watch(goatGoalDetailProvider(goalId));

    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Goal'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => showAddContributionSheet(context, ref, goalId),
            ),
          ],
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
          error: (e, _) => Center(child: Text('$e', style: TextStyle(color: GoatTokens.textMuted))),
          data: (bundle) {
            final g = bundle.goal;
            if (g == null) {
              return const Center(child: Text('Goal not found'));
            }
            final pace = GoalEngine.computePace(g, rules: bundle.rules);
            final target = (g['target_amount'] as num?)?.toDouble() ?? 0;
            final current = (g['current_amount'] as num?)?.toDouble() ?? 0;
            final rem = (target - current).clamp(0.0, double.infinity);
            final td = g['target_date'] != null ? DateTime.tryParse(g['target_date'].toString()) : null;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                Text(
                  g['title'] as String? ?? 'Goal',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: GoatTokens.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  (g['goal_type'] as String? ?? '').replaceAll('_', ' '),
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                GoatPremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Progress', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: pace.paceStatus == 'behind'
                                  ? const Color(0xFF7F1D1D).withValues(alpha: 0.4)
                                  : GoatTokens.surfaceElevated,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _paceLabel(pace.paceStatus),
                              style: TextStyle(
                                color: pace.paceStatus == 'behind' ? const Color(0xFFFCA5A5) : GoatTokens.gold,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: pace.progressFraction.clamp(0.0, 1.0),
                          minHeight: 10,
                          backgroundColor: GoatTokens.surfaceElevated,
                          color: GoatTokens.gold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${AppCurrency.format(current, currency)} of ${AppCurrency.format(target, currency)}',
                        style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${AppCurrency.format(rem, currency)} remaining',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GoatPremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Funding (deterministic)', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(
                        'Required monthly: ${AppCurrency.format(CashflowMoneyLine.fromMinor(pace.requiredMonthlyMinor), currency)}',
                        style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Required weekly: ${AppCurrency.format(CashflowMoneyLine.fromMinor(pace.requiredWeeklyMinor), currency)}',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
                      ),
                      if (td != null)
                        Text(
                          'Target date: ${td.year}-${td.month.toString().padLeft(2, '0')}-${td.day.toString().padLeft(2, '0')}',
                          style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
                        ),
                      if (pace.projectedCompletionDate != null)
                        Text(
                          'At current pace, done around: ${pace.projectedCompletionDate!.year}-${pace.projectedCompletionDate!.month.toString().padLeft(2, '0')}-${pace.projectedCompletionDate!.day.toString().padLeft(2, '0')}',
                          style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'Forecast reserve: ${g['forecast_reserve'] ?? 'none'}',
                        style: TextStyle(color: GoatTokens.gold, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Contributions', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (bundle.contribs.isEmpty)
                  Text('No contributions yet.', style: TextStyle(color: GoatTokens.textMuted, fontSize: 13))
                else
                  ...bundle.contribs.take(20).map(
                        (c) => GoatPremiumCard(
                          accentBorder: false,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppCurrency.format((c['amount'] as num?)?.toDouble() ?? 0, currency),
                                      style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w700),
                                    ),
                                    if ((c['note'] as String?)?.isNotEmpty == true)
                                      Text(c['note'] as String, style: TextStyle(color: GoatTokens.textMuted, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Text(
                                (c['contributed_at'] as String?)?.substring(0, 10) ?? '',
                                style: TextStyle(color: GoatTokens.textMuted, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () async {
                    final rule = await showDialog<double>(
                      context: context,
                      builder: (ctx) {
                        final ctrl = TextEditingController();
                        return AlertDialog(
                          backgroundColor: GoatTokens.surface,
                          title: const Text('Fixed monthly rule'),
                          content: TextField(
                            controller: ctrl,
                            decoration: const InputDecoration(labelText: 'Amount / month', border: OutlineInputBorder()),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', ''))),
                              child: const Text('Add'),
                            ),
                          ],
                        );
                      },
                    );
                    if (rule != null && rule > 0) {
                      await GoalsRepository.insertRule(goalId: goalId, ruleType: 'monthly_fixed', ruleValue: rule);
                      ref.invalidate(goatGoalDetailProvider(goalId));
                      ref.invalidate(goatGoalsForecastInputProvider);
                      ref.invalidate(goatForecastProvider);
                    }
                  },
                  icon: const Icon(Icons.rule_folder_outlined, size: 18),
                  label: const Text('Add monthly funding rule'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await GoalsRepository.updateGoal(id: goalId, status: 'paused');
                          ref.invalidate(goatGoalDetailProvider(goalId));
                          ref.invalidate(goatGoalsProvider);
                          ref.invalidate(goatGoalsForecastInputProvider);
                          ref.invalidate(goatForecastProvider);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Pause'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          await GoalsRepository.updateGoal(id: goalId, status: 'completed');
                          ref.invalidate(goatGoalDetailProvider(goalId));
                          ref.invalidate(goatGoalsProvider);
                          ref.invalidate(goatGoalsForecastInputProvider);
                          ref.invalidate(goatForecastProvider);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Complete'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
