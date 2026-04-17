import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';

/// Compact calm status pill. Never shouts — even "failed" is soft red, not
/// alarming. Animates on status changes to confirm state transitions.
class GoatStatusChip extends StatelessWidget {
  final GoatJobStatus status;
  final bool isRefreshing;
  final bool stale;

  const GoatStatusChip({
    super.key,
    required this.status,
    this.isRefreshing = false,
    this.stale = false,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _spec();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: spec.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRefreshing)
            _PulsingDot(color: spec.fg)
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: spec.fg,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 7),
          Text(
            _label(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: spec.fg,
            ),
          ),
        ],
      ),
    );
  }

  String _label() {
    if (isRefreshing) {
      return status == GoatJobStatus.running ? 'Analyzing…' : 'Starting…';
    }
    if (stale) return 'Stale';
    return status.label;
  }

  _ChipSpec _spec() {
    if (isRefreshing) {
      return const _ChipSpec(
        bg: Color(0xFFEFF6FF),
        fg: BillyTheme.blue400,
      );
    }
    if (stale) {
      return const _ChipSpec(bg: BillyTheme.gray100, fg: BillyTheme.gray500);
    }
    switch (status) {
      case GoatJobStatus.succeeded:
        return const _ChipSpec(bg: BillyTheme.emerald50, fg: BillyTheme.emerald600);
      case GoatJobStatus.partial:
        return const _ChipSpec(bg: Color(0xFFFEF3C7), fg: Color(0xFFB45309));
      case GoatJobStatus.failed:
        return const _ChipSpec(bg: Color(0xFFFEE2E2), fg: BillyTheme.red500);
      case GoatJobStatus.running:
      case GoatJobStatus.queued:
        return const _ChipSpec(bg: Color(0xFFEFF6FF), fg: BillyTheme.blue400);
      case GoatJobStatus.cancelled:
      case GoatJobStatus.unknown:
        return const _ChipSpec(bg: BillyTheme.gray100, fg: BillyTheme.gray500);
    }
  }
}

class _ChipSpec {
  final Color bg;
  final Color fg;
  const _ChipSpec({required this.bg, required this.fg});
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = 0.5 + _c.value * 0.5;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: t),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
