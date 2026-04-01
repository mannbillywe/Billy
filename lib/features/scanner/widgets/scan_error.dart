import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

class ScanError extends StatelessWidget {
  const ScanError({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: BillyTheme.red500.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BillyTheme.red500.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline, color: BillyTheme.red500),
                  SizedBox(width: 8),
                  Text('Could not read invoice', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 12),
              Text(message, style: const TextStyle(color: BillyTheme.gray700, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: BillyTheme.emerald600),
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
