import 'package:supabase_flutter/supabase_flutter.dart';

class FinanceRepository {
  FinanceRepository._();

  static SupabaseClient get _c => Supabase.instance.client;
  static String? get _uid => _c.auth.currentUser?.id;

  static Future<List<Map<String, dynamic>>> fetchAccounts() async {
    if (_uid == null) return [];
    final rows = await _c.from('financial_accounts').select().eq('user_id', _uid!).order('created_at');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> upsertAccount({
    String? id,
    required String name,
    required String accountType,
    required double currentBalance,
    String currency = 'INR',
    bool includeInSafeToSpend = true,
    bool isPrimary = false,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    if (id != null) {
      await _c.from('financial_accounts').update({
        'name': name,
        'account_type': accountType,
        'current_balance': currentBalance,
        'currency': currency,
        'include_in_safe_to_spend': includeInSafeToSpend,
        'is_primary': isPrimary,
      }).eq('id', id).eq('user_id', uid);
      return;
    }

    if (isPrimary) {
      await _c.from('financial_accounts').update({'is_primary': false}).eq('user_id', uid);
    }

    await _c.from('financial_accounts').insert({
      'user_id': uid,
      'name': name,
      'account_type': accountType,
      'current_balance': currentBalance,
      'currency': currency,
      'include_in_safe_to_spend': includeInSafeToSpend,
      'is_primary': isPrimary,
    });
  }

  static Future<List<Map<String, dynamic>>> fetchIncomeStreams() async {
    if (_uid == null) return [];
    final rows = await _c.from('income_streams').select().eq('user_id', _uid!).order('next_expected_date');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> insertIncomeStream({
    required String title,
    required String frequency,
    required double expectedAmount,
    DateTime? nextExpectedDate,
    String status = 'active',
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    await _c.from('income_streams').insert({
      'user_id': uid,
      'title': title,
      'frequency': frequency,
      'expected_amount': expectedAmount,
      'status': status,
      if (nextExpectedDate != null)
        'next_expected_date':
            '${nextExpectedDate.year}-${nextExpectedDate.month.toString().padLeft(2, '0')}-${nextExpectedDate.day.toString().padLeft(2, '0')}',
    });
  }

  static Future<List<Map<String, dynamic>>> fetchPlannedEvents() async {
    if (_uid == null) return [];
    final rows = await _c.from('planned_cashflow_events').select().eq('user_id', _uid!).order('event_date');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> insertPlannedEvent({
    required String title,
    required DateTime eventDate,
    required double amount,
    required String direction,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    await _c.from('planned_cashflow_events').insert({
      'user_id': uid,
      'title': title,
      'event_date':
          '${eventDate.year}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}',
      'amount': amount,
      'direction': direction,
    });
  }
}
