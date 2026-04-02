/// Parsed payload from `analytics-insights` Edge Function or `analytics_insight_snapshots` row.
class AnalyticsInsightsResult {
  AnalyticsInsightsResult({
    required this.success,
    this.deterministic,
    this.aiLayer,
    this.generatedAt,
    this.dataFingerprint,
    this.geminiUsed,
  });

  final bool success;
  final Map<String, dynamic>? deterministic;
  final Map<String, dynamic>? aiLayer;
  final DateTime? generatedAt;
  final String? dataFingerprint;
  final bool? geminiUsed;

  String? get shortNarrative {
    final a = aiLayer;
    if (a == null) return null;
    final v = a['short_narrative'];
    return v?.toString();
  }

  List<Map<String, dynamic>> get prioritizedInsights {
    final a = aiLayer;
    if (a == null) return [];
    final raw = a['prioritized_insights'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  factory AnalyticsInsightsResult.fromInvokeResponse(Map<String, dynamic> j) {
    final det = j['deterministic'];
    return AnalyticsInsightsResult(
      success: j['success'] == true,
      deterministic: det is Map ? Map<String, dynamic>.from(det) : null,
      aiLayer: _mapOrNull(j['ai_layer']),
      generatedAt: DateTime.tryParse(j['generated_at']?.toString() ?? ''),
      dataFingerprint: j['data_fingerprint']?.toString(),
      geminiUsed: j['gemini_used'] as bool?,
    );
  }

  factory AnalyticsInsightsResult.fromSnapshotRow(Map<String, dynamic> row) {
    return AnalyticsInsightsResult(
      success: true,
      deterministic: _mapOrNull(row['deterministic']),
      aiLayer: _mapOrNull(row['ai_layer']),
      generatedAt: DateTime.tryParse(row['generated_at']?.toString() ?? ''),
      dataFingerprint: row['data_fingerprint']?.toString(),
      geminiUsed: null,
    );
  }

  static Map<String, dynamic>? _mapOrNull(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }
}
