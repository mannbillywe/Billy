import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/goat_theme.dart';
import '../../../providers/goat_cash_providers.dart';
import '../../../providers/goat_goals_providers.dart';
import '../../../providers/profile_provider.dart';
import '../finance/cashflow_engine.dart';
import '../goals/goal_engine.dart';
import '../goals/goal_suggestion_engine.dart';
import '../goals/goals_repository.dart';
import '../goals/goat_goal_sheets.dart';
import '../widgets/goat_premium_card.dart';
import 'emergency_fund_screen.dart';
import 'goal_detail_screen.dart';
import 'goal_suggestions_screen.dart';

int _compareGoals(Map<String, dynamic> a, Map<String, dynamic> b) {
  final pa = (a['priority'] as num?)?.toInt() ?? 3;
  final pb = (b['priority'] as num?)?.toInt() ?? 3;
  final c = pa.compareTo(pb);
  if (c != 0) return c;
  final ca = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  final cb = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  return ca.compareTo(cb);
}

Map<String, dynamic>? _firstEmergencyFund(Iterable<Map<String, dynamic>> active) {
  for (final g in active) {
    if (g['goal_type'] == 'emergency_fund') return g;
  }
  return null;
}

class GoatGoalsScreen extends ConsumerStatefulWidget {
  const GoatGoalsScreen({super.key});

  @override
  ConsumerState<GoatGoalsScreen> createState() => _GoatGoalsScreenState();
}

