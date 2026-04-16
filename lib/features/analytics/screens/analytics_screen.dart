import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../core/utils/document_date_range.dart';
import '../../../providers/budgets_provider.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/lend_borrow_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/recurring_provider.dart';
import '../../../providers/week_spend_basis_provider.dart';
import '../../documents/screens/documents_history_screen.dart';
import '../widgets/ai_insights_panel.dart';

String _categoryBucket(Map<String, dynamic> d) {
  final parts = (d['description'] as String?)?.split(',');
  final first = parts != null && parts.isNotEmpty ? parts.first.trim() : '';
  return first.isNotEmpty ? first : 'Other';
}

String analyticsCategoryBucket(Map<String, dynamic> d) => _categoryBucket(d);

/// Resolves a budget's effective category name by checking the joined
/// `categories(name)` relation first, falling back to the budget's own `name`.
String _budgetCategoryName(Map<String, dynamic> b) {
  final joined = b['categories'];
  if (joined is Map && joined['name'] is String) return joined['name'] as String;
  return b['name'] as String? ?? 'Other';
}

/// Matches a document's spend to a budget using `category_id` first,
/// falling back to description-based name matching.
double _matchSpendToBudget(
  Map<String, dynamic> budget,
  Map<String, double> catSpendByName,
  Map<String, double> catSpendByCatId,
) {
  final budgetCatId = budget['category_id'] as String?;
  if (budgetCatId != null && catSpendByCatId.containsKey(budgetCatId)) {
    return catSpendByCatId[budgetCatId]!;
  }
  final name = _budgetCategoryName(budget);
  return catSpendByName[name] ?? catSpendByName[name.toLowerCase()] ?? 0;
}

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String _range = '1M';
  bool _showAi = false;

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;
    final docs = docsAsync.valueOrNull ?? [];
    final weekBasis = ref.watch(weekSpendBasisProvider);
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? [];
    final recurring = ref.watch(recurringSeriesProvider).valueOrNull ?? [];
    final lbEntries = ref.watch(lendBorrowProvider).valueOrNull ?? [];
    final uid = Supabase.instance.client.auth.currentUser?.id;

    final range = DocumentDateRange.forFilter(_range);
    final filtered = DocumentDateRange.filterDocumentsForWeekBasis(docs, range, weekBasis);

    // ── Compute all deterministic analytics from loaded data ──
    double totalExpenses = 0;
    double totalTax = 0;
    int docCount = 0;
    final catMap = <String, double>{};
    final catDocIds = <String, Set<String>>{};
    final merchantMap = <String, double>{};
    final merchantCount = <String, int>{};
    final dailyMap = <String, double>{};

    for (final d in filtered) {
      if ((d['status'] as String?) == 'draft') continue;
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      final tax = (d['tax_amount'] as num?)?.toDouble() ?? 0;
      totalExpenses += amount;
      totalTax += tax;
      docCount++;

      final cat = _categoryBucket(d);
      catMap[cat] = (catMap[cat] ?? 0) + amount;
      final id = d['id'] as String?;
      if (id != null) catDocIds.putIfAbsent(cat, () => <String>{}).add(id);

      final vendor = (d['vendor_name'] as String?)?.trim() ?? 'Unknown';
      merchantMap[vendor] = (merchantMap[vendor] ?? 0) + amount;
      merchantCount[vendor] = (merchantCount[vendor] ?? 0) + 1;

      final dateStr = d['date']?.toString().substring(0, 10);
      if (dateStr != null) dailyMap[dateStr] = (dailyMap[dateStr] ?? 0) + amount;
    }

    final sortedCats = catMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final sortedMerchants = merchantMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // ── Previous period comparison (per-category) ──
    // Use the exact same range length for a fair comparison
    final rangeDays = range.end.difference(range.start).inDays.clamp(1, 365);
    final prevEnd = range.start.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: rangeDays - 1));
    final prevRange = DocumentDateRange(prevStart, prevEnd);
    final prevFiltered = DocumentDateRange.filterDocumentsForWeekBasis(docs, prevRange, weekBasis);
    double prevTotal = 0;
    final prevCatMap = <String, double>{};
    for (final d in prevFiltered) {
      if ((d['status'] as String?) == 'draft') continue;
      final amt = (d['amount'] as num?)?.toDouble() ?? 0;
      prevTotal += amt;
      final cat = _categoryBucket(d);
      prevCatMap[cat] = (prevCatMap[cat] ?? 0) + amt;
    }
    final changePct = prevTotal > 0 ? ((totalExpenses - prevTotal) / prevTotal * 100).round() : null;

    // Daily spend data for bar chart
    final barData = <double>[];
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final dayStr = now.subtract(Duration(days: i)).toIso8601String().substring(0, 10);
      barData.add(dailyMap[dayStr] ?? 0);
    }
    final avgDaily = docCount > 0 && totalExpenses > 0
        ? totalExpenses / (range.end.difference(range.start).inDays.clamp(1, 365))
        : 0.0;

    // Projected month-end
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayOfMonth = now.day;
    final projected = avgDaily * daysInMonth;

    // ── Budget vs actual (matches by category_id + name) ──
    double budgetTotal = 0;
    double budgetSpent = 0;
    final monthStart = DateTime(now.year, now.month, 1);
    final monthDocs = docs.where((d) {
      final dt = DateTime.tryParse(d['date']?.toString() ?? '');
      return dt != null && !dt.isBefore(monthStart) && (d['status'] as String?) != 'draft';
    }).toList();
    final catSpendByName = <String, double>{};
    final catSpendByCatId = <String, double>{};
    for (final d in monthDocs) {
      final desc = (d['description'] as String?)?.split(',').first.trim() ?? 'Other';
      final amt = (d['amount'] as num?)?.toDouble() ?? 0;
      catSpendByName[desc] = (catSpendByName[desc] ?? 0) + amt;
      final catId = d['category_id'] as String?;
      if (catId != null) {
        catSpendByCatId[catId] = (catSpendByCatId[catId] ?? 0) + amt;
      }
    }

    final budgetDetails = <_BudgetLine>[];
    for (final b in budgets) {
      final limit = (b['amount'] as num?)?.toDouble() ?? 0;
      final spent = _matchSpendToBudget(b, catSpendByName, catSpendByCatId);
      budgetTotal += limit;
      budgetSpent += spent;
      budgetDetails.add(_BudgetLine(name: _budgetCategoryName(b), limit: limit, spent: spent));
    }

    // Lend/borrow outstanding
    double lentOut = 0, borrowedOwed = 0;
    for (final lb in lbEntries) {
      if ((lb['status'] as String?) != 'pending') continue;
      final amt = (lb['amount'] as num?)?.toDouble() ?? 0;
      final type = lb['type'] as String?;
      final creator = lb['user_id'] as String?;
      if (type == 'lent' && creator == uid) {
        lentOut += amt;
      } else if (type == 'borrowed' && creator == uid) {
        borrowedOwed += amt;
      }
    }

    // Upcoming recurring
    int upcomingBills = 0;
    for (final r in recurring) {
      final nd = r['next_due'] as String?;
      if (nd == null) continue;
      final due = DateTime.tryParse(nd);
      if (due == null) continue;
      if (due.difference(now).inDays <= 7) {
        upcomingBills++;
      }
    }

    // Spending spikes (days > 2x average)
    final spikeEntries = <MapEntry<String, double>>[];
    for (final entry in dailyMap.entries) {
      if (entry.value > avgDaily * 2 && avgDaily > 0) {
        spikeEntries.add(entry);
      }
    }
    spikeEntries.sort((a, b) => b.value.compareTo(a.value));

    // ── Savings suggestions ──
    final savingsTips = _computeSavingsTips(
      sortedCats: sortedCats,
      prevCatMap: prevCatMap,
      budgetDetails: budgetDetails,
      totalExpenses: totalExpenses,
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(documentsProvider);
        ref.invalidate(budgetsProvider);
        ref.invalidate(recurringSeriesProvider);
        ref.invalidate(lendBorrowProvider);
      },
      color: BillyTheme.emerald600,
      child: SingleChildScrollView(
        key: const ValueKey('analytics'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Insights', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: BillyTheme.gray800)),
                _RangePicker(selected: _range, onChanged: (v) => setState(() => _range = v)),
              ],
            ),
            const SizedBox(height: 16),

            // ── Period summary strip (1W / 1M / 3M) ──
            _PeriodSummaryStrip(docs: docs, currency: currency, weekBasis: weekBasis, activeRange: _range),
            const SizedBox(height: 16),

            // ── Spend hero card ──
            _SpendHeroCard(
              totalExpenses: totalExpenses,
              docCount: docCount,
              changePct: changePct,
              avgDaily: avgDaily,
              projected: projected,
              daysInMonth: daysInMonth,
              dayOfMonth: dayOfMonth,
              currency: currency,
              rangeLabel: _range,
            ),
            const SizedBox(height: 12),

            // ── Top categories for selected period ──
            if (sortedCats.isNotEmpty)
              _TopCategoriesForPeriod(
                categories: sortedCats.take(5).toList(),
                totalExpenses: totalExpenses,
                currency: currency,
                rangeLabel: _range,
              ),
            if (sortedCats.isNotEmpty) const SizedBox(height: 12),

            // ── Quick stat pills ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (totalTax > 0) _StatPill(icon: Icons.receipt_long_rounded, label: 'Tax', value: AppCurrency.formatCompact(totalTax, currency), color: const Color(0xFFF59E0B)),
                if (budgetTotal > 0) _StatPill(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Budget',
                  value: '${((budgetSpent / budgetTotal) * 100).round()}%',
                  color: budgetSpent > budgetTotal ? BillyTheme.red400 : BillyTheme.emerald600,
                ),
                if (upcomingBills > 0) _StatPill(icon: Icons.schedule_rounded, label: 'Due', value: '$upcomingBills bills', color: const Color(0xFF8B5CF6)),
                if (lentOut > 0) _StatPill(icon: Icons.arrow_upward_rounded, label: 'Lent', value: AppCurrency.formatCompact(lentOut, currency), color: BillyTheme.blue400),
                if (borrowedOwed > 0) _StatPill(icon: Icons.arrow_downward_rounded, label: 'Owe', value: AppCurrency.formatCompact(borrowedOwed, currency), color: BillyTheme.red400),
              ],
            ),
            const SizedBox(height: 16),

            // ── Savings suggestions (the new smart card) ──
            if (savingsTips.isNotEmpty)
              _SavingsSuggestionsCard(tips: savingsTips, currency: currency),
            if (savingsTips.isNotEmpty) const SizedBox(height: 12),

            // ── Daily spend trend ──
            _DailyTrendCard(data: barData, avgDaily: avgDaily, totalSpent: totalExpenses, currency: currency),
            const SizedBox(height: 12),

            // ── Category breakdown with full donut ──
            _CategoryBreakdownCard(
              categories: sortedCats,
              totalExpenses: totalExpenses,
              currency: currency,
              catDocIds: catDocIds,
              prevCatMap: prevCatMap,
              budgetDetails: budgetDetails,
            ),
            const SizedBox(height: 12),

            // ── Top merchants ──
            if (sortedMerchants.isNotEmpty)
              _TopMerchantsCard(merchants: sortedMerchants.take(6).toList(), merchantCount: merchantCount, currency: currency),
            if (sortedMerchants.isNotEmpty) const SizedBox(height: 12),

            // ── Budget vs actual ──
            if (budgetDetails.isNotEmpty)
              _BudgetVsActualCard(budgetDetails: budgetDetails, budgetTotal: budgetTotal, budgetSpent: budgetSpent, currency: currency),
            if (budgetDetails.isNotEmpty) const SizedBox(height: 12),

            // ── Spending spikes ──
            if (spikeEntries.isNotEmpty)
              _SpikesCard(spikes: spikeEntries.take(3).toList(), avgDaily: avgDaily, currency: currency),
            if (spikeEntries.isNotEmpty) const SizedBox(height: 12),

            // ── AI Insights toggle ──
            _AiInsightsToggle(
              isOpen: _showAi,
              onToggle: () => setState(() => _showAi = !_showAi),
            ),
            if (_showAi) ...[
              const SizedBox(height: 12),
              AiInsightsPanel(rangePreset: _range),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static List<_SavingTip> _computeSavingsTips({
    required List<MapEntry<String, double>> sortedCats,
    required Map<String, double> prevCatMap,
    required List<_BudgetLine> budgetDetails,
    required double totalExpenses,
  }) {
    final tips = <_SavingTip>[];

    // Categories that are discretionary and grew vs previous period
    const discretionary = {'Dining', 'Shopping', 'Entertainment', 'Food & Beverage', 'Subscriptions', 'Other'};

    for (final cat in sortedCats) {
      final prev = prevCatMap[cat.key] ?? 0;
      final current = cat.value;
      if (current <= 0) continue;

      final pctOfTotal = totalExpenses > 0 ? current / totalExpenses * 100 : 0;
      final isDiscretionary = discretionary.contains(cat.key);
      final grew = prev > 0 && current > prev;
      final growthPct = prev > 0 ? ((current - prev) / prev * 100).round() : 0;

      // Over-budget category
      final budgetMatch = budgetDetails.where((b) => b.name.toLowerCase() == cat.key.toLowerCase()).firstOrNull;
      final overBudget = budgetMatch != null && budgetMatch.spent > budgetMatch.limit && budgetMatch.limit > 0;
      final overBy = overBudget ? budgetMatch.spent - budgetMatch.limit : 0.0;

      if (overBudget) {
        tips.add(_SavingTip(
          category: cat.key,
          type: _SavingTipType.overBudget,
          amount: overBy,
          description: 'Over budget by ${(overBy / budgetMatch.limit * 100).round()}%. Cut ${(overBy * 0.5).ceil()} to get back on track.',
          severity: 3,
        ));
      } else if (grew && isDiscretionary && growthPct > 15 && current > 100) {
        final saveable = (current - prev) * 0.5;
        tips.add(_SavingTip(
          category: cat.key,
          type: _SavingTipType.growingFast,
          amount: saveable,
          description: 'Up $growthPct% from last period. Cutting back halfway could save ~${saveable.round()}.',
          severity: 2,
        ));
      } else if (isDiscretionary && pctOfTotal > 25) {
        final saveable = current * 0.2;
        tips.add(_SavingTip(
          category: cat.key,
          type: _SavingTipType.highShare,
          amount: saveable,
          description: '${pctOfTotal.round()}% of total spend. A 20% cut would save ~${saveable.round()}.',
          severity: 1,
        ));
      }
    }

    tips.sort((a, b) => b.severity.compareTo(a.severity));
    return tips.take(4).toList();
  }
}

