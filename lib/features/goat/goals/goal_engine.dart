import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../finance/cashflow_engine.dart';

/// Deterministic goal / sinking-fund math (minor units = paise).
@immutable
class GoalPaceResult {
  const GoalPaceResult({
    required this.requiredMonthlyMinor,
    required this.requiredWeeklyMinor,
    required this.paceStatus,
    required this.progressFraction,
    this.projectedCompletionDate,
  });

  final int requiredMonthlyMinor;
  final int requiredWeeklyMinor;

  /// `on_track` | `behind` | `ahead` | `unknown`
  final String paceStatus;
  final double progressFraction;
  final DateTime? projectedCompletionDate;
}

class GoalEngine {
  GoalEngine._();

  static DateTime _dOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static int _toMinor(double v) => CashflowMoneyLine.toMinor(v);

  static double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;

  /// Whole months from [from] (exclusive of partial) to [to], minimum 1 if [to] is after [from].
  static int wholeMonthsRemaining(DateTime from, DateTime to) {
    final a = _dOnly(from);
    final b = _dOnly(to);
    if (!b.isAfter(a)) return 1;
    var m = (b.year - a.year) * 12 + b.month - a.month;
    if (b.day < a.day) m -= 1;
    return m < 1 ? 1 : m;
  }

  /// Remaining amount to fund (minor), clamped at 0.
  static int remainingMinor(Map<String, dynamic> g) {
    final t = _num(g['target_amount']);
    final c = _num(g['current_amount']);
    return _toMinor((t - c).clamp(0.0, double.infinity));
  }

  /// Monthly savings required to reach target by [target_date], or 0 if no date / already funded.
  static int requiredMonthlyMinorFromPlan({
    required double targetAmount,
    required double currentAmount,
    DateTime? targetDate,
    DateTime? now,
  }) {
    final rem = (targetAmount - currentAmount).clamp(0.0, double.infinity);
    if (rem <= 0) return 0;
    final td = targetDate;
    if (td == null) return 0;
    final n = _dOnly(now ?? DateTime.now());
    final end = _dOnly(td);
    if (!end.isAfter(n)) {
      return _toMinor(rem);
    }
    final months = wholeMonthsRemaining(n, end);
    return _toMinor(rem / months);
  }

  /// Weekly equivalent (spread ~4.345 weeks per month).
  static int monthlyToWeeklyMinor(int monthlyMinor) =>
      ((monthlyMinor * 7.0) / 30.0).round();

  /// Uses DB [monthly_target] / [weekly_target] when set; else derives from target + date.
  static GoalPaceResult computePace(
    Map<String, dynamic> goal, {
    DateTime? now,
    List<Map<String, dynamic>> rules = const [],
  }) {
    final n = now ?? DateTime.now();
    final target = _num(goal['target_amount']);
    final current = _num(goal['current_amount']);
    final td = goal['target_date'] != null ? DateTime.tryParse(goal['target_date'].toString()) : null;
    final created = DateTime.tryParse(goal['created_at']?.toString() ?? '') ?? n;

    var monthlyMinor = 0;
    final dbMonthly = _num(goal['monthly_target']);
    if (dbMonthly > 0) {
      monthlyMinor = _toMinor(dbMonthly);
    } else {
      for (final r in rules) {
        if ((r['enabled'] as bool?) == false) continue;
        if (r['rule_type'] == 'monthly_fixed') {
          monthlyMinor = math.max(monthlyMinor, _toMinor(_num(r['rule_value'])));
        }
      }
      if (monthlyMinor == 0) {
        monthlyMinor = requiredMonthlyMinorFromPlan(
          targetAmount: target,
          currentAmount: current,
          targetDate: td,
          now: n,
        );
      }
    }

    var weeklyMinor = 0;
    final dbWeekly = _num(goal['weekly_target']);
    if (dbWeekly > 0) {
      weeklyMinor = _toMinor(dbWeekly);
    } else {
      for (final r in rules) {
        if ((r['enabled'] as bool?) == false) continue;
        if (r['rule_type'] == 'weekly_fixed') {
          weeklyMinor = math.max(weeklyMinor, _toMinor(_num(r['rule_value'])));
        }
      }
      if (weeklyMinor == 0) {
        weeklyMinor = monthlyToWeeklyMinor(monthlyMinor);
      }
    }

    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;

    String pace = 'unknown';
    DateTime? projected;

    if (td != null && target > 0) {
      final totalDays = td.difference(_dOnly(created)).inDays;
      final elapsedDays = _dOnly(n).difference(_dOnly(created)).inDays;
      if (totalDays > 0 && elapsedDays >= 0) {
        final expected = (elapsedDays / totalDays).clamp(0.0, 1.0);
        if (progress + 0.02 >= expected) {
          pace = progress > expected + 0.05 ? 'ahead' : 'on_track';
        } else if (progress < expected - 0.03) {
          pace = 'behind';
        } else {
          pace = 'on_track';
        }
      }
    } else if (target > 0 && current >= target) {
      pace = 'on_track';
    }

    if (current > 0 && current < target) {
      final elapsed = n.difference(created).inDays;
      if (elapsed > 0) {
        final perDay = current / elapsed;
        if (perDay > 0) {
          final daysLeft = ((target - current) / perDay).ceil();
          projected = n.add(Duration(days: daysLeft));
        }
      }
    }

    return GoalPaceResult(
      requiredMonthlyMinor: monthlyMinor,
      requiredWeeklyMinor: weeklyMinor,
      paceStatus: pace,
      progressFraction: progress,
      projectedCompletionDate: projected,
    );
  }

  /// Monthly outflow to treat as committed for **hard** forecast reserve.
  static int effectiveHardReserveMonthlyMinor(Map<String, dynamic> goal, List<Map<String, dynamic>> rules) {
    if ((goal['status'] as String?) != 'active') return 0;
    if ((goal['forecast_reserve'] as String?) != 'hard') return 0;
    return computePace(goal, rules: rules).requiredMonthlyMinor;
  }

  static int totalHardReserveMonthlyMinor(List<Map<String, dynamic>> goals, Map<String, List<Map<String, dynamic>>> rulesByGoalId) {
    var s = 0;
    for (final g in goals) {
      final id = g['id'] as String?;
      final rules = id != null ? (rulesByGoalId[id] ?? const []) : const <Map<String, dynamic>>[];
      s += effectiveHardReserveMonthlyMinor(g, rules);
    }
    return s;
  }
}
