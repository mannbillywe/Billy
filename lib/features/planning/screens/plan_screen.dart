import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';
import '../../../providers/budgets_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/recurring_provider.dart';
import '../widgets/budget_create_sheet.dart';
import '../widgets/recurring_create_sheet.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(budgetsProvider);
    final recurringAsync = ref.watch(recurringSeriesProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(budgetsProvider.notifier).refresh();
        await ref.read(recurringSeriesProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          const Text('Plan', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
          const SizedBox(height: 4),
          const Text('Budgets and recurring bills', style: TextStyle(fontSize: 14, color: BillyTheme.gray500)),
          const SizedBox(height: 24),

          // ─── Budgets ────────────────────────────────────────
          _SectionHeader(
            label: 'Budgets',
            icon: Icons.pie_chart_outline_rounded,
            onAdd: () => _openBudgetSheet(context),
          ),
          const SizedBox(height: 10),
          budgetsAsync.when(
            data: (budgets) => budgets.isEmpty
                ? _EmptyCard(
                    icon: Icons.pie_chart_outline_rounded,
                    title: 'No budgets yet',
                    subtitle: 'Set spending limits to stay on track',
                    actionLabel: 'Create budget',
                    onAction: () => _openBudgetSheet(context),
                  )
                : Column(
                    children: budgets.map((b) => _BudgetCard(budget: b, currency: currency, ref: ref)).toList(),
                  ),
            loading: () => const _ShimmerLoader(),
            error: (e, _) => _ErrorCard(onRetry: () => ref.read(budgetsProvider.notifier).refresh()),
          ),

          const SizedBox(height: 28),

          // ─── Recurring ──────────────────────────────────────
          _SectionHeader(
            label: 'Recurring bills',
            icon: Icons.autorenew_rounded,
            onAdd: () => _openRecurringSheet(context),
          ),
          const SizedBox(height: 10),
          recurringAsync.when(
            data: (series) => series.isEmpty
                ? _EmptyCard(
                    icon: Icons.autorenew_rounded,
                    title: 'No recurring bills',
                    subtitle: 'Track subscriptions and regular payments',
                    actionLabel: 'Add bill',
                    onAction: () => _openRecurringSheet(context),
                  )
                : Column(
                    children: series.map((s) => _RecurringCard(series: s, currency: currency, ref: ref)).toList(),
                  ),
            loading: () => const _ShimmerLoader(),
            error: (e, _) => _ErrorCard(onRetry: () => ref.read(recurringSeriesProvider.notifier).refresh()),
          ),
        ],
      ),
    );
  }

  void _openBudgetSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const BudgetCreateSheet(),
    );
  }

  void _openRecurringSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const RecurringCreateSheet(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.icon, required this.onAdd});
  final String label;
  final IconData icon;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: BillyTheme.emerald600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
        ),
        Material(
          color: BillyTheme.emerald50,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 16, color: BillyTheme.emerald600),
                  SizedBox(width: 4),
                  Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BillyTheme.emerald600)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget, required this.currency, required this.ref});
  final Map<String, dynamic> budget;
  final String? currency;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final name = budget['name'] as String? ?? 'Budget';
    final amount = (budget['amount'] as num?)?.toDouble() ?? 0;
    final cat = budget['categories'] as Map<String, dynamic>?;
    final catName = cat?['name'] as String?;
    final period = budget['period'] as String? ?? 'monthly';
    final isActive = budget['is_active'] as bool? ?? true;
    final id = budget['id'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showBudgetDetail(context, name, amount, period, catName, isActive, id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive ? BillyTheme.emerald50 : BillyTheme.gray100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.pie_chart_outline_rounded, size: 22, color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800), overflow: TextOverflow.ellipsis),
                          ),
                          if (!isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: BillyTheme.gray200, borderRadius: BorderRadius.circular(6)),
                              child: const Text('Paused', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: BillyTheme.gray500)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${AppCurrency.format(amount, currency)} / $period${catName != null ? ' · $catName' : ''}',
                        style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: BillyTheme.gray300),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBudgetDetail(BuildContext context, String name, double amount, String period, String? catName, bool isActive, String? id) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
            const SizedBox(height: 4),
            Text(
              '${AppCurrency.format(amount, currency)} per $period${catName != null ? ' · $catName' : ''}',
              style: const TextStyle(fontSize: 14, color: BillyTheme.gray500),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BillyTheme.gray50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                      color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400, size: 20),
                  const SizedBox(width: 10),
                  Text(isActive ? 'Active' : 'Paused',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isActive ? BillyTheme.emerald600 : BillyTheme.gray500)),
                ],
              ),
            ),
            if (id != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(budgetsProvider.notifier).deleteBudget(id);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete budget'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BillyTheme.red500,
                    side: const BorderSide(color: BillyTheme.red500),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecurringCard extends StatelessWidget {
  const _RecurringCard({required this.series, required this.currency, required this.ref});
  final Map<String, dynamic> series;
  final String? currency;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final title = series['title'] as String? ?? 'Bill';
    final amount = (series['amount'] as num?)?.toDouble() ?? 0;
    final cadence = series['cadence'] as String? ?? '';
    final nextDue = series['next_due'] as String?;
    final isActive = series['is_active'] as bool? ?? true;
    final id = series['id'] as String?;

    String dueLabel = '';
    Color dueColor = BillyTheme.gray500;
    if (nextDue != null) {
      try {
        final dt = DateTime.parse(nextDue);
        final now = DateTime.now();
        final diff = dt.difference(DateTime(now.year, now.month, now.day)).inDays;
        if (diff < 0) {
          dueLabel = 'Overdue';
          dueColor = BillyTheme.red500;
        } else if (diff == 0) {
          dueLabel = 'Due today';
          dueColor = const Color(0xFFD97706);
        } else if (diff <= 3) {
          dueLabel = 'Due in $diff days';
          dueColor = const Color(0xFFD97706);
        } else {
          dueLabel = 'Due ${DateFormat('dd MMM').format(dt)}';
        }
      } catch (_) {
        dueLabel = 'Due: $nextDue';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDetail(context, title, amount, cadence, nextDue, isActive, id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive ? BillyTheme.emerald50 : BillyTheme.gray100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.autorenew_rounded, size: 22, color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${AppCurrency.format(amount, currency)} · $cadence',
                            style: const TextStyle(fontSize: 13, color: BillyTheme.gray500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (dueLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: dueColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(dueLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: dueColor)),
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: BillyTheme.gray300),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, String title, double amount, String cadence, String? nextDue, bool isActive, String? id) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: BillyTheme.gray300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
            const SizedBox(height: 4),
            Text(
              '${AppCurrency.format(amount, currency)} · $cadence',
              style: const TextStyle(fontSize: 14, color: BillyTheme.gray500),
            ),
            if (nextDue != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.event_outlined, size: 18, color: BillyTheme.gray500),
                  const SizedBox(width: 8),
                  Text('Next due: $nextDue', style: const TextStyle(fontSize: 14, color: BillyTheme.gray700)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: BillyTheme.gray50, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                      color: isActive ? BillyTheme.emerald600 : BillyTheme.gray400, size: 20),
                  const SizedBox(width: 10),
                  Text(isActive ? 'Active' : 'Paused',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isActive ? BillyTheme.emerald600 : BillyTheme.gray500)),
                ],
              ),
            ),
            if (id != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(recurringSeriesProvider.notifier).deleteSeries(id);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete recurring bill'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BillyTheme.red500,
                    side: const BorderSide(color: BillyTheme.red500),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.title, required this.subtitle, required this.actionLabel, required this.onAction});
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: BillyTheme.gray100, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 26, color: BillyTheme.gray400),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BillyTheme.gray600)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: BillyTheme.gray400), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: BillyTheme.emerald600,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _ShimmerLoader extends StatelessWidget {
  const _ShimmerLoader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: const Center(child: CircularProgressIndicator(color: BillyTheme.emerald600, strokeWidth: 2)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: BillyTheme.red500),
          const SizedBox(width: 10),
          const Expanded(child: Text('Failed to load', style: TextStyle(fontSize: 13, color: BillyTheme.gray700))),
          TextButton(onPressed: onRetry, child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
