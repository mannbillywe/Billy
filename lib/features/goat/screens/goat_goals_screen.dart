import 'package:flutter/material.dart';

import '../../../core/theme/goat_theme.dart';
import '../widgets/goat_premium_card.dart';

class GoatGoalsScreen extends StatelessWidget {
  const GoatGoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Goals',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GoatTokens.textPrimary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Targets & sinking funds',
            style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          GoatPremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.flag_outlined, color: GoatTokens.gold.withValues(alpha: 0.9)),
                    const SizedBox(width: 10),
                    Text(
                      'No goals yet',
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
                  'Define savings targets and sinking funds here. Use Forecast for cash-flow and safe-to-spend; goal creation will plug into the same balances soon.',
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
