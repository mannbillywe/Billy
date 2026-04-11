import 'package:supabase_flutter/supabase_flutter.dart';

class ActivityLogger {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  static Future<void> log({
    required String eventType,
    required String summary,
    String? targetUserId,
    String? groupId,
    String? transactionId,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? details,
    Map<String, dynamic>? previousState,
    String visibility = 'private',
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _client.from('activity_events').insert({
        'user_id': uid,
        'event_type': eventType,
        'actor_user_id': uid,
        if (targetUserId != null) 'target_user_id': targetUserId,
        if (groupId != null) 'group_id': groupId,
        if (transactionId != null) 'transaction_id': transactionId,
        if (entityType != null) 'entity_type': entityType,
        if (entityId != null) 'entity_id': entityId,
        'summary': summary,
        if (details != null) 'details': details,
        if (previousState != null) 'previous_state': previousState,
        'visibility': visibility,
      });
    } catch (_) {
      // Activity logging should never block main flows
    }
  }
}
