import 'package:flutter/material.dart';

import '../../../core/theme/goat_theme.dart';
import '../widgets/goat_premium_card.dart';

class GoatRecurringScreen extends StatelessWidget {
  const GoatRecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recurring',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GoatTokens.textPrimary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Subscriptions & bills center',
            style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          GoatPremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_repeat_rounded, color: GoatTokens.gold.withValues(alpha: 0.9)),
                    const SizedBox(width: 10),
                    Text(
                      'Coming soon',
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
                  'Track renewals, cable, rent, and subscriptions in one ledger. You will pin vendors, amounts, and cadence here.',
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
