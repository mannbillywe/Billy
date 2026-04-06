import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/goat_theme.dart';
import '../../../providers/goat_lens_provider.dart';
import '../statements/goat_analysis_lens.dart';

/// Sticky analysis lens control for GOAT (deduped vs statement-only vs receipts vs raw).
class GoatAnalysisLensBar extends ConsumerWidget {
  const GoatAnalysisLensBar({super.key});

  void _explain(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GoatTokens.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analysis lens',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: GoatTokens.textPrimary,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Smart avoids double counting by preferring matched bank/card lines over duplicate OCR receipts when both exist. '
              'Statements Only is for posted movement from imports. Bills & receipts is classic Billy documents. '
              'Combined raw shows every source and may inflate totals — use for audit only.',
              style: TextStyle(color: GoatTokens.textMuted, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lens = ref.watch(goatAnalysisLensProvider);
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<GoatAnalysisLens>(
                  segments: [
                    ButtonSegment(value: GoatAnalysisLens.smart, label: Text(GoatAnalysisLens.smart.label)),
                    ButtonSegment(value: GoatAnalysisLens.statementsOnly, label: Text('Stmt')),
                    ButtonSegment(value: GoatAnalysisLens.ocrOnly, label: Text('Receipts')),
                    ButtonSegment(value: GoatAnalysisLens.combinedRaw, label: Text('Raw')),
                  ],
                  selected: {lens},
                  onSelectionChanged: (next) {
                    ref.read(goatAnalysisLensProvider.notifier).setLens(next.first);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return GoatTokens.gold;
                      return GoatTokens.textMuted;
                    }),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'What is this?',
              onPressed: () => _explain(context),
              icon: Icon(Icons.info_outline, color: GoatTokens.gold.withValues(alpha: 0.85), size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
