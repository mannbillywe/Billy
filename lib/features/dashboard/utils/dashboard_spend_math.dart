import '../../../core/utils/document_date_range.dart';
import '../../lend_borrow/lend_borrow_perspective.dart';

/// Calendar-week document spend and aligned daily series (local dates).
/// Used so the hero total, sparkline, and document list stay consistent after deletes.
class DashboardSpendMath {
  DashboardSpendMath._();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Monday (local) of the ISO week containing [now].
  static DateTime mondayOfWeek([DateTime? now]) {
    final n = _dateOnly(now ?? DateTime.now());
    return n.subtract(Duration(days: n.weekday - DateTime.monday));
  }

  static DateTime? _parseDocDay(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return null;
    return _dateOnly(dt);
  }

  static DateTime? _parseCreatedDay(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return null;
    return _dateOnly(dt);
  }

  /// Which calendar day to attribute spend for "this week" UI.
  ///
  /// Prefer [documents.date] when it falls in the current ISO week (Mon–Sun) and is
  /// not after [today]. Otherwise use [created_at] when the row was saved — scans often
  /// store the invoice date, which can be months old, so category totals (all-time) would
  /// update while "this week" stayed 0 without this fallback.
  static DateTime? _thisWeekActivityDay(
    Map<String, dynamic> d,
    DateTime mon,
    DateTime today,
    DateTime weekSunday,
    WeekSpendBasis basis,
  ) {
    final docDay = _parseDocDay(d['date']);
    final createdDay = _parseCreatedDay(d['created_at']);

    switch (basis) {
      case WeekSpendBasis.uploadDate:
        if (createdDay != null &&
            !createdDay.isBefore(mon) &&
            !createdDay.isAfter(today) &&
            !createdDay.isAfter(weekSunday)) {
          return createdDay;
        }
        return null;
      case WeekSpendBasis.invoiceDate:
        if (docDay != null &&
            !docDay.isBefore(mon) &&
            !docDay.isAfter(weekSunday) &&
            !docDay.isAfter(today)) {
          return docDay;
        }
        return null;
      case WeekSpendBasis.hybrid:
        if (docDay != null &&
            !docDay.isBefore(mon) &&
            !docDay.isAfter(weekSunday) &&
            !docDay.isAfter(today)) {
          return docDay;
        }
        if (createdDay != null && !createdDay.isBefore(mon) && !createdDay.isAfter(today)) {
          return createdDay;
        }
        return null;
    }
  }

  /// Same idea as [_thisWeekActivityDay] for the previous calendar week (Mon–Sun).
  static DateTime? _prevWeekActivityDay(
    Map<String, dynamic> d,
    DateTime prevMon,
    DateTime prevSun,
    WeekSpendBasis basis,
  ) {
    final docDay = _parseDocDay(d['date']);
    final createdDay = _parseCreatedDay(d['created_at']);

    switch (basis) {
      case WeekSpendBasis.uploadDate:
        if (createdDay != null && !createdDay.isBefore(prevMon) && !createdDay.isAfter(prevSun)) {
          return createdDay;
        }
        return null;
      case WeekSpendBasis.invoiceDate:
        if (docDay != null && !docDay.isBefore(prevMon) && !docDay.isAfter(prevSun)) {
          return docDay;
        }
        return null;
      case WeekSpendBasis.hybrid:
        if (docDay != null && !docDay.isBefore(prevMon) && !docDay.isAfter(prevSun)) {
          return docDay;
        }
        if (createdDay != null && !createdDay.isBefore(prevMon) && !createdDay.isAfter(prevSun)) {
          return createdDay;
        }
        return null;
    }
  }

  /// Count of non-draft documents in the **calendar** ISO week (same rules as [thisWeekDocumentSpend]).
  static int thisWeekDocumentCount(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    final sunday = _dateOnly(mon.add(const Duration(days: 6)));
    var c = 0;
    for (final d in docs) {
      if ((d['status'] as String?) == 'draft') continue;
      if (_thisWeekActivityDay(d, mon, n, sunday, basis) == null) continue;
      c++;
    }
    return c;
  }

