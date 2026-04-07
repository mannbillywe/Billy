import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../core/utils/document_date_range.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/goat_cash_providers.dart';
import '../../../providers/goat_goals_providers.dart';
import '../../../providers/goat_statements_providers.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/week_spend_basis_provider.dart';
import '../finance/cashflow_engine.dart';
import '../utils/goat_dashboard_helpers.dart';
import '../widgets/goat_chip.dart';
import '../statements/screens/goat_statements_hub_screen.dart';
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

  static String _forecastRiskChip(String r) {
    switch (r) {
      case 'low':
        return 'Low';
      case 'medium':
        return 'Medium';
      case 'high':
        return 'Elevated';
      default:
        return r;
    }
  }

  static GoatCashFlowRisk _forecastRiskToDocStyle(String r) {
    switch (r) {
      case 'high':
        return GoatCashFlowRisk.high;
      case 'medium':
        return GoatCashFlowRisk.medium;
      default:
        return GoatCashFlowRisk.low;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsProvider);
    final forecastAsync = ref.watch(goatForecastProvider);
    final goalsSummaryAsync = ref.watch(goatGoalsSummaryProvider);
    final lensWeekSpendAsync = ref.watch(goatLensWeekDebitSpendProvider);
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'USD';
    final weekBasis = ref.watch(weekSpendBasisProvider);
    final all = docsAsync.valueOrNull ?? [];
    final loading = docsAsync.isLoading && docsAsync.value == null;

    final upcoming = upcomingDocumentsWithinDays(all, daysAhead: 14);
    final docWeekSpend = spendLastDaysByBasis(all, 7, weekBasis);
    final weekSpend = lensWeekSpendAsync.maybeWhen(
      data: (v) => v,
      orElse: () => docWeekSpend,
    );
    final daily = weekSpend / 7;
    final risk = cashFlowRiskFromDocumentsByBasis(all, weekBasis);
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
            '7-day spend basis',
            style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<WeekSpendBasis>(
            segments: const [
              ButtonSegment<WeekSpendBasis>(
                value: WeekSpendBasis.uploadDate,
                label: Text('Upload'),
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
                if (states.contains(WidgetState.selected)) return GoatTokens.gold;
                return GoatTokens.textMuted;
              }),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '7-day spend uses the lens (top) for bank/receipt mix; Upload/Bill/Both applies to receipt documents only — statement lines use posted dates.',
            style: TextStyle(color: GoatTokens.textMuted.withValues(alpha: 0.9), fontSize: 10, height: 1.35),
          ),
          const SizedBox(height: 16),
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
                      'Safe to spend',
                      style: TextStyle(
                        color: GoatTokens.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    GoatChip(
                      label: forecastAsync.hasValue
                          ? _forecastRiskChip(forecastAsync.requireValue.riskLevel)
                          : _riskLabel(risk),
                      selected: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (forecastAsync.isLoading && !forecastAsync.hasValue)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2),
                      ),
                    ),
                  )
                else if (forecastAsync.hasError && !forecastAsync.hasValue)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppCurrency.format(roughBuffer, currency),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: GoatTokens.gold,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Forecast could not load (check DB migrations and Forecast tab). Showing a rough 2-day buffer from recorded spend instead.',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
                      ),
                    ],
                  )
                else if (forecastAsync.hasValue) ...[
                  Text(
                    AppCurrency.format(CashflowMoneyLine.fromMinor(forecastAsync.requireValue.safeToSpendNowMinor), currency),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: GoatTokens.gold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _forecastHomeSubtitle(forecastAsync.requireValue, currency),
                    style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
                  ),
                ] else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppCurrency.format(roughBuffer, currency),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: GoatTokens.gold,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Rough 2-day buffer from your last 7 days of recorded spend. Open Forecast to add accounts, income, and bills for a deterministic number.',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.35),
                      ),
                    ],
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
          GoatPremiumCard(
            padding: const EdgeInsets.all(14),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const GoatStatementsHubScreen()),
              );
            },
            child: Row(
              children: [
                Icon(Icons.description_outlined, color: GoatTokens.gold.withValues(alpha: 0.95), size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Statements', style: TextStyle(color: GoatTokens.textMuted, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        'Import bank & card files',
                        style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text('PDF · CSV · XLSX · dedupe vs receipts', style: TextStyle(color: GoatTokens.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: GoatTokens.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                        forecastAsync.hasValue
                            ? _forecastRiskChip(forecastAsync.requireValue.riskLevel)
                            : _riskLabel(risk),
                        style: TextStyle(
                          color: (forecastAsync.hasValue
                                  ? _forecastRiskToDocStyle(forecastAsync.requireValue.riskLevel)
                                  : risk) ==
                                  GoatCashFlowRisk.high
                              ? const Color(0xFFFCA5A5)
                              : GoatTokens.textPrimary,
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
                        '${goalsSummaryAsync.maybeWhen(data: (s) => s.activeCount, orElse: () => 0)} active',
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
                        _goatCoachCopy(forecastAsync),
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
              GoatChip(label: 'Recurring & subs', onTap: () => onNavigateToModule(1)),
              GoatChip(label: 'Add income', onTap: () => onNavigateToModule(2)),
              GoatChip(label: 'Add goal', onTap: () => onNavigateToModule(3)),
              GoatChip(label: 'Review forecast', onTap: () => onNavigateToModule(2)),
              GoatChip(
                label: 'Statements',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const GoatStatementsHubScreen()),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _forecastHomeSubtitle(CashflowForecastResult f, String currency) {
    final b = StringBuffer()
      ..write(
        'Deterministic: included liquid balances, your reserve, and scheduled in/out until the next income date (or horizon end). ',
      );
    if (f.nextIncomeDate != null) {
      b.write(
        'Next modeled income: ${f.nextIncomeDate!.year}-${f.nextIncomeDate!.month.toString().padLeft(2, '0')}-${f.nextIncomeDate!.day.toString().padLeft(2, '0')}. ',
      );
    } else {
      b.write('Add an income stream with a next date in Forecast to anchor obligations to payday. ');
    }
    if (f.lowestBalanceDate != null) {
      b.write(
        'Lowest projected closing: ${AppCurrency.format(CashflowMoneyLine.fromMinor(f.projectedMinBalanceMinor), currency)} on '
        '${f.lowestBalanceDate!.year}-${f.lowestBalanceDate!.month.toString().padLeft(2, '0')}-${f.lowestBalanceDate!.day.toString().padLeft(2, '0')}.',
      );
    }
    return b.toString().trim();
  }

  static String _goatCoachCopy(AsyncValue<CashflowForecastResult> forecastAsync) {
    if (forecastAsync.hasValue) {
      final f = forecastAsync.requireValue;
      if (f.riskLevel == 'high') {
        return 'The model flags high risk: safe-to-spend may be below zero or projected balance can go negative. Open Forecast for the breakdown and to adjust accounts, buffer, or income.';
      }
      if (f.riskLevel == 'medium') {
        return 'Cushion is thin relative to your buffer and upcoming obligations. Review the next two weeks in Forecast.';
      }
      if (f.nextIncomeDate == null) {
        return 'Add an active income stream with a next expected date in Forecast so safe-to-spend can anchor to payday.';
      }
      return 'Outlook is stable for the selected horizon. Keep recurring bills updated so projected outflows stay accurate.';
    }
    return 'Set up accounts, recurring bills, and income in Forecast and Recurring so tips match the same numbers as the model.';
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
