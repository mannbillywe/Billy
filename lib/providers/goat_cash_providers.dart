import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/goat/finance/cashflow_engine.dart';
import '../features/goat/finance/finance_repository.dart';
import '../features/goat/recurring/recurring_repository.dart';

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
  final bundle = await ref.watch(goatRecurringBundleProvider.future);
  final reserve = ref.watch(forecastReserveProvider);
  final horizon = ref.watch(goatForecastHorizonProvider);
  final whatIf = ref.watch(whatIfSpendTodayProvider);

  final accounts = await FinanceRepository.fetchAccounts();
  final income = await FinanceRepository.fetchIncomeStreams();
  final planned = await FinanceRepository.fetchPlannedEvents();

  return CashflowEngine.compute(
    horizonDays: horizon,
    accounts: accounts,
    recurringSeries: bundle.series,
    occurrences: bundle.occ,
    incomeStreams: income,
    plannedEvents: planned,
    reserveMinor: reserve,
    whatIfExtraOutflowTodayMinor: whatIf,
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
