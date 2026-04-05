import 'document_date_range.dart';

/// Document segment of server `fingerprintFor` for the same preset and [InsightsDateBasis] (drafts excluded).
String analyticsDocumentFingerprintForPreset(
  List<Map<String, dynamic>> allDocs,
  String preset, {
  InsightsDateBasis basis = InsightsDateBasis.billDate,
}) {
  final range = DocumentDateRange.forFilter(preset);
  final inRange = allDocs
      .where((d) => DocumentDateRange.documentInInsightsBasis(d, range, basis))
      .toList();
  var maxU = '';
  var total = 0.0;
  for (final d in inRange) {
    final u = d['updated_at']?.toString() ?? '';
    if (u.compareTo(maxU) > 0) maxU = u;
    total += (d['amount'] as num?)?.toDouble() ?? 0;
  }
  return '${inRange.length}:$maxU:${(total * 100).round()}';
}

/// True when cached insight fingerprint no longer matches vault documents for this basis.
bool analyticsInsightsDocumentsStale({
  required String? snapshotFingerprint,
  required List<Map<String, dynamic>> allDocs,
  required String preset,
  required InsightsDateBasis basis,
}) {
  final snap = snapshotFingerprint;
  if (snap == null || snap.isEmpty) return false;
  final docFp = analyticsDocumentFingerprintForPreset(allDocs, preset, basis: basis);
  final prefixed = '${basis.apiValue}|$docFp';
  if (snap.startsWith('bill_date|') || snap.startsWith('upload_window|')) {
    if (basis == InsightsDateBasis.billDate && !snap.startsWith('bill_date|')) return true;
    if (basis == InsightsDateBasis.uploadWindow && !snap.startsWith('upload_window|')) return true;
    if (snap.startsWith('$prefixed|')) return false;
    if (snap == prefixed) return false;
    return true;
  }
  // Legacy snapshots (no date_basis prefix): server used bill-date document queries only.
  if (basis != InsightsDateBasis.billDate) return true;
  if (snap.startsWith('$docFp|') || snap == docFp) return false;
  return true;
}
