import 'package:flutter/material.dart';

import '../../core/theme/billy_theme.dart';

/// Shown when the user taps GOAT in the header. Full GOAT workspace is not bundled in this build.
class GoatModePlaceholderScreen extends StatelessWidget {
  const GoatModePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: BillyTheme.scaffoldBg,
        elevation: 0,
        foregroundColor: BillyTheme.gray800,
        title: const Text('GOAT Mode'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.construction_rounded, size: 48, color: BillyTheme.emerald600.withValues(alpha: 0.85)),
            const SizedBox(height: 20),
            Text(
              'GOAT Mode is in the works',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'We are rebuilding this experience. For now, use Home, Analytics, and your receipts as usual.',
              style: TextStyle(fontSize: 15, height: 1.45, color: BillyTheme.gray600),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(
                backgroundColor: BillyTheme.emerald600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              child: const Text('Back to Billy'),
            ),
          ],
        ),
      ),
    );
  }
}
