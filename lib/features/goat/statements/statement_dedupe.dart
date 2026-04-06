import 'dart:math' as math;

/// Deterministic match score (0–100) between a saved document and a parsed statement row.
class StatementDedupe {
  StatementDedupe._();

  static const thresholdExact = 90.0;
  static const thresholdHigh = 75.0;
  static const thresholdPossible = 55.0;

  static double scoreDocumentMatch({
    required Map<String, dynamic> document,
    required DateTime stmtDate,
    required double stmtAmount,
    required String stmtDescription,
  }) {
    final rawDate = document['date']?.toString();
    final docDate = DateTime.tryParse(rawDate ?? '');
    if (docDate == null) return 0;
    final dOnly = DateTime(docDate.year, docDate.month, docDate.day);
    final sOnly = DateTime(stmtDate.year, stmtDate.month, stmtDate.day);
    final dayDiff = (dOnly.difference(sOnly).inDays).abs();
    if (dayDiff > 2) return 0;

    final docAmt = (document['amount'] as num?)?.toDouble() ?? 0;
    final diff = (docAmt - stmtAmount).abs();
    final rel = docAmt <= 0 && stmtAmount <= 0 ? 0.0 : diff / math.max(docAmt, stmtAmount).clamp(0.01, 1e12);
    if (diff > 0.05 && rel > 0.02) return 0;

    final vendor = (document['vendor_name'] as String? ?? '').toLowerCase().trim();
    final desc = stmtDescription.toLowerCase();
    var textScore = 0.0;
    if (vendor.isEmpty) {
      textScore = dayDiff == 0 && diff < 0.01 ? 65 : 40;
    } else if (desc.contains(vendor)) {
      textScore = 95;
    } else {
      final parts = vendor.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
      final hits = parts.where((w) => desc.contains(w)).length;
      textScore = hits == 0 ? 50 : (50 + math.min(40, hits * 15)).toDouble();
    }

    var total = textScore;
    if (dayDiff == 0) total += 5;
    if (diff < 0.01) total += 5;
    return total.clamp(0.0, 100.0);
  }

  static String matchTypeForScore(double s) {
    if (s <= 0) return 'none';
    if (s >= thresholdExact) return 'exact';
    if (s >= thresholdHigh) return 'high_confidence';
    if (s >= thresholdPossible) return 'possible';
    return 'none';
  }
}
