import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/goat/finance/cashflow_engine.dart';
import '../features/goat/finance/finance_repository.dart';
import '../features/goat/goals/goal_engine.dart';
import '../features/goat/recurring/recurring_repository.dart';
import '../features/goat/statements/goat_analysis_lens.dart';
import '../features/goat/statements/statement_repository.dart';
import 'goat_goals_providers.dart';
import 'goat_lens_provider.dart';

/// Recurring series + near-future occurrences (GOAT Recurring + Forecast input).
class GoatRecurringBundleNotifier extends AsyncNotifier<({List<Map<String, dynamic>> series, List<Map<String, dynamic>> occ})> {
  @override
  Future<({List<Map<String, dynamic>> series, List<Map<String, dynamic>> occ})> build() async {
    final series = await RecurringRepository.fetchSeries();
    final from = DateTime.now();
    final to = from.add(const Duration(days: 120));
    final occ = await RecurringRepository.fetchOccurrences(fromDue: from, toDue: to, limit: 200);
    return (series: series, occ: occ);
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final series = await RecurringRepository.fetchSeries();
      final from = DateTime.now();
      final to = from.add(const Duration(days: 120));
      final occ = await RecurringRepository.fetchOccurrences(fromDue: from, toDue: to, limit: 200);
      return (series: series, occ: occ);
    });
  }
}

final goatRecurringBundleProvider =
    AsyncNotifierProvider<GoatRecurringBundleNotifier, ({List<Map<String, dynamic>> series, List<Map<String, dynamic>> occ})>(
  GoatRecurringBundleNotifier.new,
);

/// Reserve / buffer in **minor units** (e.g. ₹500 → 50000 paise).
class ForecastReserveNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setReservePaise(int paise) => state = paise < 0 ? 0 : paise;
}

final forecastReserveProvider = NotifierProvider<ForecastReserveNotifier, int>(ForecastReserveNotifier.new);

class GoatForecastHorizonNotifier extends Notifier<int> {
  @override
  int build() => 30;

  void setDays(int d) => state = d.clamp(7, 90);
}

final goatForecastHorizonProvider = NotifierProvider<GoatForecastHorizonNotifier, int>(GoatForecastHorizonNotifier.new);

/// Optional one-off outflow today for “what if I spend X?” (minor units / paise).
class WhatIfSpendTodayNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setPaise(int p) => state = p < 0 ? 0 : p;

  void clear() => state = 0;
}

final whatIfSpendTodayProvider = NotifierProvider<WhatIfSpendTodayNotifier, int>(WhatIfSpendTodayNotifier.new);

/// Deterministic forecast from DB (accounts, recurring, income, planned).
final goatForecastProvider = FutureProvider<CashflowForecastResult>((ref) async {
  final lens = ref.watch(goatAnalysisLensProvider);
  final bundle = await ref.watch(goatRecurringBundleProvider.future);
  final reserve = ref.watch(forecastReserveProvider);
  final horizon = ref.watch(goatForecastHorizonProvider);
  final whatIf = ref.watch(whatIfSpendTodayProvider);

  final accounts = await FinanceRepository.fetchAccounts();
  final income = await FinanceRepository.fetchIncomeStreams();
  final planned = await FinanceRepository.fetchPlannedEvents();

  final goalsInput = await ref.watch(goatGoalsForecastInputProvider.future);
  final goalsHard = GoalEngine.totalHardReserveMonthlyMinor(goalsInput.activeGoals, goalsInput.rulesByGoalId);

  List<StatementForecastDebit> stmtDebits = const [];
  if (lens == GoatAnalysisLens.statementsOnly) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = today.add(Duration(days: horizon));
    final rows = await StatementRepository.fetchDebitTransactionsInDateRange(fromInclusive: today, toInclusive: end);
    stmtDebits = rows
        .map((t) {
          final raw = t['txn_date']?.toString();
          final d = DateTime.tryParse(raw ?? '') ?? today;
          final day = DateTime(d.year, d.month, d.day);
          final amt = (t['amount'] as num?)?.toDouble() ?? 0;
          final lab = (t['description_raw'] as String?)?.trim() ?? '';
          return StatementForecastDebit(
            date: day,
            minor: CashflowMoneyLine.toMinor(amt),
            label: lab.isEmpty ? 'Statement debit' : lab,
          );
        })
        .where((e) => e.minor > 0)
        .toList();
  }

  return CashflowEngine.compute(
    horizonDays: horizon,
    accounts: accounts,
    recurringSeries: bundle.series,
    occurrences: bundle.occ,
    incomeStreams: income,
    plannedEvents: planned,
    reserveMinor: reserve,
    whatIfExtraOutflowTodayMinor: whatIf,
    goalsHardReserveMonthlyMinor: goalsHard,
    statementDebitsInHorizon: stmtDebits,
  );
});

final financialAccountsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return FinanceRepository.fetchAccounts();
});

final incomeStreamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FinanceRepository.fetchIncomeStreams();
});

final plannedCashEventsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return FinanceRepository.fetchPlannedEvents();
});
