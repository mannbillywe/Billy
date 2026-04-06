import 'package:intl/intl.dart';

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

/// Total spend in the last [days] calendar days (non-draft).
double spendLastDays(List<Map<String, dynamic>> all, int days) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final start = end.subtract(Duration(days: days - 1));
  var sum = 0.0;
  for (final d in all) {
    if ((d['status'] as String?) == 'draft') continue;
    final dt = DateTime.tryParse(d['date']?.toString() ?? '');
    if (dt == null) continue;
    final day = DateTime(dt.year, dt.month, dt.day);
    if (!day.isBefore(start) && !day.isAfter(end)) {
      sum += (d['amount'] as num?)?.toDouble() ?? 0;
    }
  }
  return sum;
}

enum GoatCashFlowRisk { low, medium, high }

/// Compare last-7d spend pace vs prior-7d window (rough heuristic).
GoatCashFlowRisk cashFlowRiskFromDocuments(List<Map<String, dynamic>> all) {
  final w0 = spendLastDays(all, 7);
  final w1 = _spendInRange(all, 14, 8);
  if (w1 <= 0 && w0 <= 0) return GoatCashFlowRisk.low;
  if (w1 <= 0) return w0 > 0 ? GoatCashFlowRisk.medium : GoatCashFlowRisk.low;
  final ratio = w0 / w1;
  if (ratio >= 1.25) return GoatCashFlowRisk.high;
  if (ratio >= 1.08) return GoatCashFlowRisk.medium;
  return GoatCashFlowRisk.low;
}

double _spendInRange(List<Map<String, dynamic>> all, int endDaysAgo, int startDaysAgo) {
  final now = DateTime.now();
  final endDay = DateTime(now.year, now.month, now.day).subtract(Duration(days: endDaysAgo));
  final startDay = DateTime(now.year, now.month, now.day).subtract(Duration(days: startDaysAgo));
  var sum = 0.0;
  for (final d in all) {
    if ((d['status'] as String?) == 'draft') continue;
    final dt = DateTime.tryParse(d['date']?.toString() ?? '');
    if (dt == null) continue;
    final day = DateTime(dt.year, dt.month, dt.day);
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
