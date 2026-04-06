import 'package:flutter/foundation.dart';

import '../recurring/recurring_cadence.dart';

/// Money in **minor units** (e.g. paise) for deterministic integer math.
@immutable
class CashflowMoneyLine {
  const CashflowMoneyLine({
    required this.label,
    required this.minor,
    required this.kind,
  });

  final String label;
  final int minor;
  final String kind;

  static int toMinor(double amount) => (amount * 100).round();
  static double fromMinor(int m) => m / 100.0;
}

@immutable
class CashflowDay {
  const CashflowDay({
    required this.date,
    required this.openingMinor,
    required this.inflowMinor,
    required this.outflowMinor,
    required this.closingMinor,
    required this.lines,
  });

  final DateTime date;
  final int openingMinor;
  final int inflowMinor;
  final int outflowMinor;
  final int closingMinor;
  final List<CashflowMoneyLine> lines;
}

@immutable
class CashflowForecastResult {
  const CashflowForecastResult({
    required this.horizonDays,
    required this.startDate,
    required this.endDate,
    required this.liquidMinor,
    required this.reserveMinor,
    required this.safeToSpendNowMinor,
    required this.safeToSpend7dMinor,
    required this.projectedMinBalanceMinor,
    required this.projectedEndBalanceMinor,
    required this.riskLevel,
    required this.days,
    required this.breakdownLines,
    required this.nextIncomeDate,
    this.lowestBalanceDate,
  });

  final int horizonDays;
  final DateTime startDate;
  final DateTime endDate;
  final int liquidMinor;
  final int reserveMinor;
  final int safeToSpendNowMinor;
  final int safeToSpend7dMinor;
  final int projectedMinBalanceMinor;
  final int projectedEndBalanceMinor;
  final String riskLevel;
  final List<CashflowDay> days;
  final List<CashflowMoneyLine> breakdownLines;
  final DateTime? nextIncomeDate;
  /// First day in the horizon where closing balance equals [projectedMinBalanceMinor].
  final DateTime? lowestBalanceDate;
}

/// Deterministic cash-flow simulation (no AI).
class CashflowEngine {
  CashflowEngine._();

  static DateTime _dOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static int _numMinor(dynamic v) => CashflowMoneyLine.toMinor((v as num?)?.toDouble() ?? 0);

