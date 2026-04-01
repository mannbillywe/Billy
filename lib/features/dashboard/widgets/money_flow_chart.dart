import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

class MoneyFlowChart extends StatelessWidget {
  const MoneyFlowChart({super.key, this.data = const []});

  final List<double> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Money Flow',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            height: 140,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BillyTheme.gray50),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: const Text(
              'No spending in the last 7 days',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: BillyTheme.gray500),
            ),
          ),
        ],
      );
    }

    final chartData = data;
    final spots = chartData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final maxY = chartData.reduce((a, b) => a > b ? a : b) * 1.3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Money Flow',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray50),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    minX: 0,
                    maxX: (chartData.length - 1).toDouble(),
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
                            colors: [BillyTheme.emerald500.withValues(alpha: 0.2), BillyTheme.emerald500.withValues(alpha: 0)],
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: const LineTouchData(enabled: false),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Dot(color: BillyTheme.emerald500, label: 'Daily spend'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: BillyTheme.gray500)),
      ],
    );
  }
}
