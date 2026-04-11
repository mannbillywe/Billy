import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecurringSeriesNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
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
        .from('recurring_series')
        .select('*, categories(name)')
        .eq('user_id', uid)
        .eq('is_active', true)
        .order('next_due', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<String?> addSeries({
    required String title,
    required double amount,
    required String cadence,
    required String anchorDate,
    String? categoryId,
    String currency = 'INR',
    int remindDaysBefore = 1,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    final res = await _client.from('recurring_series').insert({
      'user_id': uid,
      'title': title,
      'amount': amount,
      'cadence': cadence,
      'anchor_date': anchorDate,
      'next_due': anchorDate,
      if (categoryId != null) 'category_id': categoryId,
      'currency': currency,
      'remind_days_before': remindDaysBefore,
    }).select('id').single();
    await refresh();
    return res['id'] as String?;
  }

  Future<void> updateSeries(String id, Map<String, dynamic> updates) async {
    final uid = _uid;
    if (uid == null) return;
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _client.from('recurring_series').update(updates).eq('id', id).eq('user_id', uid);
    await refresh();
  }

  Future<void> deactivateSeries(String id) async {
    await updateSeries(id, {'is_active': false});
  }

  Future<void> deleteSeries(String id) async {
    await updateSeries(id, {'is_active': false});
  }
}

final recurringSeriesProvider =
    AsyncNotifierProvider<RecurringSeriesNotifier, List<Map<String, dynamic>>>(
  RecurringSeriesNotifier.new,
);
