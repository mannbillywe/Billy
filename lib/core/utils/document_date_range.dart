import 'package:flutter/foundation.dart';

/// How AI Insights / analytics range includes documents (matches Edge `date_basis`).
enum InsightsDateBasis {
  /// Filter by receipt/invoice date on the document.
  billDate,

  /// Filter by when the document was saved (`created_at`) in the range.
  uploadWindow,
}

extension InsightsDateBasisApi on InsightsDateBasis {
  String get apiValue => switch (this) {
        InsightsDateBasis.billDate => 'bill_date',
        InsightsDateBasis.uploadWindow => 'upload_window',
      };
}

InsightsDateBasis insightsDateBasisFromApi(String? raw) {
  if (raw == 'upload_window' || raw == 'uploaded_in_range') {
    return InsightsDateBasis.uploadWindow;
  }
  return InsightsDateBasis.billDate;
}

/// Home dashboard "this week" and strict analytics axis (upload vs bill vs legacy OR).
enum WeekSpendBasis {
  /// Bucket by `documents.created_at` (saved/upload time).
  uploadDate,

  /// Bucket by `documents.date` (bill date) only.
  invoiceDate,

  /// Prefer invoice date in week, else upload date in week (legacy Billy behavior).
  hybrid,
}

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

  /// Analytics-style range filter using a single axis (or legacy OR for [WeekSpendBasis.hybrid]).
  static List<Map<String, dynamic>> filterDocumentsForWeekBasis(
    List<Map<String, dynamic>> docs,
    DocumentDateRange range,
    WeekSpendBasis basis,
  ) {
    switch (basis) {
      case WeekSpendBasis.hybrid:
        return filterDocuments(docs, range);
      case WeekSpendBasis.uploadDate:
        return docs.where((d) => documentInInsightsBasis(d, range, InsightsDateBasis.uploadWindow)).toList();
      case WeekSpendBasis.invoiceDate:
        return docs.where((d) => documentInInsightsBasis(d, range, InsightsDateBasis.billDate)).toList();
    }
  }

  /// Single-axis filter for analytics (bill date only vs upload time only).
  static bool documentInInsightsBasis(
    Map<String, dynamic> d,
    DocumentDateRange range,
    InsightsDateBasis basis,
  ) {
    if ((d['status'] as String?) == 'draft') return false;
    final startDay = DateTime(range.start.year, range.start.month, range.start.day);
    final endDay = DateTime(range.end.year, range.end.month, range.end.day);
    if (basis == InsightsDateBasis.billDate) {
      final docDay = _dayOnlyFromField(d['date']);
      return docDay != null && !docDay.isBefore(startDay) && !docDay.isAfter(endDay);
    }
    final createdDay = _dayOnlyFromField(d['created_at']);
    return createdDay != null && !createdDay.isBefore(startDay) && !createdDay.isAfter(endDay);
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

  static DateTime? _bucketDayForSevenDayWindowBasis(
    Map<String, dynamic> doc,
    DateTime windowStart,
    DateTime windowEnd,
    WeekSpendBasis basis,
  ) {
    switch (basis) {
      case WeekSpendBasis.hybrid:
        return _bucketDayForSevenDayWindow(doc, windowStart, windowEnd);
      case WeekSpendBasis.uploadDate:
        final createdDay = _dayOnlyFromField(doc['created_at']);
        if (createdDay != null && !createdDay.isBefore(windowStart) && !createdDay.isAfter(windowEnd)) {
          return createdDay;
        }
        return null;
      case WeekSpendBasis.invoiceDate:
        final docDay = _dayOnlyFromField(doc['date']);
        if (docDay != null && !docDay.isBefore(windowStart) && !docDay.isAfter(windowEnd)) {
          return docDay;
        }
        return null;
    }
  }

  /// Last 7 calendar days ending at [endDate], one axis per [basis].
  static List<double> lastSevenDaySpendingByBasis(
    List<Map<String, dynamic>> docs,
    DateTime endDate,
    WeekSpendBasis basis,
  ) {
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);
    final startDay = endDay.subtract(const Duration(days: 6));
    final out = <double>[];
    for (var i = 6; i >= 0; i--) {
      final d = endDay.subtract(Duration(days: i));
      var sum = 0.0;
      for (final doc in docs) {
        if ((doc['status'] as String?) == 'draft') continue;
        final bucket = _bucketDayForSevenDayWindowBasis(doc, startDay, endDay, basis);
        if (bucket == d) {
          sum += (doc['amount'] as num?)?.toDouble() ?? 0;
        }
      }
      out.add(sum);
    }
    return out;
  }

  /// Sum of [lastSevenDaySpendingByBasis] — matches Analytics overview when filter is **1W**.
  static double totalRollingSevenDaySpend(
    List<Map<String, dynamic>> docs,
    DateTime endDate,
    WeekSpendBasis basis,
  ) {
    return lastSevenDaySpendingByBasis(docs, endDate, basis).fold<double>(0, (a, b) => a + b);
  }

  /// Non-draft documents that land in the rolling 7-day window (same bucketing as the 1W chart).
  static int countDocumentsRollingSevenDay(
    List<Map<String, dynamic>> docs,
    DateTime endDate,
    WeekSpendBasis basis,
  ) {
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);
    final startDay = endDay.subtract(const Duration(days: 6));
    var c = 0;
    for (final doc in docs) {
      if ((doc['status'] as String?) == 'draft') continue;
      if (_bucketDayForSevenDayWindowBasis(doc, startDay, endDay, basis) != null) {
        c++;
      }
    }
    return c;
  }
}