  /// Builds a day-by-day projection and safe-to-spend figures.
  static CashflowForecastResult compute({
    required int horizonDays,
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> recurringSeries,
    required List<Map<String, dynamic>> occurrences,
    required List<Map<String, dynamic>> incomeStreams,
    required List<Map<String, dynamic>> plannedEvents,
    int reserveMinor = 0,
    int whatIfExtraOutflowTodayMinor = 0,
    DateTime? now,
  }) {
    final today = _dOnly(now ?? DateTime.now());
    final end = today.add(Duration(days: horizonDays < 1 ? 30 : horizonDays));

    var liquid = 0;
    for (final a in accounts) {
      if (a['include_in_safe_to_spend'] == false) continue;
      liquid += _numMinor(a['current_balance']);
    }

    final events = <DateTime, List<CashflowMoneyLine>>{};

    void addEv(DateTime d, CashflowMoneyLine line) {
      final k = _dOnly(d);
      events.putIfAbsent(k, () => <CashflowMoneyLine>[]).add(line);
    }

    void addBillOutflowsFromOccurrences() {
      for (final o in occurrences) {
        if ((o['status'] as String?) == 'paid' || (o['status'] as String?) == 'skipped') continue;
        final due = _parseDate(o['due_date']);
        if (due == null) continue;
        final dd = _dOnly(due);
        if (dd.isBefore(today) || dd.isAfter(end)) continue;
        final amt = _numMinor(o['expected_amount']);
        if (amt <= 0) continue;
        addEv(dd, CashflowMoneyLine(label: 'Bill / subscription', minor: amt, kind: 'bill'));
      }
    }

    void addBillOutflowsFromSeries() {
      for (final s in recurringSeries) {
        final st = s['status'] as String? ?? '';
        if (st != 'active' && st != 'suggested') continue;
        final freq = s['frequency'] as String? ?? 'monthly';
        final iv = (s['interval_count'] as num?)?.toInt() ?? 1;
        final firstDue = _parseDate(s['next_due_date']);
        if (firstDue == null) continue;
        DateTime cursor = _dOnly(firstDue);
        final exp = _numMinor(s['expected_amount']);
        if (exp <= 0) continue;
        final title = (s['title'] as String?)?.trim().isNotEmpty == true ? s['title'] as String : 'Recurring';
        while (!cursor.isAfter(end)) {
          if (!cursor.isBefore(today)) {
            addEv(cursor, CashflowMoneyLine(label: title, minor: exp, kind: 'recurring'));
          }
          cursor = addRecurringPeriod(cursor, freq, iv);
        }
      }
    }

    if (occurrences.isNotEmpty) {
      addBillOutflowsFromOccurrences();
    } else {
      addBillOutflowsFromSeries();
    }

    DateTime? nextIncome;
    for (final inc in incomeStreams) {
      if ((inc['status'] as String?) != 'active') continue;
      final freq = inc['frequency'] as String? ?? 'monthly';
      final amt = _numMinor(inc['expected_amount']);
      if (amt <= 0) continue;
      final incFirst = _parseDate(inc['next_expected_date']);
      if (incFirst == null) continue;
      DateTime cursor = _dOnly(incFirst);
      final title = (inc['title'] as String?) ?? 'Income';
      while (!cursor.isAfter(end)) {
        if (!cursor.isBefore(today)) {
          addEv(cursor, CashflowMoneyLine(label: title, minor: -amt, kind: 'income'));
          if (nextIncome == null || cursor.isBefore(nextIncome!)) {
            nextIncome = cursor;
          }
        }
        if (freq == 'irregular') break;
        if (freq == 'weekly') {
          cursor = cursor.add(const Duration(days: 7));
        } else if (freq == 'biweekly') {
          cursor = cursor.add(const Duration(days: 14));
        } else if (freq == 'monthly') {
          cursor = addRecurringPeriod(cursor, 'monthly', 1);
        } else {
          cursor = addRecurringPeriod(cursor, 'monthly', 1);
        }
      }
    }

    if (whatIfExtraOutflowTodayMinor > 0) {
      addEv(
        today,
        CashflowMoneyLine(label: 'What-if spend today', minor: whatIfExtraOutflowTodayMinor, kind: 'what_if'),
      );
    }

    for (final p in plannedEvents) {
      final dt = _parseDate(p['event_date']);
      if (dt == null) continue;
      final dd = _dOnly(dt);
      if (dd.isBefore(today) || dd.isAfter(end)) continue;
      final amt = _numMinor(p['amount']);
      final dir = p['direction'] as String? ?? 'outflow';
      final title = (p['title'] as String?) ?? 'Planned';
      if (dir == 'inflow') {
        addEv(dd, CashflowMoneyLine(label: title, minor: -amt, kind: 'planned_in'));
      } else {
        addEv(dd, CashflowMoneyLine(label: title, minor: amt, kind: 'planned_out'));
      }
    }

    final sortedDays = <DateTime>[];
    for (var i = 0; i <= end.difference(today).inDays; i++) {
      sortedDays.add(today.add(Duration(days: i)));
    }

    var opening = liquid;
    final dayRows = <CashflowDay>[];
    var minClose = opening;
    var endClose = opening;

    for (final day in sortedDays) {
      final lines = List<CashflowMoneyLine>.from(events[day] ?? []);
      int inflow = 0;
      int outflow = 0;
      for (final l in lines) {
        final int m = l.minor;
        if (m < 0) {
          inflow = inflow - m;
        } else {
          outflow = outflow + m;
        }
      }
      final closing = opening - outflow + inflow;
      dayRows.add(
        CashflowDay(
          date: day,
          openingMinor: opening,
          inflowMinor: inflow,
          outflowMinor: outflow,
          closingMinor: closing,
          lines: lines,
        ),
      );
      if (closing < minClose) minClose = closing;
      endClose = closing;
      opening = closing;
    }

    final anchor = nextIncome ?? end;
    int dueOut = 0;
    int dueIn = 0;
    for (final day in sortedDays) {
      if (day.isAfter(anchor)) break;
      for (final l in events[day] ?? const <CashflowMoneyLine>[]) {
        final int m = l.minor;
        if (m > 0) {
          dueOut = dueOut + m;
        } else {
          dueIn = dueIn - m;
        }
      }
    }

    final safeNow = liquid - reserveMinor - dueOut + dueIn;

    final sevenEnd = today.add(const Duration(days: 7));
    int dueOut7 = 0;
    int dueIn7 = 0;
    for (final day in sortedDays) {
      if (day.isAfter(sevenEnd)) break;
      for (final l in events[day] ?? const <CashflowMoneyLine>[]) {
        final int m = l.minor;
        if (m > 0) {
          dueOut7 = dueOut7 + m;
        } else {
          dueIn7 = dueIn7 - m;
        }
      }
    }
    final safe7 = liquid - reserveMinor - dueOut7 + dueIn7;

    String risk = 'low';
    if (minClose < 0 || safeNow < 0) {
      risk = 'high';
    } else if (minClose < reserveMinor || safeNow < CashflowMoneyLine.toMinor(500)) {
      risk = 'medium';
    }

    final breakdown = <CashflowMoneyLine>[
      CashflowMoneyLine(label: 'Liquid balances (included accounts)', minor: liquid, kind: 'breakdown_base'),
      CashflowMoneyLine(label: 'Reserve / buffer held back', minor: reserveMinor, kind: 'breakdown_sub'),
      CashflowMoneyLine(
        label: 'Committed outflows until ${_ymd(anchor)}',
        minor: dueOut,
        kind: 'breakdown_sub',
      ),
      CashflowMoneyLine(
        label: 'Expected inflows until ${_ymd(anchor)} (offsets outflows)',
        minor: dueIn,
        kind: 'breakdown_add',
      ),
    ];

    DateTime? lowestBalanceDate;
    for (final row in dayRows) {
      if (row.closingMinor == minClose) {
        lowestBalanceDate = row.date;
        break;
      }
    }

    return CashflowForecastResult(
      horizonDays: horizonDays < 1 ? 30 : horizonDays,
      startDate: today,
      endDate: end,
      liquidMinor: liquid,
      reserveMinor: reserveMinor,
      safeToSpendNowMinor: safeNow,
      safeToSpend7dMinor: safe7,
      projectedMinBalanceMinor: minClose,
      projectedEndBalanceMinor: endClose,
      riskLevel: risk,
      days: dayRows,
      breakdownLines: breakdown,
      nextIncomeDate: nextIncome,
      lowestBalanceDate: lowestBalanceDate,
    );
  }
}
