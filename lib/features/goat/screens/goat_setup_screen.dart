import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_setup_models.dart';
import '../providers/goat_mode_providers.dart';
import '../providers/goat_setup_providers.dart';
import '../widgets/goat_empty_state.dart';
import '../widgets/goat_goal_sheet.dart';
import '../widgets/goat_obligation_sheet.dart';
import '../widgets/goat_user_inputs_sheet.dart';

/// Full screen "Your setup" — hosts the three write-path entry points:
///   • Edit your Goat inputs (monthly income, preferences, targets)
///   • Add / edit goals
///   • Add / edit obligations
///
/// This deliberately lives off the main Goat Mode screen (via
/// [GoatModeScreen]'s "Your setup" card) so the main screen stays
/// summary-first and the setup loop feels contextual, not intrusive.
class GoatSetupScreen extends ConsumerWidget {
  const GoatSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitled = ref.watch(goatModeEntitlementProvider);

    // Belt-and-suspenders: the RLS migration added in Phase 8 rejects setup
    // writes for non-entitled users, so any form submit would fail anyway.
    // We still short-circuit here so users who somehow land on this screen
    // (deep link, stale route) see the same calm rollout card as the main
    // Goat Mode entry point instead of an empty form they can't save.
    if (!entitled) {
      return Scaffold(
        backgroundColor: BillyTheme.scaffoldBg,
        appBar: AppBar(
          title: const Text(
            'Your setup',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
              letterSpacing: -0.2,
            ),
          ),
          backgroundColor: BillyTheme.scaffoldBg,
          elevation: 0,
          iconTheme: const IconThemeData(color: BillyTheme.gray800),
        ),
        body: const SafeArea(child: GoatNotEnabledState()),
      );
    }

    final inputs = ref.watch(goatUserInputsControllerProvider);
    final goals = ref.watch(goatGoalsControllerProvider);
    final obligations = ref.watch(goatObligationsControllerProvider);
    final goat = ref.watch(goatModeControllerProvider);

    return Scaffold(
      backgroundColor: BillyTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text(
          'Your setup',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: BillyTheme.gray800,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: BillyTheme.scaffoldBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: BillyTheme.gray800),
      ),
      body: RefreshIndicator(
        color: BillyTheme.emerald600,
        onRefresh: () async {
          ref.invalidate(goatUserInputsControllerProvider);
          await Future.wait([
            ref.read(goatGoalsControllerProvider.notifier).refreshFromDb(),
            ref
                .read(goatObligationsControllerProvider.notifier)
                .refreshFromDb(),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          children: [
            _UserInputsTile(
              value: inputs.valueOrNull ?? GoatUserInputs.empty,
              onTap: () async {
                await showGoatUserInputsSheet(
                  context,
                  onSaved: () => _postSetupSave(ref),
                );
              },
            ),
            const SizedBox(height: 22),
            _SectionHeader(
              title: 'Goals',
              count: goals.valueOrNull?.length ?? 0,
              onAdd: () async {
                await showGoatGoalSheet(
                  context,
                  onSaved: () => _postSetupSave(ref),
                );
              },
            ),
            const SizedBox(height: 8),
            if (goals.isLoading && goals.valueOrNull == null)
              const _LoadingCard()
            else if ((goals.valueOrNull ?? const []).isEmpty)
              _EmptyCard(
                icon: Icons.flag_outlined,
                title: 'No goals yet',
                body: 'Add your first goal so Goat Mode can pace it for you.',
                ctaLabel: 'Add a goal',
                onTap: () async {
                  await showGoatGoalSheet(
                    context,
                    onSaved: () => _postSetupSave(ref),
                  );
                },
              )
            else
              for (final g in goals.valueOrNull!) ...[
                _GoalTile(
                  goal: g,
                  onTap: () async {
                    await showGoatGoalSheet(
                      context,
                      initial: g,
                      onSaved: () => _postSetupSave(ref),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 18),
            _SectionHeader(
              title: 'Obligations',
              count: obligations.valueOrNull?.length ?? 0,
              onAdd: () async {
                await showGoatObligationSheet(
                  context,
                  onSaved: () => _postSetupSave(ref),
                );
              },
            ),
            const SizedBox(height: 8),
            if (obligations.isLoading && obligations.valueOrNull == null)
              const _LoadingCard()
            else if ((obligations.valueOrNull ?? const []).isEmpty)
              _EmptyCard(
                icon: Icons.payments_outlined,
                title: 'No obligations yet',
                body:
                    'Add EMIs, rent or insurance so Goat Mode can forecast runway.',
                ctaLabel: 'Add an obligation',
                onTap: () async {
                  await showGoatObligationSheet(
                    context,
                    onSaved: () => _postSetupSave(ref),
                  );
                },
              )
            else
              for (final o in obligations.valueOrNull!) ...[
                _ObligationTile(
                  obligation: o,
                  onTap: () async {
                    await showGoatObligationSheet(
                      context,
                      initial: o,
                      onSaved: () => _postSetupSave(ref),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 22),
            _RerunBanner(
              lastRefreshedAt: goat.valueOrNull?.lastRefreshedAt,
              isRefreshing: goat.valueOrNull?.isRefreshing ?? false,
              onRerun: () =>
                  ref.read(goatModeControllerProvider.notifier).refresh(),
            ),
          ],
        ),
      ),
    );
  }

  /// Called after any setup save. We don't auto-trigger a new Goat run —
  /// compute has a cost and new snapshots are created by explicit user
  /// intent. The sticky "Refresh analysis" banner on this screen and the
  /// home hero CTA make that action obvious. Provider list caches are
  /// updated optimistically inside the controllers themselves; this hook is
  /// reserved for future telemetry / toast coordination.
  static void _postSetupSave(WidgetRef ref) {}
}

// ──────────────────────────────────────────────────────────────────────────
// section components
// ──────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onAdd;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
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
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            count == 0 ? '' : '· $count',
            style: const TextStyle(
              fontSize: 13,
              color: BillyTheme.gray400,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded,
              size: 16, color: BillyTheme.emerald600),
          label: const Text(
            'Add',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: BillyTheme.emerald600,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: BillyTheme.emerald600,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 32),
          ),
        ),
      ],
    );
  }
}

