import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_chart_models.dart';
import '../models/goat_models.dart';
import '../providers/goat_providers.dart';
import 'goat_chart_widgets.dart';
import 'goat_humanize.dart';
import 'goat_report_sheets.dart';
import 'goat_sections.dart';

String _isoCurrency(GoatSnapshot s) {
  for (final m in s.metrics) {
    if (m.unit != null && m.unit!.length == 3) return m.unit!.toUpperCase();
  }
  return 'INR';
}

class _GoatTimeseriesChartStrip extends StatelessWidget {
  const _GoatTimeseriesChartStrip({
    required this.charts,
    required this.defaultCurrency,
  });

  final GoatChartBundle charts;
  final String defaultCurrency;

  @override
  Widget build(BuildContext context) {
    if (charts.timeseries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.timeline_rounded,
                  size: 16,
                  color: BillyTheme.gray500,
                ),
                SizedBox(width: 6),
                Text(
                  'Trend charts',
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
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: charts.timeseries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final ts = charts.timeseries[i];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => showGoatTimeseriesReportSheet(
                      context,
                      spec: ts,
                      currencyCode: ts.unit ?? defaultCurrency,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: BillyTheme.gray100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.show_chart_rounded,
                            size: 18,
                            color: BillyTheme.emerald700,
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              ts.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: BillyTheme.gray800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: BillyTheme.emerald700,
                          ),
                        ],
                      ),
                    ),
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

/// Tab 1 — headline snapshot: hero, scores, headline metrics, AI pillars.
class GoatOverviewTab extends StatelessWidget {
  const GoatOverviewTab({
    super.key,
    required this.snapshot,
    required this.previous,
    required this.onRefresh,
  });

  final GoatSnapshot snapshot;
  final GoatSnapshot? previous;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final cur = _isoCurrency(snapshot);
    return RefreshIndicator(
      color: BillyTheme.emerald600,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          GoatHeroCard(snapshot: snapshot, previous: previous),
          GoatScoreRow(snapshot: snapshot, previous: previous),
          GoatCoveragePillarChart(coverage: snapshot.coverage),
          if (snapshot.charts != null)
            _GoatTimeseriesChartStrip(
              charts: snapshot.charts!,
              defaultCurrency: cur,
            ),
          if (snapshot.charts != null)
            for (final bar in snapshot.charts!.barGroups)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GoatBackendBarChart(
                  title: bar.title,
                  items: bar.items,
                  currencyCode: bar.unit ?? cur,
                ),
              ),
          GoatMetricHighlights(
            snapshot: snapshot,
            onMetricTap: (metric, label) => showGoatMetricReportSheet(
              context,
              snapshot: snapshot,
              metric: metric,
              label: label,
            ),
          ),
          if (snapshot.ai.pillars.isNotEmpty)
            GoatInsightsSection(snapshot: snapshot),
        ],
      ),
    );
  }
}

/// Tab 2 — what to do next: priorities, setup gaps, coaching, unlockable scopes.
class GoatActionsTab extends StatelessWidget {
  const GoatActionsTab({
    super.key,
    required this.snapshot,
    required this.recommendations,
    required this.onDismiss,
    required this.onRefresh,
  });

  final GoatSnapshot snapshot;
  final List<GoatRecommendation> recommendations;
  final void Function(GoatRecommendation rec) onDismiss;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: BillyTheme.emerald600,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (recommendations.isNotEmpty)
            GoatPrioritySection(
              recommendations: recommendations,
              aiPhrasings: snapshot.ai.recommendationPhrasings,
              onDismiss: onDismiss,
            ),
          if (snapshot.coverage.unlockableScopes.isNotEmpty)
            _UnlockableScopesCard(scopes: snapshot.coverage.unlockableScopes),
          if (snapshot.coverage.missingInputs.isNotEmpty)
            GoatMissingInputsSection(snapshot: snapshot),
          if (snapshot.ai.coaching.isNotEmpty)
            GoatCoachingSection(snapshot: snapshot),
          if (recommendations.isEmpty &&
              snapshot.coverage.missingInputs.isEmpty &&
              snapshot.ai.coaching.isEmpty &&
              snapshot.coverage.unlockableScopes.isEmpty)
            const _TabEmpty(
              icon: Icons.check_circle_outline_rounded,
              title: 'All quiet',
              body: 'New items appear here after the next analysis run.',
            ),
        ],
      ),
    );
  }
}

class _UnlockableScopesCard extends StatelessWidget {
  const _UnlockableScopesCard({required this.scopes});
  final List<String> scopes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lock_open_rounded,
                  size: 18,
                  color: BillyTheme.emerald700,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Can unlock',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'After you add missing details, the next analysis can include:',
              style: TextStyle(
                fontSize: 11.5,
                color: BillyTheme.gray500,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in scopes)
                  Chip(
                    label: Text(
                      s,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: BillyTheme.emerald50,
                    side: BorderSide(color: BillyTheme.emerald100),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab 3 — forecast targets only.
class GoatTrendsTab extends StatelessWidget {
  const GoatTrendsTab({
    super.key,
    required this.snapshot,
    required this.onRefresh,
  });

  final GoatSnapshot snapshot;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: BillyTheme.emerald600,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (snapshot.forecasts.isNotEmpty)
            GoatForecastSection(snapshot: snapshot)
          else
            const _TabEmpty(
              icon: Icons.show_chart_rounded,
              title: 'No forecasts yet',
              body: 'More history usually unlocks this view.',
            ),
        ],
      ),
    );
  }
}

