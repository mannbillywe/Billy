import 'dart:math';

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

const _amber500 = Color(0xFFF59E0B);
const _blue500 = Color(0xFF3B82F6);

IconData _categoryIcon(String? name) {
  switch (name?.toLowerCase()) {
    case 'housing':
    case 'rent':
    case 'mortgage':
      return Icons.home_rounded;
    case 'dining':
    case 'food':
    case 'restaurants':
    case 'groceries':
      return Icons.restaurant_rounded;
    case 'travel':
    case 'transport':
    case 'transportation':
      return Icons.flight_rounded;
    case 'shopping':
    case 'retail':
      return Icons.shopping_bag_rounded;
    case 'entertainment':
    case 'fun':
      return Icons.movie_rounded;
    case 'utilities':
    case 'bills':
      return Icons.bolt_rounded;
    case 'health':
    case 'medical':
    case 'healthcare':
      return Icons.favorite_rounded;
    case 'education':
      return Icons.school_rounded;
    case 'subscriptions':
    case 'subscription':
      return Icons.subscriptions_rounded;
    case 'creative':
    case 'design':
      return Icons.palette_rounded;
    case 'insurance':
      return Icons.shield_rounded;
    case 'savings':
    case 'investments':
      return Icons.savings_rounded;
    case 'personal':
    case 'personal care':
      return Icons.spa_rounded;
    default:
      return Icons.category_rounded;
  }
}

Color _categoryColor(String? name) {
  switch (name?.toLowerCase()) {
    case 'housing':
    case 'rent':
    case 'mortgage':
      return const Color(0xFF8B5CF6);
    case 'dining':
    case 'food':
    case 'restaurants':
    case 'groceries':
      return const Color(0xFFF97316);
    case 'travel':
    case 'transport':
    case 'transportation':
      return _blue500;
    case 'shopping':
    case 'retail':
      return const Color(0xFFEC4899);
    case 'entertainment':
    case 'fun':
      return const Color(0xFF8B5CF6);
    case 'utilities':
    case 'bills':
      return _amber500;
    case 'health':
    case 'medical':
    case 'healthcare':
      return const Color(0xFFEF4444);
    case 'subscriptions':
    case 'subscription':
      return BillyTheme.emerald600;
    case 'creative':
    case 'design':
      return _blue500;
    default:
      return BillyTheme.emerald600;
  }
}

String _billTypeBadge(String? categoryName, String? cadence) {
  final cat = categoryName?.toLowerCase() ?? '';
  if (cat.contains('subscri') || cadence == 'monthly' || cadence == 'yearly') {
    return 'SUBSCRIPTION';
  }
  if (cat.contains('creative') || cat.contains('design')) return 'CREATIVE';
  if (cat.contains('utilit') || cat.contains('bill')) return 'UTILITIES';
  if (cat.contains('insurance')) return 'INSURANCE';
  return 'RECURRING';
}

Color _billBadgeColor(String badge) {
  switch (badge) {
    case 'SUBSCRIPTION':
      return BillyTheme.emerald600;
    case 'CREATIVE':
      return _blue500;
    case 'UTILITIES':
      return _amber500;
    case 'INSURANCE':
      return const Color(0xFF8B5CF6);
    default:
      return BillyTheme.gray500;
  }
}

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
          const Text('Plan',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: BillyTheme.gray800)),
          const SizedBox(height: 4),
          const Text('Budgets and recurring bills',
              style: TextStyle(fontSize: 14, color: BillyTheme.gray500)),
          const SizedBox(height: 24),

          // ─── Spending Ring ───────────────────────────────────
          budgetsAsync.when(
            data: (budgets) =>
                _SpendingRingSummary(budgets: budgets, currency: currency),
            loading: () => const SizedBox(
                height: 260,
                child: Center(
                    child: CircularProgressIndicator(
                        color: BillyTheme.emerald600, strokeWidth: 2))),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 28),

          // ─── Category Budgets ────────────────────────────────
          _V5SectionHeader(
            label: 'Category Budgets',
            trailing: GestureDetector(
              onTap: () => _openBudgetSheet(context),
              child: const Text('Edit Limits',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BillyTheme.emerald600)),
            ),
          ),
          const SizedBox(height: 12),
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
                    children: budgets
                        .map((b) =>
                            _V5BudgetCard(budget: b, currency: currency, ref: ref))
                        .toList(),
                  ),
            loading: () => const _ShimmerLoader(),
            error: (e, _) => _ErrorCard(
                onRetry: () => ref.read(budgetsProvider.notifier).refresh()),
          ),

          const SizedBox(height: 28),

          // ─── Upcoming Bills ──────────────────────────────────
          recurringAsync.when(
            data: (series) {
              final pending = series.where((s) {
                final nd = s['next_due'] as String?;
                if (nd == null) return false;
                try {
                  final dt = DateTime.parse(nd);
                  return !dt.isBefore(
                      DateTime.now().subtract(const Duration(days: 1)));
                } catch (_) {
                  return true;
                }
              }).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _V5SectionHeader(
                    label: 'Upcoming Bills',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: BillyTheme.emerald50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('$pending Pending',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: BillyTheme.emerald600)),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _openRecurringSheet(context),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: BillyTheme.emerald50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.add_rounded,
                                size: 18, color: BillyTheme.emerald600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (series.isEmpty)
                    _EmptyCard(
                      icon: Icons.autorenew_rounded,
                      title: 'No recurring bills',
                      subtitle: 'Track subscriptions and regular payments',
                      actionLabel: 'Add bill',
                      onAction: () => _openRecurringSheet(context),
                    )
                  else
                    Column(
                      children: series
                          .map((s) => _V5BillCard(
                              series: s, currency: currency, ref: ref))
                          .toList(),
                    ),
                ],
              );
            },
            loading: () => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _V5SectionHeader(
                  label: 'Upcoming Bills',
                  trailing: const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                const _ShimmerLoader(),
              ],
            ),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _V5SectionHeader(
                  label: 'Upcoming Bills',
                  trailing: const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                _ErrorCard(
                    onRetry: () =>
                        ref.read(recurringSeriesProvider.notifier).refresh()),
              ],
            ),
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const BudgetCreateSheet(),
    );
  }

  void _openRecurringSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const RecurringCreateSheet(),
    );
  }
}

