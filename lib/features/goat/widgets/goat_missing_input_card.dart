import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';

/// Missing-inputs are framed as unlocks, never as setup errors. The card is
/// low-contrast and optional — tapping will hand off to a future setup route
/// (Phase 7). For now we expose a clean CTA via [onAction].
class GoatMissingInputCard extends StatelessWidget {
  final GoatMissingInput input;

  /// Optional AI-phrased title/body for this input (by input_key).
  final String? aiTitle;
  final String? aiBody;

  final VoidCallback? onAction;

  const GoatMissingInputCard({
    super.key,
    required this.input,
    this.aiTitle,
    this.aiBody,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final title = (aiTitle?.isNotEmpty ?? false) ? aiTitle! : input.label;
    final body = (aiBody?.isNotEmpty ?? false) ? aiBody! : input.why;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAction,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                BillyTheme.emerald50,
                Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BillyTheme.emerald100),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: BillyTheme.emerald100),
                ),
                child: const Icon(Icons.lock_open_rounded,
                    color: BillyTheme.emerald600, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: BillyTheme.gray800,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: BillyTheme.gray500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: BillyTheme.emerald600),
            ],
          ),
        ),
      ),
    );
  }
}
