import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

/// Minimal shimmer block without pulling in a new dependency. Mirrors the
/// gradient-sweep pattern already used by `_GoatModeButton` in billy_header.
class GoatShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const GoatShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<GoatShimmerBox> createState() => _GoatShimmerBoxState();
}

class _GoatShimmerBoxState extends State<GoatShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
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
        final t = _c.value;
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 + t * 2, 0),
                end: Alignment(0 + t * 2, 0),
                colors: const [
                  BillyTheme.gray100,
                  BillyTheme.gray50,
                  BillyTheme.gray100,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// First-load skeleton: a hero block + two summary rows. Kept small & calm.
class GoatInitialSkeleton extends StatelessWidget {
  const GoatInitialSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          GoatShimmerBox(
            width: double.infinity,
            height: 160,
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          SizedBox(height: 20),
          GoatShimmerBox(
            width: 160,
            height: 16,
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          SizedBox(height: 12),
          GoatShimmerBox(
            width: double.infinity,
            height: 100,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          SizedBox(height: 14),
          GoatShimmerBox(
            width: double.infinity,
            height: 100,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ],
      ),
    );
  }
}
