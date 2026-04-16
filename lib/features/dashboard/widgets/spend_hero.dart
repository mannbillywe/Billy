import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/formatting/app_currency.dart';

/// Hero card: **weekSpend** is document-only (receipts & invoices), same basis as [weeklyData].
class SpendHero extends StatelessWidget {
  const SpendHero({
    super.key,
    required this.weekSpend,
    required this.currencyCode,
    this.weekSubtitle = 'Receipts & invoices · last 7 days by save date',
    this.documentCountThisWeek,
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
  final String weekSubtitle;
  final int? documentCountThisWeek;
  final List<double> weeklyData;
  final List<double> lendCollectWeek;
  final List<double> lendPayWeek;
  final double lastWeekSpend;
  final double friendPendingCollect;
  final double friendPendingPay;
  final double friendAddedThisWeekCollect;
  final double friendAddedThisWeekPay;

  @override
  Widget build(BuildContext context) {
    final formatted = AppCurrency.format(weekSpend, currencyCode);
    final changePct = lastWeekSpend > 0
        ? (((weekSpend - lastWeekSpend) / lastWeekSpend) * 100).round().abs()
        : null;
    final isUp = weekSpend >= lastWeekSpend;
    final showDocChart = weeklyData.length == 7;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF047857), Color(0xFF065F46)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // Mini chart positioned behind content
          if (showDocChart)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 80,
              child: Opacity(
                opacity: 0.2,
                child: _MiniAreaChart(data: weeklyData),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Spend',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Last 7 days',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  formatted,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                if (changePct != null)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isUp
                              ? Colors.red.withValues(alpha: 0.25)
                              : Colors.green.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isUp
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${isUp ? '+' : '-'}$changePct%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'vs prior 7 days',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                if (documentCountThisWeek != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${documentCountThisWeek!} ${documentCountThisWeek == 1 ? 'document' : 'documents'} this period',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Lend/borrow pending summary
                if (friendPendingCollect > 0 || friendPendingPay > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LEND / BORROW',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                            Container(
                              width: 1,
                              height: 28,
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: _FriendMiniStat(
                                  label: 'To pay',
                                  amount: friendPendingPay,
                                  currencyCode: currencyCode,
                                  positive: false,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (friendAddedThisWeekCollect > 0 ||
                            friendAddedThisWeekPay > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Added this week: +${AppCurrency.format(friendAddedThisWeekCollect, currencyCode)} collect · '
                            '+${AppCurrency.format(friendAddedThisWeekPay, currencyCode)} owe',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                // Spacer for the chart area
                if (showDocChart) const SizedBox(height: 24),
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
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        Text(
          AppCurrency.format(amount, currencyCode),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: positive
                ? const Color(0xFF6EE7B7)
                : const Color(0xFFFCA5A5),
          ),
        ),
      ],
    );
  }
}

class _MiniAreaChart extends StatelessWidget {
  const _MiniAreaChart({required this.data});
  final List<double> data;

  @override
  Widget build(BuildContext context) {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
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
            color: Colors.white.withValues(alpha: 0.5),
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
