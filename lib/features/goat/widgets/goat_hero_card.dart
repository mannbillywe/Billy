import 'package:flutter/material.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';
import 'goat_status_chip.dart';

/// Top-of-screen hero. Summary-first: one sentence, one big state, one action.
///
/// UX intent:
///   • the hero is the user's 3-second answer ("am I okay right now?")
///   • the refresh action is always reachable, never hidden behind menus
///   • while refreshing we don't change the layout — only the chip softly
///     pulses, so the eye stays with the content underneath
class GoatHeroCard extends StatelessWidget {
  final GoatSnapshot? snapshot;
  final GoatJob? job;
  final bool isRefreshing;
  final DateTime? lastRefreshedAt;
  final VoidCallback onRefresh;

  const GoatHeroCard({
    super.key,
    required this.snapshot,
    required this.job,
    required this.isRefreshing,
    required this.lastRefreshedAt,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final narrative = _narrativeLine();
    final chipStatus = job?.status ?? GoatJobStatus.unknown;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF10B981), Color(0xFF34D399)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withValues(alpha: 0.25),
            blurRadius: 22,
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'GOAT Mode',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              _RefreshButton(
                onTap: onRefresh,
                isRefreshing: isRefreshing,
              ),
            ],
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Text(
              narrative,
              key: ValueKey(narrative),
              style: const TextStyle(
                fontSize: 22,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              GoatStatusChip(
                status: chipStatus,
                isRefreshing: isRefreshing,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _freshnessLabel(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _narrativeLine() {
    if (snapshot == null) {
      return 'Let\'s take a first look at your money.';
    }
    final ai = snapshot!.ai?.narrativeSummary;
    if (ai != null && ai.isNotEmpty) return ai;
    final bullets = snapshot!.narrativeBullets;
    if (bullets.isNotEmpty) return bullets.first;
    switch (snapshot!.readiness) {
      case GoatReadiness.l3:
        return 'Everything\'s in view. Here\'s what stands out.';
      case GoatReadiness.l2:
        return 'Your picture is getting clearer.';
      case GoatReadiness.l1:
        return 'We have enough to get started.';
    }
  }

  String _freshnessLabel() {
    if (isRefreshing && lastRefreshedAt == null) return 'Running your first analysis…';
    if (isRefreshing) return 'Refreshing — showing your last snapshot';
    if (lastRefreshedAt == null) return 'No snapshot yet';
    final diff = DateTime.now().difference(lastRefreshedAt!);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }
}

class _RefreshButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isRefreshing;
  const _RefreshButton({required this.onTap, required this.isRefreshing});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isRefreshing ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: isRefreshing ? 0.14 : 0.22),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRefreshing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              else
                const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                isRefreshing ? 'Refreshing' : 'Refresh',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Narrative-only fallback when we have nothing yet — used by the empty state
/// to echo the same typographic weight so the transition into live mode
/// feels continuous rather than abrupt.
class GoatHeroShellOnly extends StatelessWidget {
  final String title;
  final String subtitle;

  const GoatHeroShellOnly({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: BillyTheme.gray800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: BillyTheme.gray500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
