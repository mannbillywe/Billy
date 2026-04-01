import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';

/// Hero card using real aggregates (no placeholder balance).
class SpendHero extends StatelessWidget {
  const SpendHero({
    super.key,
    required this.weekSpend,
    required this.currencyCode,
    this.weeklyData = const [],
    this.lastWeekSpend = 0,
  });

  final double weekSpend;
  final String? currencyCode;
  final List<double> weeklyData;
  final double lastWeekSpend;

  @override
  Widget build(BuildContext context) {
    final formatted = AppCurrency.format(weekSpend, currencyCode);
    final changePct = lastWeekSpend > 0 ? (((weekSpend - lastWeekSpend) / lastWeekSpend) * 100).round().abs() : null;
    final isUp = weekSpend >= lastWeekSpend;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BillyTheme.emerald50, BillyTheme.emerald100.withValues(alpha: 0.5)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BillyTheme.emerald100),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This week',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: BillyTheme.emerald700.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatted,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF064E3B),
                ),
              ),
              if (changePct != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${isUp ? 'Up' : 'Down'} $changePct% vs last week',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isUp ? BillyTheme.red400 : BillyTheme.emerald600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  _LegendDot(color: BillyTheme.emerald500, label: '7-day spend trend'),
                ],
              ),
            ],
          ),
          if (weeklyData.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 60,
              child: Opacity(
                opacity: 0.5,
                child: _MiniAreaChart(data: weeklyData),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: BillyTheme.emerald700.withValues(alpha: 0.7))),
      ],
    );
  }
}

class _MiniAreaChart extends StatelessWidget {
  const _MiniAreaChart({required this.data});
  final List<double> data;

  @override
  Widget build(BuildContext context) {
    final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final maxY = data.reduce((a, b) => a > b ? a : b) * 1.3;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: BillyTheme.emerald500,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [BillyTheme.emerald500.withValues(alpha: 0.3), BillyTheme.emerald500.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
