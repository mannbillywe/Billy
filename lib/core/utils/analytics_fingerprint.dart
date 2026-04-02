import 'document_date_range.dart';

/// Matches server `analytics-insights` fingerprint for the same date preset (drafts excluded).
String analyticsDataFingerprintForPreset(List<Map<String, dynamic>> allDocs, String preset) {
  final range = DocumentDateRange.forFilter(preset);
  final inRange = DocumentDateRange.filterDocuments(allDocs, range);
  var maxU = '';
  var total = 0.0;
  for (final d in inRange) {
    final u = d['updated_at']?.toString() ?? '';
    if (u.compareTo(maxU) > 0) maxU = u;
    total += (d['amount'] as num?)?.toDouble() ?? 0;
  }
  return '${inRange.length}:$maxU:${(total * 100).round()}';
}
