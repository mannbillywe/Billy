import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BudgetsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> build() async {
    return _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await _client
        .from('budgets')
        .select('*, categories(name)')
        .eq('user_id', uid)
        .eq('is_active', true)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<String?> addBudget({
    required String name,
    required double amount,
    String? categoryId,
    String period = 'monthly',
    String currency = 'INR',
    bool rollover = false,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    final res = await _client.from('budgets').insert({
      'user_id': uid,
      'name': name,
      'amount': amount,
      if (categoryId != null) 'category_id': categoryId,
      'period': period,
      'currency': currency,
      'rollover_enabled': rollover,
    }).select('id').single();
    await refresh();
    return res['id'] as String?;
  }

  Future<void> updateBudget(String id, Map<String, dynamic> updates) async {
    final uid = _uid;
    if (uid == null) return;
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _client.from('budgets').update(updates).eq('id', id).eq('user_id', uid);
    await refresh();
  }

  Future<void> deleteBudget(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('budgets').update({
      'is_active': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('user_id', uid);
    await refresh();
  }
}

final budgetsProvider =
    AsyncNotifierProvider<BudgetsNotifier, List<Map<String, dynamic>>>(
  BudgetsNotifier.new,
);