class _BudgetLine {
  final String name;
  final double limit;
  final double spent;
  const _BudgetLine({required this.name, required this.limit, required this.spent});
}

enum _SavingTipType { overBudget, growingFast, highShare }

class _SavingTip {
  final String category;
  final _SavingTipType type;
  final double amount;
  final String description;
  final int severity;
  const _SavingTip({required this.category, required this.type, required this.amount, required this.description, required this.severity});
}

// ═══════════════════════════════════════════════════════════════════════════════
// Widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: BillyTheme.gray50, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['1W', '1M', '3M'].map((f) {
          final active = selected == f;
          return GestureDetector(
            onTap: () => onChanged(f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)] : null,
              ),
              child: Text(f, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? BillyTheme.emerald700 : BillyTheme.gray500)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SpendHeroCard extends StatelessWidget {
  const _SpendHeroCard({
    required this.totalExpenses, required this.docCount, required this.changePct,
    required this.avgDaily, required this.projected, required this.daysInMonth,
    required this.dayOfMonth, this.currency, required this.rangeLabel,
  });
  final double totalExpenses;
  final int docCount;
  final int? changePct;
  final double avgDaily, projected;
  final int daysInMonth, dayOfMonth;
  final String? currency;
  final String rangeLabel;

  String get _rangeTitle {
    switch (rangeLabel) {
      case '1W': return 'Spent this week';
      case '3M': return 'Spent (3 months)';
      case '1M':
      default: return 'Spent this month';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF059669), Color(0xFF10B981)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF059669).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_rangeTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(AppCurrency.format(totalExpenses, currency), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 8),
          Row(
            children: [
              _HeroPill(label: '$docCount items'),
              if (changePct != null) ...[
                const SizedBox(width: 8),
                _HeroPill(
                  label: '${changePct! >= 0 ? "+" : ""}$changePct% vs prev',
                  accent: changePct! > 10,
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _HeroStat(label: 'Daily avg', value: AppCurrency.formatCompact(avgDaily, currency))),
              Container(width: 1, height: 28, color: Colors.white24),
              Expanded(child: _HeroStat(label: 'Projected', value: AppCurrency.formatCompact(projected, currency))),
              Container(width: 1, height: 28, color: Colors.white24),
              Expanded(child: _HeroStat(label: 'Day', value: '$dayOfMonth/$daysInMonth')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, this.accent = false});
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? Colors.red.shade400.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: BillyTheme.gray100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: BillyTheme.gray500)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _DailyTrendCard extends StatelessWidget {
  const _DailyTrendCard({required this.data, required this.avgDaily, required this.totalSpent, this.currency});
  final List<double> data;
  final double avgDaily, totalSpent;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final maxY = data.isNotEmpty ? data.reduce((a, b) => a > b ? a : b) * 1.3 : 1.0;
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final dayLabels = List.generate(7, (i) => days[(now.subtract(Duration(days: 6 - i)).weekday - 1) % 7]);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: BillyTheme.gray50)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Daily spend', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
              Text('avg ${AppCurrency.formatCompact(avgDaily, currency)}/day', style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: data.every((e) => e == 0)
                ? const Center(child: Text('No spending data', style: TextStyle(color: BillyTheme.gray400)))
                : BarChart(BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(AppCurrency.formatCompact(rod.toY, currency), const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600));
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(dayLabels[val.toInt() % 7], style: const TextStyle(fontSize: 10, color: BillyTheme.gray500)),
                        ),
                      )),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: data.asMap().entries.map((e) {
                      final isToday = e.key == 6;
                      return BarChartGroupData(x: e.key, barRods: [
                        BarChartRodData(
                          toY: e.value,
                          color: isToday ? BillyTheme.emerald600 : BillyTheme.emerald600.withValues(alpha: 0.35),
                          width: 18,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ]);
                    }).toList(),
                  )),
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  const _CategoryBreakdownCard({
    required this.categories, required this.totalExpenses, this.currency,
    required this.catDocIds, required this.prevCatMap, required this.budgetDetails,
  });
  final List<MapEntry<String, double>> categories;
  final double totalExpenses;
  final String? currency;
  final Map<String, Set<String>> catDocIds;
  final Map<String, double> prevCatMap;
  final List<_BudgetLine> budgetDetails;

  static const _colors = [BillyTheme.green400, BillyTheme.blue400, Color(0xFFF59E0B), BillyTheme.red400, Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF97316), Color(0xFF06B6D4)];

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: BillyTheme.gray50)),
        child: const Center(child: Text('No categories yet', style: TextStyle(color: BillyTheme.gray400))),
      );
    }

    final pieData = categories.take(6).toList().asMap().entries.map((e) {
      return PieChartSectionData(value: e.value.value, color: _colors[e.key % _colors.length], radius: 20, showTitle: false);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: BillyTheme.gray50)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Categories', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: Row(
              children: [
                Expanded(
                  child: PieChart(PieChartData(
                    sections: pieData, centerSpaceRadius: 32, sectionsSpace: 3, startDegreeOffset: -90,
                  )),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: categories.take(5).toList().asMap().entries.map((e) {
                      final pct = totalExpenses > 0 ? (e.value.value / totalExpenses * 100).round() : 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: _colors[e.key % _colors.length], borderRadius: BorderRadius.circular(3))),
                            const SizedBox(width: 6),
                            Expanded(child: Text(e.value.key, style: const TextStyle(fontSize: 12, color: BillyTheme.gray700), overflow: TextOverflow.ellipsis)),
                            Text('$pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: BillyTheme.gray100),
          const SizedBox(height: 12),
          ...categories.take(8).toList().asMap().entries.map((e) {
            final cat = e.value;
            final pct = totalExpenses > 0 ? (cat.value / totalExpenses * 100).round() : 0;
            final color = _colors[e.key % _colors.length];
            final ids = catDocIds[cat.key];

            // Trend badge
            final prev = prevCatMap[cat.key] ?? 0;
            final grew = prev > 0 && cat.value > prev;
            final shrank = prev > 0 && cat.value < prev;
            final trendPct = prev > 0 ? ((cat.value - prev) / prev * 100).round() : 0;

            // Budget badge
            final budgetMatch = budgetDetails.where((b) => b.name.toLowerCase() == cat.key.toLowerCase()).firstOrNull;
            final overBudget = budgetMatch != null && budgetMatch.spent > budgetMatch.limit && budgetMatch.limit > 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: ids == null || ids.isEmpty ? null : () {
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocumentsHistoryScreen(restrictToDocumentIds: ids, restrictContextTitle: cat.key)));
                },
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(cat.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillyTheme.gray800))),
                        // Trend indicator
                        if (grew || shrank)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: grew ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(grew ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 12, color: grew ? BillyTheme.red400 : BillyTheme.emerald600),
                                const SizedBox(width: 2),
                                Text('${trendPct.abs()}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: grew ? BillyTheme.red400 : BillyTheme.emerald600)),
                              ],
                            ),
                          ),
                        // Over budget badge
                        if (overBudget)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                            child: const Text('Over budget', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: BillyTheme.red400)),
                          ),
                        Text(AppCurrency.format(cat.value, currency), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                        if (ids != null && ids.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, size: 16, color: BillyTheme.gray300),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (pct / 100).clamp(0.0, 1.0),
                        backgroundColor: BillyTheme.gray100,
                        valueColor: AlwaysStoppedAnimation(overBudget ? BillyTheme.red400 : color),
                        minHeight: 6,
                      ),
                    ),
                    // Budget context line
                    if (budgetMatch != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${AppCurrency.formatCompact(budgetMatch.spent, currency)} of ${AppCurrency.formatCompact(budgetMatch.limit, currency)} budget used',
                        style: TextStyle(fontSize: 10, color: overBudget ? BillyTheme.red400 : BillyTheme.gray500),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TopMerchantsCard extends StatelessWidget {
  const _TopMerchantsCard({required this.merchants, required this.merchantCount, this.currency});
  final List<MapEntry<String, double>> merchants;
  final Map<String, int> merchantCount;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: BillyTheme.gray50)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top merchants', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
          const SizedBox(height: 14),
          ...merchants.asMap().entries.map((e) {
            final m = e.value;
            final count = merchantCount[m.key] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(color: BillyTheme.gray50, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: Text(m.key.isNotEmpty ? m.key[0].toUpperCase() : '?', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BillyTheme.gray600)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillyTheme.gray800), overflow: TextOverflow.ellipsis),
                        Text('$count ${count == 1 ? "visit" : "visits"}', style: const TextStyle(fontSize: 11, color: BillyTheme.gray500)),
                      ],
                    ),
                  ),
                  Text(AppCurrency.format(m.value, currency), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BudgetVsActualCard extends StatelessWidget {
  const _BudgetVsActualCard({required this.budgetDetails, required this.budgetTotal, required this.budgetSpent, this.currency});
  final List<_BudgetLine> budgetDetails;
  final double budgetTotal, budgetSpent;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final pct = budgetTotal > 0 ? (budgetSpent / budgetTotal).clamp(0.0, 1.5) : 0.0;
    final over = pct > 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: BillyTheme.gray50)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Budget vs actual', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: over ? const Color(0xFFFEE2E2) : BillyTheme.emerald50, borderRadius: BorderRadius.circular(8)),
                child: Text(over ? 'Over budget' : 'On track', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: over ? BillyTheme.red400 : BillyTheme.emerald700)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(AppCurrency.format(budgetSpent, currency), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: over ? BillyTheme.red400 : BillyTheme.gray800)),
              Text(' / ${AppCurrency.format(budgetTotal, currency)}', style: const TextStyle(fontSize: 14, color: BillyTheme.gray500)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: pct.clamp(0.0, 1.0), backgroundColor: BillyTheme.gray100, valueColor: AlwaysStoppedAnimation(over ? BillyTheme.red400 : BillyTheme.emerald600), minHeight: 10),
          ),
          const SizedBox(height: 14),
          ...budgetDetails.take(6).map((b) {
            final bPct = b.limit > 0 ? (b.spent / b.limit).clamp(0.0, 1.5) : 0.0;
            final bOver = bPct > 1.0;
            final remaining = (b.limit - b.spent);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(child: Text(b.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillyTheme.gray700), overflow: TextOverflow.ellipsis)),
                            if (bOver) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(4)),
                                child: Text('Over by ${AppCurrency.formatCompact(b.spent - b.limit, currency)}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: BillyTheme.red400)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text('${AppCurrency.formatCompact(b.spent, currency)} / ${AppCurrency.formatCompact(b.limit, currency)}', style: TextStyle(fontSize: 11, color: bOver ? BillyTheme.red400 : BillyTheme.gray500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: bPct.clamp(0.0, 1.0), backgroundColor: BillyTheme.gray100, valueColor: AlwaysStoppedAnimation(bOver ? BillyTheme.red400 : BillyTheme.emerald600), minHeight: 5),
                  ),
                  if (!bOver && remaining > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${AppCurrency.formatCompact(remaining, currency)} left', style: const TextStyle(fontSize: 10, color: BillyTheme.emerald600)),
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

class _SavingsSuggestionsCard extends StatelessWidget {
  const _SavingsSuggestionsCard({required this.tips, this.currency});
  final List<_SavingTip> tips;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    if (tips.isEmpty) return const SizedBox.shrink();

    double potentialTotal = 0;
    for (final t in tips) {
      potentialTotal += t.amount;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD1FAE5)),
        gradient: const LinearGradient(colors: [Color(0xFFF0FDF4), Colors.white], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: BillyTheme.emerald50, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.savings_rounded, size: 18, color: BillyTheme.emerald600),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Where you can save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: BillyTheme.emerald50, borderRadius: BorderRadius.circular(8)),
                child: Text('~${AppCurrency.formatCompact(potentialTotal, currency)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BillyTheme.emerald700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Potential monthly savings based on your patterns', style: TextStyle(fontSize: 12, color: BillyTheme.gray500)),
          const SizedBox(height: 14),
          ...tips.asMap().entries.map((e) {
            final tip = e.value;
            final isFirst = e.key == 0;

            IconData icon;
            Color badgeColor;
            String badge;
            switch (tip.type) {
              case _SavingTipType.overBudget:
                icon = Icons.warning_amber_rounded;
                badgeColor = BillyTheme.red400;
                badge = 'Over budget';
                break;
              case _SavingTipType.growingFast:
                icon = Icons.trending_up_rounded;
                badgeColor = const Color(0xFFF59E0B);
                badge = 'Growing fast';
                break;
              case _SavingTipType.highShare:
                icon = Icons.pie_chart_rounded;
                badgeColor = const Color(0xFF8B5CF6);
                badge = 'High share';
                break;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isFirst ? badgeColor.withValues(alpha: 0.06) : BillyTheme.gray50,
                borderRadius: BorderRadius.circular(14),
                border: isFirst ? Border.all(color: badgeColor.withValues(alpha: 0.15)) : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 16, color: badgeColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(tip.category, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BillyTheme.gray800))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                              child: Text(badge, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: badgeColor)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(tip.description, style: const TextStyle(fontSize: 12, color: BillyTheme.gray600, height: 1.3)),
                        const SizedBox(height: 4),
                        Text('Save ~${AppCurrency.formatCompact(tip.amount, currency)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: BillyTheme.emerald600)),
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

// ═══════════════════════════════════════════════════════════════════════════════
// Top categories for the selected period — compact horizontal list
// ═══════════════════════════════════════════════════════════════════════════════

class _TopCategoriesForPeriod extends StatelessWidget {
  const _TopCategoriesForPeriod({
    required this.categories,
    required this.totalExpenses,
    this.currency,
    required this.rangeLabel,
  });
  final List<MapEntry<String, double>> categories;
  final double totalExpenses;
  final String? currency;
  final String rangeLabel;

  static const _catColors = [
    BillyTheme.emerald600,
    BillyTheme.blue400,
    Color(0xFFF59E0B),
    BillyTheme.red400,
    Color(0xFF8B5CF6),
  ];

  String get _periodLabel {
    switch (rangeLabel) {
      case '1W': return 'This week';
      case '3M': return 'Last 3 months';
      case '1M':
      default: return 'This month';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray50),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded, size: 18, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Text('Top spending · $_periodLabel', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
            ],
          ),
          const SizedBox(height: 14),
          ...categories.asMap().entries.map((e) {
            final cat = e.value;
            final pct = totalExpenses > 0 ? cat.value / totalExpenses : 0.0;
            final color = _catColors[e.key % _catColors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${e.key + 1}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.key,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillyTheme.gray800),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: pct.clamp(0.0, 1.0),
                            backgroundColor: BillyTheme.gray100,
                            valueColor: AlwaysStoppedAnimation(color),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        AppCurrency.formatCompact(cat.value, currency),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BillyTheme.gray800),
                      ),
                      Text(
                        '${(pct * 100).round()}%',
                        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                      ),
                    ],
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

// ═══════════════════════════════════════════════════════════════════════════════
// Period summary strip: always shows 1W / 1M / 3M totals side-by-side
// ═══════════════════════════════════════════════════════════════════════════════

class _PeriodSummaryStrip extends StatelessWidget {
  const _PeriodSummaryStrip({
    required this.docs,
    this.currency,
    required this.weekBasis,
    required this.activeRange,
  });
  final List<Map<String, dynamic>> docs;
  final String? currency;
  final WeekSpendBasis weekBasis;
  final String activeRange;

  @override
  Widget build(BuildContext context) {
    double total(String key) {
      final range = DocumentDateRange.forFilter(key);
      final filtered = DocumentDateRange.filterDocumentsForWeekBasis(docs, range, weekBasis);
      var sum = 0.0;
      for (final d in filtered) {
        if ((d['status'] as String?) == 'draft') continue;
        sum += (d['amount'] as num?)?.toDouble() ?? 0;
      }
      return sum;
    }

    int count(String key) {
      final range = DocumentDateRange.forFilter(key);
      final filtered = DocumentDateRange.filterDocumentsForWeekBasis(docs, range, weekBasis);
      var c = 0;
      for (final d in filtered) {
        if ((d['status'] as String?) != 'draft') c++;
      }
      return c;
    }

    Widget card(String label, String rangeKey) {
      final isActive = activeRange == rangeKey;
      final t = total(rangeKey);
      final c = count(rangeKey);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? BillyTheme.emerald50 : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? BillyTheme.emerald600.withValues(alpha: 0.4) : BillyTheme.gray100,
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isActive ? BillyTheme.emerald700 : BillyTheme.gray500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppCurrency.formatCompact(t, currency),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isActive ? BillyTheme.emerald700 : BillyTheme.gray800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$c items',
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        card('1 Week', '1W'),
        const SizedBox(width: 8),
        card('1 Month', '1M'),
        const SizedBox(width: 8),
        card('3 Months', '3M'),
      ],
    );
  }
}

class _SpikesCard extends StatelessWidget {
  const _SpikesCard({required this.spikes, required this.avgDaily, this.currency});
  final List<MapEntry<String, double>> spikes;
  final double avgDaily;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFEE2E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, size: 18, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              const Text('Spending spikes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Days where you spent 2x+ your average (${AppCurrency.formatCompact(avgDaily, currency)}/day)', style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
          const SizedBox(height: 12),
          ...spikes.map((s) {
            String label = s.key;
            try { label = DateFormat('EEE, dd MMM').format(DateTime.parse(s.key)); } catch (_) {}
            final multiplier = avgDaily > 0 ? (s.value / avgDaily).toStringAsFixed(1) : '?';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.center,
                    child: Text('${multiplier}x', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFF59E0B))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillyTheme.gray700))),
                  Text(AppCurrency.format(s.value, currency), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BillyTheme.red400)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AiInsightsToggle extends StatelessWidget {
  const _AiInsightsToggle({required this.isOpen, required this.onToggle});
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDE9FE)),
            gradient: isOpen ? null : const LinearGradient(colors: [Color(0xFFFAF5FF), Colors.white]),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.auto_awesome_rounded, size: 20, color: Color(0xFF8B5CF6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI Insights', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                    Text(isOpen ? 'Money Coach + JAI Insight' : 'Tap to expand AI-powered analysis', style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                  ],
                ),
              ),
              Icon(isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: BillyTheme.gray400),
            ],
          ),
        ),
      ),
    );
  }
}
