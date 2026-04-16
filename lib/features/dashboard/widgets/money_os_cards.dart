import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';

class UpcomingBillsCard extends StatelessWidget {
  const UpcomingBillsCard({
    super.key,
    required this.recurringItems,
    this.currencyCode,
    this.onViewAll,
  });

  final List<Map<String, dynamic>> recurringItems;
  final String? currencyCode;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final upcoming = recurringItems.where((r) {
      final nd = r['next_due'] as String?;
      if (nd == null) return false;
      final due = DateTime.tryParse(nd);
      if (due == null) return false;
      return due.difference(DateTime.now()).inDays <= 7;
    }).take(3).toList();

    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.schedule_rounded, size: 16, color: Color(0xFFF59E0B)),
                  ),
                  const SizedBox(width: 10),
                  const Text('Upcoming Bills', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                ],
              ),
              if (onViewAll != null)
                GestureDetector(
                  onTap: onViewAll,
                  child: const Text('View all', style: TextStyle(fontSize: 13, color: BillyTheme.emerald600, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...upcoming.map((r) {
            final title = r['title'] as String? ?? 'Bill';
            final amount = (r['amount'] as num?)?.toDouble() ?? 0;
            final nd = r['next_due'] as String? ?? '';
            String dueLabel = nd;
            try {
              final due = DateTime.parse(nd);
              final diff = due.difference(DateTime.now()).inDays;
              if (diff < 0) {
                dueLabel = 'Overdue';
              } else if (diff == 0) {
                dueLabel = 'Due today';
              } else if (diff == 1) {
                dueLabel = 'Tomorrow';
              } else {
                dueLabel = 'Due ${DateFormat('dd MMM').format(due)}';
              }
            } catch (_) {}
            final isOverdue = dueLabel == 'Overdue';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: isOverdue ? const Color(0xFFFEE2E2) : BillyTheme.gray50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.repeat_rounded, size: 16, color: isOverdue ? BillyTheme.red400 : BillyTheme.gray500),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BillyTheme.gray800), overflow: TextOverflow.ellipsis),
                        Text(dueLabel, style: TextStyle(fontSize: 11, color: isOverdue ? BillyTheme.red400 : BillyTheme.gray500)),
                      ],
                    ),
                  ),
                  Text(AppCurrency.format(amount, currencyCode), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class BudgetStatusCard extends StatelessWidget {
  const BudgetStatusCard({
    super.key,
    required this.budgets,
    required this.docs,
    this.currencyCode,
    this.onViewAll,
  });

  final List<Map<String, dynamic>> budgets;
  final List<Map<String, dynamic>> docs;
  final String? currencyCode;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    if (budgets.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
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

    double totalBudget = 0;
    double totalSpent = 0;
    for (final b in budgets) {
      totalBudget += (b['amount'] as num?)?.toDouble() ?? 0;
      // Match by category_id first, then by name
      final budgetCatId = b['category_id'] as String?;
      double spent = 0;
      if (budgetCatId != null && catSpendByCatId.containsKey(budgetCatId)) {
        spent = catSpendByCatId[budgetCatId]!;
      } else {
        final catName = (b['categories'] as Map?)?['name'] as String? ?? b['name'] as String? ?? '';
        spent = catSpendByName[catName] ?? 0;
      }
      totalSpent += spent;
    }

    final pct = totalBudget > 0 ? (totalSpent / totalBudget).clamp(0.0, 1.5) : 0.0;
    final overBudget = pct > 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppCurrency.format(totalSpent, currencyCode),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: overBudget ? BillyTheme.red400 : BillyTheme.gray800,
                ),
              ),
              Text(
                ' / ${AppCurrency.format(totalBudget, currencyCode)}',
                style: const TextStyle(fontSize: 14, color: BillyTheme.gray500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              backgroundColor: BillyTheme.gray200,
              valueColor: AlwaysStoppedAnimation<Color>(
                overBudget ? BillyTheme.red400 : BillyTheme.emerald600,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            overBudget
                ? 'Over budget by ${AppCurrency.format(totalSpent - totalBudget, currencyCode)}'
                : '${AppCurrency.format(totalBudget - totalSpent, currencyCode)} remaining',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: overBudget ? BillyTheme.red400 : BillyTheme.emerald600,
            ),
          ),
          // Per-budget breakdown
          if (budgets.length > 1) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: BillyTheme.gray100),
            const SizedBox(height: 14),
            ...budgets.take(3).map((b) {
              final budgetAmt = (b['amount'] as num?)?.toDouble() ?? 0;
              final budgetCatId = b['category_id'] as String?;
              double spent = 0;
              if (budgetCatId != null && catSpendByCatId.containsKey(budgetCatId)) {
                spent = catSpendByCatId[budgetCatId]!;
              } else {
                final catName = (b['categories'] as Map?)?['name'] as String? ?? b['name'] as String? ?? '';
                spent = catSpendByName[catName] ?? 0;
              }
              final itemPct = budgetAmt > 0 ? (spent / budgetAmt).clamp(0.0, 1.0) : 0.0;
              final catName = (b['categories'] as Map?)?['name'] as String? ?? b['name'] as String? ?? 'Budget';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            catName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: BillyTheme.gray800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${AppCurrency.format(spent, currencyCode)} / ${AppCurrency.format(budgetAmt, currencyCode)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: BillyTheme.gray500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: itemPct,
                        backgroundColor: BillyTheme.gray200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          spent > budgetAmt ? BillyTheme.red400 : BillyTheme.emerald600,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class PendingSuggestionsCard extends StatelessWidget {
  const PendingSuggestionsCard({
    super.key,
    required this.count,
    this.onTap,
  });

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray50),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 20, color: Color(0xFF8B5CF6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$count suggestions', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                    const Text('Review AI recommendations', style: TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(20)),
                child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8B5CF6))),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 20, color: BillyTheme.gray300),
            ],
          ),
        ),
      ),
    );
  }
}

class PendingSettlementsCard extends StatelessWidget {
  const PendingSettlementsCard({
    super.key,
    required this.pendingCount,
    required this.totalOwed,
    this.currencyCode,
    this.onTap,
  });

  final int pendingCount;
  final double totalOwed;
  final String? currencyCode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (pendingCount <= 0) return const SizedBox.shrink();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray50),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.handshake_rounded, size: 20, color: Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$pendingCount pending settlements', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                    Text('Total: ${AppCurrency.format(totalOwed, currencyCode)}', style: const TextStyle(fontSize: 12, color: BillyTheme.gray500)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20, color: BillyTheme.gray300),
            ],
          ),
        ),
      ),
    );
  }
}

class OcrUsageCard extends StatelessWidget {
  const OcrUsageCard({
    super.key,
    required this.used,
    required this.limit,
    this.onTap,
  });

  final int used;
  final int limit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = (limit - used).clamp(0, limit);
    final pct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final isLow = remaining <= 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isLow ? const Color(0xFFFEF2F2) : BillyTheme.emerald50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.camera_alt_rounded, size: 16, color: isLow ? BillyTheme.red400 : BillyTheme.emerald600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$remaining OCR scans remaining',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isLow ? BillyTheme.red400 : BillyTheme.emerald700),
            ),
          ),
          SizedBox(
            width: 40,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.white.withValues(alpha: 0.5),
                valueColor: AlwaysStoppedAnimation<Color>(isLow ? BillyTheme.red400 : BillyTheme.emerald600),
                minHeight: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
