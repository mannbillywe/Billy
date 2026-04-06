import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../core/utils/document_date_range.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/lend_borrow_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/week_spend_basis_provider.dart';
import '../../documents/utils/document_backdate_hint.dart';
import '../../goat/widgets/goat_mode_home_cta.dart';
import '../utils/dashboard_spend_math.dart';
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
    this.onOpenGoatMode,
  });

  final VoidCallback? onOpenScan;
  final VoidCallback? onExportData;
  final VoidCallback? onCreateBill;
  final void Function(String documentId)? onOpenDocumentDetail;
  final VoidCallback? onOpenAllDocuments;
  final VoidCallback? onOpenGoatMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsProvider);
    final lbAsync = ref.watch(lendBorrowProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    final allDocs = docsAsync.valueOrNull ?? [];
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final weekBasis = ref.watch(weekSpendBasisProvider);
    final weekSpend = DashboardSpendMath.rollingSevenDayDocumentSpend(allDocs, null, weekBasis);
    final weekDocCount = DashboardSpendMath.rollingSevenDayDocumentCount(allDocs, null, weekBasis);
    final lastWeekSpend = DashboardSpendMath.priorRollingSevenDayDocumentSpend(allDocs, null, weekBasis);
    final dailyData = DashboardSpendMath.rollingSevenDayDailyDocumentSpend(allDocs, null, weekBasis);
    final lbEntries = lbAsync.valueOrNull ?? [];
    final pendingLb = DashboardSpendMath.pendingLendBorrowTotals(lbEntries, uid);
    final addedLb = DashboardSpendMath.lendBorrowAddedThisCalendarWeek(lbEntries, uid);
    final lbWeekDaily = DashboardSpendMath.thisWeekDailyLendBorrow(lbEntries, uid);
    final docsStillLoading = docsAsync.isLoading && docsAsync.value == null;

    final recentSorted = allDocs.where((d) => (d['status'] as String?) != 'draft').toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['date']?.toString() ?? '');
        final db = DateTime.tryParse(b['date']?.toString() ?? '');
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    final recentDocs = recentSorted.take(10).toList();

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
        backdateHint: DocumentBackdateHint.fromDocumentRow(d)?.shortLabel,
      );
    }).toList();

    // Match server spend queries and Analytics overview: drafts are not "saved" spend.
    final insightDocs = allDocs.where((d) => (d['status'] as String?) != 'draft');
    double totalExpenses = 0;
    final catMap = <String, double>{};
    for (final d in insightDocs) {
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
          Text(
            'Last 7 days (same as Analytics 1W) — count by',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BillyTheme.gray600),
          ),
          const SizedBox(height: 8),
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
                label: Text('Both'),
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
          if (onOpenGoatMode != null) GoatModeHomeCta(onPressed: onOpenGoatMode!),
          SpendHero(
            weekSpend: weekSpend,
            currencyCode: currency,
            weekSubtitle: DashboardSpendMath.weekBasisSubtitle(weekBasis),
            documentCountThisWeek: weekDocCount,
            weeklyData: dailyData,
            lendCollectWeek: lbWeekDaily.collect,
            lendPayWeek: lbWeekDaily.pay,
            lastWeekSpend: lastWeekSpend,
            friendPendingCollect: pendingLb.collect,
            friendPendingPay: pendingLb.pay,
            friendAddedThisWeekCollect: addedLb.collect,
            friendAddedThisWeekPay: addedLb.pay,
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
