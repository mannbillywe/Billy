import 'package:intl/intl.dart';

import '../../../core/utils/document_date_range.dart';

/// Documents with `date` in [today, today + daysAhead], non-draft.
List<Map<String, dynamic>> upcomingDocumentsWithinDays(
  List<Map<String, dynamic>> all, {
  int daysAhead = 14,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(Duration(days: daysAhead));
  final out = <Map<String, dynamic>>[];
  for (final d in all) {
    if ((d['status'] as String?) == 'draft') continue;
    final dt = DateTime.tryParse(d['date']?.toString() ?? '');
    if (dt == null) continue;
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day.isBefore(today) || day.isAfter(end)) continue;
    out.add(d);
  }
  out.sort((a, b) {
    final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? today;
    final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? today;
    return da.compareTo(db);
  });
  return out;
}

DateTime? _activityDayForSpend(Map<String, dynamic> d, WeekSpendBasis basis) {
  final docRaw = DateTime.tryParse(d['date']?.toString() ?? '');
  final createdRaw = DateTime.tryParse(d['created_at']?.toString() ?? '');
  final docDay = docRaw != null ? DateTime(docRaw.year, docRaw.month, docRaw.day) : null;
  final createdDay = createdRaw != null ? DateTime(createdRaw.year, createdRaw.month, createdRaw.day) : null;
  switch (basis) {
    case WeekSpendBasis.uploadDate:
      return createdDay;
    case WeekSpendBasis.invoiceDate:
      return docDay;
    case WeekSpendBasis.hybrid:
      return docDay ?? createdDay;
  }
}

/// Total spend in the last [days] calendar days (non-draft), by activity day.
double spendLastDaysByBasis(List<Map<String, dynamic>> all, int days, WeekSpendBasis basis) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final start = end.subtract(Duration(days: days - 1));
  var sum = 0.0;
  for (final d in all) {
    if ((d['status'] as String?) == 'draft') continue;
    final day = _activityDayForSpend(d, basis);
    if (day == null) continue;
    if (!day.isBefore(start) && !day.isAfter(end)) {
      sum += (d['amount'] as num?)?.toDouble() ?? 0;
    }
  }
  return sum;
}

/// Same window and basis as [spendLastDaysByBasis], but skips documents whose `id` is in [excludedDocIds].
double spendLastDaysByBasisExcluding(
  List<Map<String, dynamic>> all,
  int days,
  WeekSpendBasis basis,
  Set<String> excludedDocIds,
) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final start = end.subtract(Duration(days: days - 1));
  var sum = 0.0;
  for (final d in all) {
    if ((d['status'] as String?) == 'draft') continue;
    final id = d['id'] as String?;
    if (id != null && excludedDocIds.contains(id)) continue;
    if (d['exclude_from_goat_smart_analytics'] == true) continue;
    final day = _activityDayForSpend(d, basis);
    if (day == null) continue;
    if (!day.isBefore(start) && !day.isAfter(end)) {
      sum += (d['amount'] as num?)?.toDouble() ?? 0;
    }
  }
  return sum;
}

/// Active statement debits in the same rolling window as [spendLastDaysByBasis] (posted `txn_date`).
double sumStatementDebitsLastDays(List<Map<String, dynamic>> statementRows, int days) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final start = end.subtract(Duration(days: days - 1));
  var sum = 0.0;
  for (final t in statementRows) {
    if ((t['direction'] as String?) != 'debit') continue;
    if ((t['status'] as String?) != 'active') continue;
    final dt = DateTime.tryParse(t['txn_date']?.toString() ?? '');
    if (dt == null) continue;
    final day = DateTime(dt.year, dt.month, dt.day);
    if (!day.isBefore(start) && !day.isAfter(end)) {
      sum += (t['amount'] as num?)?.toDouble() ?? 0;
    }
  }
  return sum;
}

/// Total spend in the last [days] calendar days using bill date only (legacy).
double spendLastDays(List<Map<String, dynamic>> all, int days) =>
    spendLastDaysByBasis(all, days, WeekSpendBasis.invoiceDate);

enum GoatCashFlowRisk { low, medium, high }

/// Compare last-7d spend pace vs prior-7d window (rough heuristic).
GoatCashFlowRisk cashFlowRiskFromDocumentsByBasis(List<Map<String, dynamic>> all, WeekSpendBasis basis) {
  final w0 = spendLastDaysByBasis(all, 7, basis);
  final w1 = _spendInRangeByBasis(all, 14, 8, basis);
  if (w1 <= 0 && w0 <= 0) return GoatCashFlowRisk.low;
  if (w1 <= 0) return w0 > 0 ? GoatCashFlowRisk.medium : GoatCashFlowRisk.low;
  final ratio = w0 / w1;
  if (ratio >= 1.25) return GoatCashFlowRisk.high;
  if (ratio >= 1.08) return GoatCashFlowRisk.medium;
  return GoatCashFlowRisk.low;
}

GoatCashFlowRisk cashFlowRiskFromDocuments(List<Map<String, dynamic>> all) =>
    cashFlowRiskFromDocumentsByBasis(all, WeekSpendBasis.invoiceDate);

double _spendInRangeByBasis(List<Map<String, dynamic>> all, int endDaysAgo, int startDaysAgo, WeekSpendBasis basis) {
  final now = DateTime.now();
  final endDay = DateTime(now.year, now.month, now.day).subtract(Duration(days: endDaysAgo));
  final startDay = DateTime(now.year, now.month, now.day).subtract(Duration(days: startDaysAgo));
  var sum = 0.0;
  for (final d in all) {
    if ((d['status'] as String?) == 'draft') continue;
    final day = _activityDayForSpend(d, basis);
    if (day == null) continue;
    if (!day.isBefore(startDay) && !day.isAfter(endDay)) {
      sum += (d['amount'] as num?)?.toDouble() ?? 0;
    }
  }
  return sum;
}

String formatShortDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return DateFormat.MMMd().format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}
