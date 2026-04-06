import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/goat_theme.dart';
import '../goals/goat_goal_sheets.dart';
import '../widgets/goat_premium_card.dart';
import 'goal_detail_screen.dart';

/// First-class emergency buffer UX: purpose, milestones (conceptual), deterministic create flow.
class EmergencyFundScreen extends ConsumerWidget {
  const EmergencyFundScreen({super.key, this.existingGoalId});

  /// When set, screen focuses on progress for an existing emergency goal.
  final String? existingGoalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        appBar: AppBar(
          backgroundColor: GoatTokens.background,
          foregroundColor: GoatTokens.textPrimary,
          title: const Text('Emergency fund'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            Text(
              'Cash you can reach quickly when income pauses or bills bunch up. It lowers forecast risk because you are funding the buffer on purpose.',
              style: TextStyle(color: GoatTokens.textMuted, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 20),
            GoatPremiumCard(
              accentBorder: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Milestones', style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6)),
                  const SizedBox(height: 10),
                  _milestoneRow('First cushion', 'Enough to cover one month of essentials you define.'),
                  _milestoneRow('Stability', 'Often quoted as 3× monthly essentials — you choose the number.'),
                  _milestoneRow('Resilience', '6× or more if your income is variable or you support dependents.'),
                  const SizedBox(height: 8),
                  Text(
                    'Targets are yours; pace and progress stay fully deterministic in Goals.',
                    style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (existingGoalId != null) ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => GoalDetailScreen(goalId: existingGoalId!)),
                  );
                },
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Open your emergency fund'),
              ),
            ] else ...[
              Text('Suggested starting target', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'If you are unsure, pick a round number you can sustain monthly, then raise the target as your picture of essentials sharpens.',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => showCreateGoalSheet(
                  context,
                  ref,
                  prefill: const CreateGoalPrefill(
                    title: 'Emergency fund',
                    goalType: 'emergency_fund',
                    forecastReserve: 'soft',
                  ),
                ),
                icon: const Icon(Icons.shield_moon_outlined),
                label: const Text('Create emergency fund'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _milestoneRow(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 8, color: GoatTokens.gold.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                Text(body, style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
