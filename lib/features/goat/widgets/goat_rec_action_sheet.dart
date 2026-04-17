import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/billy_theme.dart';
import '../models/goat_models.dart';
import '../providers/goat_setup_providers.dart';

/// Bottom-sheet "actions" menu for a single recommendation: dismiss, snooze,
/// mark as done. Kept intentionally small — this is the polite, reversible
/// path that doesn't crowd the main list with controls.
Future<void> showGoatRecActionSheet(
  BuildContext context,
  GoatRecommendation rec, {
  String? displayTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => GoatRecActionSheet(rec: rec, displayTitle: displayTitle),
  );
}

class GoatRecActionSheet extends ConsumerWidget {
  final GoatRecommendation rec;
  final String? displayTitle;

  const GoatRecActionSheet({
    super.key,
    required this.rec,
    this.displayTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = displayTitle ?? rec.titleFor();
    final actions = ref.read(goatRecommendationActionsProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: BillyTheme.gray200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: BillyTheme.gray800,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                'Pick what to do. You can always run a new analysis later.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: BillyTheme.gray500,
                  height: 1.4,
                ),
              ),
            ),
            _ActionTile(
              icon: Icons.check_circle_outline_rounded,
              color: BillyTheme.emerald600,
              title: 'Mark as done',
              subtitle: 'I\'ve acted on this.',
              onTap: () async {
                Navigator.of(context).pop();
                await _run(context, () => actions.resolve(rec.id),
                    successLabel: 'Marked as done');
              },
            ),
            _ActionTile(
              icon: Icons.snooze_rounded,
              color: const Color(0xFFB45309),
              title: 'Snooze',
              subtitle: 'Hide for a few days.',
              onTap: () async {
                final picked = await _pickSnooze(context);
                if (picked == null) return;
                if (!context.mounted) return;
                Navigator.of(context).pop();
                await _run(
                  context,
                  () => actions.snooze(rec.id, picked.duration),
                  successLabel: 'Snoozed for ${picked.label}',
                );
              },
            ),
            _ActionTile(
              icon: Icons.close_rounded,
              color: BillyTheme.gray500,
              title: 'Dismiss',
              subtitle: 'Not useful to me right now.',
              onTap: () async {
                Navigator.of(context).pop();
                await _run(context, () => actions.dismiss(rec.id),
                    successLabel: 'Dismissed');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() op, {
    required String successLabel,
  }) async {
    try {
      await op();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successLabel),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      // GoatModeController already set an error banner via rollback.
    }
  }

  Future<_SnoozeChoice?> _pickSnooze(BuildContext context) {
    return showModalBottomSheet<_SnoozeChoice>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _SnoozePicker(),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: BillyTheme.gray50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BillyTheme.gray100),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: BillyTheme.gray800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: BillyTheme.gray500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: BillyTheme.gray400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SnoozeChoice {
  final String label;
  final Duration duration;
  const _SnoozeChoice(this.label, this.duration);
}

class _SnoozePicker extends StatelessWidget {
  const _SnoozePicker();

  @override
  Widget build(BuildContext context) {
    const choices = <_SnoozeChoice>[
      _SnoozeChoice('1 day', Duration(days: 1)),
      _SnoozeChoice('3 days', Duration(days: 3)),
      _SnoozeChoice('1 week', Duration(days: 7)),
      _SnoozeChoice('2 weeks', Duration(days: 14)),
      _SnoozeChoice('1 month', Duration(days: 30)),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: BillyTheme.gray200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Hide this for…',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: BillyTheme.gray800,
                ),
              ),
            ),
            for (final c in choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(c),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: BillyTheme.gray50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BillyTheme.gray100),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.label,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: BillyTheme.gray800,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              size: 18, color: BillyTheme.gray400),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
