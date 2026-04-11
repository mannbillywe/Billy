import 'dart:math' as math;

import '../models/recurring_candidate.dart';

class RecurringDetectionService {
  RecurringDetectionService._();

  static const _toleranceDays = 5;
  static const _maxAmountVariance = 0.30;

  static const _cadences = <String, int>{
    'weekly': 7,
    'biweekly': 14,
    'monthly': 30,
    'quarterly': 90,
    'yearly': 365,
  };

  static List<RecurringCandidate> detect(
    List<Map<String, dynamic>> documents,
  ) {
    final groups = _groupByVendor(documents);
    final candidates = <RecurringCandidate>[];

    for (final entry in groups.entries) {
      final docs = entry.value;
      if (docs.length < 2) continue;

      docs.sort((a, b) => _parseDate(a).compareTo(_parseDate(b)));

      final intervals = _computeIntervals(docs);
      if (intervals.isEmpty) continue;

      final cadenceMatch = _matchCadence(intervals);
      if (cadenceMatch == null) continue;

      final amounts = docs
          .map((d) => (d['amount'] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      if (amounts.isEmpty) continue;

      final avgAmount = amounts.reduce((a, b) => a + b) / amounts.length;
      if (avgAmount == 0) continue;

      final variance = _amountVariance(amounts, avgAmount);
      if (variance > _maxAmountVariance) continue;

      final dates = docs.map(_parseDate).toList();
      final ids = docs
          .map((d) => d['id']?.toString())
          .whereType<String>()
          .toList();

      candidates.add(RecurringCandidate(
        vendorPattern: entry.key,
        suggestedCadence: cadenceMatch.cadence,
        avgAmount: _round2(avgAmount),
        occurrenceCount: docs.length,
        firstSeen: dates.first,
        lastSeen: dates.last,
        sampleTransactionIds: ids,
        confidence: _round2(cadenceMatch.confidence),
      ));
    }

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates;
  }

  static Map<String, List<Map<String, dynamic>>> _groupByVendor(
    List<Map<String, dynamic>> documents,
  ) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final doc in documents) {
      final vendor = (doc['vendor_name'] as String?)?.toLowerCase().trim();
      if (vendor == null || vendor.isEmpty) continue;
      groups.putIfAbsent(vendor, () => []).add(doc);
    }
    return groups;
  }

  static DateTime _parseDate(Map<String, dynamic> doc) {
    final raw = doc['date'];
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.parse(raw);
    return DateTime(1970);
  }

  static List<int> _computeIntervals(List<Map<String, dynamic>> sortedDocs) {
    final intervals = <int>[];
    for (var i = 1; i < sortedDocs.length; i++) {
      final prev = _parseDate(sortedDocs[i - 1]);
      final curr = _parseDate(sortedDocs[i]);
      intervals.add(curr.difference(prev).inDays);
    }
    return intervals;
  }

  static _CadenceMatch? _matchCadence(List<int> intervals) {
    _CadenceMatch? best;

    for (final entry in _cadences.entries) {
      final expected = entry.value;
      var consistent = 0;

      for (final gap in intervals) {
        if ((gap - expected).abs() <= _toleranceDays) {
          consistent++;
        }
      }

      if (consistent < 2) continue;

      final ratio = consistent / intervals.length;
      final confidence = ratio * _recencyWeight(intervals.length);

      if (best == null || confidence > best.confidence) {
        best = _CadenceMatch(entry.key, confidence.clamp(0.0, 1.0));
      }
    }

    return best;
  }

  static double _recencyWeight(int sampleCount) {
    if (sampleCount >= 6) return 1.0;
    if (sampleCount >= 4) return 0.9;
    if (sampleCount >= 3) return 0.8;
    return 0.65;
  }

  static double _amountVariance(List<double> amounts, double mean) {
    if (amounts.length < 2 || mean == 0) return 0;
    final sumSqDiff = amounts.fold<double>(
      0,
      (sum, a) => sum + (a - mean) * (a - mean),
    );
    final stdDev = math.sqrt(sumSqDiff / amounts.length);
    return stdDev / mean.abs();
  }

  static double _round2(double value) =>
      (value * 100).roundToDouble() / 100;
}

class _CadenceMatch {
  final String cadence;
  final double confidence;

  const _CadenceMatch(this.cadence, this.confidence);
}
