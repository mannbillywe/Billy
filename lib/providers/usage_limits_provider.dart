import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

final usageLimitsProvider =
    AsyncNotifierProvider<UsageLimitsNotifier, Map<String, dynamic>?>(
  UsageLimitsNotifier.new,
);

class UsageLimitsNotifier extends AsyncNotifier<Map<String, dynamic>?> {
  @override
  Future<Map<String, dynamic>?> build() => SupabaseService.fetchUsageLimits();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await SupabaseService.fetchUsageLimits());
  }

  int get ocrScansUsed =>
      (state.valueOrNull?['ocr_scans_used'] as num?)?.toInt() ?? 0;
  int get ocrScansLimit =>
      (state.valueOrNull?['ocr_scans_limit'] as num?)?.toInt() ?? 5;
  int get refreshUsed =>
      (state.valueOrNull?['refresh_used'] as num?)?.toInt() ?? 0;
  int get refreshLimit =>
      (state.valueOrNull?['refresh_limit'] as num?)?.toInt() ?? 5;

  bool get isOcrLocked => ocrScansUsed >= ocrScansLimit;
  bool get isRefreshLocked => refreshUsed >= refreshLimit;
}