  /// Non-draft document amounts attributed to the current calendar week (local).
  static double thisWeekDocumentSpend(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    final sunday = _dateOnly(mon.add(const Duration(days: 6)));
    var total = 0.0;
    for (final d in docs) {
      if ((d['status'] as String?) == 'draft') continue;
      if (_thisWeekActivityDay(d, mon, n, sunday, basis) == null) continue;
      total += (d['amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  /// Full previous calendar week (Mon–Sun), non-draft documents.
  static double lastCalendarWeekDocumentSpend(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    final n = _dateOnly(now ?? DateTime.now());
    final thisMon = mondayOfWeek(n);
    final prevSun = _dateOnly(thisMon.subtract(const Duration(days: 1)));
    final prevMon = _dateOnly(thisMon.subtract(const Duration(days: 7)));
    var total = 0.0;
    for (final d in docs) {
      if ((d['status'] as String?) == 'draft') continue;
      if (_prevWeekActivityDay(d, prevMon, prevSun, basis) == null) continue;
      total += (d['amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  /// Seven values for Mon–Sun of the current calendar week. Future days (after today) are 0.
  static List<double> thisWeekDailyDocumentSpend(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    final sunday = _dateOnly(mon.add(const Duration(days: 6)));
    final byDay = <DateTime, double>{};
    for (final d in docs) {
      if ((d['status'] as String?) == 'draft') continue;
      final day = _thisWeekActivityDay(d, mon, n, sunday, basis);
      if (day == null) continue;
      byDay[day] = (byDay[day] ?? 0) + ((d['amount'] as num?)?.toDouble() ?? 0);
    }
    final out = <double>[];
    for (var i = 0; i < 7; i++) {
      final day = mon.add(Duration(days: i));
      if (day.isAfter(n)) {
        out.add(0);
      } else {
        out.add(byDay[_dateOnly(day)] ?? 0);
      }
    }
    return out;
  }

  /// Verifies [thisWeekDocumentSpend] equals the sum of Mon..today in [thisWeekDailyDocumentSpend].
  static bool debugSeriesMatchesHero(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    final series = thisWeekDailyDocumentSpend(docs, now, basis);
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    var sum = 0.0;
    for (var i = 0; i < 7; i++) {
      final day = mon.add(Duration(days: i));
      if (day.isAfter(n)) break;
      sum += series[i];
    }
    return (sum - thisWeekDocumentSpend(docs, now, basis)).abs() < 0.0001;
  }

  /// Verifies [rollingSevenDayDocumentSpend] equals the sum of all 7 buckets in [rollingSevenDayDailyDocumentSpend].
  static bool debugRollingSeriesMatchesHero(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    final series = rollingSevenDayDailyDocumentSpend(docs, now, basis);
    final sum = series.fold<double>(0, (a, b) => a + b);
    return (sum - rollingSevenDayDocumentSpend(docs, now, basis)).abs() < 0.0001;
  }

  /// Home hero + Money Flow: **rolling last 7 days** ending today (same logic as Analytics **1W** chart).
  static List<double> rollingSevenDayDailyDocumentSpend(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    final n = _dateOnly(now ?? DateTime.now());
    return DocumentDateRange.lastSevenDaySpendingByBasis(docs, n, basis);
  }

  static double rollingSevenDayDocumentSpend(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    return DocumentDateRange.totalRollingSevenDaySpend(docs, _dateOnly(now ?? DateTime.now()), basis);
  }

  static int rollingSevenDayDocumentCount(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    return DocumentDateRange.countDocumentsRollingSevenDay(docs, _dateOnly(now ?? DateTime.now()), basis);
  }

  /// The 7 days immediately before the current rolling window (for "vs prior week" on home).
  static double priorRollingSevenDayDocumentSpend(
    List<Map<String, dynamic>> docs, [
    DateTime? now,
    WeekSpendBasis basis = WeekSpendBasis.hybrid,
  ]) {
    final priorEnd = _dateOnly(now ?? DateTime.now()).subtract(const Duration(days: 7));
    return DocumentDateRange.totalRollingSevenDaySpend(docs, priorEnd, basis);
  }

  static String weekBasisSubtitle(WeekSpendBasis basis) {
    switch (basis) {
      case WeekSpendBasis.uploadDate:
        return 'Receipts & invoices · last 7 days by save date (matches Analytics 1W)';
      case WeekSpendBasis.invoiceDate:
        return 'Receipts & invoices · last 7 days by bill date (matches Analytics 1W)';
      case WeekSpendBasis.hybrid:
        return 'Receipts & invoices · last 7 days — bill date in window, else save date (matches Analytics 1W)';
    }
  }

  /// Pending lend/borrow from the viewer's perspective (same as Friends tab).
  static ({double collect, double pay}) pendingLendBorrowTotals(
    List<Map<String, dynamic>> entries,
    String? viewerUid,
  ) {
    double collect = 0;
    double pay = 0;
    for (final e in entries) {
      if (e['status'] != 'pending') continue;
      final amount = (e['amount'] as num?)?.toDouble() ?? 0;
      if (effectiveTypeForViewer(e, viewerUid) == 'lent') {
        collect += amount;
      } else {
        pay += amount;
      }
    }
    return (collect: collect, pay: pay);
  }

  /// Pending entries whose `created_at` falls Mon–today this week (new IOU activity).
  static ({double collect, double pay}) lendBorrowAddedThisCalendarWeek(
    List<Map<String, dynamic>> entries,
    String? viewerUid, [
    DateTime? now,
  ]) {
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    double collect = 0;
    double pay = 0;
    for (final e in entries) {
      if (e['status'] != 'pending') continue;
      final created = _parseCreatedDay(e['created_at']);
      if (created == null || created.isBefore(mon) || created.isAfter(n)) continue;
      final amount = (e['amount'] as num?)?.toDouble() ?? 0;
      if (effectiveTypeForViewer(e, viewerUid) == 'lent') {
        collect += amount;
      } else {
        pay += amount;
      }
    }
    return (collect: collect, pay: pay);
  }

  /// Seven values (Mon–Sun): pending IOUs **created** that day (local), viewer perspective.
  /// Future days after [now] are zero. Aligns with [lendBorrowAddedThisCalendarWeek] totals.
  static ({List<double> collect, List<double> pay}) thisWeekDailyLendBorrow(
    List<Map<String, dynamic>> entries,
    String? viewerUid, [
    DateTime? now,
  ]) {
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    final collectByDay = <DateTime, double>{};
    final payByDay = <DateTime, double>{};
    for (final e in entries) {
      if (e['status'] != 'pending') continue;
      final created = _parseCreatedDay(e['created_at']);
      if (created == null || created.isBefore(mon) || created.isAfter(n)) continue;
      final amount = (e['amount'] as num?)?.toDouble() ?? 0;
      if (effectiveTypeForViewer(e, viewerUid) == 'lent') {
        collectByDay[created] = (collectByDay[created] ?? 0) + amount;
      } else {
        payByDay[created] = (payByDay[created] ?? 0) + amount;
      }
    }
    final collect = <double>[];
    final pay = <double>[];
    for (var i = 0; i < 7; i++) {
      final day = mon.add(Duration(days: i));
      if (day.isAfter(n)) {
        collect.add(0);
        pay.add(0);
      } else {
        final key = _dateOnly(day);
        collect.add(collectByDay[key] ?? 0);
        pay.add(payByDay[key] ?? 0);
      }
    }
    return (collect: collect, pay: pay);
  }

  /// Sum of Mon..today in [thisWeekDailyLendBorrow] equals [lendBorrowAddedThisCalendarWeek] collect+pay split.
  static bool debugLendWeekSeriesMatchesTotals(
    List<Map<String, dynamic>> entries,
    String? viewerUid, [
    DateTime? now,
  ]) {
    final s = thisWeekDailyLendBorrow(entries, viewerUid, now);
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    var c = 0.0;
    var p = 0.0;
    for (var i = 0; i < 7; i++) {
      final day = mon.add(Duration(days: i));
      if (day.isAfter(n)) break;
      c += s.collect[i];
      p += s.pay[i];
    }
    final t = lendBorrowAddedThisCalendarWeek(entries, viewerUid, now);
    return (c - t.collect).abs() < 0.0001 && (p - t.pay).abs() < 0.0001;
  }
}
