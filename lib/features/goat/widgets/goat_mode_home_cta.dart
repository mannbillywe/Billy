import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/telemetry/goat_telemetry.dart';
import '../../../core/theme/goat_theme.dart';
import '../goat_profile.dart';

/// Prominent home entry to GOAT Mode (only when [goatAccessProvider] is true).
class GoatModeHomeCta extends ConsumerStatefulWidget {
  const GoatModeHomeCta({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  ConsumerState<GoatModeHomeCta> createState() => _GoatModeHomeCtaState();
}

class _GoatModeHomeCtaState extends ConsumerState<GoatModeHomeCta> {
  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(goatAccessProvider, (prev, next) {
      if (next && prev != true) {
        logGoatEvent('goat_cta_seen');
      }
    });
    final enabled = ref.watch(goatAccessProvider);
    if (!enabled) return const SizedBox.shrink();

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
                          'Control bills, cash flow, and goals',
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
