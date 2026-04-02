import 'package:flutter/foundation.dart';

@immutable
class DocumentDateRange {
  const DocumentDateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;

  /// Filter keys: 1W, 1M, 3M
  static DocumentDateRange forFilter(String key) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (key) {
      case '1W':
        return DocumentDateRange(now.subtract(const Duration(days: 7)), end);
      case '3M':
        return DocumentDateRange(DateTime(now.year, now.month - 3, now.day), end);
      case '1M':
      default:
        return DocumentDateRange(DateTime(now.year, now.month - 1, now.day), end);
    }
  }

  static List<Map<String, dynamic>> filterDocuments(
    List<Map<String, dynamic>> docs,
    DocumentDateRange range,
  ) {
    return docs.where((d) {
      if ((d['status'] as String?) == 'draft') return false;
      final raw = d['date'];
      if (raw == null) return false;
      final dt = DateTime.tryParse(raw.toString());
      if (dt == null) return false;
      final day = DateTime(dt.year, dt.month, dt.day);
      return !day.isBefore(DateTime(range.start.year, range.start.month, range.start.day)) &&
          !day.isAfter(DateTime(range.end.year, range.end.month, range.end.day));
    }).toList();
  }

  /// Last 7 calendar days ending at [endDate], sums document amounts per day.
  static List<double> lastSevenDaySpending(List<Map<String, dynamic>> docs, DateTime endDate) {
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);
    final out = <double>[];
    for (var i = 6; i >= 0; i--) {
      final d = endDay.subtract(Duration(days: i));
      var sum = 0.0;
      for (final doc in docs) {
        if ((doc['status'] as String?) == 'draft') continue;
        final dt = DateTime.tryParse(doc['date'].toString());
        if (dt == null) continue;
        if (DateTime(dt.year, dt.month, dt.day) == d) {
          sum += (doc['amount'] as num?)?.toDouble() ?? 0;
        }
      }
      out.add(sum);
    }
    return out;
  }
}
