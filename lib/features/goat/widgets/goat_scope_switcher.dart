import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';

/// Horizontally-scrollable scope chips. Uses `AnimatedContainer` for the
/// selection state so the handoff feels alive without being flashy.
class GoatScopeSwitcher extends StatelessWidget {
  final GoatScope selected;
  final ValueChanged<GoatScope> onSelected;

  const GoatScopeSwitcher({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: GoatScope.userVisible.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final scope = GoatScope.userVisible[i];
          final isOn = scope == selected;
          return _ScopeChip(
            label: scope.label,
            selected: isOn,
            onTap: () => onSelected(scope),
          );
        },
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? BillyTheme.gray800 : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? BillyTheme.gray800 : BillyTheme.gray200,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : BillyTheme.gray600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}
