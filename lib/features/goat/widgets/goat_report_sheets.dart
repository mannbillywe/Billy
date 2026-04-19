import 'package:flutter/material.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../analytics/widgets/trend_chart.dart';
import '../models/goat_models.dart';
import 'goat_chart_widgets.dart';

String _inferCurrencySnapshot(GoatSnapshot s) {
  for (final m in s.metrics) {
    if (m.unit != null && m.unit!.isNotEmpty) return m.unit!;
  }
  return 'INR';
}

String _forecastTitle(String key) {
  switch (key) {
    case 'short_horizon_spend_7d':
      return 'Spending · next 7 days';
    case 'short_horizon_spend_30d':
      return 'Spending · next 30 days';
    case 'end_of_month_liquidity':
      return 'End-of-month liquidity';
    case 'budget_overrun_trajectory':
      return 'Budget pace';
    case 'emergency_fund_depletion_horizon':
      return 'Emergency fund runway';
    case 'goal_completion_trajectory':
      return 'Goal completion';
    default:
      return key.replaceAll('_', ' ');
  }
}

String _fmtMetricValue(GoatMetric m) {
  final v = m.value;
  if (v is num) {
    if (m.unit != null &&
        (m.unit!.toUpperCase() == 'INR' ||
            m.unit!.toUpperCase() == 'USD' ||
            m.unit!.length == 3)) {
      return AppCurrency.format(v.toDouble(), m.unit);
    }
    if (m.key.contains('rate') || m.unit == '%') {
      return '${(v.toDouble() * 100).round()}%';
    }
    return v.toString();
  }
  return v?.toString() ?? '—';
}

/// Full-screen style report for one forecast target.
Future<void> showGoatForecastReportSheet(
  BuildContext context, {
  required GoatSnapshot snapshot,
  required GoatForecastTarget target,
}) async {
  final currency = _inferCurrencySnapshot(snapshot);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollCtrl) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: BillyTheme.scaffoldBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: CustomScrollView(
            controller: scrollCtrl,
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 12),
                    decoration: BoxDecoration(
                      color: BillyTheme.gray300,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _forecastTitle(target.target),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: BillyTheme.gray800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (target.entityLabel != null &&
                          target.entityLabel!.isNotEmpty)
                        Text(
                          target.entityLabel!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: BillyTheme.gray500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (target.horizonDays != null)
                            _chip(
                              '${target.horizonDays}d horizon',
                              Icons.schedule,
                            ),
                          if (target.modelUsed != null)
                            _chip(
                              target.modelUsed!.replaceAll('_', ' '),
                              Icons.model_training_rounded,
                            ),
                          _chip(target.status, Icons.flag_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (target.hasChartableSeries)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: BillyTheme.gray100),
                      ),
                      child: GoatForecastSeriesChart(
                        points: target.seriesPoints,
                        currencyCode: currency,
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _percentileSummary(target, currency),
                ),
              ),
              if (target.reasonCodes.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    child: _bulletBlock('Notes', target.reasonCodes),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

Widget _chip(String text, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: BillyTheme.gray100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: BillyTheme.gray500),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: BillyTheme.gray700,
          ),
        ),
      ],
    ),
  );
}

Widget _percentileSummary(GoatForecastTarget t, String currency) {
  final p10 = t.p10;
  final p50 = t.p50;
  final p90 = t.p90;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BillyTheme.gray100),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Range',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: BillyTheme.gray800,
          ),
        ),
        const SizedBox(height: 10),
        if (p50 != null)
          Text(
            AppCurrency.format(p50, currency),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
              letterSpacing: -0.5,
            ),
          ),
        if (p10 != null && p90 != null) ...[
          const SizedBox(height: 6),
          Text(
            '${AppCurrency.format(p10, currency)} – ${AppCurrency.format(p90, currency)}',
            style: const TextStyle(
              fontSize: 14,
              color: BillyTheme.gray500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _bulletBlock(String title, List<String> lines) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: BillyTheme.gray800,
        ),
      ),
      const SizedBox(height: 8),
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '•  ',
                style: TextStyle(
                  fontSize: 13,
                  color: BillyTheme.emerald600,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Expanded(
                child: Text(
                  line,
                  style: const TextStyle(
                    fontSize: 13,
                    color: BillyTheme.gray600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Report for one headline metric + optional backend chart (`metric:<key>` id).
Future<void> showGoatMetricReportSheet(
  BuildContext context, {
  required GoatSnapshot snapshot,
  required GoatMetric metric,
  required String label,
}) async {
  final currency = _inferCurrencySnapshot(snapshot);
  final ts = snapshot.charts?.timeseriesById('metric:${metric.key}');

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollCtrl) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: BillyTheme.scaffoldBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BillyTheme.gray300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                metric.reportTitle ?? label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: BillyTheme.gray800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _fmtMetricValue(metric),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: BillyTheme.emerald700,
                  letterSpacing: -0.8,
                ),
              ),
              if (metric.reportSummary != null &&
                  metric.reportSummary!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  metric.reportSummary!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: BillyTheme.gray600,
                    height: 1.45,
                  ),
                ),
              ],
              if (ts != null && ts.points.length >= 2) ...[
                const SizedBox(height: 20),
                Text(
                  ts.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
                const SizedBox(height: 10),
                TrendChart(data: ts.points, currencyCode: ts.unit ?? currency),
              ],
              if (metric.inputsUsed.isNotEmpty ||
                  metric.inputsMissing.isNotEmpty) ...[
                const SizedBox(height: 20),
                if (metric.inputsUsed.isNotEmpty)
                  _bulletBlock('Data used', metric.inputsUsed),
                if (metric.inputsMissing.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _bulletBlock(
                    'Missing for higher confidence',
                    metric.inputsMissing,
                  ),
                ],
              ],
              if (metric.reasonCodes.isNotEmpty) ...[
                const SizedBox(height: 16),
                _bulletBlock('Reason codes', metric.reasonCodes),
              ],
            ],
          ),
        );
      },
    ),
  );
}
