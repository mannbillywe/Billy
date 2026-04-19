import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';
import 'goat_humanize.dart';

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
    final rawNarrative = snapshot.ai.narrativeSummary.trim();
    // The deterministic fallback narrative contains strings like "scope=full"
    // and "deterministic fallback phrasing" — treat it as absent and use a
    // computed headline instead.
    final looksLikeFallback = rawNarrative.contains('deterministic fallback') ||
        rawNarrative.contains('scope=') ||
        rawNarrative.contains('readiness L');
    final hasNarrative = rawNarrative.isNotEmpty && !looksLikeFallback;
    final narrative = hasNarrative ? rawNarrative : '';
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
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Snapshot',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: Colors.white.withValues(alpha: 0.95),
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
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.35,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hasNarrative
                  ? narrative
                  : _deterministicHeadline(snapshot),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.9),
                height: 1.4,
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
        ? 'Coverage steady'
        : '${improved ? '+' : ''}$diffPct% vs last run';
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
    final openRecs =
        s.recommendationCountsByKind.values.fold<int>(0, (a, b) => a + b);
    if (openRecs > 0) {
      bits.add(openRecs == 1
          ? '1 priority to review'
          : '$openRecs priorities to review');
    }
    if (bits.isEmpty) {
      return 'Numbers update each run — check the tabs below for details.';
    }
    return bits.join(' · ');
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
              secondary: snapshot.coverage.score >= 0.72
                  ? 'Strong signal'
                  : 'Add more data',
              fraction: snapshot.coverage.score.clamp(0, 1),
              tintBg: const Color(0xFFEFF6FF),
              tintFg: const Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.flag_rounded,
              title: 'Queue',
              primary: openRecs == 0 ? '0' : openRecs.toString(),
              secondary: openRecs == 0 ? 'Inbox clear' : 'To review',
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
        return 'Starter depth';
      case GoatReadiness.l2:
        return 'Solid depth';
      case GoatReadiness.l3:
        return 'Full depth';
      case GoatReadiness.unknown:
        return '—';
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
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
              color: BillyTheme.gray400,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            primary,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
              height: 1.15,
              letterSpacing: -0.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
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
    // Collapse recs that share the same fingerprint/kind-entity so we don't
    // show three copies of the same "Category spike" card.
    final seen = <String>{};
    final deduped = <GoatRecommendation>[];
    for (final r in recommendations) {
      final key = r.recFingerprint.isNotEmpty
          ? r.recFingerprint
          : '${r.kind}|${r.entityId ?? ''}';
      if (seen.add(key)) deduped.add(r);
    }
    // Sort: severity first (critical→info), then priority.
    final sorted = [...deduped]
      ..sort((a, b) {
        final s = b.severity.rank.compareTo(a.severity.rank);
        if (s != 0) return s;
        return b.priority.compareTo(a.priority);
      });
    final visible = sorted.take(5).toList(growable: false);
    final more = sorted.length - visible.length;

    return _SectionShell(
      kicker: 'Priorities',
      title: 'Start here',
      subtitle: 'Dismiss when you\'ve handled an item.',
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
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                '+$more similar · grouped',
                style: const TextStyle(
                  fontSize: 11,
                  color: BillyTheme.gray400,
                  fontWeight: FontWeight.w600,
                ),
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
    final title = bestRecTitle(rec, phrasing);
    final body = bestRecBody(rec, phrasing);
    final rawWhy = phrasing?.whyShown ?? '';
    // Hide the canned deterministic "why_shown" line — it adds noise without
    // explaining anything specific to the recommendation.
    final why = isAiPlaceholderWhy(rawWhy) ? '' : rawWhy;

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
                  rec.severity.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
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
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: BillyTheme.gray600,
                height: 1.4,
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
    // Rewrite synthetic (fallback) pillars into something user-facing, and
    // drop any that would still show internal metadata (metric keys, model
    // names, method names).
    final cleaned = <GoatAIPillar>[];
    for (final p in snapshot.ai.pillars) {
      final next = isSyntheticPillar(p) ? rewriteSyntheticPillar(p, snapshot) : p;
      if (isSyntheticPillar(next)) continue;
      cleaned.add(next);
    }
    if (cleaned.isEmpty) return const SizedBox.shrink();
    return _SectionShell(
      kicker: 'Insights',
      title: 'Plain-English read',
      subtitle: 'Grounded in your latest numbers.',
      child: Column(
        children: [
          for (final p in cleaned.take(6))
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
                  _pillarLabel(pillar.pillar),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
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
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: BillyTheme.gray800,
              height: 1.35,
              letterSpacing: -0.1,
            ),
          ),
          if (pillar.inference.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              pillar.inference,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: BillyTheme.gray500,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _confidenceChip(String bucket) {
    final label = switch (bucket) {
      'high' => 'High',
      'medium' => 'Med',
      'low' => 'Low',
      'very_low' => 'Low+',
      _ => '—',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: BillyTheme.gray50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: BillyTheme.gray500,
        ),
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
      return 'Pattern';
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
    final maxHorizon = forecasts
        .map((f) => f.horizonDays ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final horizonLabel =
        maxHorizon > 0 ? 'the next $maxHorizon days' : 'the coming period';

    return _SectionShell(
      kicker: 'Outlook',
      title: 'Forward view',
      subtitle: 'Bands are guides for $horizonLabel — not guarantees.',
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
                _forecastModelLabel(target),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.gray400,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (target.horizonDays != null && target.horizonDays! > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Window · next ${target.horizonDays} days',
              style: const TextStyle(
                fontSize: 11,
                color: BillyTheme.gray500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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

String _forecastModelLabel(GoatForecastTarget t) {
  final raw = (t.modelUsed ?? 'statistical blend').replaceAll('_', ' ');
  return raw.length <= 24 ? raw : '${raw.substring(0, 21)}…';
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

// ─── at-a-glance metrics (deterministic layer) ─────────────────────────────

class GoatMetricHighlights extends StatelessWidget {
  const GoatMetricHighlights({super.key, required this.snapshot});
  final GoatSnapshot snapshot;

  static const _items = <(String key, String label)>[
    ('net_worth', 'Net worth'),
    ('month_to_date_spend', 'Month to date'),
    ('daily_spend_avg', 'Daily avg spend'),
    ('savings_rate', 'Savings rate'),
  ];

  @override
  Widget build(BuildContext context) {
    final chips = <({String label, String value})>[];
    for (final (key, label) in _items) {
      final m = snapshot.metricByKey(key);
      final v = m?.value;
      if (v == null) continue;
      if (v is! num) continue;
      final formatted = key == 'savings_rate'
          ? '${(v * 100).round()}%'
          : _money(v, m?.unit);
      chips.add((label: label, value: formatted));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(Icons.speed_rounded, size: 16, color: BillyTheme.gray400),
                SizedBox(width: 6),
                Text(
                  'Key figures',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BillyTheme.gray600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final c = chips[i];
                return Container(
                  width: 118,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: BillyTheme.gray100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: BillyTheme.gray400,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: BillyTheme.gray800,
                          letterSpacing: -0.35,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── watchouts (anomalies + risks) ─────────────────────────────────────────

class GoatWatchoutsSection extends StatelessWidget {
  const GoatWatchoutsSection({
    super.key,
    required this.snapshot,
    this.anomalyEntityIdsInPriorities = const {},
  });

  final GoatSnapshot snapshot;
  /// Entity IDs already shown as priority cards — hide duplicate anomaly rows.
  final Set<String> anomalyEntityIdsInPriorities;

  @override
  Widget build(BuildContext context) {
    final risks = snapshot.risks
        .where((r) =>
            r.severity == GoatSeverity.warn ||
            r.severity == GoatSeverity.critical)
        .toList(growable: false);
    // Collapse duplicate anomalies (same kind + same entity) and keep the most
    // severe representative of each cluster.
    var anomalies = dedupeAnomalies(
      snapshot.anomalies
          .where((a) => a.severity.rank >= GoatSeverity.watch.rank)
          .toList(growable: false),
    );
    if (anomalyEntityIdsInPriorities.isNotEmpty) {
      anomalies = anomalies
          .where((a) {
            final id = a.entityId;
            if (id == null || id.isEmpty) return true;
            return !anomalyEntityIdsInPriorities.contains(id);
          })
          .toList(growable: false);
    }

    // Nothing worth showing? Hide the whole block rather than rendering an
    // empty section header.
    if (risks.isEmpty && anomalies.isEmpty) return const SizedBox.shrink();

    // Count how many anomaly clusters we dropped so we can hint at the total.
    final extra = anomalies.length > 6 ? anomalies.length - 6 : 0;

    return _SectionShell(
      kicker: 'Alerts',
      title: 'Watch closely',
      subtitle: 'Risk + unusual patterns.',
      child: Column(
        children: [
          for (final r in risks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WatchoutRow(
                icon: Icons.shield_moon_rounded,
                severity: r.severity,
                title: _riskLabel(r.target),
                body: humanRiskBody(r),
              ),
            ),
          for (final a in anomalies.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WatchoutRow(
                icon: Icons.insights_rounded,
                severity: a.severity,
                title: _anomalyTitle(a.kind),
                body: humanAnomalyBody(a),
              ),
            ),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                '+$extra similar · grouped',
                style: const TextStyle(
                  fontSize: 11,
                  color: BillyTheme.gray400,
                  fontWeight: FontWeight.w600,
                ),
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

  String _anomalyTitle(String kind) {
    switch (kind) {
      case 'amount_spike_category':
        return 'Unusually large charge';
      case 'recurring_bill_jump':
        return 'Recurring bill jumped';
      case 'budget_pace_acceleration':
        return 'Budget pace accelerating';
      case 'low_liquidity_pattern':
        return 'Low cash buffer';
      case 'duplicate_like_pattern':
        return 'Possible duplicate charges';
      case 'noisy_import_cluster':
        return 'Noisy import batch';
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
      kicker: 'Ideas',
      title: 'Next moves',
      subtitle: null,
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
                  humanizeCoachingTopic(nudge.topic),
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
      kicker: 'Setup',
      title: 'Unlock more depth',
      subtitle: 'Optional fields that improve the next run.',
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
    final chips = <Widget>[
      if (snapshot.generatedAt != null)
        _MetaChip(
          icon: Icons.schedule_rounded,
          label: _relativeTime(snapshot.generatedAt),
        ),
      _MetaChip(
        icon: Icons.layers_rounded,
        label: snapshot.scope,
      ),
      if (snapshot.isPartial)
        const _MetaChip(
          icon: Icons.warning_amber_rounded,
          label: 'Partial',
          emphasis: true,
        ),
      _MetaChip(
        icon: Icons.smart_toy_outlined,
        label: footerAiStatusLabel(snapshot.ai),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.emphasis = false,
  });
  final IconData icon;
  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final fg = emphasis ? const Color(0xFFB45309) : BillyTheme.gray500;
    final bg = emphasis ? const Color(0xFFFFFBEB) : BillyTheme.gray50;
    final bd = emphasis ? const Color(0xFFFDE68A) : BillyTheme.gray100;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── shared section shell ──────────────────────────────────────────────────

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.kicker,
    required this.title,
    this.subtitle,
    required this.child,
  });
  final String kicker;
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kicker,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: BillyTheme.gray400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: BillyTheme.gray800,
              letterSpacing: -0.35,
              height: 1.2,
            ),
          ),
          if (sub != null && sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              style: const TextStyle(
                fontSize: 12,
                color: BillyTheme.gray500,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
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
