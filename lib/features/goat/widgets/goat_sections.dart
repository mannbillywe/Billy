import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';

// ─── shared colors for severity ────────────────────────────────────────────

class _SeverityColors {
  const _SeverityColors(this.fg, this.bg, this.border);
  final Color fg;
  final Color bg;
  final Color border;

  static _SeverityColors of(GoatSeverity s) {
    switch (s) {
      case GoatSeverity.critical:
        return const _SeverityColors(
          Color(0xFFB91C1C),
          Color(0xFFFEF2F2),
          Color(0xFFFECACA),
        );
      case GoatSeverity.warn:
        return const _SeverityColors(
          Color(0xFFB45309),
          Color(0xFFFFFBEB),
          Color(0xFFFDE68A),
        );
      case GoatSeverity.watch:
        return const _SeverityColors(
          Color(0xFF1D4ED8),
          Color(0xFFEFF6FF),
          Color(0xFFBFDBFE),
        );
      case GoatSeverity.info:
        return _SeverityColors(
          BillyTheme.emerald700,
          BillyTheme.emerald50,
          BillyTheme.emerald100,
        );
    }
  }
}

// ─── hero card ─────────────────────────────────────────────────────────────

class GoatHeroCard extends StatelessWidget {
  const GoatHeroCard({
    super.key,
    required this.snapshot,
    required this.previous,
  });
  final GoatSnapshot snapshot;
  final GoatSnapshot? previous;

  @override
  Widget build(BuildContext context) {
    final narrative = snapshot.ai.narrativeSummary.trim();
    final hasNarrative = narrative.isNotEmpty;
    final generatedLabel = _relativeTime(snapshot.generatedAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF047857), Color(0xFF059669), Color(0xFF10B981)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF059669).withValues(alpha: 0.28),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 12, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'MONTHLY DEEP ANALYSIS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  generatedLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              hasNarrative
                  ? "Here's what matters right now"
                  : 'Your financial snapshot',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.4,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              hasNarrative
                  ? narrative
                  : _deterministicHeadline(snapshot),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.92),
                height: 1.45,
              ),
            ),
            if (previous != null && previous!.id != snapshot.id) ...[
              const SizedBox(height: 14),
              _trendStrip(snapshot: snapshot, previous: previous!),
            ],
          ],
        ),
      ),
    );
  }

  /// Small comparison chip row when a previous snapshot exists.
  Widget _trendStrip({
    required GoatSnapshot snapshot,
    required GoatSnapshot previous,
  }) {
    final covDelta = snapshot.coverage.score - previous.coverage.score;
    final diffPct = (covDelta * 100).round();
    final improved = diffPct > 0;
    final same = diffPct == 0;
    final label = same
        ? 'Coverage unchanged from last run'
        : '${improved ? '+' : ''}$diffPct% coverage vs last run';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            improved
                ? Icons.trending_up_rounded
                : (same
                    ? Icons.trending_flat_rounded
                    : Icons.trending_down_rounded),
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _deterministicHeadline(GoatSnapshot s) {
    final bits = <String>[];
    final netWorth = s.metricByKey('net_worth');
    if (netWorth?.value is num) {
      bits.add('Net worth ${_money(netWorth!.value as num, netWorth.unit)}');
    }
    final mtd = s.metricByKey('month_to_date_spend');
    if (mtd?.value is num) {
      bits.add('MTD spend ${_money(mtd!.value as num, mtd.unit)}');
    }
    if (bits.isEmpty) {
      return 'Your latest analysis is ready. Scroll for priorities, forecasts, and insights.';
    }
    return '${bits.join(' · ')}. Scroll for the full picture.';
  }
}

// ─── score row (readiness + coverage + open-items counts) ──────────────────

class GoatScoreRow extends StatelessWidget {
  const GoatScoreRow({
    super.key,
    required this.snapshot,
    required this.previous,
  });
  final GoatSnapshot snapshot;
  final GoatSnapshot? previous;

