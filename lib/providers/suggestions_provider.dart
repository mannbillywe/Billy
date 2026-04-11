import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SuggestionsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> build() async {
    return _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final uid = _uid;
    if (uid == null) return [];
    final now = DateTime.now().toUtc().toIso8601String();
    final res = await _client
        .from('ai_suggestions')
        .select()
        .eq('user_id', uid)
        .or('status.eq.pending,and(status.eq.snoozed,snoozed_until.lte.$now)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<void> acceptSuggestion(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('ai_suggestions').update({
      'status': 'accepted',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('user_id', uid);
    await refresh();
  }

  Future<void> dismissSuggestion(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('ai_suggestions').update({
      'status': 'dismissed',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('user_id', uid);
    await refresh();
  }

  Future<void> snoozeSuggestion(String id, Duration duration) async {
    final uid = _uid;
    if (uid == null) return;
    final until = DateTime.now().toUtc().add(duration).toIso8601String();
    await _client.from('ai_suggestions').update({
      'status': 'snoozed',
      'snoozed_until': until,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('user_id', uid);
    await refresh();
  }

  Future<void> provideFeedback(String id, String feedback) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('ai_suggestions').update({
      'feedback': feedback,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).eq('user_id', uid);
    await refresh();
  }
}

final suggestionsProvider =
    AsyncNotifierProvider<SuggestionsNotifier, List<Map<String, dynamic>>>(
  SuggestionsNotifier.new,
);
