import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';
import '../providers/goat_providers.dart';
import 'goat_humanize.dart';
import 'goat_sections.dart';

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
          GoatMetricHighlights(snapshot: snapshot),
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
              title: 'Nothing urgent here',
              body:
                  'When the backend surfaces new recommendations or missing inputs, '
                  'they will show up in this tab.',
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
                Icon(Icons.lock_open_rounded,
                    size: 18, color: BillyTheme.emerald700),
                const SizedBox(width: 8),
                const Text(
                  'More analysis available',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Add the missing inputs from the card above and the next run can unlock:',
              style: TextStyle(
                fontSize: 12,
                color: BillyTheme.gray500,
                height: 1.35,
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
              title: 'No forecasts in this snapshot',
              body:
                  'Forecasts need enough history. After more transactions accrue, '
                  're-run the Docker backend and check again.',
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
              title: 'No watchouts right now',
              body:
                  'Risk scores and anomalies look calm for this run. '
                  'Keep logging expenses so the next analysis stays accurate.',
            ),
        ],
      ),
    );
  }

  bool _hasWatchouts(GoatSnapshot s, Set<String> priorityAnomalyEntities) {
    final hasRisk = s.risks.any((r) =>
        r.severity == GoatSeverity.warn ||
        r.severity == GoatSeverity.critical);
    if (hasRisk) return true;
    final anomalies = dedupeAnomalies(s.anomalies
        .where((a) => a.severity.rank >= GoatSeverity.watch.rank)
        .toList(growable: false));
    for (final a in anomalies) {
      final id = a.entityId;
      if (id != null &&
          id.isNotEmpty &&
          priorityAnomalyEntities.contains(id)) {
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
          if (snapshot.recommendationCountsBySeverity.isNotEmpty)
            _RecSeverityCard(counts: snapshot.recommendationCountsBySeverity),
          if (snapshot.recommendationCountsByKind.isNotEmpty)
            _RecKindCard(counts: snapshot.recommendationCountsByKind),
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
                    const Text(
                      'Recent backend runs',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: BillyTheme.gray800,
                      ),
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

class _RecSeverityCard extends StatelessWidget {
  const _RecSeverityCard({required this.counts});
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recommendations by severity',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in counts.entries)
                  if (e.value > 0)
                    Text(
                      '${e.key}: ${e.value}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: BillyTheme.gray600,
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecKindCard extends StatelessWidget {
  const _RecKindCard({required this.counts});
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recommendations by kind',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in counts.entries)
                  if (e.value > 0)
                    Text(
                      '${e.key}: ${e.value}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: BillyTheme.gray600,
                      ),
                    ),
              ],
            ),
          ],
        ),
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
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                const Text(
                  'Layer notes (partial run)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final e in errors.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${e.key}: ${e.value}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: BillyTheme.gray700,
                    height: 1.35,
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
                    style: TextStyle(
                      fontSize: 11,
                      color: BillyTheme.gray500,
                    ),
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
            Icon(icon, size: 40, color: BillyTheme.gray300),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: BillyTheme.gray500,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
