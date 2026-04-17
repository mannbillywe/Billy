import 'package:flutter/foundation.dart';

/// Goat Mode scope (mirrors backend `Scope` literal in `contracts.py`).
///
/// `full` is the orchestration-wide scope; the UI never exposes it as a
/// user-facing scope chip — users pick `overview` and swap between
/// cashflow/budgets/recurring/debt/goals to see per-pillar details.
enum GoatScope {
  overview,
  cashflow,
  budgets,
  recurring,
  debt,
  goals,
  full;

  String get wire => name;

  String get label {
    switch (this) {
      case GoatScope.overview:
        return 'Overview';
      case GoatScope.cashflow:
        return 'Cashflow';
      case GoatScope.budgets:
        return 'Budgets';
      case GoatScope.recurring:
        return 'Recurring';
      case GoatScope.debt:
        return 'Debt';
      case GoatScope.goals:
        return 'Goals';
      case GoatScope.full:
        return 'Full';
    }
  }

  static GoatScope fromWire(String? v) {
    if (v == null) return GoatScope.overview;
    for (final s in GoatScope.values) {
      if (s.name == v) return s;
    }
    return GoatScope.overview;
  }

  /// Scopes shown as chips on the UI (no `full`).
  static const List<GoatScope> userVisible = [
    GoatScope.overview,
    GoatScope.cashflow,
    GoatScope.budgets,
    GoatScope.recurring,
    GoatScope.debt,
    GoatScope.goals,
  ];
}

enum GoatJobStatus { queued, running, succeeded, partial, failed, cancelled, unknown;
  bool get isTerminal =>
      this == succeeded || this == partial || this == failed || this == cancelled;
  bool get isActive => this == queued || this == running;

  static GoatJobStatus fromWire(String? v) {
    switch (v) {
      case 'queued':
        return queued;
      case 'running':
        return running;
      case 'succeeded':
        return succeeded;
      case 'partial':
        return partial;
      case 'failed':
        return failed;
      case 'cancelled':
        return cancelled;
      default:
        return unknown;
    }
  }

  String get label {
    switch (this) {
      case GoatJobStatus.queued:
        return 'Queued';
      case GoatJobStatus.running:
        return 'Running';
      case GoatJobStatus.succeeded:
        return 'Up to date';
      case GoatJobStatus.partial:
        return 'Partial';
      case GoatJobStatus.failed:
        return 'Failed';
      case GoatJobStatus.cancelled:
        return 'Cancelled';
      case GoatJobStatus.unknown:
        return 'Idle';
    }
  }
}

enum GoatReadiness { l1, l2, l3;
  static GoatReadiness fromWire(String? v) {
    switch (v) {
      case 'L3':
        return l3;
      case 'L2':
        return l2;
      case 'L1':
      default:
        return l1;
    }
  }

  String get wire => switch (this) {
        GoatReadiness.l1 => 'L1',
        GoatReadiness.l2 => 'L2',
        GoatReadiness.l3 => 'L3',
      };

  /// Readiness renders as a user-friendly description, never as a raw "L1" chip.
  String get shortLabel => switch (this) {
        GoatReadiness.l1 => 'Getting started',
        GoatReadiness.l2 => 'Good coverage',
        GoatReadiness.l3 => 'Deep insights',
      };

  double get progress => switch (this) {
        GoatReadiness.l1 => 0.33,
        GoatReadiness.l2 => 0.66,
        GoatReadiness.l3 => 1.0,
      };
}

