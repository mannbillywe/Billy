/// Small, dependency-free helpers that turn the raw Goat backend output into
/// user-friendly copy. The backend degrades to deterministic fallback phrasing
/// when the AI layer is off, and that fallback phrasing leaks internal names
/// (UUIDs, metric keys, placeholder strings). Everything in this file exists to
/// keep that leakage out of the UI.
library;

import '../models/goat_models.dart';

// ─── regex patterns kept private, compiled once ─────────────────────────────

final RegExp _uuidRe = RegExp(
  r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
  caseSensitive: false,
);
final RegExp _multiSpaceRe = RegExp(r'\s+');
final RegExp _trailingZeroRe = RegExp(r'(\d+)\.0+\b');
final RegExp _multiplierRe = RegExp(r'(\d+(?:\.\d+)?)x\b');

const String _placeholderMarker = 'Deterministic phrasing based on your';
const String _whyShownPlaceholder =
    'Derived from your transactions, budgets, and recurring series without AI.';

bool isAiPlaceholderBody(String? s) {
  if (s == null || s.isEmpty) return false;
  return s.trimLeft().startsWith(_placeholderMarker);
}

bool isAiPlaceholderWhy(String? s) {
  if (s == null) return false;
  return s.trim() == _whyShownPlaceholder;
}

// ─── generic text cleanup ──────────────────────────────────────────────────

String stripIds(String raw) {
  var s = raw.replaceAll(_uuidRe, '').replaceAll('  ', ' ').trim();
  // Remove dangling "This  charge" style artefacts from UUID removal.
  s = s.replaceAll(RegExp(r'\bThis\s+charge\b'), 'A charge');
  s = s.replaceAll(RegExp(r'\bthis\s+charge\b'), 'a charge');
  s = s.replaceAll(_multiSpaceRe, ' ');
  return s;
}

String prettifyNumbers(String raw) {
  var s = raw.replaceAllMapped(_trailingZeroRe, (m) => m[1]!);
  s = s.replaceAllMapped(_multiplierRe, (m) => '${m[1]}×');
  return s;
}

/// Format a number as ₹1,23,456 / ₹1.2L / ₹1.2Cr style, matching the rest of the app.
String formatInr(num value) {
  final amount = value.abs();
  String body;
  if (amount >= 10000000) {
    body = '${(amount / 10000000).toStringAsFixed(2)} Cr';
  } else if (amount >= 100000) {
    body = '${(amount / 100000).toStringAsFixed(2)} L';
  } else if (amount >= 1000) {
    body = amount.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  } else {
    body = amount.toStringAsFixed(0);
  }
  final sign = value < 0 ? '-' : '';
  return '$sign₹$body';
}

// ─── recommendation kind → clean fallback title / body ─────────────────────

String recKindTitle(String kind) {
  switch (kind) {
    case 'budget_overrun':
      return 'Budget is running hot';
    case 'anomaly_review':
      return 'Unusual transaction to review';
    case 'liquidity_warning':
      return 'Cash buffer is low';
    case 'goal_shortfall':
      return 'Goal is off pace';
    case 'missed_payment_risk':
      return 'A bill may be missed';
    case 'recurring_drift':
      return 'A recurring bill shifted';
    case 'duplicate_cluster':
      return 'Possible duplicate charge';
    case 'missing_input':
      return 'Add a detail to sharpen analysis';
    case 'uncategorized_cleanup':
      return 'Uncategorized transactions';
    case 'recovery_iou':
      return 'Money still owed to you';
    default:
      return 'Recommendation';
  }
}

/// Picks the best title for a priority card. We prefer an explicit AI title,
/// but fall back to our own per-kind copy rather than leaking a vendor name
/// plus a meaningless body.
String bestRecTitle(
  GoatRecommendation rec,
  GoatAIRecommendationPhrasing? phrasing,
) {
  final raw = (phrasing?.title.isNotEmpty == true)
      ? phrasing!.title
      : rec.defaultTitle;
  final cleaned = stripIds(raw).trim();
  if (cleaned.isEmpty) return recKindTitle(rec.kind);
  return cleaned;
}