/// Tab 4 — risks and anomalies (watchouts).
class GoatSafetyTab extends StatelessWidget {
  const GoatSafetyTab({
    super.key,
    required this.snapshot,
    required this.priorityAnomalyEntities,
    required this.onRefresh,
  });

  final GoatSnapshot snapshot;
  final Set<String> priorityAnomalyEntities;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final hasWatchouts = _hasWatchouts(snapshot, priorityAnomalyEntities);
    return RefreshIndicator(
      color: BillyTheme.emerald600,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (hasWatchouts)
            GoatWatchoutsSection(
              snapshot: snapshot,
              anomalyEntityIdsInPriorities: priorityAnomalyEntities,
            )
          else
            const _TabEmpty(
              icon: Icons.shield_outlined,
              title: 'Looks steady',
              body: 'No risk or anomaly flags for this run.',
            ),
        ],
      ),
    );
  }

  bool _hasWatchouts(GoatSnapshot s, Set<String> priorityAnomalyEntities) {
    final hasRisk = s.risks.any(
      (r) =>
          r.severity == GoatSeverity.warn ||
          r.severity == GoatSeverity.critical,
    );
    if (hasRisk) return true;
    final anomalies = dedupeAnomalies(
      s.anomalies
          .where((a) => a.severity.rank >= GoatSeverity.watch.rank)
          .toList(growable: false),
    );
    for (final a in anomalies) {
      final id = a.entityId;
      if (id != null && id.isNotEmpty && priorityAnomalyEntities.contains(id)) {
        continue;
      }
      return true;
    }
    return false;
  }
}

/// Tab 5 — run metadata, recommendation histogram, layer soft-fails, job list.
class GoatRunLogTab extends ConsumerWidget {
  const GoatRunLogTab({
    super.key,
    required this.snapshot,
    required this.onRefresh,
  });

  final GoatSnapshot snapshot;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(goatRecentJobsProvider);
    return RefreshIndicator(
      color: BillyTheme.emerald600,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (snapshot.recommendationCountsBySeverity.isNotEmpty ||
              snapshot.recommendationCountsByKind.isNotEmpty)
            _RunSummaryCard(
              bySeverity: snapshot.recommendationCountsBySeverity,
              byKind: snapshot.recommendationCountsByKind,
            ),
          if (snapshot.layerErrors.isNotEmpty)
            _LayerErrorsCard(errors: snapshot.layerErrors),
          GoatFooterMeta(snapshot: snapshot),
          const SizedBox(height: 8),
          jobsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: LinearProgressIndicator(minHeight: 3),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (jobs) {
              if (jobs.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 18,
                          color: BillyTheme.gray500,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Past runs',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: BillyTheme.gray800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...jobs.map((j) => _JobTile(job: j)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RunSummaryCard extends StatelessWidget {
  const _RunSummaryCard({required this.bySeverity, required this.byKind});

  final Map<String, int> bySeverity;
  final Map<String, int> byKind;

  static String _shortKind(String k) {
    if (k.length <= 14) return k.replaceAll('_', ' ');
    return '${k.replaceAll('_', ' ').substring(0, 12)}…';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BillyTheme.gray100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.pie_chart_outline_rounded,
                  size: 18,
                  color: BillyTheme.gray500,
                ),
                SizedBox(width: 8),
                Text(
                  'This run',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
              ],
            ),
            if (bySeverity.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in bySeverity.entries)
                    if (e.value > 0) _StatPill(label: e.key, value: e.value),
                ],
              ),
            ],
            if (byKind.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in byKind.entries)
                    if (e.value > 0)
                      _StatPill(label: _shortKind(e.key), value: e.value),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BillyTheme.gray50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: BillyTheme.gray600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerErrorsCard extends StatelessWidget {
  const _LayerErrorsCard({required this.errors});
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Colors.amber.shade800,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Heads up',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final e in errors.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${e.key}: ${e.value}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: BillyTheme.gray700,
                    height: 1.3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});
  final GoatJobSummary job;

  @override
  Widget build(BuildContext context) {
    final st = job.status;
    Color dot = BillyTheme.gray400;
    if (st == 'succeeded') dot = BillyTheme.emerald600;
    if (st == 'failed' || st == 'cancelled') dot = const Color(0xFFEF4444);
    if (st == 'running' || st == 'queued' || st == 'partial') {
      dot = const Color(0xFF2563EB);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4, right: 10),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job.scope} · $st',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
                if (job.createdAt != null)
                  Text(
                    _fmt(job.createdAt!),
                    style: TextStyle(fontSize: 11, color: BillyTheme.gray500),
                  ),
                if ((job.errorMessage ?? '').isNotEmpty)
                  Text(
                    job.errorMessage!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFB91C1C),
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _TabEmpty extends StatelessWidget {
  const _TabEmpty({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: Column(
          children: [
            Icon(icon, size: 48, color: BillyTheme.gray200),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: BillyTheme.gray500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
