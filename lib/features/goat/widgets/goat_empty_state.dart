import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

/// First-run state — no snapshot yet and we haven't run an analysis.
///
/// Intentionally inviting, not intimidating. One clear action.
class GoatFirstRunState extends StatelessWidget {
  final bool isRefreshing;
  final VoidCallback onRunFirstAnalysis;

  const GoatFirstRunState({
    super.key,
    required this.isRefreshing,
    required this.onRunFirstAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFECFDF5), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: BillyTheme.emerald100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BillyTheme.emerald100),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: BillyTheme.emerald600, size: 22),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your first GOAT snapshot',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'We\'ll look at your money the way a thoughtful friend would — '
                  'highlight what matters, skip the noise, and suggest what to do next.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: BillyTheme.gray600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isRefreshing ? null : onRunFirstAnalysis,
                    style: FilledButton.styleFrom(
                      backgroundColor: BillyTheme.emerald600,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isRefreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'Run my first analysis',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _QuietHint(),
        ],
      ),
    );
  }
}

class _QuietHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Icon(Icons.lock_outline_rounded, size: 14, color: BillyTheme.gray400),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'Everything stays in your Billy account. GOAT only analyses your own data.',
            style: TextStyle(
              fontSize: 11.5,
              color: BillyTheme.gray500,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown when `profiles.goat_mode` is false (user lacks access).
class GoatNotEnabledState extends StatelessWidget {
  const GoatNotEnabledState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.auto_awesome_outlined,
                size: 28, color: BillyTheme.emerald600),
            SizedBox(height: 14),
            Text(
              'GOAT Mode is rolling out',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'We\'re enabling GOAT Mode for Billy users in waves. '
              'You\'ll see it here the moment your account is included.',
              style: TextStyle(
                fontSize: 13,
                color: BillyTheme.gray500,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