/// Builds a grounded body sentence from the rec's observation/recommendation
/// JSON. Falls back to the per-kind phrasing when nothing usable exists.
String bestRecBody(
  GoatRecommendation rec,
  GoatAIRecommendationPhrasing? phrasing,
) {
  // 1) If AI produced a real (non-placeholder) body, trust it.
  final aiBody = phrasing?.body;
  if (aiBody != null && aiBody.isNotEmpty && !isAiPlaceholderBody(aiBody)) {
    return prettifyNumbers(stripIds(aiBody));
  }

  // 2) The deterministic layer stores a rich `headline` in recommendation_json
  //    that Flutter previously ignored. Prefer that when available.
  final headline = rec.recommendation['headline'];
  if (headline is String && headline.isNotEmpty) {
    return prettifyNumbers(stripIds(headline));
  }

  // 3) Build a sentence from observation fields, shaped per rec kind.
  final built = _buildRecBodyFromObservation(rec);
  if (built.isNotEmpty) return prettifyNumbers(built);

  // 4) Per-kind generic fallback.
  return _genericKindBody(rec.kind);
}

String _genericKindBody(String kind) {
  switch (kind) {
    case 'budget_overrun':
      return 'This budget is tracking ahead of pace for the period.';
    case 'anomaly_review':
      return 'An unusual transaction stood out compared to your normal pattern.';
    case 'liquidity_warning':
      return 'Your liquid balances are running below comfortable levels.';
    case 'goal_shortfall':
      return 'At the current pace, this goal will finish after its target date.';
    case 'missed_payment_risk':
      return 'Recent bill history shows a pattern of missed or late payments.';
    case 'recurring_drift':
      return 'A recurring charge has drifted from its usual amount.';
    case 'duplicate_cluster':
      return 'Charges look similar enough to be worth a quick review.';
    case 'missing_input':
      return 'Adding this information unlocks deeper analysis below.';
    case 'uncategorized_cleanup':
      return 'Categorising these will sharpen budgets and trend views.';
    case 'recovery_iou':
      return 'Pending IOUs are sitting past their due date.';
    default:
      return 'Open this item for details.';
  }
}

