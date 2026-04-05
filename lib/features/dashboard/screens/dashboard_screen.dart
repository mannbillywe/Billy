import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/profile_provider.dart';
import '../widgets/insights_card.dart';
import '../widgets/money_flow_chart.dart';
import '../widgets/ocr_banner.dart';
import '../widgets/quick_actions.dart';
import '../widgets/recent_activity.dart';
import '../widgets/spend_hero.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({
    super.key,
    this.onOpenScan,
    this.onExportData,
    this.onCreateBill,
    this.onOpenAllDocuments,
    this.onOpenDocumentDetail,
  });

  final VoidCallback? onOpenScan;
  final VoidCallback? onExportData;
  final VoidCallback? onCreateBill;
  final void Function(String documentId)? onOpenDocumentDetail;
  final VoidCallback? onOpenAllDocuments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekAsync = ref.watch(weekSpendProvider);
    final lastWeekAsync = ref.watch(lastWeekSpendProvider);
    final recentAsync = ref.watch(recentDocsProvider);
    final dailyAsync = ref.watch(dailySpendProvider);
    final docsAsync = ref.watch(documentsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    final weekSpend = weekAsync.valueOrNull ?? 0;
    final lastWeekSpend = lastWeekAsync.valueOrNull ?? 0;
    final recentDocs = recentAsync.valueOrNull ?? [];
    final allDocs = docsAsync.valueOrNull ?? [];
    final dailyData = dailyAsync.valueOrNull ?? [];
    final docsStillLoading = docsAsync.isLoading && docsAsync.value == null;

    final recentItems = recentDocs.take(5).map((d) {
      final vendor = d['vendor_name'] as String? ?? 'Unknown';
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      final desc = d['description'] as String? ?? '';
      final dateStr = d['date'] as String? ?? '';
      final docId = d['id'] as String?;
      String formattedDate = dateStr;
      try {
        final dt = DateTime.parse(dateStr);
        final now = DateTime.now();
        final diff = now.difference(dt).inDays;
        if (diff == 0) {
          formattedDate = 'Today';
        } else if (diff == 1) {
          formattedDate = 'Yesterday';
        } else {
          formattedDate = DateFormat('dd MMM').format(dt);
        }
      } catch (_) {}

      return RecentActivityItem(
        documentId: docId,
        vendor: vendor,
        amount: amount,
        category: desc.isNotEmpty ? desc.split(',').first.trim() : 'Expense',
        date: formattedDate,
        icon: vendor.isNotEmpty ? vendor[0].toUpperCase() : '?',
      );
    }).toList();

    double totalExpenses = 0;
    final catMap = <String, double>{};
    for (final d in allDocs) {
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      final desc = (d['description'] as String?)?.split(',').first.trim() ?? 'Other';
      totalExpenses += amount;
      catMap[desc] = (catMap[desc] ?? 0) + amount;
    }
    final categories = catMap.entries.map((e) {
      final pct = totalExpenses > 0 ? e.value / totalExpenses : 0.0;
      return (e.key, pct);
    }).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    return SingleChildScrollView(
      key: const ValueKey('dashboard'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (docsStillLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: BillyTheme.emerald600,
                backgroundColor: BillyTheme.gray100,
              ),
            ),
          SpendHero(
            weekSpend: weekSpend,
            currencyCode: currency,
            weeklyData: dailyData,
            lastWeekSpend: lastWeekSpend,
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: QuickActions(
                  onCreateBill: onCreateBill,
                  onOpenAllDocuments: onOpenAllDocuments,
                  onExportData: onExportData,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    MoneyFlowChart(data: dailyData),
                    const SizedBox(height: 16),
                    InsightsCard(
                      totalExpenses: totalExpenses,
                      categories: categories.take(4).toList(),
                      currencyCode: currency,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          OcrBanner(onManualEntry: onCreateBill),
          if (recentItems.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                TextButton(
                  onPressed: onOpenAllDocuments,
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RecentActivity(
              items: recentItems,
              currencyCode: currency,
              onItemTap: onOpenDocumentDetail,
            ),
          ],
        ],
      ),
    );
  }
}
