// Read-only, client-side models for the GOAT Mode analysis backend.
//
// These mirror the relevant JSON columns on `goat_mode_snapshots` and the row
// shape of `goat_mode_recommendations`. They are intentionally forgiving:
// fields are nullable and fall back to sensible defaults, because the backend
// degrades gracefully (see docs/GOAT_MODE_INTEGRATION_GUIDE.md section 5).
import 'dart:convert';

import 'goat_chart_models.dart';

// ─── helpers ────────────────────────────────────────────────────────────────

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  if (v is String && v.isNotEmpty) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asListOfMaps(dynamic v) {
  if (v is List) {
    return v
        .whereType<dynamic>()
        .map(
          (e) => e is Map<String, dynamic>
              ? e
              : (e is Map ? e.cast<String, dynamic>() : <String, dynamic>{}),
        )
        .toList(growable: false);
  }
  if (v is String && v.isNotEmpty) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is List) return _asListOfMaps(decoded);
    } catch (_) {}
  }
  return const <Map<String, dynamic>>[];
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

// ─── readiness / severity enums (kept as Dart strings; backend is source of truth)

enum GoatReadiness { l1, l2, l3, unknown }

GoatReadiness readinessFrom(String? raw) {
  switch (raw) {
    case 'L1':
      return GoatReadiness.l1;
    case 'L2':
      return GoatReadiness.l2;
    case 'L3':
      return GoatReadiness.l3;
    default:
      return GoatReadiness.unknown;
  }
}

extension GoatReadinessX on GoatReadiness {
  String get label {
    switch (this) {
      case GoatReadiness.l1:
        return 'Getting started';
      case GoatReadiness.l2:
        return 'Good signal';
      case GoatReadiness.l3:
        return 'High fidelity';
      case GoatReadiness.unknown:
        return 'Unknown';
    }
  }

  /// 0.0–1.0 for visual ring/bar.
  double get fraction {
    switch (this) {
      case GoatReadiness.l1:
        return 0.34;
      case GoatReadiness.l2:
        return 0.67;
      case GoatReadiness.l3:
        return 1.0;
      case GoatReadiness.unknown:
        return 0.0;
    }
  }
}

enum GoatSeverity { info, watch, warn, critical }

GoatSeverity severityFrom(String? raw) {
  switch (raw) {
    case 'critical':
      return GoatSeverity.critical;
    case 'warn':
      return GoatSeverity.warn;
    case 'watch':
      return GoatSeverity.watch;
    default:
      return GoatSeverity.info;
  }
}

extension GoatSeverityX on GoatSeverity {
  int get rank => switch (this) {
    GoatSeverity.critical => 3,
    GoatSeverity.warn => 2,
    GoatSeverity.watch => 1,
    GoatSeverity.info => 0,
  };

  String get label => switch (this) {
    GoatSeverity.critical => 'Critical',
    GoatSeverity.warn => 'Important',
    GoatSeverity.watch => 'Watch',
    GoatSeverity.info => 'Good to know',
  };
}

// ─── models ────────────────────────────────────────────────────────────────

class GoatMetric {
  const GoatMetric({
    required this.key,
    required this.value,
    required this.unit,
    required this.confidence,
    required this.confidenceBucket,
    required this.reasonCodes,
    required this.inputsUsed,
    required this.inputsMissing,
    required this.detail,
    required this.reportTitle,
    required this.reportSummary,
  });

  final String key;
  final dynamic value; // num | String | null
  final String? unit;
  final double? confidence;
  final String confidenceBucket;
  final List<String> reasonCodes;

  /// Declared data sources the metric consumed (backend `Metric.inputs_used`).
  final List<String> inputsUsed;

  /// Missing inputs that capped confidence (backend `Metric.inputs_missing`).
  final List<String> inputsMissing;
  final Map<String, dynamic> detail;

  /// Optional drill-down copy from backend (`report_title` / inside `detail`).
  final String? reportTitle;
  final String? reportSummary;

