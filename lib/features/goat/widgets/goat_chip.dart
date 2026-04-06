import 'package:flutter/material.dart';

import '../../../core/theme/goat_theme.dart';

class GoatChip extends StatelessWidget {
  const GoatChip({super.key, required this.label, this.selected = false, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? GoatTokens.gold.withValues(alpha: 0.14) : GoatTokens.surfaceElevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? GoatTokens.gold.withValues(alpha: 0.45) : GoatTokens.borderSubtle,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? GoatTokens.gold : GoatTokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