enum GoatRecSeverity { info, watch, warn, critical;
  static GoatRecSeverity fromWire(String? v) {
    switch (v) {
      case 'critical':
        return critical;
      case 'warn':
        return warn;
      case 'watch':
        return watch;
      case 'info':
      default:
        return info;
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Row → view-model
// ──────────────────────────────────────────────────────────────────────────

@immutable
class GoatJob {
  final String id;
  final String userId;
  final GoatScope scope;
  final GoatJobStatus status;
  final GoatReadiness? readiness;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime createdAt;

  const GoatJob({
    required this.id,
    required this.userId,
    required this.scope,
    required this.status,
    this.readiness,
    this.errorMessage,
    this.startedAt,
    this.finishedAt,
    required this.createdAt,
  });

  factory GoatJob.fromRow(Map<String, dynamic> row) {
    return GoatJob(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      scope: GoatScope.fromWire(row['scope'] as String?),
      status: GoatJobStatus.fromWire(row['status'] as String?),
      readiness: row['readiness_level'] == null
          ? null
          : GoatReadiness.fromWire(row['readiness_level'] as String?),
      errorMessage: row['error_message'] as String?,
      startedAt: _ts(row['started_at']),
      finishedAt: _ts(row['finished_at']),
      createdAt: _ts(row['created_at']) ?? DateTime.now().toUtc(),
    );
  }
}

@immutable
class GoatSnapshot {
  final String id;
  final String userId;
  final GoatScope scope;
  final GoatReadiness readiness;
  final String snapshotStatus; // completed | partial | failed
  final String dataFingerprint;
  final DateTime generatedAt;
  final Map<String, dynamic> coverage;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> metrics;
  final Map<String, dynamic> forecast;
  final Map<String, dynamic> anomalies;
  final Map<String, dynamic> risk;
  final Map<String, dynamic> recsSummary;
  final Map<String, dynamic> aiLayer;

  const GoatSnapshot({
    required this.id,
    required this.userId,
    required this.scope,
    required this.readiness,
    required this.snapshotStatus,
    required this.dataFingerprint,
    required this.generatedAt,
    required this.coverage,
    required this.summary,
    required this.metrics,
    required this.forecast,
    required this.anomalies,
    required this.risk,
    required this.recsSummary,
    required this.aiLayer,
  });

  bool get isPartial => snapshotStatus == 'partial';
  bool get isFailed => snapshotStatus == 'failed';

  double? get coverageScore {
    final v = coverage['coverage_score'];
    if (v is num) return v.toDouble().clamp(0.0, 1.0);
    return null;
  }

  /// Narrative slots surfaced by the deterministic layer (always safe — never Gemini).
  List<String> get narrativeBullets {
    final raw = summary['narrative'];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return const [];
  }

  /// Top-line deterministic headline metrics (already curated by backend).
  List<GoatMetricView> get headlineMetrics {
    final raw = summary['headline_metrics'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => GoatMetricView.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  List<GoatMissingInput> get missingInputs {
    final raw = coverage['missing_inputs'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => GoatMissingInput.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  List<GoatMetricView> metricsForScope(GoatScope scope) {
    final raw = metrics[scope.wire];
    if (raw is Map && raw['metrics'] is List) {
      return (raw['metrics'] as List)
          .whereType<Map>()
          .map((e) => GoatMetricView.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  GoatAIView? get ai {
    if (aiLayer.isEmpty) return null;
    return GoatAIView.fromMap(aiLayer);
  }

  factory GoatSnapshot.fromRow(Map<String, dynamic> row) {
    return GoatSnapshot(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      scope: GoatScope.fromWire(row['scope'] as String?),
      readiness: GoatReadiness.fromWire(row['readiness_level'] as String?),
      snapshotStatus: (row['snapshot_status'] as String?) ?? 'completed',
      dataFingerprint: (row['data_fingerprint'] as String?) ?? '',
      generatedAt: _ts(row['generated_at']) ?? DateTime.now().toUtc(),
      coverage: _obj(row['coverage_json']),
      summary: _obj(row['summary_json']),
      metrics: _obj(row['metrics_json']),
      forecast: _obj(row['forecast_json']),
      anomalies: _obj(row['anomalies_json']),
      risk: _obj(row['risk_json']),
      recsSummary: _obj(row['recommendations_summary_json']),
      aiLayer: _obj(row['ai_layer']),
    );
  }
}

@immutable
class GoatMetricView {
  final String key;
  final String? label;
  final Object? value;
  final String? unit;
  final String? confidenceBucket;
  final List<String> reasonCodes;

  const GoatMetricView({
    required this.key,
    this.label,
    this.value,
    this.unit,
    this.confidenceBucket,
    this.reasonCodes = const [],
  });

  factory GoatMetricView.fromMap(Map<String, dynamic> m) {
    final rc = m['reason_codes'];
    return GoatMetricView(
      key: (m['key'] as String?) ?? '',
      label: m['label'] as String?,
      value: m['value'],
      unit: m['unit'] as String?,
      confidenceBucket: m['confidence_bucket'] as String?,
      reasonCodes: rc is List ? rc.whereType<String>().toList() : const [],
    );
  }

  /// User-visible name: prefer explicit label, else humanise the `key`.
  String get displayLabel {
    if (label != null && label!.isNotEmpty) return label!;
    return key
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }
}

@immutable
class GoatMissingInput {
  final String key;
  final String label;
  final String why;
  final List<String> unlocks;
  final String severity;

  const GoatMissingInput({
    required this.key,
    required this.label,
    required this.why,
    this.unlocks = const [],
    this.severity = 'info',
  });

  factory GoatMissingInput.fromMap(Map<String, dynamic> m) {
    final unlocks = m['unlocks'];
    return GoatMissingInput(
      key: (m['key'] as String?) ?? '',
      label: (m['label'] as String?) ?? 'Add more context',
      why: (m['why'] as String?) ?? '',
      unlocks: unlocks is List ? unlocks.whereType<String>().toList() : const [],
      severity: (m['severity'] as String?) ?? 'info',
    );
  }
}

@immutable
class GoatRecommendation {
  final String id;
  final String userId;
  final String kind; // RecKind
  final GoatRecSeverity severity;
  final int priority;
  final double? confidence;
  final double? impact;
  final double? effort;
  final String recFingerprint;
  final String status; // open | dismissed | ...
  final Map<String, dynamic> observation;
  final Map<String, dynamic> recommendation;

  const GoatRecommendation({
    required this.id,
    required this.userId,
    required this.kind,
    required this.severity,
    required this.priority,
    required this.recFingerprint,
    required this.status,
    required this.observation,
    required this.recommendation,
    this.confidence,
    this.impact,
    this.effort,
  });

  String get kindLabel {
    switch (kind) {
      case 'budget_overrun':
        return 'Budget overrun';
      case 'anomaly_review':
        return 'Unusual activity';
      case 'liquidity_warning':
        return 'Cash runway';
      case 'goal_shortfall':
        return 'Goal at risk';
      case 'missed_payment_risk':
        return 'Missed-payment risk';
      case 'recurring_drift':
        return 'Recurring drift';
      case 'duplicate_cluster':
        return 'Possible duplicates';
      case 'missing_input':
        return 'Unlock more insight';
      case 'uncategorized_cleanup':
        return 'Tidy up categories';
      case 'recovery_iou':
        return 'Recover an IOU';
      default:
        return 'Heads up';
    }
  }

  /// Short title for the card. Falls back to the kind label.
  String titleFor({Map<String, String>? aiTitleByFingerprint}) {
    if (aiTitleByFingerprint != null) {
      final ai = aiTitleByFingerprint[recFingerprint];
      if (ai != null && ai.isNotEmpty) return ai;
    }
    final t = recommendation['title'];
    if (t is String && t.isNotEmpty) return t;
    return kindLabel;
  }

  /// 1-line body: AI phrasing wins, else deterministic copy, else nothing.
  String? bodyFor({Map<String, String>? aiBodyByFingerprint}) {
    if (aiBodyByFingerprint != null) {
      final ai = aiBodyByFingerprint[recFingerprint];
      if (ai != null && ai.isNotEmpty) return ai;
    }
    final b = recommendation['summary'];
    if (b is String && b.isNotEmpty) return b;
    final obs = observation['summary'];
    if (obs is String && obs.isNotEmpty) return obs;
    return null;
  }

  String? whyShownFor({Map<String, String>? aiWhyByFingerprint}) {
    if (aiWhyByFingerprint != null) {
      final ai = aiWhyByFingerprint[recFingerprint];
      if (ai != null && ai.isNotEmpty) return ai;
    }
    final w = observation['why'];
    if (w is String && w.isNotEmpty) return w;
    return null;
  }

  factory GoatRecommendation.fromRow(Map<String, dynamic> row) {
    double? asDouble(Object? v) => v is num ? v.toDouble() : null;
    return GoatRecommendation(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      kind: (row['recommendation_kind'] as String?) ?? 'other',
      severity: GoatRecSeverity.fromWire(row['severity'] as String?),
      priority: (row['priority'] as num?)?.toInt() ?? 0,
      confidence: asDouble(row['confidence']),
      impact: asDouble(row['impact_score']),
      effort: asDouble(row['effort_score']),
      recFingerprint: (row['rec_fingerprint'] as String?) ?? '',
      status: (row['status'] as String?) ?? 'open',
      observation: _obj(row['observation_json']),
      recommendation: _obj(row['recommendation_json']),
    );
  }
}

/// View over the persisted AI layer (safe accessors that never explode).
@immutable
class GoatAIView {
  final String? narrativeSummary;
  final List<GoatAIPillar> pillars;
  final Map<String, String> phrasingTitleByFingerprint;
  final Map<String, String> phrasingBodyByFingerprint;
  final Map<String, String> phrasingWhyByFingerprint;
  final List<GoatAIMissingPrompt> missingPrompts;
  final bool validated;
  final bool fallbackUsed;

  const GoatAIView({
    this.narrativeSummary,
    this.pillars = const [],
    this.phrasingTitleByFingerprint = const {},
    this.phrasingBodyByFingerprint = const {},
    this.phrasingWhyByFingerprint = const {},
    this.missingPrompts = const [],
    this.validated = false,
    this.fallbackUsed = false,
  });

  factory GoatAIView.fromMap(Map<String, dynamic> ai) {
    final envelope = ai['envelope'];
    if (envelope is! Map) {
      return GoatAIView(
        validated: ai['ai_validated'] == true,
        fallbackUsed: ai['fallback_used'] == true,
      );
    }
    final env = Map<String, dynamic>.from(envelope);
    final pillarsRaw = env['pillars'];
    final phrasingRaw = env['recommendation_phrasings'];
    final missingRaw = env['missing_input_prompts'];

    final titleByFp = <String, String>{};
    final bodyByFp = <String, String>{};
    final whyByFp = <String, String>{};
    if (phrasingRaw is List) {
      for (final p in phrasingRaw) {
        if (p is Map) {
          final fp = p['rec_fingerprint'];
          if (fp is String && fp.isNotEmpty) {
            if (p['title'] is String) titleByFp[fp] = p['title'] as String;
            if (p['body'] is String) bodyByFp[fp] = p['body'] as String;
            if (p['why_shown'] is String) whyByFp[fp] = p['why_shown'] as String;
          }
        }
      }
    }

    return GoatAIView(
      narrativeSummary: env['narrative_summary'] as String?,
      pillars: pillarsRaw is List
          ? pillarsRaw
              .whereType<Map>()
              .map((e) => GoatAIPillar.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      phrasingTitleByFingerprint: titleByFp,
      phrasingBodyByFingerprint: bodyByFp,
      phrasingWhyByFingerprint: whyByFp,
      missingPrompts: missingRaw is List
          ? missingRaw
              .whereType<Map>()
              .map((e) => GoatAIMissingPrompt.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      validated: ai['ai_validated'] == true,
      fallbackUsed: ai['fallback_used'] == true,
    );
  }
}

@immutable
class GoatAIPillar {
  final String pillar;
  final String observation;
  final String inference;
  final String confidence;

  const GoatAIPillar({
    required this.pillar,
    required this.observation,
    required this.inference,
    required this.confidence,
  });

  factory GoatAIPillar.fromMap(Map<String, dynamic> m) => GoatAIPillar(
        pillar: (m['pillar'] as String?) ?? '',
        observation: (m['observation'] as String?) ?? '',
        inference: (m['inference'] as String?) ?? '',
        confidence: (m['confidence'] as String?) ?? 'unknown',
      );
}

@immutable
class GoatAIMissingPrompt {
  final String inputKey;
  final String title;
  final String body;

  const GoatAIMissingPrompt({
    required this.inputKey,
    required this.title,
    required this.body,
  });

  factory GoatAIMissingPrompt.fromMap(Map<String, dynamic> m) => GoatAIMissingPrompt(
        inputKey: (m['input_key'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
      );
}

// ──────────────────────────────────────────────────────────────────────────
// helpers
// ──────────────────────────────────────────────────────────────────────────

DateTime? _ts(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

Map<String, dynamic> _obj(Object? v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return const {};
}
