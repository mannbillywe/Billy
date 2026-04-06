import 'package:flutter/material.dart';

import '../../../core/theme/goat_theme.dart';

class GoatHeaderBanner extends StatelessWidget {
  const GoatHeaderBanner({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            GoatTokens.surface.withValues(alpha: 0.95),
            GoatTokens.background,
          ],
        ),
        border: Border(bottom: BorderSide(color: GoatTokens.gold.withValues(alpha: 0.12))),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Image.asset(
              'assets/branding/billy_logo.png',
              height: 32,
              errorBuilder: (_, _, _) => const Icon(Icons.account_balance_wallet_outlined, color: GoatTokens.gold, size: 28),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'BILLY',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: GoatTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        fontSize: 11,
                      ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.workspace_premium_rounded, size: 14, color: GoatTokens.gold.withValues(alpha: 0.9)),
                    const SizedBox(width: 4),
                    ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFFFEF08A), GoatTokens.gold, GoatTokens.goldDeep],
                      ).createShader(bounds),
                      child: Text(
                        'GOAT',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 3,
                              color: Colors.white,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              onPressed: onExit,
              tooltip: 'Back to Billy',
              style: IconButton.styleFrom(
                backgroundColor: GoatTokens.surfaceElevated,
                foregroundColor: GoatTokens.textMuted,
                side: BorderSide(color: GoatTokens.borderSubtle),
              ),
              icon: const Icon(Icons.home_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
