import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';

class InsightsCard extends StatelessWidget {
  const InsightsCard({
    super.key,
    required this.totalExpenses,
    required this.categories,
    this.allCategories,
    this.currencyCode,
    this.docs,
    this.onOpenDocumentDetail,
  });

  final double totalExpenses;
  /// Top 4 for the mini donut on dashboard.
  final List<(String, double)> categories;
  /// Full sorted list for the breakdown sheet.
  final List<(String, double)>? allCategories;
  final String? currencyCode;
  /// All non-draft documents so we can drill into per-category lists.
  final List<Map<String, dynamic>>? docs;
  final void Function(String documentId)? onOpenDocumentDetail;

  static const _colors = [
    BillyTheme.green400,
    BillyTheme.blue400,
    BillyTheme.yellow400,
    BillyTheme.red400,
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF97316),
    Color(0xFF06B6D4),
  ];

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty || totalExpenses <= 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Categories', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BillyTheme.gray50),
            ),
            child: const Text('Add expenses to see categories', style: TextStyle(fontSize: 13, color: BillyTheme.gray500)),
          ),
        ],
      );
    }

    final pieData = categories.asMap().entries.map((e) {
      return PieChartSectionData(
        value: e.value.$2 * 100,
        color: _colors[e.key % _colors.length],
        radius: 16,
        showTitle: false,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Categories', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => _showBreakdown(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: BillyTheme.gray50),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 90,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(PieChartData(
                          sections: pieData,
                          centerSpaceRadius: 24,
                          sectionsSpace: 2,
                          startDegreeOffset: -90,
                        )),
                        Text(
                          AppCurrency.formatCompact(totalExpenses, currencyCode),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap for details', style: TextStyle(fontSize: 10, color: BillyTheme.gray400)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Breakdown sheet ─────────────────────────────────────────────────────

  void _showBreakdown(BuildContext context) {
    final cats = allCategories ?? categories;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text('Spending breakdown', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
              const SizedBox(height: 4),
              Text('Total: ${AppCurrency.format(totalExpenses, currencyCode)}', style: const TextStyle(fontSize: 14, color: BillyTheme.gray500)),
              const SizedBox(height: 20),
              SizedBox(
                height: 130,
                child: PieChart(PieChartData(
                  sections: cats.asMap().entries.map((e) {
                    return PieChartSectionData(
                      value: e.value.$2 * 100,
                      color: _colors[e.key % _colors.length],
                      radius: 22,
                      showTitle: false,
                    );
                  }).toList(),
                  centerSpaceRadius: 34,
                  sectionsSpace: 3,
                  startDegreeOffset: -90,
                )),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: cats.length,
                  itemBuilder: (ctx2, i) {
                    final (name, pct) = cats[i];
                    final color = _colors[i % _colors.length];
                    final amount = totalExpenses * pct;
                    return _CategoryRow(
                      name: name,
                      amount: amount,
                      pct: pct,
                      color: color,
                      currencyCode: currencyCode,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCategoryDetail(context, name, color);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Per-category detail ────────────────────────────────────────────────

  void _showCategoryDetail(BuildContext context, String categoryName, Color color) {
    final allDocs = docs ?? [];
    final catDocs = allDocs.where((d) {
      final desc = (d['description'] as String?)?.split(',').first.trim() ?? 'Other';
      return desc == categoryName;
    }).toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['date']?.toString() ?? '');
        final db = DateTime.tryParse(b['date']?.toString() ?? '');
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    double catTotal = 0;
    for (final d in catDocs) {
      catTotal += (d['amount'] as num?)?.toDouble() ?? 0;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(categoryName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
                        Text(
                          '${catDocs.length} ${catDocs.length == 1 ? 'transaction' : 'transactions'} · ${AppCurrency.format(catTotal, currencyCode)}',
                          style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Percentage of total
              if (totalExpenses > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (catTotal / totalExpenses).clamp(0.0, 1.0),
                    backgroundColor: BillyTheme.gray200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${((catTotal / totalExpenses) * 100).toStringAsFixed(1)}% of total spending',
                  style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Transactions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray700)),
              const SizedBox(height: 8),
              Expanded(
                child: catDocs.isEmpty
                    ? const Center(child: Text('No transactions', style: TextStyle(color: BillyTheme.gray400)))
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: catDocs.length,
                        itemBuilder: (ctx2, i) {
                          final d = catDocs[i];
                          final vendor = d['vendor_name'] as String? ?? 'Unknown';
                          final amount = (d['amount'] as num?)?.toDouble() ?? 0;
                          final dateStr = d['date'] as String? ?? '';
                          final docId = d['id'] as String?;
                          final type = d['type'] as String? ?? '';

                          String formattedDate = dateStr;
                          try {
                            final dt = DateTime.parse(dateStr);
                            formattedDate = DateFormat('dd MMM yyyy').format(dt);
                          } catch (_) {}

                          final tappable = onOpenDocumentDetail != null && docId != null && docId.isNotEmpty;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: BillyTheme.gray50,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: tappable
                                    ? () {
                                        Navigator.pop(ctx);
                                        onOpenDocumentDetail!(docId);
                                      }
                                    : null,
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          vendor.isNotEmpty ? vendor[0].toUpperCase() : '?',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(vendor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BillyTheme.gray800), overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Text(formattedDate, style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                                                if (type.isNotEmpty) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                    decoration: BoxDecoration(color: BillyTheme.gray200, borderRadius: BorderRadius.circular(6)),
                                                    child: Text(
                                                      type[0].toUpperCase() + type.substring(1),
                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: BillyTheme.gray500),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        AppCurrency.format(amount, currencyCode),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                                      ),
                                      if (tappable) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.chevron_right_rounded, size: 18, color: BillyTheme.gray300),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // Back to breakdown button
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showBreakdown(context);
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to all categories'),
                  style: TextButton.styleFrom(foregroundColor: BillyTheme.emerald600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.name,
    required this.amount,
    required this.pct,
    required this.color,
    required this.currencyCode,
    required this.onTap,
  });
  final String name;
  final double amount;
  final double pct;
  final Color color;
  final String? currencyCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: BillyTheme.gray50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          backgroundColor: BillyTheme.gray200,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(AppCurrency.format(amount, currencyCode), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                    Text('${(pct * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18, color: BillyTheme.gray300),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
