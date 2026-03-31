import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';

class InsightsCard extends StatelessWidget {
  const InsightsCard({
    super.key,
    required this.totalExpenses,
    required this.categories,
  });

  final double totalExpenses;
  final List<(String, double)> categories;

  static const _categoryColors = [
    BillyTheme.green400,
    BillyTheme.blue400,
    BillyTheme.yellow400,
    BillyTheme.red400,
  ];

  @override
  Widget build(BuildContext context) {
    final pieData = categories.asMap().entries.map((e) {
      return PieChartSectionData(
        value: e.value.$2 * 100,
        color: _categoryColors[e.key % _categoryColors.length],
        radius: 16,
        showTitle: false,
      );
    }).toList();

    if (pieData.isEmpty) {
      pieData.add(PieChartSectionData(value: 100, color: BillyTheme.gray200, radius: 16, showTitle: false));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Monthly Spending',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
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
              SizedBox(
                height: 100,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sections: pieData,
                        centerSpaceRadius: 28,
                        sectionsSpace: 2,
                        startDegreeOffset: -90,
                      ),
                    ),
                    Text(
                      '\$${totalExpenses.toInt()}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: categories.asMap().entries.map((e) {
                  final color = _categoryColors[e.key % _categoryColors.length];
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(
                        e.value.$1,
                        style: const TextStyle(fontSize: 10, color: BillyTheme.gray600),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
