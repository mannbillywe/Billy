import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/supabase_service.dart';
import '../models/analytics_insights_models.dart';
import '../services/analytics_insights_service.dart';

/// Cached + last-refreshed analytics insights for the Analytics tab.
/// Gemini runs only when [refreshInsights] is called (manual), not from [build].
class AnalyticsInsightsNotifier extends Notifier<AsyncValue<AnalyticsInsightsResult?>> {
  @override
  AsyncValue<AnalyticsInsightsResult?> build() => const AsyncValue.data(null);

  /// Loads the last Postgres snapshot for [rangePreset] (no Edge invoke, no Gemini).
  Future<void> loadCachedSnapshot(String rangePreset) async {
    final row = await SupabaseService.fetchAnalyticsInsightSnapshot(rangePreset);
    if (row == null) {
      state = const AsyncValue.data(null);
      return;
    }
    state = AsyncValue.data(AnalyticsInsightsResult.fromSnapshotRow(row));
  }

  /// Manual refresh: one Edge call; at most one Gemini batch per request when [includeAi].
  /// On failure, restores the previous snapshot and returns an error message for a SnackBar.
  Future<String?> refreshInsights(String rangePreset, {bool includeAi = true}) async {
    final keep = state.valueOrNull;
    state = const AsyncValue.loading();
    try {
      final r = await AnalyticsInsightsService.refreshRange(
        rangePreset: rangePreset,
        includeAi: includeAi,
      );
      if (!r.success) {
        state = keep != null ? AsyncValue.data(keep) : const AsyncValue.data(null);
        return 'Could not refresh insights';
      }
      state = AsyncValue.data(r);
      return null;
    } catch (e) {
      state = keep != null ? AsyncValue.data(keep) : const AsyncValue.data(null);
      return e.toString();
    }
  }
}

final analyticsInsightsProvider =
    NotifierProvider<AnalyticsInsightsNotifier, AsyncValue<AnalyticsInsightsResult?>>(
  AnalyticsInsightsNotifier.new,
);
