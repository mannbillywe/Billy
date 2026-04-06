import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/telemetry/goat_telemetry.dart';
import '../../core/theme/billy_theme.dart';
import '../../core/theme/goat_theme.dart';
import '../../features/goat/goat_profile.dart';
import '../../providers/profile_provider.dart';

class BillyHeader extends ConsumerWidget {
  const BillyHeader({super.key, required this.onOpenGoatMode});

  final VoidCallback onOpenGoatMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final goat = parseProfileGoatAccess(profile);
    final showGoatEntry = profile != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: BillyTheme.scaffoldBg,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/branding/billy_logo.png',
              height: 48,
              width: 48,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: BillyTheme.emerald100,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('B', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.emerald600)),
              ),
            ),
          ),
          if (showGoatEntry) ...[
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  logGoatEvent('goat_header_chip_clicked');
                  onOpenGoatMode();
                },
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: goat
                        ? LinearGradient(
                            colors: [
                              GoatTokens.gold.withValues(alpha: 0.2),
                              GoatTokens.goldDeep.withValues(alpha: 0.12),
                            ],
                          )
                        : null,
                    color: goat ? null : BillyTheme.gray100,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: goat ? GoatTokens.gold.withValues(alpha: 0.35) : BillyTheme.gray300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        size: 16,
                        color: goat ? GoatTokens.gold.withValues(alpha: 0.95) : BillyTheme.gray600,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'GOAT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: BillyTheme.gray800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: BillyTheme.gray500,
                  ),
                ),
                Text(
                  'Billy',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: BillyTheme.gray800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