String _buildRecBodyFromObservation(GoatRecommendation rec) {
  final o = rec.observation;
  num? n(String key) {
    final v = o[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  switch (rec.kind) {
    case 'budget_overrun':
      final util = n('utilization');
      final pace = n('pace_fraction');
      final spent = n('spent');
      final limit = n('limit');
      final name = o['name'];
      final who = (name is String && name.isNotEmpty) ? name : 'This budget';
      if (util != null && pace != null) {
        return '$who is ${(util * 100).round()}% used at ${(pace * 100).round()}% of the period.';
      }
      if (spent != null && limit != null && limit > 0) {
        return '$who: ${formatInr(spent)} spent of ${formatInr(limit)}.';
      }
      return '';

    case 'liquidity_warning':
      final liquid = n('liquid_total');
      final floor = n('floor');
      if (liquid != null && floor != null) {
        return 'Liquid balances ${formatInr(liquid)} are below your declared floor of ${formatInr(floor)}.';
      }
      return '';

    case 'goal_shortfall':
      final req = n('required_monthly');
      final title = o['title'];
      final name = (title is String && title.isNotEmpty) ? title : 'this goal';
      if (req != null && req > 0) {
        return 'Set aside about ${formatInr(req)} per month to hit $name on time.';
      }
      return '$name needs a target date to unlock a required monthly plan.';

    case 'anomaly_review':
      final anomalyType = o['anomaly_type'];
      final amt = n('amount') ?? n('latest_amount');
      final title = o['title'];
      final baseline = o['baseline'];
      num? median;
      int? samples;
      if (baseline is Map) {
        median = (baseline['median'] is num)
            ? baseline['median'] as num
            : num.tryParse('${baseline['median']}');
        samples = (baseline['sample_size'] is num)
            ? (baseline['sample_size'] as num).toInt()
            : null;
      }
      final vendor = (title is String && title.isNotEmpty) ? title : null;
      switch (anomalyType) {
        case 'amount_spike_category':
          if (amt != null && median != null && median > 0) {
            final mult = (amt / median).toStringAsFixed(1);
            final vendorBit = vendor != null ? ' at $vendor' : '';
            final sampleBit =
                samples != null ? ' (median ${formatInr(median)}, $samples samples)' : '';
            return 'A ${formatInr(amt)} charge$vendorBit is $mult× the typical amount for this category$sampleBit.';
          }
          break;
        case 'recurring_bill_jump':
          if (amt != null && median != null && median > 0) {
            final pct = ((amt - median) / median * 100).round();
            return 'The latest bill ${formatInr(amt)} is $pct% above its trailing median (${formatInr(median)}).';
          }
          break;
        case 'budget_pace_acceleration':
          final name = o['budget_name'];
          final pace = n('pace_fraction');
          final spentPct = n('pct_spent');
          if (pace != null && spentPct != null) {
            final who = (name is String && name.isNotEmpty) ? name : 'A budget';
            return '$who is ${(spentPct * 100).round()}% used at ${(pace * 100).round()}% of the period.';
          }
          break;
        case 'low_liquidity_pattern':
          final runway = n('runway_months');
          final liquid = n('liquid_total');
          if (runway != null && liquid != null) {
            return 'Liquid balances ${formatInr(liquid)} cover about ${runway.toStringAsFixed(1)} months of spend.';
          }
          break;
      }
      if (amt != null) {
        return 'A ${formatInr(amt)} charge stood out versus your baseline for this pattern.';
      }
      return '';

    case 'missed_payment_risk':
      final prob = n('probability');
      if (prob != null) {
        return '${(prob * 100).round()}% chance a bill slips this cycle based on your recent payment history.';
      }
      return '';

    case 'recurring_drift':
      final newAmt = n('latest_amount') ?? n('amount');
      final prevAmt = n('prior_amount') ?? n('expected_amount');
      if (newAmt != null && prevAmt != null && prevAmt > 0) {
        final pct = ((newAmt - prevAmt) / prevAmt * 100).round();
        final dir = pct >= 0 ? '+' : '';
        return 'Amount moved from ${formatInr(prevAmt)} → ${formatInr(newAmt)} ($dir$pct%).';
      }
      return '';

    case 'duplicate_cluster':
      final count = n('count');
      final total = n('total_amount');
      if (count != null) {
        final totalBit = total != null ? ' totalling ${formatInr(total)}' : '';
        return '${count.toInt()} similar charges$totalBit detected inside a narrow window.';
      }
      return '';

    case 'uncategorized_cleanup':
      final count = n('uncategorized_count');
      if (count != null) {
        return '${count.toInt()} transactions in this period have no category assigned yet.';
      }
      return '';

    case 'recovery_iou':
      final count = n('overdue_count');
      final total = n('overdue_total');
      if (count != null && total != null) {
        return '${count.toInt()} lent amount(s) totalling ${formatInr(total)} are past due.';
      }
      return '';

    case 'missing_input':
      final label = o['label'];
      final why = o['why'];
      if (label is String && label.isNotEmpty) {
        if (why is String && why.isNotEmpty) {
          return '$label · $why';
        }
        return 'Add: $label.';
      }
      return '';
  }
  return '';
}

// ─── anomaly copy ──────────────────────────────────────────────────────────

String humanAnomalyBody(GoatAnomaly a) {
  // Prefer a structured body built from observation/baseline rather than the
  // raw explanation string which tends to embed category UUIDs.
  final built = _buildAnomalyBody(a);
  if (built.isNotEmpty) return prettifyNumbers(built);
  final raw = a.explanation ?? '';
  if (raw.isEmpty) return '';
  return prettifyNumbers(stripIds(raw));
}

String _buildAnomalyBody(GoatAnomaly a) {
  num? amt = (a.observation['amount'] is num)
      ? a.observation['amount'] as num
      : num.tryParse('${a.observation['amount']}');
  amt ??= (a.observation['latest_amount'] is num)
      ? a.observation['latest_amount'] as num
      : num.tryParse('${a.observation['latest_amount']}');
  num? median = (a.baseline['median'] is num)
      ? a.baseline['median'] as num
      : num.tryParse('${a.baseline['median']}');
  int? samples = (a.baseline['sample_size'] is num)
      ? (a.baseline['sample_size'] as num).toInt()
      : null;
  final title = a.observation['title'];
  final vendor = (title is String && title.isNotEmpty) ? title : null;

  switch (a.kind) {
    case 'amount_spike_category':
      if (amt != null && median != null && median > 0) {
        final mult = (amt / median).toStringAsFixed(1);
        final sampleBit = samples != null
            ? ' (typical ${formatInr(median)} · $samples bills)'
            : '';
        if (vendor != null) {
          return '${formatInr(amt)} at $vendor is $mult× the usual for this category$sampleBit.';
        }
        return 'A ${formatInr(amt)} charge is $mult× the usual for this category$sampleBit.';
      }
      break;
    case 'recurring_bill_jump':
      if (amt != null && median != null && median > 0) {
        final pct = ((amt - median) / median * 100).round();
        return 'Latest bill ${formatInr(amt)} is $pct% above its trailing median (${formatInr(median)}).';
      }
      break;
    case 'budget_pace_acceleration':
      final name = a.observation['budget_name'];
      final pace = (a.baseline['pace_fraction'] is num)
          ? a.baseline['pace_fraction'] as num
          : null;
      final pctSpent = (a.observation['pct_spent'] is num)
          ? a.observation['pct_spent'] as num
          : null;
      if (pace != null && pctSpent != null) {
        final who = (name is String && name.isNotEmpty) ? name : 'Budget';
        return '$who is ${(pctSpent * 100).round()}% used at ${(pace * 100).round()}% of the period.';
      }
      break;
    case 'low_liquidity_pattern':
      final runway = (a.observation['runway_months'] is num)
          ? a.observation['runway_months'] as num
          : null;
      final liquid = (a.observation['liquid_total'] is num)
          ? a.observation['liquid_total'] as num
          : null;
      if (runway != null && liquid != null) {
        return 'Liquid balances ${formatInr(liquid)} cover about ${runway.toStringAsFixed(1)} months at current spend.';
      }
      break;
  }
  return '';
}

/// Collapses multiple anomalies that point at the same underlying signal
/// (same kind + same entity + near-identical severity) into a single card.
List<GoatAnomaly> dedupeAnomalies(List<GoatAnomaly> all) {
  final byKey = <String, GoatAnomaly>{};
  for (final a in all) {
    final key = '${a.kind}|${a.entityId ?? ''}';
    final existing = byKey[key];
    if (existing == null || a.severity.rank > existing.severity.rank) {
      byKey[key] = a;
    }
  }
  return byKey.values.toList(growable: false)
    ..sort((a, b) => b.severity.rank.compareTo(a.severity.rank));
}

// ─── risk copy ─────────────────────────────────────────────────────────────

String humanRiskBody(GoatRiskScore r) {
  final parts = <String>[];
  if (r.probability != null) {
    parts.add('${(r.probability! * 100).round()}% likely this cycle.');
  }
  if (r.reasonCodes.isNotEmpty) {
    final drivers =
        r.reasonCodes.map(_humanizeReasonCode).where((s) => s.isNotEmpty).toList();
    if (drivers.isNotEmpty) {
      parts.add('Drivers: ${drivers.join(' · ')}.');
    }
  }
  return parts.join(' ');
}

String _humanizeReasonCode(String code) {
  final idx = code.indexOf(':');
  if (idx < 0) {
    return code.replaceAll('_', ' ');
  }
  var key = code.substring(0, idx).replaceAll('_', ' ').trim();
  var value = code.substring(idx + 1).trim();
  // Strip trailing zero decimals like "0.0" → "0".
  if (value.contains('.')) {
    final n = num.tryParse(value);
    if (n != null && n == n.truncate()) value = n.truncate().toString();
  }
  // Friendlier names for the most common risk drivers.
  switch (key) {
    case 'runway':
    case 'runway months':
      key = 'runway';
      return '$key $value mo';
    case 'target':
    case 'target months':
      key = 'target';
      return '$key $value mo';
    case 'mad z':
      return 'spike score $value';
    case 'jump pct':
      return 'jump $value%';
    case 'pace':
      return 'pace ${(num.tryParse(value) ?? 0) * 100}%';
    case 'pct spent':
      return 'used ${((num.tryParse(value) ?? 0) * 100).round()}%';
    case 'readiness':
      return 'readiness $value';
  }
  return '$key $value';
}

// ─── AI pillars ────────────────────────────────────────────────────────────

/// Pillars produced by the deterministic fallback often leak internal names
/// (metric keys, method names). This returns true when the pillar's
/// observation is essentially a summary of backend internals rather than a
/// user-facing insight.
bool isSyntheticPillar(GoatAIPillar p) {
  final text = p.observation.toLowerCase();
  if (text.isEmpty) return true;
  const markers = <String>[
    'ran via',
    'scored via',
    'snapshot generated at readiness',
    'flagged via',
  ];
  for (final m in markers) {
    if (text.contains(m)) return true;
  }
  return false;
}

/// When a pillar is synthetic we still want _something_ meaningful for the
/// most useful ones (overview + forecast + risk). This rewrites them using
/// the already-computed snapshot data.
GoatAIPillar rewriteSyntheticPillar(GoatAIPillar p, GoatSnapshot snap) {
  switch (p.pillar) {
    case 'overview':
      final covPct = (snap.coverage.score * 100).round();
      final readiness = snap.readiness.label.toLowerCase();
      final open = snap.recommendationCountsByKind.values
          .fold<int>(0, (a, b) => a + b);
      final parts = <String>[
        'Signal quality: $readiness ($covPct% coverage).',
      ];
      if (open > 0) parts.add('$open item(s) worth reviewing below.');
      return GoatAIPillar(
        pillar: p.pillar,
        observation: parts.join(' '),
        inference: p.inference.isNotEmpty
            ? p.inference
            : 'The more inputs Billy has, the sharper the next analysis gets.',
        confidenceBucket: p.confidenceBucket,
      );
    case 'forecast':
      final fc = snap.forecasts.firstWhere(
        (f) => f.status == 'ok' && f.p50 != null,
        orElse: () => const GoatForecastTarget(
          target: '',
          status: '',
          modelUsed: null,
          horizonDays: null,
          confidence: null,
          value: {},
          reasonCodes: [],
          entityLabel: null,
        ),
      );
      if (fc.target.isNotEmpty && fc.p50 != null) {
        final horizon = fc.horizonDays ?? 0;
        final currency = 'INR';
        final pretty = _formatForecastTarget(fc.target);
        return GoatAIPillar(
          pillar: p.pillar,
          observation:
              '$pretty projected at ${_forecastMoney(fc.p50!, currency)} over the next ${horizon == 0 ? 'cycle' : '$horizon days'}.',
          inference: 'Treat the low–high range as the primary signal, not the midpoint.',
          confidenceBucket: p.confidenceBucket,
        );
      }
      return p;
    case 'risk':
      final r = snap.risks
          .where((x) => x.probability != null)
          .toList(growable: false);
      if (r.isNotEmpty) {
        r.sort((a, b) => (b.probability ?? 0).compareTo(a.probability ?? 0));
        final top = r.first;
        return GoatAIPillar(
          pillar: p.pillar,
          observation:
              '${_riskLabel(top.target)} · ${((top.probability ?? 0) * 100).round()}% likely this cycle.',
          inference: 'Severity is the signal — act on the label, not the number.',
          confidenceBucket: p.confidenceBucket,
        );
      }
      return p;
    case 'anomaly':
      final top = snap.anomalies.isNotEmpty
          ? (dedupeAnomalies(snap.anomalies).first)
          : null;
      if (top != null) {
        final body = humanAnomalyBody(top);
        return GoatAIPillar(
          pillar: p.pillar,
          observation: body.isEmpty
              ? 'One unusual pattern stood out in the latest window.'
              : body,
          inference:
              'Scan it before acting — anomalies often reflect a one-off, not a trend.',
          confidenceBucket: p.confidenceBucket,
        );
      }
      return p;
    default:
      return p;
  }
}

String _formatForecastTarget(String key) {
  switch (key) {
    case 'short_horizon_spend_7d':
      return 'Spending · next 7 days';
    case 'short_horizon_spend_30d':
      return 'Spending · next 30 days';
    case 'end_of_month_liquidity':
      return 'End-of-month liquidity';
    case 'budget_overrun_trajectory':
      return 'Budget pace';
    case 'emergency_fund_depletion_horizon':
      return 'Emergency fund runway';
    case 'goal_completion_trajectory':
      return 'Goal completion';
    default:
      return key.replaceAll('_', ' ');
  }
}

String _forecastMoney(num v, String _) => formatInr(v);

String _riskLabel(String key) {
  switch (key) {
    case 'budget_overrun_risk':
      return 'Budget overrun risk';
    case 'missed_payment_risk':
      return 'Missed-payment risk';
    case 'short_term_liquidity_stress_risk':
      return 'Short-term liquidity stress';
    case 'emergency_fund_breach_risk':
      return 'Emergency-fund breach risk';
    case 'goal_shortfall_risk':
      return 'Goal shortfall risk';
    default:
      return key.replaceAll('_', ' ');
  }
}

// ─── footer ────────────────────────────────────────────────────────────────

/// Coaching nudge topics from the backend may be sentence case or snake_case.
String humanizeCoachingTopic(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 'Tip';
  if (!t.contains('_')) return t;
  return t
      .split('_')
      .where((s) => s.isNotEmpty)
      .map(
        (w) =>
            '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1).toLowerCase() : ''}',
      )
      .join(' ');
}

String footerAiStatusLabel(GoatAIEnvelope ai) {
  switch (ai.mode) {
    case 'real':
      return ai.validated ? 'AI-written analysis' : 'AI draft, unreviewed';
    case 'fake':
      return 'Preview narrative';
    case 'disabled':
    default:
      return 'Deterministic insights';
  }
}
