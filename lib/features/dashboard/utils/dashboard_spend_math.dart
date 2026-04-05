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
  ) {
    final docDay = _parseDocDay(d['date']);
    if (docDay != null &&
        !docDay.isBefore(mon) &&
        !docDay.isAfter(weekSunday) &&
        !docDay.isAfter(today)) {
      return docDay;
    }
    final createdDay = _parseCreatedDay(d['created_at']);
    if (createdDay != null && !createdDay.isBefore(mon) && !createdDay.isAfter(today)) {
      return createdDay;
    }
    return null;
  }

  /// Same idea as [_thisWeekActivityDay] for the previous calendar week (Mon–Sun).
  static DateTime? _prevWeekActivityDay(
    Map<String, dynamic> d,
    DateTime prevMon,
    DateTime prevSun,
  ) {
    final docDay = _parseDocDay(d['date']);
    if (docDay != null && !docDay.isBefore(prevMon) && !docDay.isAfter(prevSun)) {
      return docDay;
    }
    final createdDay = _parseCreatedDay(d['created_at']);
    if (createdDay != null && !createdDay.isBefore(prevMon) && !createdDay.isAfter(prevSun)) {
      return createdDay;
    }
    return null;
  }

  /// Non-draft document amounts attributed to the current calendar week (local).
  static double thisWeekDocumentSpend(List<Map<String, dynamic>> docs, [DateTime? now]) {
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    final sunday = _dateOnly(mon.add(const Duration(days: 6)));
    var total = 0.0;
    for (final d in docs) {
      if ((d['status'] as String?) == 'draft') continue;
      if (_thisWeekActivityDay(d, mon, n, sunday) == null) continue;
      total += (d['amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  /// Full previous calendar week (Mon–Sun), non-draft documents.
  static double lastCalendarWeekDocumentSpend(List<Map<String, dynamic>> docs, [DateTime? now]) {
    final n = _dateOnly(now ?? DateTime.now());
    final thisMon = mondayOfWeek(n);
    final prevSun = _dateOnly(thisMon.subtract(const Duration(days: 1)));
    final prevMon = _dateOnly(thisMon.subtract(const Duration(days: 7)));
    var total = 0.0;
    for (final d in docs) {
      if ((d['status'] as String?) == 'draft') continue;
      if (_prevWeekActivityDay(d, prevMon, prevSun) == null) continue;
      total += (d['amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  /// Seven values for Mon–Sun of the current calendar week. Future days (after today) are 0.
  static List<double> thisWeekDailyDocumentSpend(List<Map<String, dynamic>> docs, [DateTime? now]) {
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    final sunday = _dateOnly(mon.add(const Duration(days: 6)));
    final byDay = <DateTime, double>{};
    for (final d in docs) {
      if ((d['status'] as String?) == 'draft') continue;
      final day = _thisWeekActivityDay(d, mon, n, sunday);
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
  static bool debugSeriesMatchesHero(List<Map<String, dynamic>> docs, [DateTime? now]) {
    final series = thisWeekDailyDocumentSpend(docs, now);
    final n = _dateOnly(now ?? DateTime.now());
    final mon = mondayOfWeek(n);
    var sum = 0.0;
    for (var i = 0; i < 7; i++) {
      final day = mon.add(Duration(days: i));
      if (day.isAfter(n)) break;
      sum += series[i];
    }
    return (sum - thisWeekDocumentSpend(docs, now)).abs() < 0.0001;
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
}
