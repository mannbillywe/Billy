import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';

/// Ambient AI-narrative card. Supportive, not dominant.
///
/// UX rules:
///   • Only renders if the AI layer was actually validated & has content —
///     otherwise the deterministic narrative on the hero is enough.
///   • Never shows raw "fake mode" / validator state.
class GoatAISummaryCard extends StatelessWidget {
  final GoatAIView ai;

  const GoatAISummaryCard({super.key, required this.ai});

  @override
  Widget build(BuildContext context) {
    final text = ai.narrativeSummary;
    final pillars = ai.pillars.take(3).toList(growable: false);
    final hasAnything = (text != null && text.isNotEmpty) || pillars.isNotEmpty;
    if (!hasAnything) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.psychology_alt_rounded,
                    size: 15, color: Color(0xFF7C3AED)),
              ),
              const SizedBox(width: 10),
              const Text(
                'What this means',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.gray800,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          if (text != null && text.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: BillyTheme.gray700,
                height: 1.5,
              ),
            ),
          ],
          if (pillars.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (int i = 0; i < pillars.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _PillarRow(pillar: pillars[i]),
            ],
          ],
        ],
      ),
    );
  }
}

class _PillarRow extends StatelessWidget {
  final GoatAIPillar pillar;
  const _PillarRow({required this.pillar});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: BillyTheme.emerald500,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _pillarLabel(pillar.pillar),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: BillyTheme.gray500,
                ),
              ),
              const SizedBox(height: 2),
              if (pillar.observation.isNotEmpty)
                Text(
                  pillar.observation,
                  style: const TextStyle(
                    fontSize: 13,
                    color: BillyTheme.gray700,
                    height: 1.4,
                  ),
                ),
              if (pillar.inference.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  pillar.inference,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: BillyTheme.gray500,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _pillarLabel(String p) {
    if (p.isEmpty) return 'INSIGHT';
    return p.toUpperCase();
  }
}
