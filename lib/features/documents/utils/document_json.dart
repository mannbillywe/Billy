// Normalizes `documents.extracted_data` from Supabase (Map or JSON-decoded map).

Map<String, dynamic>? asJsonMap(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? stringFromEd(Map<String, dynamic>? ed, String key) {
  if (ed == null) return null;
  final v = ed[key];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

double doubleFromEd(Map<String, dynamic>? ed, String key) {
  if (ed == null) return 0;
  final v = ed[key];
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(RegExp(r'[₹Rs,\s]'), '')) ?? 0;
}
