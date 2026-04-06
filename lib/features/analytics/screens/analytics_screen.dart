import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../core/utils/document_date_range.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/week_spend_basis_provider.dart';
import '../../documents/screens/documents_history_screen.dart';
import '../widgets/ai_insights_panel.dart';

/// Category bucket for Analytics Overview (must match aggregation and drill-down).
String analyticsCategoryBucket(Map<String, dynamic> d) {
  final parts = (d['description'] as String?)?.split(',');
  final first = parts != null && parts.isNotEmpty ? parts.first.trim() : '';
  return first.isNotEmpty ? first : 'Other';
}

String _analyticsBasisCaption(WeekSpendBasis basis) {
  switch (basis) {
    case WeekSpendBasis.uploadDate:
      return 'Overview uses save (upload) time inside the range.';
    case WeekSpendBasis.invoiceDate:
      return 'Overview uses bill / receipt date inside the range.';
    case WeekSpendBasis.hybrid:
      return 'Overview includes a document if bill date or save date is in range.';
  }
}

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String _dateFilter = '1M';
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;
    final docs = docsAsync.valueOrNull ?? [];
    final weekBasis = ref.watch(weekSpendBasisProvider);

    final range = DocumentDateRange.forFilter(_dateFilter);
    final filtered = DocumentDateRange.filterDocumentsForWeekBasis(docs, range, weekBasis);

    double totalExpenses = 0;
    final catMap = <String, double>{};
    final categoryDocIds = <String, Set<String>>{};
    for (final d in filtered) {
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      final bucket = analyticsCategoryBucket(d);
      totalExpenses += amount;
      catMap[bucket] = (catMap[bucket] ?? 0) + amount;
      final id = d['id'] as String?;
      if (id != null && id.isNotEmpty) {
        categoryDocIds.putIfAbsent(bucket, () => <String>{}).add(id);
      }
    }
    final sortedCats = catMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final topCategory = sortedCats.isNotEmpty ? sortedCats.first : null;
    final topPct = topCategory != null && totalExpenses > 0
        ? ((topCategory.value / totalExpenses) * 100).round()
        : 0;

    final barData = DocumentDateRange.lastSevenDaySpendingByBasis(filtered, range.end, weekBasis);
    final avgSpend = barData.isNotEmpty ? barData.reduce((a, b) => a + b) / barData.length : 0.0;

    return SingleChildScrollView(
      key: const ValueKey('analytics'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Analytics', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
          const SizedBox(height: 8),
          Text(
            'Range: ${_labelForFilter(_dateFilter)}',
            style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
          ),
          const SizedBox(height: 4),
          Text(
            _analyticsBasisCaption(weekBasis),
            style: const TextStyle(fontSize: 11, color: BillyTheme.gray500),
          ),
          const SizedBox(height: 12),
          _DateFilterBar(selected: _dateFilter, onChanged: (v) => setState(() => _dateFilter = v)),
          const SizedBox(height: 10),
          SegmentedButton<WeekSpendBasis>(
            segments: const [
              ButtonSegment<WeekSpendBasis>(
                value: WeekSpendBasis.uploadDate,
                label: Text('Upload date'),
                icon: Icon(Icons.cloud_upload_outlined, size: 16),
              ),
              ButtonSegment<WeekSpendBasis>(
                value: WeekSpendBasis.invoiceDate,
                label: Text('Bill date'),
                icon: Icon(Icons.receipt_long_outlined, size: 16),
              ),
              ButtonSegment<WeekSpendBasis>(
                value: WeekSpendBasis.hybrid,
                label: Text('Either'),
                icon: Icon(Icons.merge_type_outlined, size: 16),
              ),
            ],
            selected: {weekBasis},
            onSelectionChanged: (next) {
              ref.read(weekSpendBasisProvider.notifier).setBasis(next.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return BillyTheme.emerald700;
                return BillyTheme.gray600;
              }),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                label: Text('Overview'),
                icon: Icon(Icons.insights_outlined, size: 18),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('AI Insights'),
                icon: Icon(Icons.auto_awesome_outlined, size: 18),
              ),
            ],
            selected: {_segment},
            onSelectionChanged: (Set<int> next) {
              setState(() => _segment = next.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return BillyTheme.emerald700;
                return BillyTheme.gray600;
              }),
            ),
          ),
          const SizedBox(height: 20),
          if (_segment == 0) ...[
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
            _TopCategoriesList(
              categories: sortedCats,
              totalExpenses: totalExpenses,
              currencyCode: currency,
              categoryDocumentIds: categoryDocIds,
            ),
          ] else
            AiInsightsPanel(rangePreset: _dateFilter),
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
    required this.categoryDocumentIds,
    this.currencyCode,
  });
  final List<MapEntry<String, double>> categories;
  final double totalExpenses;
  final String? currencyCode;
  /// Same keys as [categories] — document ids in that bucket for drill-down.
  final Map<String, Set<String>> categoryDocumentIds;

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
          const SizedBox(height: 4),
          Text(
            'Tap a row to open bills in that category',
            style: TextStyle(fontSize: 11, color: BillyTheme.gray500.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 16),
          ...items.asMap().entries.map((e) {
            final cat = e.value;
            final pct = totalExpenses > 0 ? ((cat.value / totalExpenses) * 100).round() : 0;
            final icon = _icons[e.key % _icons.length];
            final color = _colors[e.key % _colors.length];
            final ids = categoryDocumentIds[cat.key];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: ids == null || ids.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DocumentsHistoryScreen(
                                restrictToDocumentIds: ids,
                                restrictContextTitle: cat.key,
                              ),
                            ),
                          );
                        },
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
                                  Expanded(
                                    child: Text(
                                      cat.key,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: BillyTheme.gray800),
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        AppCurrency.format(cat.value, currencyCode),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                                      ),
                                      if (ids != null && ids.isNotEmpty) ...[
                                        const SizedBox(width: 4),
                                        Icon(Icons.chevron_right, size: 18, color: BillyTheme.gray400),
                                      ],
                                    ],
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
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
