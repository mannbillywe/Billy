import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/document_date_range.dart';
import '../../../providers/usage_limits_provider.dart';
import '../../../services/supabase_service.dart';
import '../models/analytics_insights_models.dart';
import '../services/analytics_insights_service.dart';

/// Cached + last-refreshed analytics insights for the Analytics tab.
/// Gemini runs only when [refreshInsights] is called (manual), not from [build].
class AnalyticsInsightsNotifier extends Notifier<AsyncValue<AnalyticsInsightsResult?>> {
  @override
  AsyncValue<AnalyticsInsightsResult?> build() => const AsyncValue.data(null);

  /// Loads the last Postgres snapshot for [rangePreset] (no Edge invoke, no Gemini).
  /// Ignores rows generated with a different [dateBasis] than the one requested.
  Future<void> loadCachedSnapshot(String rangePreset, InsightsDateBasis dateBasis) async {
    final row = await SupabaseService.fetchAnalyticsInsightSnapshot(rangePreset);
    if (row == null) {
      state = const AsyncValue.data(null);
      return;
    }
    final parsed = AnalyticsInsightsResult.fromSnapshotRow(row);
    if (parsed.insightDateBasis != dateBasis) {
      state = const AsyncValue.data(null);
      return;
    }
    state = AsyncValue.data(parsed);
  }

  /// Manual refresh: one Edge call, or two sequential calls when [includeAi] and the service uses dual AI (coach + JAI).
  /// On failure, restores the previous snapshot and returns an error message for a SnackBar.
  Future<String?> refreshInsights(
    String rangePreset, {
    bool includeAi = true,
    InsightsDateBasis dateBasis = InsightsDateBasis.billDate,
    AnalyticsGeminiScope geminiScope = AnalyticsGeminiScope.billy,
  }) async {
    final keep = state.valueOrNull;
    try {
      await SupabaseService.incrementRefreshCount();
      ref.invalidate(usageLimitsProvider);
    } catch (e) {
      return _refreshLimitMessage(e);
    }
    state = const AsyncValue.loading();
    try {
      final r = await AnalyticsInsightsService.refreshRange(
        rangePreset: rangePreset,
        includeAi: includeAi,
        dateBasis: dateBasis,
        geminiScope: geminiScope,
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

  static String _refreshLimitMessage(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('refresh limit')) {
      return 'Monthly refresh limit reached. Try again in the next period.';
    }
    return e.toString();
  }
}

final analyticsInsightsProvider =
    NotifierProvider<AnalyticsInsightsNotifier, AsyncValue<AnalyticsInsightsResult?>>(
  AnalyticsInsightsNotifier.new,
);
