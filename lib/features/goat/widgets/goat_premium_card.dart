import 'package:flutter/material.dart';

import '../../../core/theme/goat_theme.dart';

class GoatPremiumCard extends StatelessWidget {
  const GoatPremiumCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.accentBorder = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool accentBorder;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          GoatTokens.surface,
          GoatTokens.surfaceElevated.withValues(alpha: 0.85),
        ],
      ),
      border: Border.all(
        color: accentBorder ? GoatTokens.gold.withValues(alpha: 0.22) : GoatTokens.borderSubtle,
        width: 1,
      ),
      boxShadow: GoatTokens.cardGlow,
    );

    final inner = Padding(padding: padding, child: child);

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(decoration: decoration, child: inner),
        ),
      );
    }

    return DecoratedBox(decoration: decoration, child: inner);
  }
}