class _GoatGoalsScreenState extends ConsumerState<GoatGoalsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await GoalSuggestionEngine.syncRecommendations();
    ref.invalidate(goatGoalsProvider);
    ref.invalidate(goatGoalsSummaryProvider);
    ref.invalidate(goatGoalRecommendationsProvider);
    ref.invalidate(goatGoalsForecastInputProvider);
    ref.invalidate(goatForecastProvider);
  }

  void _openDetail(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GoalDetailScreen(goalId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(profileProvider).valueOrNull?['preferred_currency'] as String? ?? 'INR';
    final goalsAsync = ref.watch(goatGoalsProvider);
    final summaryAsync = ref.watch(goatGoalsSummaryProvider);
    final recAsync = ref.watch(goatGoalRecommendationsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Goals',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: GoatTokens.textPrimary,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'All suggestions',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const GoalSuggestionsScreen()),
                  );
                },
                icon: const Icon(Icons.lightbulb_outline, color: GoatTokens.gold),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Text(
            'Sinking funds and milestones. Contribution math and pace are deterministic; any AI coach must use these numbers as ground truth.',
            style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: GoatTokens.gold,
          unselectedLabelColor: GoatTokens.textMuted,
          indicatorColor: GoatTokens.gold,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Paused'),
            Tab(text: 'Done'),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            color: GoatTokens.gold,
            onRefresh: _refresh,
            child: goalsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: GoatTokens.gold, strokeWidth: 2)),
              error: (e, stackTrace) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load goals. Apply the GOAT goals migration, then pull to refresh.\n\n$e',
                      style: TextStyle(color: GoatTokens.textMuted, height: 1.4),
                    ),
                  ),
                ],
              ),
              data: (allGoals) {
                final active = allGoals.where((g) => (g['status'] as String?) == 'active').toList()..sort(_compareGoals);
                final emergency = _firstEmergencyFund(active);
                final emergencyId = emergency?['id'] as String?;
                final pool = active.where((g) => g['id'] != emergencyId).toList()..sort(_compareGoals);
                final topThree = pool.take(3).toList();
                final restActive = pool.length > 3 ? pool.sublist(3) : <Map<String, dynamic>>[];

                final paused = allGoals.where((g) => (g['status'] as String?) == 'paused').toList()..sort(_compareGoals);
                final done = allGoals.where((g) => (g['status'] as String?) == 'completed').toList()..sort(_compareGoals);

                return TabBarView(
                  controller: _tabs,
                  children: [
                    _GoalsTabBody(
                      currency: currency,
                      showDashboard: true,
                      emergencyGoal: emergency,
                      priorityGoals: topThree,
                      otherGoals: restActive,
                      summaryAsync: summaryAsync,
                      recAsync: recAsync,
                      onOpenDetail: _openDetail,
                      onCreate: () => showCreateGoalSheet(context, ref),
                    ),
                    _GoalsTabBody(
                      currency: currency,
                      showDashboard: false,
                      emergencyGoal: null,
                      priorityGoals: const [],
                      otherGoals: paused,
                      summaryAsync: summaryAsync,
                      recAsync: recAsync,
                      onOpenDetail: _openDetail,
                      onCreate: () => showCreateGoalSheet(context, ref),
                      hideSummary: true,
                    ),
                    _GoalsTabBody(
                      currency: currency,
                      showDashboard: false,
                      emergencyGoal: null,
                      priorityGoals: const [],
                      otherGoals: done,
                      summaryAsync: summaryAsync,
                      recAsync: recAsync,
                      onOpenDetail: _openDetail,
                      onCreate: () => showCreateGoalSheet(context, ref),
                      hideSummary: true,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _GoalsTabBody extends ConsumerWidget {
  const _GoalsTabBody({
    required this.currency,
    required this.showDashboard,
    required this.emergencyGoal,
    required this.priorityGoals,
    required this.otherGoals,
    required this.summaryAsync,
    required this.recAsync,
    required this.onOpenDetail,
    required this.onCreate,
    this.hideSummary = false,
  });

  final String currency;
  final bool showDashboard;
  final Map<String, dynamic>? emergencyGoal;
  final List<Map<String, dynamic>> priorityGoals;
  final List<Map<String, dynamic>> otherGoals;
  final AsyncValue<GoalsSummary> summaryAsync;
  final AsyncValue<List<Map<String, dynamic>>> recAsync;
  final void Function(String id) onOpenDetail;
  final VoidCallback onCreate;
  final bool hideSummary;

  bool get _hasGoals => emergencyGoal != null || priorityGoals.isNotEmpty || otherGoals.isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (!hideSummary) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: summaryAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (err, st) => const SizedBox.shrink(),
                data: (s) => GoatPremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Overview', style: TextStyle(color: GoatTokens.textMuted, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(
                        AppCurrency.format(CashflowMoneyLine.fromMinor(s.totalSavedMinor), currency),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: GoatTokens.gold,
                            ),
                      ),
                      Text('total saved across active goals', style: TextStyle(color: GoatTokens.textMuted, fontSize: 11)),
                      const SizedBox(height: 12),
                      Text(
                        'Monthly pace needed (sum): ${AppCurrency.format(CashflowMoneyLine.fromMinor(s.totalMonthlyRequiredMinor), currency)}',
                        style: TextStyle(color: GoatTokens.textPrimary, fontSize: 13),
                      ),
                      if (s.softReserveMonthlyMinor > 0)
                        Text(
                          'Soft forecast reserve (informational): ${AppCurrency.format(CashflowMoneyLine.fromMinor(s.softReserveMonthlyMinor), currency)}/mo — does not change safe-to-spend.',
                          style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.3),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'On track ${s.onTrack} · Behind ${s.behind} · Ahead ${s.ahead} · Active ${s.activeCount}',
                        style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showDashboard)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _EmergencyFundHomeCard(
                  currency: currency,
                  goal: emergencyGoal,
                  onOpenDetail: onOpenDetail,
                  onOpenGuide: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EmergencyFundScreen(
                          existingGoalId: emergencyGoal?['id'] as String?,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: recAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (err, st) => const SizedBox.shrink(),
                data: (recs) {
                  if (recs.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Suggestions', style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700)),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => const GoalSuggestionsScreen()),
                              );
                            },
                            child: const Text('See all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: recs.length.clamp(0, 12),
                          separatorBuilder: (context, index) => const SizedBox(width: 10),
                          itemBuilder: (ctx, i) {
                            final r = recs[i];
                            final id = r['id'] as String?;
                            return SizedBox(
                              width: 220,
                              child: GoatPremiumCard(
                                accentBorder: false,
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['title'] as String? ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        TextButton(
                                          onPressed: id == null
                                              ? null
                                              : () async {
                                                  try {
                                                    await GoalsRepository.setRecommendationStatus(id, 'dismissed');
                                                    ref.invalidate(goatGoalRecommendationsProvider);
                                                  } catch (_) {}
                                                },
                                          child: const Text('Dismiss'),
                                        ),
                                        FilledButton(
                                          onPressed: id == null
                                              ? null
                                              : () async {
                                                  try {
                                                    await GoalsRepository.acceptRecommendationAsGoal(id);
                                                    ref.invalidate(goatGoalRecommendationsProvider);
                                                    ref.invalidate(goatGoalsProvider);
                                                    ref.invalidate(goatGoalsSummaryProvider);
                                                    ref.invalidate(goatGoalsForecastInputProvider);
                                                    ref.invalidate(goatForecastProvider);
                                                  } catch (e) {
                                                    if (ctx.mounted) {
                                                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                                                    }
                                                  }
                                                },
                                          child: const Text('Create'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: summaryAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (err, st) => const SizedBox.shrink(),
                data: (s) {
                  final coach = StringBuffer();
                  if (s.behind > 0) {
                    coach.write(
                      'You have ${s.behind} goal(s) behind schedule. A fixed monthly rule or a one-off contribution updates saved balances; required monthly pace is recomputed from those facts only. ',
                    );
                  }
                  if (s.activeCount == 0) {
                    coach.write(
                      'Create your first sinking fund or emergency buffer. Hard-reserve goals reduce safe-to-spend by the deterministic monthly amount shown on each goal.',
                    );
                  } else if (s.behind == 0) {
                    coach.write(
                      'Pace looks steady. Yearly and quarterly recurring items feed suggestion cards so you can fund obligations before they land.',
                    );
                  }
                  return GoatPremiumCard(
                    accentBorder: false,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome_outlined, color: GoatTokens.gold.withValues(alpha: 0.85), size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            coach.toString().trim(),
                            style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (showDashboard && priorityGoals.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Focus',
                  style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.3),
                ),
              ),
            ),
          if (showDashboard && priorityGoals.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final g = priorityGoals[i];
                    final id = g['id'] as String?;
                    if (id == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _GoalRowCard(
                        goal: g,
                        currency: currency,
                        onTap: () => onOpenDetail(id),
                      ),
                    );
                  },
                  childCount: priorityGoals.length,
                ),
              ),
            ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hideSummary
                      ? 'Goals'
                      : showDashboard
                          ? (otherGoals.isEmpty ? 'All goals' : 'More goals')
                          : 'Your goals',
                  style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 18, color: GoatTokens.gold),
                  label: const Text('New', style: TextStyle(color: GoatTokens.gold)),
                ),
              ],
            ),
          ),
        ),
        if (!_hasGoals && hideSummary)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Nothing here yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.4),
                ),
              ),
            ),
          )
        else if (!_hasGoals && !hideSummary)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No goals yet. Tap New or use a suggestion card to add a sinking fund.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoatTokens.textMuted, height: 1.4),
                ),
              ),
            ),
          )
        else ...[
          if (showDashboard && priorityGoals.isEmpty && otherGoals.isEmpty && emergencyGoal != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Add sinking funds for bills and purchases alongside your emergency buffer.',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.35),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final g = otherGoals[i];
                  final id = g['id'] as String?;
                  if (id == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GoalRowCard(
                      goal: g,
                      currency: currency,
                      onTap: () => onOpenDetail(id),
                    ),
                  );
                },
                childCount: otherGoals.length,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmergencyFundHomeCard extends StatelessWidget {
  const _EmergencyFundHomeCard({
    required this.currency,
    required this.goal,
    required this.onOpenDetail,
    required this.onOpenGuide,
  });

  final String currency;
  final Map<String, dynamic>? goal;
  final void Function(String id) onOpenDetail;
  final VoidCallback onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    if (g == null) {
      return GoatPremiumCard(
        accentBorder: true,
        onTap: onOpenGuide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emergency fund',
              style: TextStyle(color: GoatTokens.gold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              'A liquid buffer before irregular hits. Tap for milestones and to create your first fund.',
              style: TextStyle(color: GoatTokens.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      );
    }

    final id = g['id'] as String?;
    if (id == null) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: GoalsRepository.fetchRulesForGoal(id),
      builder: (context, snap) {
        final rules = snap.data ?? const <Map<String, dynamic>>[];
        final pace = GoalEngine.computePace(g, rules: rules);
        final target = (g['target_amount'] as num?)?.toDouble() ?? 0;
        final current = (g['current_amount'] as num?)?.toDouble() ?? 0;
        const firstThird = 1.0 / 3.0;
        final toFirstThird = target > 0 ? (target / 3 - current).clamp(0.0, double.infinity) : 0.0;

        return GoatPremiumCard(
          accentBorder: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Emergency fund',
                style: TextStyle(color: GoatTokens.gold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.7),
              ),
              const SizedBox(height: 8),
              Text(
                g['title'] as String? ?? 'Emergency fund',
                style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: pace.progressFraction.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: GoatTokens.surfaceElevated,
                  color: GoatTokens.gold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${AppCurrency.format(current, currency)} of ${AppCurrency.format(target, currency)}',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
              ),
              if (pace.progressFraction < firstThird && target > 0)
                Text(
                  '${AppCurrency.format(toFirstThird, currency)} to first third of target',
                  style: TextStyle(color: GoatTokens.textMuted, fontSize: 11, height: 1.3),
                ),
              const SizedBox(height: 8),
              Text(
                '${AppCurrency.format(CashflowMoneyLine.fromMinor(pace.requiredMonthlyMinor), currency)}/mo required pace',
                style: TextStyle(color: GoatTokens.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onOpenGuide(),
                      child: const Text('Guide'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => onOpenDetail(id),
                      child: const Text('Details'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GoalRowCard extends StatelessWidget {
  const _GoalRowCard({required this.goal, required this.currency, required this.onTap});

  final Map<String, dynamic> goal;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: GoalsRepository.fetchRulesForGoal(goal['id'] as String),
      builder: (context, snap) {
        final rules = snap.data ?? const <Map<String, dynamic>>[];
        final pace = GoalEngine.computePace(goal, rules: rules);
        final target = (goal['target_amount'] as num?)?.toDouble() ?? 0;
        final current = (goal['current_amount'] as num?)?.toDouble() ?? 0;
        final isEmergency = goal['goal_type'] == 'emergency_fund';

        return GoatPremiumCard(
          onTap: onTap,
          accentBorder: isEmergency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isEmergency)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Emergency fund',
                    style: TextStyle(color: GoatTokens.gold, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal['title'] as String? ?? 'Goal',
                      style: TextStyle(color: GoatTokens.textPrimary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    pace.paceStatus == 'behind'
                        ? 'Behind'
                        : pace.paceStatus == 'ahead'
                            ? 'Ahead'
                            : pace.paceStatus == 'on_track'
                                ? 'On track'
                                : '—',
                    style: TextStyle(
                      color: pace.paceStatus == 'behind' ? const Color(0xFFFCA5A5) : GoatTokens.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pace.progressFraction.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: GoatTokens.surfaceElevated,
                  color: GoatTokens.gold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${AppCurrency.format(current, currency)} / ${AppCurrency.format(target, currency)}',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 12),
              ),
              Text(
                '${AppCurrency.format(CashflowMoneyLine.fromMinor(pace.requiredMonthlyMinor), currency)}/mo suggested',
                style: TextStyle(color: GoatTokens.textMuted, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}
