import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ActivityFeedNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    return _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch({int limit = 50, int offset = 0}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return [];
    final res = await Supabase.instance.client
        .from('activity_events')
        .select()
        .or('user_id.eq.$uid,actor_user_id.eq.$uid,target_user_id.eq.$uid')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }
}

final activityFeedProvider =
    AsyncNotifierProvider<ActivityFeedNotifier, List<Map<String, dynamic>>>(
  ActivityFeedNotifier.new,
);
