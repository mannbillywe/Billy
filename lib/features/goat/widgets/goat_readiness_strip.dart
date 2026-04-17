import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';

/// A quiet readiness/coverage strip. Lives under the hero so the user can see
/// at a glance how "deep" the current analysis is without reading numbers.
class GoatReadinessStrip extends StatelessWidget {
  final GoatSnapshot snapshot;

  const GoatReadinessStrip({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final cov = (snapshot.coverageScore ?? snapshot.readiness.progress).clamp(0.0, 1.0);
    final color = _accent(cov);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.insights_rounded, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.readiness.shortLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: BillyTheme.gray800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(snapshot),
                      style: const TextStyle(
                        fontSize: 12,
                        color: BillyTheme.gray500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(cov * 100).round()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: cov),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: BillyTheme.gray100,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(GoatSnapshot s) {
    final missingCount = s.missingInputs.length;
    if (missingCount == 0) {
      return 'All key signals are connected.';
    }
    if (missingCount == 1) {
      return '1 quick unlock left to sharpen insights.';
    }
    return '$missingCount quick unlocks left to sharpen insights.';
  }

  Color _accent(double v) {
    if (v >= 0.75) return BillyTheme.emerald600;
    if (v >= 0.4) return const Color(0xFFB45309);
    return BillyTheme.red500;
  }
}