// ─── Spending Ring Summary ─────────────────────────────────────────

class _SpendingRingSummary extends StatelessWidget {
  const _SpendingRingSummary({required this.budgets, required this.currency});
  final List<Map<String, dynamic>> budgets;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    double totalBudget = 0;
    double totalSpent = 0;
    for (final b in budgets) {
      totalBudget += (b['amount'] as num?)?.toDouble() ?? 0;
      totalSpent += (b['spent'] as num?)?.toDouble() ?? 0;
    }

    final pct = totalBudget > 0 ? (totalSpent / totalBudget).clamp(0.0, 1.5) : 0.0;
    final remaining = (totalBudget - totalSpent).clamp(0.0, double.infinity);
    final pctInt = (pct * 100).round();
    final monthName = DateFormat('MMMM').format(DateTime.now());

    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(200, 200),
                painter: _RingPainter(
                  progress: pct.clamp(0.0, 1.0),
                  trackColor: BillyTheme.gray200,
                  progressColor: pct > 1.0
                      ? BillyTheme.red500
                      : pct > 0.8
                          ? _amber500
                          : BillyTheme.emerald600,
                  strokeWidth: 12,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('SPENT THIS MONTH',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: BillyTheme.gray400)),
                  const SizedBox(height: 6),
                  Text(AppCurrency.format(totalSpent, currency),
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: BillyTheme.gray800)),
                  const SizedBox(height: 4),
                  Text('$pctInt% of Budget',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: BillyTheme.emerald600)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'You have ${AppCurrency.format(remaining, currency)} remaining until the end of $monthName.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: BillyTheme.gray500,
                height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -pi / 2;
      final sweepAngle = 2 * pi * progress;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.progressColor != progressColor;
}

// ─── V5 Section Header ─────────────────────────────────────────────

class _V5SectionHeader extends StatelessWidget {
  const _V5SectionHeader({required this.label, required this.trailing});
  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.gray800)),
        ),
        trailing,
      ],
    );
  }
}

// ─── V5 Budget Card ────────────────────────────────────────────────

class _V5BudgetCard extends StatelessWidget {
  const _V5BudgetCard(
      {required this.budget, required this.currency, required this.ref});
  final Map<String, dynamic> budget;
  final String? currency;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final name = budget['name'] as String? ?? 'Budget';
    final amount = (budget['amount'] as num?)?.toDouble() ?? 0;
    final spent = (budget['spent'] as num?)?.toDouble() ?? 0;
    final cat = budget['categories'] as Map<String, dynamic>?;
    final catName = cat?['name'] as String?;
    final period = budget['period'] as String? ?? 'monthly';
    final isActive = budget['is_active'] as bool? ?? true;
    final id = budget['id'] as String?;

    final pct = amount > 0 ? (spent / amount).clamp(0.0, 1.5) : 0.0;
    final remaining = (amount - spent).clamp(0.0, double.infinity);
    final pctInt = (pct * 100).round();

    final icon = _categoryIcon(catName ?? name);
    final color = _categoryColor(catName ?? name);

