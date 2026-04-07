import 'package:flutter/material.dart';

import '../../../../core/theme/goat_theme.dart';
import '../goat_setup_readiness.dart';

class GoatReadinessCard extends StatelessWidget {
  const GoatReadinessCard({super.key, required this.readiness});

  final GoatReadinessResult readiness;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GoatTokens.gold.withValues(alpha: 0.25)),
        gradient: LinearGradient(
          colors: [
            GoatTokens.surfaceElevated,
            GoatTokens.surface.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Readiness',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: GoatTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              Text(
                '${readiness.score}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: GoatTokens.gold,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(
                ' / 100',
                style: TextStyle(color: GoatTokens.textMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: readiness.score / 100,
              minHeight: 6,
              backgroundColor: GoatTokens.borderSubtle,
              color: GoatTokens.gold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            readiness.nextBestAction,
            style: TextStyle(color: GoatTokens.textPrimary.withValues(alpha: 0.92), fontSize: 13, height: 1.35),
          ),
          if (readiness.criticalMissing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Needs attention', style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ...readiness.criticalMissing.take(3).map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.priority_high_rounded, size: 16, color: GoatTokens.gold.withValues(alpha: 0.85)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(s, style: TextStyle(color: GoatTokens.textMuted, fontSize: 12))),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