  factory GoatMetric.fromJson(Map<String, dynamic> m) {
    final d = _asMap(m['detail']);
    return GoatMetric(
      key: (m['key'] ?? '') as String,
      value: m['value'],
      unit: _asString(m['unit']),
      confidence: _asDouble(m['confidence']),
      confidenceBucket: (m['confidence_bucket'] ?? 'unknown') as String,
      reasonCodes: (m['reason_codes'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      inputsUsed: (m['inputs_used'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      inputsMissing: (m['inputs_missing'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      detail: d,
      reportTitle: _asString(m['report_title']) ?? _asString(d['report_title']),
      reportSummary:
          _asString(m['report_summary']) ?? _asString(d['report_summary']),
    );
  }
}

class GoatCoverage {
  const GoatCoverage({
    required this.score,
    required this.readiness,
    required this.breakdown,
    required this.missingInputs,
    required this.inputsUsed,
    required this.unlockableScopes,
  });

  final double score; // 0..1
  final GoatReadiness readiness;
  final Map<String, double> breakdown;
  final List<GoatMissingInput> missingInputs;
  final List<String> inputsUsed;
  final List<String> unlockableScopes;

  factory GoatCoverage.fromJson(Map<String, dynamic> m) {
    final breakdownRaw = _asMap(m['breakdown']);
    final breakdown = <String, double>{
      for (final e in breakdownRaw.entries) e.key: _asDouble(e.value) ?? 0.0,
    };
    return GoatCoverage(
      score: _asDouble(m['coverage_score']) ?? 0.0,
      readiness: readinessFrom(_asString(m['readiness_level'])),
      breakdown: breakdown,
      missingInputs: _asListOfMaps(
        m['missing_inputs'],
      ).map(GoatMissingInput.fromJson).toList(growable: false),
      inputsUsed: (m['inputs_used'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      unlockableScopes: (m['unlockable_scopes'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class GoatMissingInput {
  const GoatMissingInput({
    required this.key,
    required this.label,
    required this.why,
    required this.unlocks,
    required this.severity,
  });
  final String key;
  final String label;
  final String why;
  final List<String> unlocks;
  final GoatSeverity severity;

  factory GoatMissingInput.fromJson(Map<String, dynamic> m) => GoatMissingInput(
    key: (m['key'] ?? '') as String,
    label: (m['label'] ?? '') as String,
    why: (m['why'] ?? '') as String,
    unlocks: (m['unlocks'] as List? ?? const [])
        .map((e) => e.toString())
        .toList(),
    severity: severityFrom(_asString(m['severity'])),
  );
}

/// One step in a forecast fan chart (`forecast_json.targets[].series.points[]`).
class GoatForecastSeriesPoint {
  const GoatForecastSeriesPoint({
    required this.step,
    required this.date,
    required this.p10,
    required this.p50,
    required this.p90,
  });

  final int step;
  final DateTime? date;
  final double? p10;
  final double? p50;
  final double? p90;

  factory GoatForecastSeriesPoint.fromJson(Map<String, dynamic> m) =>
      GoatForecastSeriesPoint(
        step: _asInt(m['step']) ?? 0,
        date: _asDateTime(_asString(m['date'])),
        p10: _asDouble(m['p10']),
        p50: _asDouble(m['p50']),
        p90: _asDouble(m['p90']),
      );
}

class GoatForecastTarget {
  const GoatForecastTarget({
    required this.target,
    required this.status,
    required this.modelUsed,
    required this.horizonDays,
    required this.confidence,
    required this.value,
    required this.reasonCodes,
    required this.entityLabel,
    required this.seriesPoints,
    required this.seriesUnit,
  });
  final String target;
  final String status;
  final String? modelUsed;
  final int? horizonDays;
  final double? confidence;
  final Map<String, dynamic> value; // {p10, p50, p90, ...}
  final List<String> reasonCodes;
  final String? entityLabel;

  /// When the backend persists `series.points`, charts use this path.
  final List<GoatForecastSeriesPoint> seriesPoints;
  final String? seriesUnit;

  factory GoatForecastTarget.fromJson(Map<String, dynamic> m) {
    final seriesMap = _asMap(m['series']);
    final pts = _asListOfMaps(
      seriesMap['points'],
    ).map(GoatForecastSeriesPoint.fromJson).toList(growable: false);
    return GoatForecastTarget(
      target: (m['target'] ?? '') as String,
      status: (m['status'] ?? 'ok') as String,
      modelUsed: _asString(m['model_used']),
      horizonDays: _asInt(m['horizon_days']),
      confidence: _asDouble(m['confidence']),
      value: _asMap(m['value']),
      reasonCodes: (m['reason_codes'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      entityLabel: _asString(m['entity_label']),
      seriesPoints: pts,
      seriesUnit: _asString(seriesMap['unit']),
    );
  }

  double? get p50 => _asDouble(value['p50']);
  double? get p10 => _asDouble(value['p10']);
  double? get p90 => _asDouble(value['p90']);

  bool get hasChartableSeries =>
      seriesPoints.length >= 2 && seriesPoints.any((p) => p.p50 != null);
}

class GoatAnomaly {
  const GoatAnomaly({
    required this.kind,
    required this.severity,
    required this.explanation,
    required this.entityType,
    required this.entityId,
    required this.baseline,
    required this.observation,
    required this.windowEnd,
  });
  final String kind;
  final GoatSeverity severity;
  final String? explanation;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic> baseline;
  final Map<String, dynamic> observation;
  final DateTime? windowEnd;

  factory GoatAnomaly.fromJson(Map<String, dynamic> m) => GoatAnomaly(
    kind: (m['anomaly_type'] ?? '') as String,
    severity: severityFrom(_asString(m['severity'])),
    explanation: _asString(m['explanation']),
    entityType: _asString(m['entity_type']),
    entityId: _asString(m['entity_id']),
    baseline: _asMap(m['baseline']),
    observation: _asMap(m['observation']),
    windowEnd: _asDateTime(m['window_end']),
  );
}

class GoatRiskScore {
  const GoatRiskScore({
    required this.target,
    required this.severity,
    required this.probability,
    required this.reasonCodes,
    required this.entityType,
    required this.dataSufficient,
  });
  final String target;
  final GoatSeverity severity;
  final double? probability;
  final List<String> reasonCodes;
  final String? entityType;
  final bool dataSufficient;

  factory GoatRiskScore.fromJson(Map<String, dynamic> m) => GoatRiskScore(
    target: (m['target'] ?? '') as String,
    severity: severityFrom(_asString(m['severity'])),
    probability: _asDouble(m['probability']),
    reasonCodes: (m['reason_codes'] as List? ?? const [])
        .map((e) => e.toString())
        .toList(),
    entityType: _asString(m['entity_type']),
    dataSufficient: m['data_sufficient'] != false,
  );
}

// ─── AI envelope ────────────────────────────────────────────────────────────

class GoatAIPillar {
  const GoatAIPillar({
    required this.pillar,
    required this.observation,
    required this.inference,
    required this.confidenceBucket,
  });
  final String pillar;
  final String observation;
  final String inference;
  final String confidenceBucket;

  factory GoatAIPillar.fromJson(Map<String, dynamic> m) => GoatAIPillar(
    pillar: (m['pillar'] ?? '') as String,
    observation: (m['observation'] ?? '') as String,
    inference: (m['inference'] ?? '') as String,
    confidenceBucket: (m['confidence'] ?? 'unknown') as String,
  );
}

class GoatAIRecommendationPhrasing {
  const GoatAIRecommendationPhrasing({
    required this.recFingerprint,
    required this.title,
    required this.body,
    required this.whyShown,
    required this.urgency,
  });
  final String recFingerprint;
  final String title;
  final String body;
  final String whyShown;
  final GoatSeverity urgency;

  factory GoatAIRecommendationPhrasing.fromJson(Map<String, dynamic> m) =>
      GoatAIRecommendationPhrasing(
        recFingerprint: (m['rec_fingerprint'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        whyShown: (m['why_shown'] ?? '') as String,
        urgency: severityFrom(_asString(m['urgency_label'])),
      );
}

class GoatAICoachingNudge {
  const GoatAICoachingNudge({required this.topic, required this.body});
  final String topic;
  final String body;
  factory GoatAICoachingNudge.fromJson(Map<String, dynamic> m) =>
      GoatAICoachingNudge(
        topic: (m['topic'] ?? '') as String,
        body: (m['body'] ?? '') as String,
      );
}

class GoatAIEnvelope {
  const GoatAIEnvelope({
    required this.narrativeSummary,
    required this.pillars,
    required this.recommendationPhrasings,
    required this.coaching,
    required this.mode,
    required this.validated,
    required this.fallbackUsed,
  });

  final String narrativeSummary;
  final List<GoatAIPillar> pillars;
  final List<GoatAIRecommendationPhrasing> recommendationPhrasings;
  final List<GoatAICoachingNudge> coaching;
  final String mode; // disabled | fake | real
  final bool validated;
  final bool fallbackUsed;

  static GoatAIEnvelope empty() => const GoatAIEnvelope(
    narrativeSummary: '',
    pillars: [],
    recommendationPhrasings: [],
    coaching: [],
    mode: 'disabled',
    validated: false,
    fallbackUsed: true,
  );

  /// Parses the ai_layer jsonb column.
  factory GoatAIEnvelope.fromLayer(Map<String, dynamic> layer) {
    final env = _asMap(layer['envelope']);
    return GoatAIEnvelope(
      narrativeSummary: (env['narrative_summary'] ?? '') as String,
      pillars: _asListOfMaps(
        env['pillars'],
      ).map(GoatAIPillar.fromJson).toList(growable: false),
      recommendationPhrasings: _asListOfMaps(
        env['recommendation_phrasings'],
      ).map(GoatAIRecommendationPhrasing.fromJson).toList(growable: false),
      coaching: _asListOfMaps(
        env['coaching'],
      ).map(GoatAICoachingNudge.fromJson).toList(growable: false),
      mode: (layer['mode'] ?? 'disabled') as String,
      validated: layer['ai_validated'] == true,
      fallbackUsed: layer['fallback_used'] == true,
    );
  }
}

// ─── recommendation row (goat_mode_recommendations) ─────────────────────────

class GoatRecommendation {
  const GoatRecommendation({
    required this.id,
    required this.kind,
    required this.severity,
    required this.priority,
    required this.confidence,
    required this.recFingerprint,
    required this.entityType,
    required this.entityId,
    required this.observation,
    required this.recommendation,
    required this.status,
    required this.createdAt,
  });
  final String id;
  final String kind;
  final GoatSeverity severity;
  final int priority; // 0..100
  final double? confidence;
  final String recFingerprint;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic> observation;
  final Map<String, dynamic> recommendation;
  final String status; // open/dismissed/snoozed/resolved/expired
  final DateTime? createdAt;

  factory GoatRecommendation.fromRow(Map<String, dynamic> m) =>
      GoatRecommendation(
        id: (m['id'] ?? '') as String,
        kind: (m['recommendation_kind'] ?? 'other') as String,
        severity: severityFrom(_asString(m['severity'])),
        priority: _asInt(m['priority']) ?? 0,
        confidence: _asDouble(m['confidence']),
        recFingerprint: (m['rec_fingerprint'] ?? '') as String,
        entityType: _asString(m['entity_type']),
        entityId: _asString(m['entity_id']),
        observation: _asMap(m['observation_json']),
        recommendation: _asMap(m['recommendation_json']),
        status: (m['status'] ?? 'open') as String,
        createdAt: _asDateTime(m['created_at']),
      );

  /// Human-readable title. Falls back to the rec kind if the backend didn't
  /// write a friendlier one.
  String get defaultTitle {
    final t = recommendation['title'] ?? recommendation['action'];
    if (t is String && t.isNotEmpty) return t;
    return _kindLabel(kind);
  }

  String get defaultBody {
    final b =
        recommendation['body'] ??
        recommendation['message'] ??
        observation['message'];
    if (b is String && b.isNotEmpty) return b;
    return '';
  }
}

String _kindLabel(String kind) {
  switch (kind) {
    case 'budget_overrun':
      return 'Budget is running hot';
    case 'anomaly_review':
      return 'Unusual activity to review';
    case 'liquidity_warning':
      return 'Liquidity running low';
    case 'goal_shortfall':
      return 'Goal is behind pace';
    case 'missed_payment_risk':
      return 'Payment may be missed';
    case 'recurring_drift':
      return 'A recurring bill drifted';
    case 'duplicate_cluster':
      return 'Possible duplicate charges';
    case 'missing_input':
      return 'Add a detail to unlock more insight';
    case 'uncategorized_cleanup':
      return 'Uncategorized transactions';
    case 'recovery_iou':
      return 'Money owed to you';
    default:
      return 'Recommendation';
  }
}

// ─── top-level snapshot ─────────────────────────────────────────────────────

class GoatSnapshot {
  const GoatSnapshot({
    required this.id,
    required this.scope,
    required this.snapshotStatus,
    required this.readiness,
    required this.generatedAt,
    required this.dataFingerprint,
    required this.coverage,
    required this.metrics,
    required this.forecasts,
    required this.anomalies,
    required this.risks,
    required this.ai,
    required this.recommendationCountsByKind,
    required this.recommendationCountsBySeverity,
    required this.layerErrors,
    required this.charts,
  });

  final String id;
  final String scope;
  final String snapshotStatus; // completed | partial | failed
  final GoatReadiness readiness;
  final DateTime? generatedAt;
  final String dataFingerprint;
  final GoatCoverage coverage;
  final List<GoatMetric> metrics;
  final List<GoatForecastTarget> forecasts;
  final List<GoatAnomaly> anomalies;
  final List<GoatRiskScore> risks;
  final GoatAIEnvelope ai;
  final Map<String, int> recommendationCountsByKind;
  final Map<String, int> recommendationCountsBySeverity;
  final Map<String, String> layerErrors;

  /// Optional `summary_json.charts` — see [GoatChartBundle].
  final GoatChartBundle? charts;

  bool get isPartial => snapshotStatus == 'partial';
  bool get hasMetrics => metrics.any((m) => m.value != null);

  GoatMetric? metricByKey(String key) {
    for (final m in metrics) {
      if (m.key == key) return m;
    }
    return null;
  }

  factory GoatSnapshot.fromRow(Map<String, dynamic> row) {
    final metricsJson = _asMap(row['metrics_json']);
    final forecast = _asMap(row['forecast_json']);
    final anomaliesJson = _asMap(row['anomalies_json']);
    final risk = _asMap(row['risk_json']);
    final aiLayer = _asMap(row['ai_layer']);
    final summary = _asMap(row['summary_json']);
    final recsSummary = _asMap(row['recommendations_summary_json']);

    final layerErrorsRaw = _asMap(summary['layer_errors']);
    final layerErrors = <String, String>{
      for (final e in layerErrorsRaw.entries) e.key: e.value?.toString() ?? '',
    };

    final byKindRaw = _asMap(recsSummary['by_kind']);
    final byKind = <String, int>{
      for (final e in byKindRaw.entries) e.key: _asInt(e.value) ?? 0,
    };
    final bySevRaw = _asMap(recsSummary['by_severity']);
    final bySev = <String, int>{
      for (final e in bySevRaw.entries) e.key: _asInt(e.value) ?? 0,
    };

    final charts = GoatChartBundle.tryParse(summary);

    return GoatSnapshot(
      id: (row['id'] ?? '') as String,
      scope: (row['scope'] ?? 'overview') as String,
      snapshotStatus: (row['snapshot_status'] ?? 'completed') as String,
      readiness: readinessFrom(_asString(row['readiness_level'])),
      generatedAt: _asDateTime(row['generated_at']),
      dataFingerprint: (row['data_fingerprint'] ?? '') as String,
      coverage: GoatCoverage.fromJson(_asMap(row['coverage_json'])),
      metrics: _asListOfMaps(
        metricsJson['metrics'],
      ).map(GoatMetric.fromJson).toList(growable: false),
      forecasts: _asListOfMaps(
        forecast['targets'],
      ).map(GoatForecastTarget.fromJson).toList(growable: false),
      anomalies: _asListOfMaps(
        anomaliesJson['items'],
      ).map(GoatAnomaly.fromJson).toList(growable: false),
      risks: _asListOfMaps(
        risk['scores'],
      ).map(GoatRiskScore.fromJson).toList(growable: false),
      ai: GoatAIEnvelope.fromLayer(aiLayer),
      recommendationCountsByKind: byKind,
      recommendationCountsBySeverity: bySev,
      layerErrors: layerErrors,
      charts: charts,
    );
  }
}

/// Latest compute jobs for the current user (backend writes; app is read-only).
class GoatJobSummary {
  const GoatJobSummary({
    required this.id,
    required this.scope,
    required this.status,
    required this.readinessLevel,
    required this.createdAt,
    required this.finishedAt,
    required this.errorMessage,
  });

  final String id;
  final String scope;
  final String status;
  final String? readinessLevel;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final String? errorMessage;

  factory GoatJobSummary.fromRow(Map<String, dynamic> m) => GoatJobSummary(
    id: (m['id'] ?? '') as String,
    scope: (m['scope'] ?? '') as String,
    status: (m['status'] ?? '') as String,
    readinessLevel: _asString(m['readiness_level']),
    createdAt: _asDateTime(m['created_at']),
    finishedAt: _asDateTime(m['finished_at']),
    errorMessage: _asString(m['error_message']),
  );
}
