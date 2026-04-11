import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecurringSuggestionsNotifier
    extends AsyncNotifier<List<Map<String, dynamic>>> {
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
        .from('recurring_suggestions')
        .select()
        .eq('user_id', uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<void> confirmSuggestion(String id, String seriesId) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('recurring_suggestions').update({
      'status': 'confirmed',
      'created_series_id': seriesId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('user_id', uid);
    await refresh();
  }

  Future<void> dismissSuggestion(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('recurring_suggestions').update({
      'status': 'dismissed',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('user_id', uid);
    await refresh();
  }

  Future<void> snoozeSuggestion(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('recurring_suggestions').update({
      'status': 'snoozed',
      'snoozed_until': DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('user_id', uid);
    await refresh();
  }

  Future<void> suppressSuggestion(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('recurring_suggestions').update({
      'status': 'suppressed',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('user_id', uid);
    await refresh();
  }
}

final recurringSuggestionsProvider = AsyncNotifierProvider<
    RecurringSuggestionsNotifier, List<Map<String, dynamic>>>(
  RecurringSuggestionsNotifier.new,
);
