import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/activity_logger.dart';

class DisputesNotifier extends FamilyAsyncNotifier<List<Map<String, dynamic>>, String?> {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> build(String? groupId) async {
    return _fetch(groupId);
  }

  Future<List<Map<String, dynamic>>> _fetch(String? groupId) async {
    final uid = _uid;
    if (uid == null) return [];
    var query = _client.from('disputes').select();
    if (groupId != null) {
      query = query.eq('group_id', groupId);
    } else {
      query = query.eq('user_id', uid);
    }
    final res = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch(arg));
  }

  Future<String?> openDispute({
    required String entityType,
    required String entityId,
    required String reason,
    String? groupId,
    String? transactionId,
    double? proposedAmount,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    final res = await _client.from('disputes').insert({
      'user_id': uid,
      'entity_type': entityType,
      'entity_id': entityId,
      'reason': reason,
      if (groupId != null) 'group_id': groupId,
      if (transactionId != null) 'transaction_id': transactionId,
      if (proposedAmount != null) 'proposed_amount': proposedAmount,
    }).select('id').single();
    final id = res['id'] as String?;

    await ActivityLogger.log(
      eventType: 'dispute_opened',
      summary: 'Dispute opened: $reason',
      groupId: groupId,
      transactionId: transactionId,
      entityType: 'dispute',
      entityId: id,
      visibility: groupId != null ? 'group' : 'private',
    );

    await refresh();
    return id;
  }

  Future<void> resolveDispute(String disputeId, String notes) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('disputes').update({
      'status': 'resolved',
      'resolved_by': uid,
      'resolution_notes': notes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', disputeId);

    await ActivityLogger.log(
      eventType: 'dispute_resolved',
      summary: 'Dispute resolved: $notes',
      entityType: 'dispute',
      entityId: disputeId,
    );

    await refresh();
  }
}

final disputesProvider =
    AsyncNotifierProvider.family<DisputesNotifier, List<Map<String, dynamic>>, String?>(
  DisputesNotifier.new,
);
