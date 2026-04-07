import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/goat_theme.dart';
import '../goat_setup_providers.dart';
import '../screens/goat_setup_screen.dart';

/// GOAT Home nudge when setup was started but not finished.
class GoatSetupResumeBanner extends ConsumerWidget {
  const GoatSetupResumeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupAsync = ref.watch(goatSetupStateProvider);
    return setupAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (row) {
        if (!goatSetupNeedsResume(row)) return const SizedBox.shrink();
        if ((row?['status'] as String?) == 'skipped') return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
            color: GoatTokens.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const GoatSetupScreen()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: GoatTokens.gold.withValues(alpha: 0.95)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Continue GOAT setup',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: GoatTokens.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tell Billy about your money in plain language — or finish with forms.',
                            style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: GoatTokens.textMuted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