  @override
  Widget build(BuildContext context) {
    final openRecs =
        snapshot.recommendationCountsByKind.values.fold<int>(0, (a, b) => a + b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.verified_rounded,
              title: 'Readiness',
              primary: snapshot.readiness.label,
              secondary: _readinessSubtitle(snapshot.readiness),
              fraction: snapshot.readiness.fraction,
              tintBg: BillyTheme.emerald50,
              tintFg: BillyTheme.emerald700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.donut_small_rounded,
              title: 'Coverage',
              primary: '${(snapshot.coverage.score * 100).round()}%',
              secondary:
                  '${snapshot.coverage.breakdown.length} pillars tracked',
              fraction: snapshot.coverage.score.clamp(0, 1),
              tintBg: const Color(0xFFEFF6FF),
              tintFg: const Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.flag_rounded,
              title: 'Open items',
              primary: openRecs == 0 ? 'All clear' : openRecs.toString(),
              secondary: openRecs == 0
                  ? 'No priorities'
                  : 'Recommendations to review',
              fraction: null,
              tintBg: const Color(0xFFFEF3C7),
              tintFg: const Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  String _readinessSubtitle(GoatReadiness r) {
    switch (r) {
      case GoatReadiness.l1:
        return 'Add a few inputs to unlock more';
      case GoatReadiness.l2:
        return 'Confident insights';
      case GoatReadiness.l3:
        return 'Highest fidelity';
      case GoatReadiness.unknown:
        return '-';
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.title,
    required this.primary,
    required this.secondary,
    required this.fraction,
    required this.tintBg,
    required this.tintFg,
  });

  final IconData icon;
  final String title;
  final String primary;
  final String secondary;
  final double? fraction;
  final Color tintBg;
  final Color tintFg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: tintBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: tintFg, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: BillyTheme.gray400,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            primary,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
              height: 1.1,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            secondary,
            style: const TextStyle(
              fontSize: 11,
              color: BillyTheme.gray500,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (fraction != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction!,
                minHeight: 5,
                backgroundColor: BillyTheme.gray100,
                valueColor: AlwaysStoppedAnimation(tintFg),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── priority (top recommendations) ────────────────────────────────────────

class GoatPrioritySection extends StatelessWidget {
  const GoatPrioritySection({
    super.key,
    required this.recommendations,
    required this.aiPhrasings,
    required this.onDismiss,
  });
  final List<GoatRecommendation> recommendations;
  final List<GoatAIRecommendationPhrasing> aiPhrasings;
  final ValueChanged<GoatRecommendation> onDismiss;

  @override
  Widget build(BuildContext context) {
    final phrasingByFp = {
      for (final p in aiPhrasings) p.recFingerprint: p,
    };
    // Sort: severity first (critical→info), then priority.
    final sorted = [...recommendations]
      ..sort((a, b) {
        final s = b.severity.rank.compareTo(a.severity.rank);
        if (s != 0) return s;
        return b.priority.compareTo(a.priority);
      });
    final visible = sorted.take(5).toList(growable: false);
    final more = sorted.length - visible.length;

    return _SectionShell(
      kicker: 'MOST IMPORTANT RIGHT NOW',
      title: 'Your top priorities',
      subtitle:
          'Ranked by urgency and impact. Tap dismiss on items you\'ve handled.',
      child: Column(
        children: [
          for (final rec in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PriorityCard(
                rec: rec,
                phrasing: phrasingByFp[rec.recFingerprint],
                onDismiss: () => onDismiss(rec),
              ),
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '$more more similar items grouped behind the scenes',
                style: const TextStyle(
                    fontSize: 12,
                    color: BillyTheme.gray500,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({
    required this.rec,
    required this.phrasing,
    required this.onDismiss,
  });
  final GoatRecommendation rec;
  final GoatAIRecommendationPhrasing? phrasing;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = _SeverityColors.of(rec.severity);
    final title = phrasing?.title.isNotEmpty == true
        ? phrasing!.title
        : rec.defaultTitle;
    final body = phrasing?.body.isNotEmpty == true
        ? phrasing!.body
        : rec.defaultBody;
    final why = phrasing?.whyShown ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: colors.bg, borderRadius: BorderRadius.circular(10)),
                child: Icon(
                  _iconForKind(rec.kind),
                  size: 17,
                  color: colors.fg,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  rec.severity.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: colors.fg,
                  ),
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                fontSize: 13,
                color: BillyTheme.gray600,
                height: 1.45,
              ),
            ),
          ],
          if (why.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: BillyTheme.gray50,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: BillyTheme.gray500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      why,
                      style: const TextStyle(
                        fontSize: 11,
                        color: BillyTheme.gray500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: BillyTheme.gray500,
                  minimumSize: const Size(64, 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                ),
                child: const Text('Dismiss',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _iconForKind(String kind) {
  switch (kind) {
    case 'budget_overrun':
      return Icons.speed_rounded;
    case 'anomaly_review':
      return Icons.search_rounded;
    case 'liquidity_warning':
      return Icons.water_drop_rounded;
    case 'goal_shortfall':
      return Icons.flag_rounded;
    case 'missed_payment_risk':
      return Icons.event_busy_rounded;
    case 'recurring_drift':
      return Icons.autorenew_rounded;
    case 'duplicate_cluster':
      return Icons.copy_rounded;
    case 'missing_input':
      return Icons.edit_note_rounded;
    case 'uncategorized_cleanup':
      return Icons.filter_alt_rounded;
    case 'recovery_iou':
      return Icons.handshake_rounded;
    default:
      return Icons.lightbulb_outline_rounded;
  }
}

// ─── pillars / key insights ────────────────────────────────────────────────

class GoatInsightsSection extends StatelessWidget {
  const GoatInsightsSection({super.key, required this.snapshot});
  final GoatSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      kicker: 'KEY INSIGHTS',
      title: 'What the numbers are telling us',
      subtitle:
          'Grounded observations from your data, explained in plain English.',
      child: Column(
        children: [
          for (final p in snapshot.ai.pillars.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InsightCard(pillar: p),
            ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.pillar});
  final GoatAIPillar pillar;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: BillyTheme.emerald50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: BillyTheme.emerald100),
                ),
                child: Text(
                  _pillarLabel(pillar.pillar).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: BillyTheme.emerald700,
                  ),
                ),
              ),
              const Spacer(),
              _confidenceChip(pillar.confidenceBucket),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pillar.observation,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: BillyTheme.gray800,
              height: 1.4,
              letterSpacing: -0.1,
            ),
          ),
          if (pillar.inference.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              pillar.inference,
              style: const TextStyle(
                fontSize: 13,
                color: BillyTheme.gray500,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _confidenceChip(String bucket) {
    final label = switch (bucket) {
      'high' => 'High confidence',
      'medium' => 'Medium confidence',
      'low' => 'Low confidence',
      'very_low' => 'Very low confidence',
      _ => 'Confidence unknown',
    };
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: BillyTheme.gray400,
        letterSpacing: 0.3,
      ),
    );
  }
}

String _pillarLabel(String key) {
  switch (key) {
    case 'overview':
      return 'Overview';
    case 'cashflow':
      return 'Cashflow';
    case 'budgets':
      return 'Budgets';
    case 'recurring':
      return 'Recurring';
    case 'debt':
      return 'Debt';
    case 'goals':
      return 'Goals';
    case 'forecast':
      return 'Forecast';
    case 'anomaly':
      return 'Anomaly';
    case 'risk':
      return 'Risk';
    default:
      return key;
  }
}

// ─── forecast preview ──────────────────────────────────────────────────────

class GoatForecastSection extends StatelessWidget {
  const GoatForecastSection({super.key, required this.snapshot});
  final GoatSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final forecasts = snapshot.forecasts
        .where((f) => f.status == 'ok' && f.p50 != null)
        .toList(growable: false);
    if (forecasts.isEmpty) return const SizedBox.shrink();

    return _SectionShell(
      kicker: 'FORECAST',
      title: 'Where the next 30 days are heading',
      subtitle: 'Projected ranges with low/high bounds so you can plan.',
      child: Column(
        children: [
          for (final f in forecasts.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ForecastCard(target: f, currency: _inferCurrency(snapshot)),
            ),
        ],
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.target, required this.currency});
  final GoatForecastTarget target;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p10 = target.p10;
    final p50 = target.p50;
    final p90 = target.p90;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _targetLabel(target.target),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
              ),
              Text(
                (target.modelUsed ?? 'model').replaceAll('_', ' '),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.gray400,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (p50 != null)
            Text(
              _money(p50, currency),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
                letterSpacing: -0.4,
              ),
            ),
          if (p10 != null && p90 != null) ...[
            const SizedBox(height: 2),
            Text(
              'Typical range ${_money(p10, currency)} – ${_money(p90, currency)}',
              style: const TextStyle(
                fontSize: 12,
                color: BillyTheme.gray500,
              ),
            ),
            const SizedBox(height: 10),
            _RangeBar(p10: p10, p50: p50 ?? (p10 + p90) / 2, p90: p90),
          ],
        ],
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.p10, required this.p50, required this.p90});
  final double p10;
  final double p50;
  final double p90;
  @override
  Widget build(BuildContext context) {
    final span = (p90 - p10).abs();
    final pct = span == 0 ? 0.5 : ((p50 - p10) / span).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return SizedBox(
          height: 18,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: BillyTheme.emerald50,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Positioned(
                left: (w * pct).clamp(0, w - 10).toDouble(),
                child: Container(
                  width: 10,
                  height: 18,
                  decoration: BoxDecoration(
                    color: BillyTheme.emerald600,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color:
                            BillyTheme.emerald600.withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _targetLabel(String key) {
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

// ─── watchouts (anomalies + risks) ─────────────────────────────────────────

class GoatWatchoutsSection extends StatelessWidget {
  const GoatWatchoutsSection({super.key, required this.snapshot});
  final GoatSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final risks = snapshot.risks
        .where((r) =>
            r.severity == GoatSeverity.warn ||
            r.severity == GoatSeverity.critical)
        .toList(growable: false);
    final anomalies = snapshot.anomalies
        .where((a) => a.severity.rank >= GoatSeverity.watch.rank)
        .toList(growable: false)
      ..sort((a, b) => b.severity.rank.compareTo(a.severity.rank));

    return _SectionShell(
      kicker: 'WATCHOUTS',
      title: 'Things to keep an eye on',
      subtitle: 'Flags from the risk model and anomaly scanner.',
      child: Column(
        children: [
          for (final r in risks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WatchoutRow(
                icon: Icons.shield_moon_rounded,
                severity: r.severity,
                title: _riskLabel(r.target),
                body: _riskBody(r),
              ),
            ),
          for (final a in anomalies.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WatchoutRow(
                icon: Icons.insights_rounded,
                severity: a.severity,
                title: _anomalyTitle(a.kind),
                body: a.explanation ?? '',
              ),
            ),
        ],
      ),
    );
  }

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

  String _riskBody(GoatRiskScore r) {
    if (r.probability == null) return '';
    final pct = (r.probability! * 100).round();
    return '$pct% likely this cycle. ${r.reasonCodes.isNotEmpty ? 'Drivers: ${r.reasonCodes.join(', ')}' : ''}';
  }

  String _anomalyTitle(String kind) {
    switch (kind) {
      case 'amount_spike_category':
        return 'Category spike';
      case 'recurring_bill_jump':
        return 'Recurring bill jumped';
      case 'budget_pace_acceleration':
        return 'Budget pace accelerating';
      case 'low_liquidity_pattern':
        return 'Low-liquidity pattern';
      case 'duplicate_like_pattern':
        return 'Possible duplicate pattern';
      case 'noisy_import_cluster':
        return 'Noisy import cluster';
      case 'isolation_outlier':
        return 'Outlier transaction';
      default:
        return kind.replaceAll('_', ' ');
    }
  }
}

class _WatchoutRow extends StatelessWidget {
  const _WatchoutRow({
    required this.icon,
    required this.severity,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final GoatSeverity severity;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = _SeverityColors.of(severity);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: c.bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: c.fg, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: BillyTheme.gray800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        severity.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: c.fg,
                        ),
                      ),
                    ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 12,
                      color: BillyTheme.gray600,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── coaching (AI envelope) ────────────────────────────────────────────────

class GoatCoachingSection extends StatelessWidget {
  const GoatCoachingSection({super.key, required this.snapshot});
  final GoatSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final coaching = snapshot.ai.coaching.take(4).toList(growable: false);
    if (coaching.isEmpty) return const SizedBox.shrink();
    return _SectionShell(
      kicker: 'NEXT MOVES',
      title: 'Opportunities worth acting on',
      subtitle: 'Small, specific changes that compound over time.',
      child: Column(
        children: [
          for (final c in coaching)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CoachingCard(nudge: c),
            ),
        ],
      ),
    );
  }
}

class _CoachingCard extends StatelessWidget {
  const _CoachingCard({required this.nudge});
  final GoatAICoachingNudge nudge;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [BillyTheme.emerald50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.emerald100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: BillyTheme.emerald100),
            ),
            child: const Icon(Icons.bolt_rounded,
                color: BillyTheme.emerald700, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nudge.topic,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nudge.body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: BillyTheme.gray600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── missing inputs (unlock-more-coverage nudge) ───────────────────────────

class GoatMissingInputsSection extends StatelessWidget {
  const GoatMissingInputsSection({super.key, required this.snapshot});
  final GoatSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final items = snapshot.coverage.missingInputs
        .where((m) => m.severity.rank >= GoatSeverity.watch.rank)
        .take(4)
        .toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();
    return _SectionShell(
      kicker: 'UNLOCK MORE',
      title: 'Add these to sharpen future analyses',
      subtitle: 'Each item unlocks a specific layer of insight.',
      child: Column(
        children: [
          for (final m in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: BillyTheme.gray100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: BillyTheme.gray800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.why,
                      style: const TextStyle(
                        fontSize: 12,
                        color: BillyTheme.gray500,
                        height: 1.45,
                      ),
                    ),
                    if (m.unlocks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final u in m.unlocks.take(4))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: BillyTheme.gray50,
                                borderRadius: BorderRadius.circular(6),
                                border:
                                    Border.all(color: BillyTheme.gray100),
                              ),
                              child: Text(
                                u.replaceAll('_', ' '),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: BillyTheme.gray600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── footer meta ───────────────────────────────────────────────────────────

class GoatFooterMeta extends StatelessWidget {
  const GoatFooterMeta({super.key, required this.snapshot});
  final GoatSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (snapshot.generatedAt != null)
        'Generated ${_relativeTime(snapshot.generatedAt)}',
      'Scope: ${snapshot.scope}',
      if (snapshot.isPartial) 'Partial snapshot',
      if (snapshot.ai.mode == 'real' && snapshot.ai.validated)
        'AI narrative validated',
      if (snapshot.ai.mode == 'real' && !snapshot.ai.validated)
        'AI narrative unvalidated',
      if (snapshot.ai.mode == 'disabled') 'Deterministic-only',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Center(
        child: Text(
          parts.join(' · '),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            color: BillyTheme.gray400,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── shared section shell ──────────────────────────────────────────────────

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String kicker;
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kicker,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: BillyTheme.gray400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12.5,
              color: BillyTheme.gray500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─── formatting helpers (private to this file) ─────────────────────────────

String _inferCurrency(GoatSnapshot s) {
  for (final m in s.metrics) {
    if (m.unit != null && m.unit!.isNotEmpty) return m.unit!;
  }
  return 'INR';
}

String _money(num value, String? unit) {
  final amount = value.abs();
  String formatted;
  if (amount >= 10000000) {
    formatted = '${(amount / 10000000).toStringAsFixed(2)} Cr';
  } else if (amount >= 100000) {
    formatted = '${(amount / 100000).toStringAsFixed(2)} L';
  } else if (amount >= 1000) {
    formatted = amount.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  } else {
    formatted = amount.toStringAsFixed(0);
  }
  final symbol = _currencySymbol(unit ?? 'INR');
  final sign = value < 0 ? '-' : '';
  return '$sign$symbol$formatted';
}

String _currencySymbol(String unit) {
  switch (unit.toUpperCase()) {
    case 'INR':
      return '₹';
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    default:
      return '';
  }
}

String _relativeTime(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  final months = (diff.inDays / 30).round();
  return '${months}mo ago';
}
