import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

class SplitsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() => SupabaseService.fetchSplits();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => SupabaseService.fetchSplits());
  }

  Future<void> addSplit({
    required String title,
    required double totalAmount,
    required List<Map<String, dynamic>> participants,
  }) async {
    await SupabaseService.insertSplit(
      title: title,
      totalAmount: totalAmount,
      participants: participants,
    );
    await refresh();
  }
}

final splitsProvider =
    AsyncNotifierProvider<SplitsNotifier, List<Map<String, dynamic>>>(SplitsNotifier.new);
