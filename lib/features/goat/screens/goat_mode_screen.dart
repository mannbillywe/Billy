import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';
import '../models/goat_setup_models.dart';
import '../providers/goat_mode_providers.dart';
import '../providers/goat_setup_providers.dart';
import '../widgets/goat_ai_summary_card.dart';
import '../widgets/goat_empty_state.dart';
import '../widgets/goat_error_banner.dart';
import '../widgets/goat_hero_card.dart';
import '../widgets/goat_missing_input_card.dart';
import '../widgets/goat_readiness_strip.dart';
import '../widgets/goat_rec_action_sheet.dart';
import '../widgets/goat_recommendation_card.dart';
import '../widgets/goat_scope_detail.dart';
import '../widgets/goat_scope_switcher.dart';
import '../widgets/goat_setup_summary_card.dart';
import '../widgets/goat_skeleton.dart';
import '../widgets/goat_goal_sheet.dart';
import '../widgets/goat_obligation_sheet.dart';
import '../widgets/goat_user_inputs_sheet.dart';
import 'goat_setup_screen.dart';

/// First live Goat Mode screen.
///
/// Layout intent (top → bottom):
///   1. Hero — 3-second answer (status + narrative + refresh)
///   2. Readiness strip — how "deep" the analysis is right now
///   3. AI narrative card (optional, only if validated & present)
///   4. Top recommendations (collapsed by default)
///   5. Missing-input unlocks (optional)
///   6. Scope switcher + scope detail
class GoatModeScreen extends ConsumerWidget {
  const GoatModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitled = ref.watch(goatModeEntitlementProvider);
    // Only subscribe to the Goat controller when the user is entitled. This
    // avoids issuing empty RLS-scoped queries against the Goat tables for
    // users who will never see the live surface anyway — the rollout-card
    // path is fully self-contained and has no Supabase reads.
    final async = entitled
        ? ref.watch(goatModeControllerProvider)
        : const AsyncValue<GoatModeState>.loading();

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _AppBar(
              onBack: () => Navigator.of(context).maybePop(),
              onOpenSetup: entitled ? () => _openSetup(context) : null,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: _body(context, ref, entitled, async),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _openSetup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GoatSetupScreen()),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    bool entitled,
    AsyncValue<GoatModeState> async,
  ) {
    if (!entitled) {
      return const _Scrollable(
        key: ValueKey('not-enabled'),
        child: GoatNotEnabledState(),
      );
    }

    return async.when(
      loading: () => const _Scrollable(
        key: ValueKey('loading'),
        child: GoatInitialSkeleton(),
      ),
      error: (e, _) => _Scrollable(
        key: const ValueKey('error'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: GoatErrorBanner(
            message: 'We couldn\'t load GOAT Mode. Pull down to try again.',
            onRetry: () =>
                ref.read(goatModeControllerProvider.notifier).reloadFromDb(),
          ),
        ),
      ),
      data: (state) => _GoatLiveSurface(
        key: const ValueKey('live'),
        state: state,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// App bar
// ──────────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onOpenSetup;
  const _AppBar({required this.onBack, this.onOpenSetup});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
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
            splashRadius: 24,
          ),
          const Spacer(),
          if (onOpenSetup != null)
            Semantics(
              button: true,
              label: 'Open Goat Mode setup',
              child: InkWell(
                onTap: onOpenSetup,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: BillyTheme.gray100),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.tune_rounded,
                          size: 14, color: BillyTheme.gray800),
                      SizedBox(width: 6),
                      Text(
                        'Setup',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: BillyTheme.gray800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Live surface
// ──────────────────────────────────────────────────────────────────────────

class _GoatLiveSurface extends ConsumerWidget {
  final GoatModeState state;
  const _GoatLiveSurface({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(goatModeControllerProvider.notifier);
    final scope = ref.watch(goatSelectedScopeProvider);
    final setup =
        ref.watch(goatUserInputsControllerProvider).valueOrNull ??
            GoatUserInputs.empty;
    final goalsCount =
        ref.watch(goatGoalsControllerProvider).valueOrNull?.length ?? 0;
    final obligationsCount =
        ref.watch(goatObligationsControllerProvider).valueOrNull?.length ?? 0;

    // Before the very first run, show the first-run state — never a blank
    // dashboard. Any previous snapshot (even partial/stale) beats empty.
    if (state.isFirstLoad) {
      return _Scrollable(
        onRefresh: () => ctrl.reloadFromDb(),
        child: GoatFirstRunState(
          isRefreshing: state.isRefreshing,
          onRunFirstAnalysis: () => ctrl.refresh(),
        ),
      );
    }

    final snap = state.latestSnapshot;
    final aiView = snap?.ai;
    final openRecs = state.recommendations;

    return RefreshIndicator(
      onRefresh: () => ctrl.reloadFromDb(),
      color: BillyTheme.emerald600,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        children: [
          // ── Hero ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: GoatHeroCard(
              snapshot: snap,
              job: state.latestJob,
              isRefreshing: state.isRefreshing,
              lastRefreshedAt: state.lastRefreshedAt,
              onRefresh: () => ctrl.refresh(),
            ),
          ),
          const SizedBox(height: 14),

          // ── Error / timeout banner ───────────────────────────────────────
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: GoatErrorBanner(
                message: state.errorMessage!,
                onRetry: state.pollingTimedOut || !state.isRefreshing
                    ? () => ctrl.refresh()
                    : null,
                onDismiss: () => ctrl.dismissError(),
              ),
            ),

          // ── Readiness ─────────────────────────────────────────────────
          if (snap != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: GoatReadinessStrip(snapshot: snap),
            ),

          // Partial snapshot soft-indicator (doesn't scare the user).
          if (snap != null && snap.isPartial)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: const _PartialStripe(),
            ),

          // ── Setup summary / improve analysis CTA ───────────────────────
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GoatSetupSummaryCard(
              inputs: setup,
              goalsCount: goalsCount,
              obligationsCount: obligationsCount,
              onOpen: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GoatSetupScreen(),
                ),
              ),
            ),
          ),

          // ── AI narrative (only if validated & has content) ────────────
          if (aiView != null &&
              aiView.validated &&
              (aiView.narrativeSummary?.isNotEmpty == true ||
                  aiView.pillars.isNotEmpty)) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GoatAISummaryCard(ai: aiView),
            ),
          ],

          // ── Top recommendations ────────────────────────────────────────
          if (openRecs.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _SectionHeader(
                title: 'Top of mind',
                caption: 'Tap any card to see why it\'s here.',
              ),
            ),
            for (int i = 0; i < openRecs.take(3).length; i++) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: GoatRecommendationCard(
                  rec: openRecs[i],
                  aiTitleByFp: aiView?.phrasingTitleByFingerprint,
                  aiBodyByFp: aiView?.phrasingBodyByFingerprint,
                  aiWhyByFp: aiView?.phrasingWhyByFingerprint,
                  onActions: () => showGoatRecActionSheet(
                    context,
                    openRecs[i],
                    displayTitle: openRecs[i].titleFor(
                      aiTitleByFingerprint:
                          aiView?.phrasingTitleByFingerprint,
                    ),
                  ),
                ),
              ),
            ],
            if (openRecs.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: _MoreRecsLink(
                  count: openRecs.length - 3,
                  onTap: () => _showAllRecs(context, openRecs, aiView),
                ),
              ),
          ],

          // ── Missing inputs (capped) ───────────────────────────────────
          if (snap != null && snap.missingInputs.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _SectionHeader(
                title: 'Unlock more',
                caption: 'Small inputs, sharper insights.',
              ),
            ),
            for (final input in snap.missingInputs.take(2)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: GoatMissingInputCard(
                  input: input,
                  aiTitle: _aiMissingTitle(aiView, input.key),
                  aiBody: _aiMissingBody(aiView, input.key),
                  onAction: () => _showMissingHandoff(context, input),
                ),
              ),
            ],
          ],

          // ── Scope switcher + detail ────────────────────────────────────
          if (snap != null) ...[
            const SizedBox(height: 22),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: _SectionHeader(
                title: 'Explore by pillar',
                caption: 'Switch focus without losing context.',
              ),
            ),
            GoatScopeSwitcher(
              selected: scope,
              onSelected: (s) =>
                  ref.read(goatSelectedScopeProvider.notifier).state = s,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(
                    sizeFactor: anim,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
                child: GoatScopeDetailCard(
                  key: ValueKey('scope-${scope.name}'),
                  scope: scope,
                  snapshot: snap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _aiMissingTitle(GoatAIView? ai, String key) {
    if (ai == null) return null;
    for (final p in ai.missingPrompts) {
      if (p.inputKey == key) return p.title;
    }
    return null;
  }

  static String? _aiMissingBody(GoatAIView? ai, String key) {
    if (ai == null) return null;
    for (final p in ai.missingPrompts) {
      if (p.inputKey == key) return p.body;
    }
    return null;
  }

  void _showAllRecs(
    BuildContext context,
    List<GoatRecommendation> recs,
    GoatAIView? ai,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (_, ctrl) {
            return SafeArea(
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: BillyTheme.gray200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 6, 20, 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'All recommendations',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: BillyTheme.gray800,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: ctrl,
                      padding:
                          const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: recs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (sheetCtx, i) => GoatRecommendationCard(
                        rec: recs[i],
                        aiTitleByFp: ai?.phrasingTitleByFingerprint,
                        aiBodyByFp: ai?.phrasingBodyByFingerprint,
                        aiWhyByFp: ai?.phrasingWhyByFingerprint,
                        onActions: () => showGoatRecActionSheet(
                          sheetCtx,
                          recs[i],
                          displayTitle: recs[i].titleFor(
                            aiTitleByFingerprint:
                                ai?.phrasingTitleByFingerprint,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Route a missing-input prompt into the correct form.
  ///
  /// Missing input keys are defined by the deterministic layer in
  /// `backend/app/goat/input_load/coverage.py`. We route the common ones
  /// directly into the matching form; anything unknown falls back to the
  /// full "Improve this analysis" sheet, which covers every `goat_user_inputs`
  /// column.
  void _showMissingHandoff(BuildContext context, GoatMissingInput input) {
    final key = input.key;
    if (key == 'goals' || key.startsWith('goal_')) {
      showGoatGoalSheet(context);
      return;
    }
    if (key == 'obligations' || key.startsWith('obligation_')) {
      showGoatObligationSheet(context);
      return;
    }
    showGoatUserInputsSheet(context, focusedKey: key);
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Small shared pieces
// ──────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String caption;
  const _SectionHeader({required this.title, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: BillyTheme.gray800,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: const TextStyle(
            fontSize: 12,
            color: BillyTheme.gray500,
          ),
        ),
      ],
    );
  }
}

class _PartialStripe extends StatelessWidget {
  const _PartialStripe();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: const [
          Icon(Icons.pie_chart_outline_rounded,
              size: 14, color: Color(0xFFB45309)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This is a partial read — some pillars are still warming up.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF78350F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreRecsLink extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _MoreRecsLink({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(
            children: [
              Text(
                'See $count more ${count == 1 ? "recommendation" : "recommendations"}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.emerald600,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded,
                  color: BillyTheme.emerald600, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// A refreshable scroll container used for non-live states (empty / error /
/// not-entitled) so pull-to-refresh always works and the transition into
/// live content is seamless.
class _Scrollable extends StatelessWidget {
  final Widget child;
  final Future<void> Function()? onRefresh;
  const _Scrollable({super.key, required this.child, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final inner = ListView(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      children: [child, const SizedBox(height: 40)],
    );
    if (onRefresh == null) return inner;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      color: BillyTheme.emerald600,
      child: inner,
    );
  }
}