    Color barColor;
    String statusLabel;
    Color statusColor;
    if (pct > 1.0) {
      barColor = BillyTheme.red500;
      statusLabel = 'OVER BUDGET';
      statusColor = BillyTheme.red500;
    } else if (pct > 0.8) {
      barColor = _amber500;
      statusLabel = '$pctInt%';
      statusColor = _amber500;
    } else if (pct >= 1.0) {
      barColor = BillyTheme.emerald600;
      statusLabel = 'Fully Allocated';
      statusColor = BillyTheme.emerald600;
    } else if (spent == 0) {
      barColor = BillyTheme.emerald600;
      statusLabel = 'UNDER BUDGET';
      statusColor = BillyTheme.emerald600;
    } else {
      barColor = BillyTheme.emerald600;
      statusLabel = '${AppCurrency.format(remaining, currency)} left';
      statusColor = BillyTheme.emerald600;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showBudgetDetail(
              context, name, amount, spent, period, catName, isActive, id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 24, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: BillyTheme.gray800),
                                    overflow: TextOverflow.ellipsis),
                                if (catName != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                      '${catName[0].toUpperCase()}${catName.substring(1)} · ${period[0].toUpperCase()}${period.substring(1)}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: BillyTheme.gray500)),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(AppCurrency.format(spent, currency),
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: BillyTheme.gray800)),
                              Text(
                                  'OF ${AppCurrency.format(amount, currency)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: BillyTheme.gray400)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 8,
                          child: LinearProgressIndicator(
                            value: pct.clamp(0.0, 1.0),
                            backgroundColor: BillyTheme.gray100,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(statusLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor)),
                          ),
                          if (!isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: BillyTheme.gray200,
                                  borderRadius: BorderRadius.circular(6)),
                              child: const Text('Paused',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: BillyTheme.gray500)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBudgetDetail(BuildContext context, String name, double amount,
      double spent, String period, String? catName, bool isActive, String? id) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: BillyTheme.gray300,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(name,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800)),
            const SizedBox(height: 4),
            Text(
              '${AppCurrency.format(amount, currency)} per $period${catName != null ? ' · $catName' : ''}',
              style:
                  const TextStyle(fontSize: 14, color: BillyTheme.gray500),
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
                  Icon(
                      isActive
                          ? Icons.check_circle_rounded
                          : Icons.pause_circle_rounded,
                      color: isActive
                          ? BillyTheme.emerald600
                          : BillyTheme.gray400,
                      size: 20),
                  const SizedBox(width: 10),
                  Text(isActive ? 'Active' : 'Paused',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? BillyTheme.emerald600
                              : BillyTheme.gray500)),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
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

// ─── V5 Bill Card ──────────────────────────────────────────────────

class _V5BillCard extends StatelessWidget {
  const _V5BillCard(
      {required this.series, required this.currency, required this.ref});
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
    final cat = series['categories'] as Map<String, dynamic>?;
    final catName = cat?['name'] as String?;

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
        } else {
          dueLabel = 'Due in $diff days';
          dueColor = diff <= 3 ? const Color(0xFFD97706) : BillyTheme.gray500;
        }
      } catch (_) {
        dueLabel = 'Due: $nextDue';
      }
    }

    final badge = _billTypeBadge(catName, cadence);
    final badgeColor = _billBadgeColor(badge);
    final icon = _categoryIcon(catName ?? title);
    final color = _categoryColor(catName ?? title);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showDetail(
              context, title, amount, cadence, nextDue, isActive, id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 22, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: BillyTheme.gray800)),
                      const SizedBox(height: 3),
                      if (dueLabel.isNotEmpty)
                        Text(dueLabel,
                            style: TextStyle(
                                fontSize: 12, color: dueColor))
                      else
                        Text(cadence,
                            style: const TextStyle(
                                fontSize: 12, color: BillyTheme.gray500)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(AppCurrency.format(amount, currency),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: BillyTheme.gray800)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(badge,
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: badgeColor)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, String title, double amount,
      String cadence, String? nextDue, bool isActive, String? id) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: BillyTheme.gray300,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: BillyTheme.gray800)),
            const SizedBox(height: 4),
            Text(
              '${AppCurrency.format(amount, currency)} · $cadence',
              style:
                  const TextStyle(fontSize: 14, color: BillyTheme.gray500),
            ),
            if (nextDue != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.event_outlined,
                      size: 18, color: BillyTheme.gray500),
                  const SizedBox(width: 8),
                  Text('Next due: $nextDue',
                      style: const TextStyle(
                          fontSize: 14, color: BillyTheme.gray700)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: BillyTheme.gray50,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(
                      isActive
                          ? Icons.check_circle_rounded
                          : Icons.pause_circle_rounded,
                      color: isActive
                          ? BillyTheme.emerald600
                          : BillyTheme.gray400,
                      size: 20),
                  const SizedBox(width: 10),
                  Text(isActive ? 'Active' : 'Paused',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? BillyTheme.emerald600
                              : BillyTheme.gray500)),
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
                    await ref
                        .read(recurringSeriesProvider.notifier)
                        .deleteSeries(id);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete recurring bill'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BillyTheme.red500,
                    side: const BorderSide(color: BillyTheme.red500),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
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

// ─── Shared widgets ────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.actionLabel,
      required this.onAction});
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: BillyTheme.gray100,
                borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 26, color: BillyTheme.gray400),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BillyTheme.gray600)),
          const SizedBox(height: 4),
          Text(subtitle,
              style:
                  const TextStyle(fontSize: 13, color: BillyTheme.gray400),
              textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: BillyTheme.emerald600,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: const Center(
          child: CircularProgressIndicator(
              color: BillyTheme.emerald600, strokeWidth: 2)),
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
          const Expanded(
              child: Text('Failed to load',
                  style:
                      TextStyle(fontSize: 13, color: BillyTheme.gray700))),
          TextButton(
              onPressed: onRetry,
              child: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
