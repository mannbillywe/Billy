import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/billy_theme.dart';
import '../../../providers/documents_provider.dart';
import '../widgets/insights_card.dart';
import '../widgets/money_flow_chart.dart';
import '../widgets/ocr_banner.dart';
import '../widgets/quick_actions.dart';
import '../widgets/recent_activity.dart';
import '../widgets/spend_hero.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekAsync = ref.watch(weekSpendProvider);
    final recentAsync = ref.watch(recentDocsProvider);
    final dailyAsync = ref.watch(dailySpendProvider);

    final weekSpend = weekAsync.valueOrNull ?? 0;
    final recentDocs = recentAsync.valueOrNull ?? [];
    final dailyData = dailyAsync.valueOrNull ?? [];

    final balance = weekSpend > 0 ? weekSpend * 2.5 : 2750.56;

    final recentItems = recentDocs.take(5).map((d) {
      final vendor = d['vendor_name'] as String? ?? 'Unknown';
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      final desc = d['description'] as String? ?? '';
      final dateStr = d['date'] as String? ?? '';
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
        vendor: vendor,
        amount: amount,
        category: desc.isNotEmpty ? desc.split(',').first.trim() : 'Expense',
        date: formattedDate,
        icon: vendor.isNotEmpty ? vendor[0].toUpperCase() : '?',
      );
    }).toList();

    double totalExpenses = 0;
    final catMap = <String, double>{};
    for (final d in recentDocs) {
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
          SpendHero(balance: balance, weeklyData: dailyData),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: QuickActions()),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    MoneyFlowChart(data: dailyData),
                    const SizedBox(height: 16),
                    InsightsCard(
                      totalExpenses: totalExpenses,
                      categories: categories.take(4).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const OcrBanner(),
          if (recentItems.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
                Text('See all', style: TextStyle(fontSize: 14, color: BillyTheme.gray400)),
              ],
            ),
            const SizedBox(height: 12),
            RecentActivity(items: recentItems),
          ],
        ],
      ),
    );
  }
}
