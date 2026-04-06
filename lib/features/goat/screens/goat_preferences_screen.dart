import 'package:flutter/material.dart';

import '../../../core/theme/goat_theme.dart';
import '../widgets/goat_premium_card.dart';

class GoatPreferencesScreen extends StatelessWidget {
  const GoatPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GOAT preferences',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GoatTokens.textPrimary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Power-user defaults for this workspace',
            style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          GoatPremiumCard(
            accentBorder: false,
            child: Text(
              'Preference toggles (notifications density, forecast assumptions, goal rules) will appear here as features ship.',
              style: TextStyle(color: GoatTokens.textMuted, height: 1.45, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
