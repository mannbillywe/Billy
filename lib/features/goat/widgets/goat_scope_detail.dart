import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';

/// Per-scope detail card. Renders only the most important metric rows for the
/// currently-selected scope. Details deeper than this open in a bottom sheet.
class GoatScopeDetailCard extends StatelessWidget {
  final GoatScope scope;
  final GoatSnapshot snapshot;

  const GoatScopeDetailCard({
    super.key,
    required this.scope,
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = snapshot.metricsForScope(scope);
    if (metrics.isEmpty) {
      return _EmptyScope(scope: scope);
    }
    final top = metrics.take(4).toList(growable: false);
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
              Text(
                scope.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: BillyTheme.gray500,
                ),
              ),
              const Spacer(),
              if (metrics.length > top.length)
                GestureDetector(
                  onTap: () => _showFullMetrics(context, metrics),
                  child: Row(
                    children: [
                      Text(
                        'See all',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BillyTheme.emerald600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded,
                          size: 16, color: BillyTheme.emerald600),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < top.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: BillyTheme.gray100),
            _MetricRow(metric: top[i]),
          ],
        ],
      ),
    );
  }

  void _showFullMetrics(BuildContext context, List<GoatMetricView> metrics) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FullMetricsSheet(scope: scope, metrics: metrics),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final GoatMetricView metric;
  const _MetricRow({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.displayLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: BillyTheme.gray700,
                ),
              ),
              if (metric.confidenceBucket != null &&
                  metric.confidenceBucket != 'unknown')
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _confidenceLine(metric.confidenceBucket!),
                    style: const TextStyle(
                      fontSize: 11,
                      color: BillyTheme.gray400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _formatValue(metric),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: BillyTheme.gray800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  String _confidenceLine(String bucket) {
    switch (bucket) {
      case 'high':
        return 'Strong signal';
      case 'medium':
        return 'Moderate signal';
      case 'low':
        return 'Early signal';
      case 'very_low':
        return 'Weak signal';
      default:
        return '';
    }
  }

  String _formatValue(GoatMetricView m) {
    final v = m.value;
    if (v == null) return '—';
    if (v is num) {
      final unit = m.unit;
      if (unit == 'percent' || unit == '%') {
        return '${(v * (v.abs() <= 1 ? 100 : 1)).toStringAsFixed(1)}%';
      }
      if (unit == 'days' || unit == 'd') {
        return '${v.round()}d';
      }
      if (unit == 'count') {
        return v.toInt().toString();
      }
      // money & generic numbers — show thousands-grouped, 0–2 decimals
      final abs = v.abs();
      if (abs >= 100) return v.toStringAsFixed(0);
      return v.toStringAsFixed(2);
    }
    return v.toString();
  }
}

class _FullMetricsSheet extends StatelessWidget {
  final GoatScope scope;
  final List<GoatMetricView> metrics;
  const _FullMetricsSheet({required this.scope, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: BillyTheme.gray200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${scope.label} details',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: BillyTheme.gray800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Everything we can see for this pillar right now.',
              style: TextStyle(fontSize: 13, color: BillyTheme.gray500),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: metrics.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 18, color: BillyTheme.gray100),
                itemBuilder: (_, i) => _MetricRow(metric: metrics[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyScope extends StatelessWidget {
  final GoatScope scope;
  const _EmptyScope({required this.scope});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: BillyTheme.gray100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.hourglass_empty_rounded,
                size: 16, color: BillyTheme.gray500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not enough for ${scope.label.toLowerCase()} yet',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: BillyTheme.gray800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Add a bit more data and this pillar lights up.',
                  style: TextStyle(
                    fontSize: 12,
                    color: BillyTheme.gray500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
