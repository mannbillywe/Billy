import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/profile_provider.dart';
import '../utils/goat_dashboard_helpers.dart';
import '../widgets/goat_chip.dart';
import '../widgets/goat_premium_card.dart';

class GoatHomeTab extends ConsumerWidget {
  const GoatHomeTab({super.key, required this.onNavigateToModule});

  /// 0 home, 1 recurring, 2 forecast, 3 goals, 4 prefs
  final void Function(int index) onNavigateToModule;

  static String _riskLabel(GoatCashFlowRisk r) {
    switch (r) {
      case GoatCashFlowRisk.low:
        return 'Low';
      case GoatCashFlowRisk.medium:
        return 'Medium';
      case GoatCashFlowRisk.high:
        return 'Elevated';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsProvider);
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'USD';
    final all = docsAsync.valueOrNull ?? [];
    final loading = docsAsync.isLoading && docsAsync.value == null;

    final upcoming = upcomingDocumentsWithinDays(all, daysAhead: 14);
    final weekSpend = spendLastDays(all, 7);
    final daily = weekSpend / 7;
    final risk = cashFlowRiskFromDocuments(all);
    final roughBuffer = (daily * 2).clamp(0.0, 1e12);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: GoatTokens.gold,
                backgroundColor: GoatTokens.surfaceElevated,
              ),
            ),
          Text(
            'Command center',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GoatTokens.textPrimary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Bills, flow, and goals in one premium workspace',
            style: TextStyle(color: GoatTokens.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          GoatPremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Safe to spend (preview)',
                      style: TextStyle(
                        color: GoatTokens.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    GoatChip(label: _riskLabel(risk), selected: true),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppCurrency.format(roughBuffer, currency),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: GoatTokens.gold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Rough 2-day buffer from your last 7 days of recorded spend. Add income in Forecast for a full picture.',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _miniStat(
                        context,
                        '7-day spend',
                        AppCurrency.format(weekSpend, currency),
                      ),
                    ),
                    Expanded(
                      child: _miniStat(
                        context,
                        'Avg / day',
                        AppCurrency.format(daily, currency),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GoatPremiumCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => onNavigateToModule(2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cash-flow risk', style: TextStyle(color: GoatTokens.textMuted, fontSize: 11)),
                      const SizedBox(height: 6),
                      Text(
                        _riskLabel(risk),
                        style: TextStyle(
                          color: risk == GoatCashFlowRisk.high ? const Color(0xFFFCA5A5) : GoatTokens.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('vs prior week', style: TextStyle(color: GoatTokens.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GoatPremiumCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => onNavigateToModule(3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Goals', style: TextStyle(color: GoatTokens.textMuted, fontSize: 11)),
                      const SizedBox(height: 6),
                      Text(
                        '0 active',
                        style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text('Sinking funds', style: TextStyle(color: GoatTokens.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Upcoming (next 14 days)',
            style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          if (upcoming.isEmpty)
            GoatPremiumCard(
              accentBorder: false,
              child: Text(
                'No bills with dates in this window. Scan or add documents with due dates to populate this snapshot.',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 13, height: 1.4),
              ),
            )
          else
            ...upcoming.take(4).map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GoatPremiumCard(
                      accentBorder: false,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['vendor_name'] as String? ?? 'Bill',
                                  style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  formatShortDate(d['date'] as String?),
                                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            AppCurrency.format((d['amount'] as num?)?.toDouble() ?? 0, currency),
                            style: TextStyle(color: GoatTokens.gold, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 20),
          GoatPremiumCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, color: GoatTokens.gold.withValues(alpha: 0.85), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GOAT coach',
                        style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Keep discretionary spend flat for two weeks to lower cash-flow volatility. When Forecast ships, we will anchor this to income and fixed bills.',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Quick actions',
            style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GoatChip(label: 'Add bill', onTap: () => onNavigateToModule(1)),
              GoatChip(label: 'Add income', onTap: () => onNavigateToModule(2)),
              GoatChip(label: 'Add goal', onTap: () => onNavigateToModule(3)),
              GoatChip(label: 'Review forecast', onTap: () => onNavigateToModule(2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: GoatTokens.textMuted, fontSize: 10)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }
}
