import 'package:supabase_flutter/supabase_flutter.dart';

/// Deterministic GOAT readiness (no AI). Optionally persist onto [goat_setup_state].
class GoatReadinessResult {
  const GoatReadinessResult({
    required this.score,
    required this.criticalMissing,
    required this.optionalMissing,
    required this.nextBestAction,
  });

  final int score;
  final List<String> criticalMissing;
  final List<String> optionalMissing;
  final String nextBestAction;
}

class GoatSetupReadinessEngine {
  GoatSetupReadinessEngine._();

  static SupabaseClient get _c => Supabase.instance.client;

  static Future<GoatReadinessResult> compute({required String userId}) async {
    final critical = <String>[];
    final optional = <String>[];
    var points = 0;

    final profile = await _c.from('profiles').select('goat_analysis_lens, preferred_currency').eq('id', userId).maybeSingle();

    final accounts = await _c.from('financial_accounts').select('id, current_balance').eq('user_id', userId);
    final accountList = List<Map<String, dynamic>>.from(accounts as List);

    final income = await _c.from('income_streams').select('id, status, expected_amount').eq('user_id', userId);
    final incomeList = List<Map<String, dynamic>>.from(income as List).where((r) => (r['status'] as String? ?? 'active') == 'active').toList();

    final recurring = await _c.from('recurring_series').select('id, status').eq('user_id', userId);
    final recList = List<Map<String, dynamic>>.from(recurring as List).where((r) => (r['status'] as String? ?? 'active') == 'active').toList();

    final goals = await _c.from('goals').select('id, status').eq('user_id', userId);
    final goalList = List<Map<String, dynamic>>.from(goals as List).where((r) => (r['status'] as String? ?? 'active') == 'active').toList();

    final planned = await _c.from('planned_cashflow_events').select('id').eq('user_id', userId).limit(1);
    final hasPlanned = (planned as List).isNotEmpty;

    final stm = await _c.from('statement_imports').select('id').eq('user_id', userId).limit(1);
    final hasStatements = (stm as List).isNotEmpty;

    if (accountList.isNotEmpty) {
      points += 18;
    } else {
      critical.add('Add at least one account so GOAT knows where money lives.');
    }

    final hasMeaningfulBalance = accountList.any((a) {
      final b = a['current_balance'];
      if (b is num) return b.abs() > 0.009;
      return false;
    });
    if (hasMeaningfulBalance) {
      points += 22;
    } else if (accountList.isNotEmpty) {
      optional.add('Add current balances for better forecast accuracy.');
    }

    if (incomeList.isNotEmpty) {
      final hasAmount = incomeList.any((r) {
        final a = r['expected_amount'];
        if (a is num) return a > 0;
        return false;
      });
      if (hasAmount) {
        points += 22;
      } else {
        points += 8;
        critical.add('Set a positive expected amount on your main income stream.');
      }
    } else {
      critical.add('Add an income stream (even “irregular” is fine).');
    }

    if (recList.isNotEmpty) {
      points += 15;
    } else {
      optional.add('Add recurring bills or subscriptions you care about.');
    }

    if (goalList.isNotEmpty) {
      points += 13;
    } else {
      optional.add('Add a goal (emergency fund, travel, etc.).');
    }

    if (hasPlanned) {
      points += 5;
    }

    final lens = profile?['goat_analysis_lens'] as String?;
    if (lens != null && lens.isNotEmpty) {
      points += 5;
    } else {
      optional.add('Pick a GOAT analysis lens in Preferences.');
    }

    if (hasStatements) {
      points += 5;
    } else {
      optional.add('Import a statement if you use bank/card exports.');
    }

    final score = points.clamp(0, 100);

    if (critical.isEmpty && score < 55) {
      critical.add('Complete a few more setup items to unlock stronger forecasts.');
    }

    final next = _pickNext(critical, optional);

    return GoatReadinessResult(
      score: score,
      criticalMissing: critical,
      optionalMissing: optional,
      nextBestAction: next,
    );
  }

  static String _pickNext(List<String> critical, List<String> optional) {
    if (critical.isNotEmpty) return critical.first;
    if (optional.isNotEmpty) return optional.first;
    return 'You are in good shape — revisit GOAT when your money picture changes.';
  }
}
