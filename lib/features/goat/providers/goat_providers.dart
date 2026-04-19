import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/profile_provider.dart';
import '../models/goat_models.dart';
import '../services/goat_mode_service.dart';

/// True when the signed-in user's profile has `goat_mode = true`. Backed by
/// the `goat_mode_access` admin ledger via the sync trigger added in
/// 20260423120000_goat_mode_v1.sql.
final goatModeAccessProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  return profileGoatModeEnabled(profile);
});

/// Latest snapshot for the signed-in user. Null when nothing has been
/// computed yet (first-time users, before the backend runs).
final goatLatestSnapshotProvider =
    FutureProvider.autoDispose<GoatSnapshot?>((ref) async {
  // Only fetch when the user has access — avoids useless round-trips.
  final hasAccess = ref.watch(goatModeAccessProvider);
  if (!hasAccess) return null;
  return GoatModeService.fetchLatestSnapshot();
});

/// Previous snapshot (for trend comparison). Null if there is only one.
final goatPreviousSnapshotProvider =
    FutureProvider.autoDispose<GoatSnapshot?>((ref) async {
  final latest = await ref.watch(goatLatestSnapshotProvider.future);
  if (latest == null) return null;
  return GoatModeService.fetchPreviousSnapshot(latest);
});

/// Open recommendations, highest priority first.
final goatOpenRecommendationsProvider =
    FutureProvider.autoDispose<List<GoatRecommendation>>((ref) async {
  final hasAccess = ref.watch(goatModeAccessProvider);
  if (!hasAccess) return const [];
  return GoatModeService.fetchOpenRecommendations();
});

/// Backend compute history (read-only audit of `goat_mode_jobs`).
final goatRecentJobsProvider =
    FutureProvider.autoDispose<List<GoatJobSummary>>((ref) async {
  final hasAccess = ref.watch(goatModeAccessProvider);
  if (!hasAccess) return const [];
  return GoatModeService.fetchRecentJobs();
});
