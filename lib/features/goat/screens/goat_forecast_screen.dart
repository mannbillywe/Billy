import 'package:flutter/material.dart';

import '../../../core/theme/goat_theme.dart';
import '../widgets/goat_premium_card.dart';

class GoatForecastScreen extends StatelessWidget {
  const GoatForecastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Forecast',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GoatTokens.textPrimary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Cash-flow outlook & safe-to-spend',
            style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          GoatPremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.insights_rounded, color: GoatTokens.gold.withValues(alpha: 0.9)),
                    const SizedBox(width: 10),
                    Text(
                      'Model in progress',
                      style: TextStyle(
                        color: GoatTokens.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Connect income schedules and recurring outflows to project balances and a daily safe-to-spend. This module will build on your Billy vault.',
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.45, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
