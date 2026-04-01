import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../core/utils/document_date_range.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/profile_provider.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String _dateFilter = '1M';

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;
    final docs = docsAsync.valueOrNull ?? [];

    final range = DocumentDateRange.forFilter(_dateFilter);
    final filtered = DocumentDateRange.filterDocuments(docs, range);

    double totalExpenses = 0;
    final catMap = <String, double>{};
    for (final d in filtered) {
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      final desc = (d['description'] as String?)?.split(',').first.trim() ?? 'Other';
      totalExpenses += amount;
      catMap[desc] = (catMap[desc] ?? 0) + amount;
    }
    final sortedCats = catMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final topCategory = sortedCats.isNotEmpty ? sortedCats.first : null;
    final topPct = topCategory != null && totalExpenses > 0
        ? ((topCategory.value / totalExpenses) * 100).round()
        : 0;

    final barData = DocumentDateRange.lastSevenDaySpending(filtered, range.end);
    final avgSpend = barData.isNotEmpty ? barData.reduce((a, b) => a + b) / barData.length : 0.0;

    return SingleChildScrollView(
      key: const ValueKey('analytics'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Analytics', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
              Row(
                children: [
                  _CircleButton(icon: Icons.notifications_outlined, onPressed: () {}),
                  const SizedBox(width: 8),
                  _CircleButton(icon: Icons.settings_outlined, onPressed: () {}),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Range: ${_labelForFilter(_dateFilter)}',
            style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
          ),
          const SizedBox(height: 12),
          _DateFilterBar(selected: _dateFilter, onChanged: (v) => setState(() => _dateFilter = v)),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ExpenseBreakdown(
                  topCategory: topCategory?.key ?? '—',
                  topPct: topPct,
                  totalExpenses: totalExpenses,
                  currencyCode: currency,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TopCategoriesBarChart(
                  data: barData,
                  totalSpent: totalExpenses,
                  avgSpend: avgSpend,
                  currencyCode: currency,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _TopCategoriesList(categories: sortedCats, totalExpenses: totalExpenses, currencyCode: currency),
        ],
      ),
    );
  }

  static String _labelForFilter(String key) {
    switch (key) {
      case '1W':
        return 'Last 7 days';
      case '3M':
        return 'Last 3 months';
      case '1M':
      default:
        return 'Last month';
    }
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: BillyTheme.gray600),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        side: BorderSide(color: BillyTheme.gray100),
      ),
    );
  }
}

class _DateFilterBar extends StatelessWidget {
  const _DateFilterBar({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BillyTheme.gray50),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
      ),
      child: Row(
        children: ['1W', '1M', '3M'].map((f) {
          final isActive = selected == f;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(f),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? BillyTheme.emerald50 : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isActive ? BillyTheme.emerald700 : BillyTheme.gray500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ExpenseBreakdown extends StatelessWidget {
  const _ExpenseBreakdown({
    required this.topCategory,
    required this.topPct,
    required this.totalExpenses,
    this.currencyCode,
  });
  final String topCategory;
  final int topPct;
  final double totalExpenses;
  final String? currencyCode;

  @override
  Widget build(BuildContext context) {
    final rest = (100 - topPct).clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BillyTheme.gray50),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Expense breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
          const SizedBox(height: 2),
          const Text('Selected range', style: TextStyle(fontSize: 12, color: BillyTheme.gray500)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: [
                      if (totalExpenses > 0) ...[
                        PieChartSectionData(value: topPct.toDouble(), color: BillyTheme.green400, radius: 16, showTitle: false),
                        PieChartSectionData(value: rest.toDouble(), color: BillyTheme.gray100, radius: 16, showTitle: false),
                      ] else
                        PieChartSectionData(value: 100, color: BillyTheme.gray100, radius: 16, showTitle: false),
                    ],
                    centerSpaceRadius: 35,
                    sectionsSpace: 0,
                    startDegreeOffset: -90,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppCurrency.format(totalExpenses, currencyCode),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                    ),
                    Text(topCategory, style: const TextStyle(fontSize: 10, color: BillyTheme.gray500)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: BillyTheme.green400, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('$topCategory $topPct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: BillyTheme.gray600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopCategoriesBarChart extends StatelessWidget {
  const _TopCategoriesBarChart({
    required this.data,
    required this.totalSpent,
    required this.avgSpend,
    this.currencyCode,
  });
  final List<double> data;
  final double totalSpent;
  final double avgSpend;
  final String? currencyCode;

  @override
  Widget build(BuildContext context) {
    final maxY = data.isNotEmpty ? data.reduce((a, b) => a > b ? a : b) * 1.2 : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BillyTheme.gray50),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Daily spend (7 days)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: data.every((e) => e == 0)
                ? const Center(child: Text('No data in range', style: TextStyle(fontSize: 11, color: BillyTheme.gray400)))
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      barTouchData: BarTouchData(enabled: false),
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barGroups: data.asMap().entries.map((e) {
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: e.value,
                              color: BillyTheme.green400.withValues(alpha: 0.6),
                              width: 12,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Spent', style: TextStyle(fontSize: 10, color: BillyTheme.gray500)),
                    Text(
                      AppCurrency.format(totalSpent, currencyCode),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Avg / day', style: TextStyle(fontSize: 10, color: BillyTheme.gray500)),
                    Text(
                      AppCurrency.format(avgSpend, currencyCode),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopCategoriesList extends StatelessWidget {
  const _TopCategoriesList({
    required this.categories,
    required this.totalExpenses,
    this.currencyCode,
  });
  final List<MapEntry<String, double>> categories;
  final double totalExpenses;
  final String? currencyCode;

  static const _icons = ['🛍️', '🍔', '⚡', '🚗', '🎬', '💊'];
  static const _colors = [
    BillyTheme.green400,
    BillyTheme.red400,
    BillyTheme.yellow400,
    BillyTheme.blue400,
    Color(0xFFA78BFA),
    Color(0xFFFB923C),
  ];

  @override
  Widget build(BuildContext context) {
    final items = categories.take(4).toList();
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: BillyTheme.gray50),
        ),
        child: const Text('No categories in this range', style: TextStyle(color: BillyTheme.gray500)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BillyTheme.gray50),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Top categories', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
            ],
          ),
          const SizedBox(height: 20),
          ...items.asMap().entries.map((e) {
            final cat = e.value;
            final pct = totalExpenses > 0 ? ((cat.value / totalExpenses) * 100).round() : 0;
            final icon = _icons[e.key % _icons.length];
            final color = _colors[e.key % _colors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: BillyTheme.gray50, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: Text(icon, style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(cat.key, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800)),
                            Text(
                              AppCurrency.format(cat.value, currencyCode),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(color: BillyTheme.gray100, borderRadius: BorderRadius.circular(3)),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: pct / 100,
                                  child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 30,
                              child: Text('$pct%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
