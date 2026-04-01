import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

class InvitationsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    await SupabaseService.syncInvitationRecipient();
    return SupabaseService.fetchContactInvitations();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await SupabaseService.syncInvitationRecipient();
      return SupabaseService.fetchContactInvitations();
    });
  }

  Future<void> inviteEmail(String email) async {
    await SupabaseService.inviteContactByEmail(email);
    await refresh();
  }

  Future<void> accept(String id) async {
    await SupabaseService.acceptContactInvitation(id);
    await refresh();
    await ref.read(connectionsNotifierProvider.notifier).refresh();
  }

  Future<void> reject(String id) async {
    await SupabaseService.rejectContactInvitation(id);
    await refresh();
  }

  Future<void> cancelOutgoing(String id) async {
    await SupabaseService.cancelOutgoingInvitation(id);
    await refresh();
  }
}

final invitationsNotifierProvider =
    AsyncNotifierProvider<InvitationsNotifier, List<Map<String, dynamic>>>(InvitationsNotifier.new);

/// Resolved connections with `other_user_id`, `display_name` for UI pickers.
class ConnectionsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await SupabaseService.fetchUserConnections();
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final low = r['user_low'] as String;
      final high = r['user_high'] as String;
      final other = low == uid ? high : low;
      final p = await SupabaseService.fetchProfileById(other);
      out.add({
        'other_user_id': other,
        'display_name': (p?['display_name'] as String?)?.trim().isNotEmpty == true
            ? p!['display_name'] as String
            : 'User',
      });
    }
    out.sort((a, b) => (a['display_name'] as String).compareTo(b['display_name'] as String));
    return out;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return <Map<String, dynamic>>[];
      final rows = await SupabaseService.fetchUserConnections();
      final out = <Map<String, dynamic>>[];
      for (final r in rows) {
        final low = r['user_low'] as String;
        final high = r['user_high'] as String;
        final other = low == uid ? high : low;
        final p = await SupabaseService.fetchProfileById(other);
        out.add({
          'other_user_id': other,
          'display_name': (p?['display_name'] as String?)?.trim().isNotEmpty == true
              ? p!['display_name'] as String
              : 'User',
        });
      }
      out.sort((a, b) => (a['display_name'] as String).compareTo(b['display_name'] as String));
      return out;
    });
  }
}

final connectionsNotifierProvider =
    AsyncNotifierProvider<ConnectionsNotifier, List<Map<String, dynamic>>>(ConnectionsNotifier.new);
