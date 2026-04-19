import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';
import '../providers/goat_inputs_providers.dart';
import '../providers/goat_providers.dart';
import '../services/goat_mode_service.dart';
import '../widgets/goat_mode_tab_pages.dart';
import 'goat_setup_screen.dart';

/// GOAT Mode dashboard: read-only views of backend-written snapshots. Organized
/// into tabs so each concern (overview, actions, trends, safety, run log) has
/// its own page instead of one endless scroll.
class GoatModeScreen extends ConsumerStatefulWidget {
  const GoatModeScreen({super.key});

  @override
  ConsumerState<GoatModeScreen> createState() => _GoatModeScreenState();
}

class _GoatModeScreenState extends ConsumerState<GoatModeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    ref.invalidate(goatLatestSnapshotProvider);
    ref.invalidate(goatPreviousSnapshotProvider);
    ref.invalidate(goatOpenRecommendationsProvider);
    ref.invalidate(goatUserInputsProvider);
    ref.invalidate(goatRecentJobsProvider);
    await ref.read(goatLatestSnapshotProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final snapAsync = ref.watch(goatLatestSnapshotProvider);
    final prevAsync = ref.watch(goatPreviousSnapshotProvider);
    final recsAsync = ref.watch(goatOpenRecommendationsProvider);
    final setupDone = ref.watch(goatSetupCompletedProvider);

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      body: snapAsync.when(
        loading: () => RefreshIndicator(
          color: BillyTheme.emerald600,
          onRefresh: _onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              Center(child: _GoatLoading()),
            ],
          ),
        ),
        error: (e, _) => RefreshIndicator(
          color: BillyTheme.emerald600,
          onRefresh: _onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 80),
              _GoatError(error: e.toString()),
            ],
          ),
        ),
        data: (snapshot) {
          if (snapshot == null || !snapshot.hasMetrics) {
            return RefreshIndicator(
              color: BillyTheme.emerald600,
              onRefresh: _onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _header(context, setupDone: setupDone, showTabs: false),
                  _GoatEmpty(onSetup: () => _openSetup(context)),
                ],
              ),
            );
          }

          final previous = prevAsync.valueOrNull;
          final recs = recsAsync.valueOrNull ?? const <GoatRecommendation>[];
          final priorityAnomalyEntities = <String>{
            for (final r in recs)
              if (r.kind == 'anomaly_review' && (r.entityId ?? '').isNotEmpty)
                r.entityId!,
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, setupDone: setupDone, showTabs: true),
              Material(
                color: BillyTheme.scaffoldBg,
                child: TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: BillyTheme.emerald700,
                  unselectedLabelColor: BillyTheme.gray500,
                  indicatorColor: BillyTheme.emerald600,
                  labelStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Actions'),
                    Tab(text: 'Trends'),
                    Tab(text: 'Safety'),
                    Tab(text: 'Run log'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    GoatOverviewTab(
                      snapshot: snapshot,
                      previous: previous,
                      onRefresh: _onRefresh,
                    ),
                    GoatActionsTab(
                      snapshot: snapshot,
                      recommendations: recs,
                      onDismiss: (rec) => _handleDismiss(context, rec),
                      onRefresh: _onRefresh,
                    ),
                    GoatTrendsTab(
                      snapshot: snapshot,
                      onRefresh: _onRefresh,
                    ),
                    GoatSafetyTab(
                      snapshot: snapshot,
                      priorityAnomalyEntities: priorityAnomalyEntities,
                      onRefresh: _onRefresh,
                    ),
                    GoatRunLogTab(
                      snapshot: snapshot,
                      onRefresh: _onRefresh,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required bool setupDone,
    required bool showTabs,
  }) {
    return Material(
      color: BillyTheme.scaffoldBg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BillyTheme.gray100),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new,
                        size: 14, color: BillyTheme.gray800),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Expanded(
                  child: Text(
                    'GOAT Mode',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: BillyTheme.gray800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Setup',
                  icon: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BillyTheme.gray100),
                    ),
                    child: const Icon(Icons.tune_rounded,
                        size: 18, color: BillyTheme.gray700),
                  ),
                  onPressed: () => _openSetup(context),
                ),
              ],
            ),
            if (!setupDone)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: _SetupBanner(onTap: () => _openSetup(context)),
              ),
            if (!showTabs) const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _openSetup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GoatSetupScreen()),
    );
  }

  Future<void> _handleDismiss(
    BuildContext context,
    GoatRecommendation rec,
  ) async {
    try {
      await GoatModeService.updateRecommendationStatus(
        rec.id,
        status: 'dismissed',
      );
      ref.invalidate(goatOpenRecommendationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dismissed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't dismiss right now"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ─── setup banner (shown until user saves a profile) ───────────────────────

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: BillyTheme.emerald100),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: BillyTheme.emerald700, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Finish your GOAT setup',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: BillyTheme.gray800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Add income, goals & obligations so the next analysis is rich.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: BillyTheme.gray500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: BillyTheme.emerald700),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── loading / empty / error ───────────────────────────────────────────────

class _GoatLoading extends StatelessWidget {
  const _GoatLoading();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _shimmerBox(180, radius: 28),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _shimmerBox(96)),
              const SizedBox(width: 12),
              Expanded(child: _shimmerBox(96)),
              const SizedBox(width: 12),
              Expanded(child: _shimmerBox(96)),
            ],
          ),
          const SizedBox(height: 20),
          _shimmerBox(120),
          const SizedBox(height: 14),
          _shimmerBox(120),
        ],
      ),
    );
  }

  Widget _shimmerBox(double h, {double radius = 20}) => Container(
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: BillyTheme.gray100),
        ),
      );
}

class _GoatEmpty extends StatelessWidget {
  const _GoatEmpty({required this.onSetup});
  final VoidCallback onSetup;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              BillyTheme.emerald50,
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: BillyTheme.emerald100),
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: BillyTheme.emerald100),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 36, color: BillyTheme.emerald600),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your first analysis is on the way',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'GOAT Mode analyses are prepared in the background. As soon as your '
              'snapshot lands, this screen will light up with insights, forecasts, '
              'watchouts, and next steps — no action needed from you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: BillyTheme.gray500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: onSetup,
              style: FilledButton.styleFrom(
                backgroundColor: BillyTheme.emerald600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 14),
              ),
              child: const Text('Set up GOAT Mode',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(
                foregroundColor: BillyTheme.emerald700,
              ),
              child: const Text('Back to Billy',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoatError extends StatelessWidget {
  const _GoatError({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BillyTheme.gray100),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF4444), size: 34),
            const SizedBox(height: 12),
            const Text(
              "We couldn't load your analysis",
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: BillyTheme.gray800),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(fontSize: 12, color: BillyTheme.gray500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
