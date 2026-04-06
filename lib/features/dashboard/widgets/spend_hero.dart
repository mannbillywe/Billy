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
    this.weekSubtitle = 'Receipts & invoices · by upload date (Mon–today)',
    this.weeklyData = const [],
    this.lendCollectWeek = const [],
    this.lendPayWeek = const [],
    this.lastWeekSpend = 0,
    this.friendPendingCollect = 0,
    this.friendPendingPay = 0,
    this.friendAddedThisWeekCollect = 0,
    this.friendAddedThisWeekPay = 0,
  });

  final double weekSpend;
  final String? currencyCode;
  /// Explains how this week is bucketed (upload vs bill date).
  final String weekSubtitle;
  final List<double> weeklyData;
  /// Mon–Sun pending IOUs created that day (collect / lent side), viewer perspective.
  final List<double> lendCollectWeek;
  /// Mon–Sun pending IOUs created that day (pay / borrowed side).
  final List<double> lendPayWeek;
  final double lastWeekSpend;
  /// Outstanding pending lend/borrow (viewer perspective).
  final double friendPendingCollect;
  final double friendPendingPay;
  /// Pending entries **created** Mon–today this calendar week.
  final double friendAddedThisWeekCollect;
  final double friendAddedThisWeekPay;

  static bool _hasLendWeekChart(List<double> c, List<double> p) {
    if (c.length != 7 || p.length != 7) return false;
    for (var i = 0; i < 7; i++) {
      if (c[i] > 0 || p[i] > 0) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final formatted = AppCurrency.format(weekSpend, currencyCode);
    final changePct = lastWeekSpend > 0 ? (((weekSpend - lastWeekSpend) / lastWeekSpend) * 100).round().abs() : null;
    final isUp = weekSpend >= lastWeekSpend;
    final showDocChart = weeklyData.length == 7;
    final showLendChart = _hasLendWeekChart(lendCollectWeek, lendPayWeek);
    final double overlayH = (showDocChart ? 56.0 : 0.0) +
        (showDocChart && showLendChart ? 6.0 : 0.0) +
        (showLendChart ? 46.0 : 0.0);

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
                weekSubtitle,
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
                    label: 'Spend · Mon–Sun',
                  ),
                  if (showLendChart) ...[
                    const SizedBox(width: 14),
                    _LegendDot(color: BillyTheme.emerald600, label: 'Collect'),
                    const SizedBox(width: 10),
                    _LegendDot(color: BillyTheme.red400, label: 'Owe'),
                  ],
                ],
              ),
              if (overlayH > 0) SizedBox(height: overlayH + 4),
            ],
          ),
          if (overlayH > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: overlayH,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDocChart)
                    SizedBox(
                      height: 56,
                      child: Opacity(
                        opacity: 0.5,
                        child: _MiniAreaChart(data: weeklyData),
                      ),
                    ),
                  if (showDocChart && showLendChart) const SizedBox(height: 6),
                  if (showLendChart)
                    SizedBox(
                      height: 44,
                      child: _LendBorrowWeekBarChart(
                        collect: lendCollectWeek,
                        pay: lendPayWeek,
                      ),
                    ),
                ],
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

/// Grouped bars: per day, collect (green) + owe (red) for pending entries created that day.
class _LendBorrowWeekBarChart extends StatelessWidget {
  const _LendBorrowWeekBarChart({required this.collect, required this.pay});
  final List<double> collect;
  final List<double> pay;

  @override
  Widget build(BuildContext context) {
    var maxY = 1.0;
    for (var i = 0; i < 7; i++) {
      final sum = collect[i] + pay[i];
      if (sum > maxY) maxY = sum;
    }
    maxY *= 1.15;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        minY: 0,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        barGroups: List.generate(7, (i) {
          return BarChartGroupData(
            x: i,
            groupVertically: false,
            barsSpace: 2,
            barRods: [
              BarChartRodData(
                toY: collect[i],
                color: BillyTheme.emerald600.withValues(alpha: 0.75),
                width: 5,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
              BarChartRodData(
                toY: pay[i],
                color: BillyTheme.red400.withValues(alpha: 0.75),
                width: 5,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ],
          );
        }),
      ),
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
