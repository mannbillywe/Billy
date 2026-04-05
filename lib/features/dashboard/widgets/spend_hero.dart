import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/formatting/app_currency.dart';
import '../../../core/theme/billy_theme.dart';

/// Hero card: **weekSpend** is document-only (receipts & invoices), same basis as [weeklyData].
class SpendHero extends StatelessWidget {
  const SpendHero({
    super.key,
    required this.weekSpend,
    required this.currencyCode,
    this.weeklyData = const [],
    this.lastWeekSpend = 0,
    this.friendPendingCollect = 0,
    this.friendPendingPay = 0,
    this.friendAddedThisWeekCollect = 0,
    this.friendAddedThisWeekPay = 0,
  });

  final double weekSpend;
  final String? currencyCode;
  final List<double> weeklyData;
  final double lastWeekSpend;
  /// Outstanding pending lend/borrow (viewer perspective).
  final double friendPendingCollect;
  final double friendPendingPay;
  /// Pending entries **created** Mon–today this calendar week.
  final double friendAddedThisWeekCollect;
  final double friendAddedThisWeekPay;

  @override
  Widget build(BuildContext context) {
    final formatted = AppCurrency.format(weekSpend, currencyCode);
    final changePct = lastWeekSpend > 0 ? (((weekSpend - lastWeekSpend) / lastWeekSpend) * 100).round().abs() : null;
    final isUp = weekSpend >= lastWeekSpend;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BillyTheme.emerald50, BillyTheme.emerald100.withValues(alpha: 0.5)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BillyTheme.emerald100),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This week',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: BillyTheme.emerald700.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatted,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF064E3B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Receipts & invoices · Mon–today',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: BillyTheme.emerald700.withValues(alpha: 0.55),
                ),
              ),
              if (friendPendingCollect > 0 || friendPendingPay > 0) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BillyTheme.emerald100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lend / borrow (pending)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: BillyTheme.emerald700.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _FriendMiniStat(
                              label: 'To collect',
                              amount: friendPendingCollect,
                              currencyCode: currencyCode,
                              positive: true,
                            ),
                          ),
                          Expanded(
                            child: _FriendMiniStat(
                              label: 'To pay',
                              amount: friendPendingPay,
                              currencyCode: currencyCode,
                              positive: false,
                            ),
                          ),
                        ],
                      ),
                      if (friendAddedThisWeekCollect > 0 || friendAddedThisWeekPay > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Added this week: +${AppCurrency.format(friendAddedThisWeekCollect, currencyCode)} collect · '
                          '+${AppCurrency.format(friendAddedThisWeekPay, currencyCode)} owe',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: BillyTheme.gray600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (changePct != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${isUp ? 'Up' : 'Down'} $changePct% vs last week',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isUp ? BillyTheme.red400 : BillyTheme.emerald600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  _LegendDot(
                    color: BillyTheme.emerald500,
                    label: 'This calendar week (Mon–Sun)',
                  ),
                ],
              ),
            ],
          ),
          if (weeklyData.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 60,
              child: Opacity(
                opacity: 0.5,
                child: _MiniAreaChart(data: weeklyData),
              ),
            ),
        ],
      ),
    );
  }
}

class _FriendMiniStat extends StatelessWidget {
  const _FriendMiniStat({
    required this.label,
    required this.amount,
    this.currencyCode,
    required this.positive,
  });
  final String label;
  final double amount;
  final String? currencyCode;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: BillyTheme.gray500)),
        Text(
          AppCurrency.format(amount, currencyCode),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: positive ? BillyTheme.emerald700 : BillyTheme.red500,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: BillyTheme.emerald700.withValues(alpha: 0.7))),
      ],
    );
  }
}

class _MiniAreaChart extends StatelessWidget {
  const _MiniAreaChart({required this.data});
  final List<double> data;

  @override
  Widget build(BuildContext context) {
    final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final maxY = data.reduce((a, b) => a > b ? a : b) * 1.3;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: BillyTheme.emerald500,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [BillyTheme.emerald500.withValues(alpha: 0.3), BillyTheme.emerald500.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
