import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';

String coveragePillarLabel(String key) {
  switch (key) {
    case 'transactions':
      return 'Spend';
    case 'accounts':
      return 'Accounts';
    case 'budgets':
      return 'Budgets';
    case 'recurring':
      return 'Recurring';
    case 'income_declared':
      return 'Income';
    case 'goals':
      return 'Goals';
    case 'obligations':
      return 'Debts';
    default:
      return key.replaceAll('_', ' ');
  }
}

/// Horizontal bar chart for `coverage_json.breakdown` (0–1 weights).
class GoatCoveragePillarChart extends StatelessWidget {
  const GoatCoveragePillarChart({super.key, required this.coverage});

  final GoatCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final entries = coverage.breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();

    final maxV = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final capY = maxV <= 0 ? 1.0 : maxV * 1.08;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: BillyTheme.gray100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.hub_rounded, size: 18, color: BillyTheme.gray500),
                SizedBox(width: 8),
                Text(
                  'Data mix',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'How complete each signal is (higher = richer analysis).',
              style: TextStyle(
                fontSize: 11.5,
                color: BillyTheme.gray500,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: (entries.length * 28.0).clamp(120.0, 220.0),
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: capY,
                  minY: 0,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 0.25,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: BillyTheme.gray100, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: 0.25,
                        getTitlesWidget: (v, _) => Text(
                          '${(v * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: BillyTheme.gray400,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= entries.length) {
                            return const SizedBox();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              coveragePillarLabel(entries[i].key),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: BillyTheme.gray600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < entries.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: entries[i].value,
                            width: 14,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                BillyTheme.emerald500.withValues(alpha: 0.35),
                                BillyTheme.emerald600,
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Line chart for forecast `series.points` (p50 primary; p10–p90 band when present).
class GoatForecastSeriesChart extends StatelessWidget {
  const GoatForecastSeriesChart({
    super.key,
    required this.points,
    required this.currencyCode,
  });

  final List<GoatForecastSeriesPoint> points;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final pairs = <(String label, double y)>[];
    for (var i = 0; i < points.length; i++) {
      final p50 = points[i].p50;
      if (p50 == null) continue;
      final d = points[i].date;
      final label = d == null
          ? '·'
          : '${d.month.toString().padLeft(2, '0')}/${d.day}';
      pairs.add((label, p50));
    }
    if (pairs.length < 2) return const SizedBox.shrink();

    final spots = pairs
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.$2))
        .toList();

    final ys = pairs.map((p) => p.$2).toList();
    var minY = ys.reduce((a, b) => a < b ? a : b);
    var maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY).abs() * 0.12;
    if (pad == 0) {
      minY -= 1;
      maxY += 1;
    } else {
      minY -= pad;
      maxY += pad;
    }

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: BillyTheme.gray100, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) => Text(
                  AppCurrency.formatCompact(v.toDouble(), currencyCode),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: BillyTheme.gray400,
                  ),
                ),
              ),
            ),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= pairs.length) return const SizedBox();
                  return Text(
                    pairs[i].$1,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: BillyTheme.gray400,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: BillyTheme.emerald600,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    BillyTheme.emerald500.withValues(alpha: 0.2),
                    BillyTheme.emerald500.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) {
                return touched.map((t) {
                  return LineTooltipItem(
                    AppCurrency.format(t.y, currencyCode),
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
              tooltipRoundedRadius: 10,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders a backend-provided bar group from `summary_json.charts.bars[]`.
class GoatBackendBarChart extends StatelessWidget {
  const GoatBackendBarChart({
    super.key,
    required this.title,
    required this.items,
    required this.currencyCode,
  });

  final String title;
  final List<(String label, double value)> items;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final maxY = items.map((e) => e.$2).reduce((a, b) => a > b ? a : b) * 1.15;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY <= 0 ? 1 : maxY,
                minY: 0,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, _) => Text(
                        AppCurrency.formatCompact(v.toDouble(), currencyCode),
                        style: const TextStyle(
                          fontSize: 9,
                          color: BillyTheme.gray400,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= items.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            items[i].$1,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: BillyTheme.gray600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                ),
                barGroups: [
                  for (var i = 0; i < items.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: items[i].$2,
                          width: 18,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                          color: BillyTheme.emerald600,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
