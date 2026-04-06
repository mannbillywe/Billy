import 'package:flutter/material.dart';

import '../../../core/telemetry/goat_telemetry.dart';
import '../../../core/theme/goat_theme.dart';

class GoatAccessDeniedScreen extends StatefulWidget {
  const GoatAccessDeniedScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<GoatAccessDeniedScreen> createState() => _GoatAccessDeniedScreenState();
}

class _GoatAccessDeniedScreenState extends State<GoatAccessDeniedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      logGoatEvent('goat_locked_access_attempt');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: GoatTheme.darkTheme(context),
      child: Scaffold(
        backgroundColor: GoatTokens.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Icon(Icons.lock_outline_rounded, size: 56, color: GoatTokens.gold.withValues(alpha: 0.85)),
                const SizedBox(height: 20),
                Text(
                  'GOAT Mode',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: GoatTokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This premium workspace is not enabled for your account yet. If you believe this is a mistake, contact the operator of this Billy deployment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.45, fontSize: 14),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: widget.onBack,
                  style: FilledButton.styleFrom(
                    backgroundColor: GoatTokens.gold,
                    foregroundColor: GoatTokens.background,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Return to Billy', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
