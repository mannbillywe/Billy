import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

/// Soft, recoverable error banner. Never blocks the rest of the screen.
class GoatErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const GoatErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF7C2D12),
                height: 1.4,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: BillyTheme.gray500),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }
}
