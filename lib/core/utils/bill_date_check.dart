import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/billy_theme.dart';

/// How many days old a bill date must be before we prompt the user.
const _staleDaysThreshold = 7;

/// Result of the bill-date dialog.
enum BillDateChoice {
  /// Keep the original bill date — analytics slot it into the bill's month.
  useBillDate,

  /// Override to today — analytics slot it into the current month.
  useToday,
}

/// Returns `true` when [billDate] is more than [_staleDaysThreshold] days
/// before today, meaning it belongs to an earlier analytics period.
bool isBillDateStale(DateTime billDate) {
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day)
      .difference(DateTime(billDate.year, billDate.month, billDate.day))
      .inDays;
  return diff > _staleDaysThreshold;
}

/// Shows a bottom-sheet dialog asking the user whether to keep the old bill
/// date or record the expense under today's date.
///
/// Returns [BillDateChoice.useBillDate] or [BillDateChoice.useToday].
/// If the user dismisses without choosing, defaults to [BillDateChoice.useBillDate].
Future<BillDateChoice> showBillDateChoiceDialog(
  BuildContext context, {
  required DateTime billDate,
}) async {
  final formatted = DateFormat('dd MMM yyyy').format(billDate);
  final daysAgo = DateTime.now().difference(billDate).inDays;
  final todayFormatted = DateFormat('dd MMM yyyy').format(DateTime.now());

  final result = await showModalBottomSheet<BillDateChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _BillDateChoiceSheet(
      formatted: formatted,
      daysAgo: daysAgo,
      todayFormatted: todayFormatted,
      billDate: billDate,
    ),
  );

  return result ?? BillDateChoice.useBillDate;
}

class _BillDateChoiceSheet extends StatelessWidget {
  const _BillDateChoiceSheet({
    required this.formatted,
    required this.daysAgo,
    required this.todayFormatted,
    required this.billDate,
  });

  final String formatted;
  final int daysAgo;
  final String todayFormatted;
  final DateTime billDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: BillyTheme.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.schedule_rounded,
                size: 28,
                color: Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Old bill date detected',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: BillyTheme.gray800,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              'This bill is from $formatted ($daysAgo days ago). '
              'Should we count it under the bill date or record it as of today?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: BillyTheme.gray500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            // Option 1: Use bill date
            _ChoiceTile(
              icon: Icons.receipt_long_rounded,
              iconColor: const Color(0xFF8B5CF6),
              iconBg: const Color(0xFFEDE9FE),
              title: 'Use bill date',
              subtitle: 'Record under $formatted — it will appear in that month\'s analytics',
              onTap: () => Navigator.of(context).pop(BillDateChoice.useBillDate),
            ),
            const SizedBox(height: 10),

            // Option 2: Use today
            _ChoiceTile(
              icon: Icons.today_rounded,
              iconColor: BillyTheme.emerald600,
              iconBg: BillyTheme.emerald50,
              title: 'Use today\'s date',
              subtitle: 'Record under $todayFormatted — it will appear in this month\'s analytics',
              onTap: () => Navigator.of(context).pop(BillDateChoice.useToday),
            ),
            const SizedBox(height: 16),

            Text(
              'Tip: Your analytics filter (1W / 1M / 3M) groups by this date',
              style: TextStyle(
                fontSize: 11,
                color: BillyTheme.gray400,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor, iconBg;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BillyTheme.gray100),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
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
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: BillyTheme.gray300),
            ],
          ),
        ),
      ),
    );
  }
}
