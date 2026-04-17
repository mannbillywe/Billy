import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_setup_models.dart';

/// Compact "Improve this analysis" card on the main Goat Mode screen.
///
/// The intent is to give users a low-pressure, always-visible doorway into
/// the setup loop without crowding the hero. It collapses down to a soft
/// emerald row + progress when the user hasn't started setup, and stays
/// quietly present (but less loud) when most inputs are filled.
class GoatSetupSummaryCard extends StatelessWidget {
  final GoatUserInputs inputs;
  final int goalsCount;
  final int obligationsCount;
  final VoidCallback onOpen;

  const GoatSetupSummaryCard({
    super.key,
    required this.inputs,
    required this.goalsCount,
    required this.obligationsCount,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final filled = inputs.filledCoreCount;
    final total = inputs.coreTotal;
    final pct = total == 0 ? 0.0 : (filled / total).clamp(0.0, 1.0);
    final fresh = !inputs.hasAnyValue && goalsCount == 0 && obligationsCount == 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                fresh ? BillyTheme.emerald50 : Colors.white,
                Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: fresh ? BillyTheme.emerald100 : BillyTheme.gray100,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: BillyTheme.emerald50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_fix_high_rounded,
                        size: 16, color: BillyTheme.emerald600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fresh
                              ? 'Improve this analysis'
                              : 'Your setup',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: BillyTheme.gray800,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: BillyTheme.gray500,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: BillyTheme.emerald600),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 5,
                    backgroundColor: BillyTheme.gray100,
                    valueColor:
                        const AlwaysStoppedAnimation(BillyTheme.emerald500),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Chip(label: '$filled/$total inputs'),
                  const SizedBox(width: 6),
                  _Chip(label: '$goalsCount ${goalsCount == 1 ? "goal" : "goals"}'),
                  const SizedBox(width: 6),
                  _Chip(
                      label:
                          '$obligationsCount ${obligationsCount == 1 ? "obligation" : "obligations"}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    if (!inputs.hasAnyValue && goalsCount == 0 && obligationsCount == 0) {
      return 'Add a few details so Goat Mode can give you sharper insight.';
    }
    if (inputs.filledCoreCount < inputs.coreTotal) {
      return 'A couple more inputs will unlock more depth.';
    }
    return 'Looking sharp. Tap to tweak anything.';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: BillyTheme.gray50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: BillyTheme.gray600,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