class _UserInputsTile extends StatelessWidget {
  final GoatUserInputs value;
  final VoidCallback onTap;

  const _UserInputsTile({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filled = value.filledCoreCount;
    final total = value.coreTotal;
    final pct = total == 0 ? 0.0 : (filled / total).clamp(0.0, 1.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [BillyTheme.emerald50, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BillyTheme.emerald100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BillyTheme.emerald100),
                    ),
                    child: const Icon(Icons.tune_rounded,
                        size: 18, color: BillyTheme.emerald600),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Your inputs',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: BillyTheme.gray800,
                      ),
                    ),
                  ),
                  Text(
                    '$filled of $total',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BillyTheme.emerald700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: BillyTheme.emerald600),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor: Colors.white,
                    valueColor:
                        const AlwaysStoppedAnimation(BillyTheme.emerald600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value.hasAnyValue
                    ? 'Sharp enough — add more to unlock deeper insight.'
                    : 'Takes under a minute. Every field is optional.',
                style: const TextStyle(
                  fontSize: 12,
                  color: BillyTheme.gray600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  final GoatGoal goal;
  final VoidCallback onTap;
  const _GoalTile({required this.goal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = goal.progress;
    final muted = goal.status != GoatGoalStatus.active;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: Opacity(
            opacity: muted ? 0.7 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: BillyTheme.emerald50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.flag_outlined,
                          size: 16, color: BillyTheme.emerald600),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goal.title.isEmpty
                                ? goal.type.label
                                : goal.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: BillyTheme.gray800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${goal.type.label} · ${goal.status.label}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: BillyTheme.gray500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${(p * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: BillyTheme.emerald700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: p,
                    minHeight: 4,
                    backgroundColor: BillyTheme.gray100,
                    valueColor: const AlwaysStoppedAnimation(
                        BillyTheme.emerald500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ObligationTile extends StatelessWidget {
  final GoatObligation obligation;
  final VoidCallback onTap;
  const _ObligationTile({required this.obligation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final o = obligation;
    final muted = o.status != GoatObligationStatus.active;
    final monthly = o.monthlyDue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: Opacity(
            opacity: muted ? 0.7 : 1.0,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.payments_outlined,
                      size: 16, color: Color(0xFFB45309)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.lenderName?.trim().isNotEmpty == true
                            ? o.lenderName!
                            : o.type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: BillyTheme.gray800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${o.type.label} · ${o.cadence.label}${o.dueDay != null ? " · day ${o.dueDay}" : ""}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: BillyTheme.gray500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (monthly != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '\u20B9${_fmt(monthly)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: BillyTheme.gray800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(num v) =>
      v == v.toInt() ? v.toInt().toString() : v.toStringAsFixed(0);
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String ctaLabel;
  final VoidCallback onTap;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: BillyTheme.gray400, size: 20),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: BillyTheme.gray800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              color: BillyTheme.gray500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(ctaLabel),
              style: FilledButton.styleFrom(
                backgroundColor: BillyTheme.emerald600,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: BillyTheme.emerald600,
          ),
        ),
      ),
    );
  }
}

class _RerunBanner extends StatelessWidget {
  final DateTime? lastRefreshedAt;
  final bool isRefreshing;
  final VoidCallback onRerun;

  const _RerunBanner({
    required this.lastRefreshedAt,
    required this.isRefreshing,
    required this.onRerun,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: BillyTheme.emerald50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 16, color: BillyTheme.emerald600),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Refresh analysis when ready',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'New setup? Rerun Goat Mode to see the difference.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: BillyTheme.gray500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: isRefreshing ? null : onRerun,
            style: FilledButton.styleFrom(
              backgroundColor: BillyTheme.emerald600,
              disabledBackgroundColor: BillyTheme.emerald100,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(isRefreshing ? 'Refreshing…' : 'Refresh'),
          ),
        ],
      ),
    );
  }
}
