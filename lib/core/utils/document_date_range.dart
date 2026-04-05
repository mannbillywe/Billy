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

  static DateTime? _dayOnlyFromField(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Includes a row if **transaction** [documents.date] or **saved-on** [created_at]
  /// falls in the range (same idea as dashboard week spend vs OCR invoice dates).
  static bool documentInDateRange(Map<String, dynamic> d, DocumentDateRange range) {
    if ((d['status'] as String?) == 'draft') return false;
    final startDay = DateTime(range.start.year, range.start.month, range.start.day);
    final endDay = DateTime(range.end.year, range.end.month, range.end.day);

    final docDay = _dayOnlyFromField(d['date']);
    if (docDay != null && !docDay.isBefore(startDay) && !docDay.isAfter(endDay)) {
      return true;
    }
    final createdDay = _dayOnlyFromField(d['created_at']);
    if (createdDay != null && !createdDay.isBefore(startDay) && !createdDay.isAfter(endDay)) {
      return true;
    }
    return false;
  }

  static List<Map<String, dynamic>> filterDocuments(
    List<Map<String, dynamic>> docs,
    DocumentDateRange range,
  ) {
    return docs.where((d) => documentInDateRange(d, range)).toList();
  }

  /// Last 7 calendar days ending at [endDate], sums document amounts per day.
  static List<double> lastSevenDaySpending(List<Map<String, dynamic>> docs, DateTime endDate) {
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);
    final startDay = endDay.subtract(const Duration(days: 6));
    final out = <double>[];
    for (var i = 6; i >= 0; i--) {
      final d = endDay.subtract(Duration(days: i));
      var sum = 0.0;
      for (final doc in docs) {
        if ((doc['status'] as String?) == 'draft') continue;
        final bucket = _bucketDayForSevenDayWindow(doc, startDay, endDay);
        if (bucket == d) {
          sum += (doc['amount'] as num?)?.toDouble() ?? 0;
        }
      }
      out.add(sum);
    }
    return out;
  }

  /// Prefer invoice [date] when it lies in the window; else [created_at] (saved day).
  static DateTime? _bucketDayForSevenDayWindow(
    Map<String, dynamic> doc,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final docDay = _dayOnlyFromField(doc['date']);
    if (docDay != null && !docDay.isBefore(windowStart) && !docDay.isAfter(windowEnd)) {
      return docDay;
    }
    final createdDay = _dayOnlyFromField(doc['created_at']);
    if (createdDay != null && !createdDay.isBefore(windowStart) && !createdDay.isAfter(windowEnd)) {
      return createdDay;
    }
    return null;
  }
}
