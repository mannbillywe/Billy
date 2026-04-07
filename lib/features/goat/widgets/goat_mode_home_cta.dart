import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/telemetry/goat_telemetry.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../providers/profile_provider.dart';
import '../goat_profile.dart';

/// Prominent Home entry to GOAT (shown once profile loads; [parseProfileGoatAccess] only affects subtitle).
class GoatModeHomeCta extends ConsumerStatefulWidget {
  const GoatModeHomeCta({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  ConsumerState<GoatModeHomeCta> createState() => _GoatModeHomeCtaState();
}

class _GoatModeHomeCtaState extends ConsumerState<GoatModeHomeCta> {
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final hasProfile = profileAsync.hasValue && profileAsync.valueOrNull != null;
    ref.listen<AsyncValue<Map<String, dynamic>?>>(profileProvider, (prev, next) {
      final now = next.hasValue && next.valueOrNull != null;
      final was = prev?.hasValue == true && prev?.valueOrNull != null;
      if (now && !was) {
        logGoatEvent('goat_cta_seen');
      }
    });
    if (!hasProfile) return const SizedBox.shrink();

    final goatOn = parseProfileGoatAccess(profileAsync.valueOrNull);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            logGoatEvent('goat_cta_clicked');
            widget.onPressed();
          },
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF18181B), Color(0xFF0A0A0B)],
              ),
              border: Border.all(color: GoatTokens.gold.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: GoatTokens.gold.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/branding/billy_logo.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 44,
                        height: 44,
                        color: GoatTokens.surfaceElevated,
                        child: const Icon(Icons.workspace_premium, color: GoatTokens.gold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'GOAT Mode',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: GoatTokens.gold,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.arrow_forward_ios_rounded, size: 11, color: GoatTokens.gold.withValues(alpha: 0.7)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          goatOn
                              ? 'Bills, recurring, forecast — import statements from the upload icon in GOAT header or Statements on Home'
                              : 'Tap to open — enable workspace if you see the lock screen',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: GoatTokens.textMuted.withValues(alpha: 0.95),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
