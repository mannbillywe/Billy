import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';

/// A single recommendation card that progressively discloses its reasoning.
///
/// UX rules:
///   • Default view is ONE line of body — the screen stays calm
///   • Expand reveals "why shown" grounded in the deterministic layer
///   • Urgency is conveyed through a small left stripe + kind label, never
///     through the whole card colour (which would feel alarmist)
class GoatRecommendationCard extends StatefulWidget {
  final GoatRecommendation rec;

  /// Optional AI phrasing maps keyed by `rec_fingerprint` — the card falls
  /// back to deterministic copy when AI is missing / invalidated.
  final Map<String, String>? aiTitleByFp;
  final Map<String, String>? aiBodyByFp;
  final Map<String, String>? aiWhyByFp;

  /// Opens the lifecycle actions sheet (dismiss / snooze / mark done).
  /// Null hides the inline "More" icon — useful in tests or read-only surfaces.
  final VoidCallback? onActions;

  const GoatRecommendationCard({
    super.key,
    required this.rec,
    this.aiTitleByFp,
    this.aiBodyByFp,
    this.aiWhyByFp,
    this.onActions,
  });

  @override
  State<GoatRecommendationCard> createState() => _GoatRecommendationCardState();
}

class _GoatRecommendationCardState extends State<GoatRecommendationCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.rec;
    final accent = _accentFor(r.severity);
    final title = r.titleFor(aiTitleByFingerprint: widget.aiTitleByFp);
    final body = r.bodyFor(aiBodyByFingerprint: widget.aiBodyByFp);
    final why = r.whyShownFor(aiWhyByFingerprint: widget.aiWhyByFp);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (why != null || body != null)
            ? () => setState(() => _open = !_open)
            : null,
        onLongPress: widget.onActions,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              r.kindLabel,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: accent,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (widget.onActions != null)
                            Semantics(
                              button: true,
                              label: 'Recommendation actions',
                              child: InkResponse(
                                onTap: widget.onActions,
                                radius: 18,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  child: Icon(
                                    Icons.more_horiz_rounded,
                                    size: 18,
                                    color: BillyTheme.gray400,
                                  ),
                                ),
                              ),
                            ),
                          AnimatedRotation(
                            turns: _open ? 0.5 : 0,
                            duration: const Duration(milliseconds: 220),
                            child: Icon(
                              Icons.expand_more_rounded,
                              size: 18,
                              color: (why != null || body != null)
                                  ? BillyTheme.gray400
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: BillyTheme.gray800,
                          height: 1.3,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (body != null) ...[
                        const SizedBox(height: 4),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: Text(
                            body,
                            maxLines: _open ? 6 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: BillyTheme.gray600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                      AnimatedSize(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _open
                            ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (why != null) _whyBlock(why, accent),
                                    if (r.confidence != null) ...[
                                      const SizedBox(height: 10),
                                      _metaRow(r),
                                    ],
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _whyBlock(String why, Color accent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BillyTheme.gray50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why this matters',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  why,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: BillyTheme.gray700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(GoatRecommendation r) {
    final conf = r.confidence;
    if (conf == null) return const SizedBox.shrink();
    final pct = (conf.clamp(0.0, 1.0) * 100).round();
    return Row(
      children: [
        const Icon(Icons.verified_outlined, size: 12, color: BillyTheme.gray400),
        const SizedBox(width: 4),
        Text(
          'Confidence $pct%',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: BillyTheme.gray500,
          ),
        ),
      ],
    );
  }

  Color _accentFor(GoatRecSeverity s) {
    switch (s) {
      case GoatRecSeverity.critical:
        return BillyTheme.red500;
      case GoatRecSeverity.warn:
        return const Color(0xFFB45309);
      case GoatRecSeverity.watch:
        return const Color(0xFFD97706);
      case GoatRecSeverity.info:
        return BillyTheme.emerald600;
    }
  }
}
