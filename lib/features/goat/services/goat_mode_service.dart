// Read-only Supabase access for GOAT Mode. The backend (docker) writes all
// analysis results; the Flutter client never triggers compute.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/goat_models.dart';

class GoatModeService {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  /// Known scope fallback order. Reading "full" first gives the richest
  /// payload; we fall back to "overview" if the backend only produced that.
  static const _preferredScopes = ['full', 'overview'];

  /// Returns the most recent snapshot for the current user across the
  /// preferred scope list, or null if nothing has been computed yet.
  static Future<GoatSnapshot?> fetchLatestSnapshot({
    String? preferredScope,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    final scopes = preferredScope != null
        ? [preferredScope, ..._preferredScopes.where((s) => s != preferredScope)]
        : _preferredScopes;

    for (final scope in scopes) {
      try {
        final rows = await _client
            .from('goat_mode_snapshots')
            .select()
            .eq('user_id', uid)
            .eq('scope', scope)
            .order('generated_at', ascending: false)
            .limit(1);
        if (rows.isNotEmpty) {
          return GoatSnapshot.fromRow(Map<String, dynamic>.from(rows.first));
        }
      } on PostgrestException catch (e) {
        if (kDebugMode) debugPrint('[GOAT] snapshot fetch ($scope) failed: $e');
        // Non-fatal — try next scope. If the table is missing it means the
        // migration hasn't been applied yet; treat as "no snapshot".
        if (e.code == '42P01') return null;
      } catch (e) {
        if (kDebugMode) debugPrint('[GOAT] snapshot fetch ($scope) error: $e');
      }
    }
    return null;
  }

  /// Second-most-recent snapshot — enables "vs previous run" comparisons on
  /// coverage/recommendations. Matches the scope of [latest] to make diffs
  /// meaningful.
  static Future<GoatSnapshot?> fetchPreviousSnapshot(
    GoatSnapshot latest,
  ) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final rows = await _client
          .from('goat_mode_snapshots')
          .select()
          .eq('user_id', uid)
          .eq('scope', latest.scope)
          .neq('id', latest.id)
          .order('generated_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        return GoatSnapshot.fromRow(Map<String, dynamic>.from(rows.first));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[GOAT] previous snapshot fetch failed: $e');
    }
    return null;
  }

  /// Open recommendations, highest-priority first. Capped at 50 because the
  /// backend already dedupes by fingerprint and surfaces the most relevant
  /// items.
  static Future<List<GoatRecommendation>> fetchOpenRecommendations({
    int limit = 50,
  }) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _client
          .from('goat_mode_recommendations')
          .select()
          .eq('user_id', uid)
          .inFilter('status', ['open', 'snoozed'])
          .order('priority', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .whereType<dynamic>()
          .map((r) => GoatRecommendation.fromRow(
              Map<String, dynamic>.from(r as Map)))
          .toList(growable: false);
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('[GOAT] recommendations fetch failed: $e');
      if (e.code == '42P01') return const [];
    } catch (e) {
      if (kDebugMode) debugPrint('[GOAT] recommendations fetch error: $e');
    }
    return const [];
  }

  /// Dismiss / snooze / resolve a recommendation. RLS only allows status
  /// updates on the user's own rows.
  /// Recent backend job rows (newest first). Empty when table missing or offline.
  static Future<List<GoatJobSummary>> fetchRecentJobs({int limit = 12}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _client
          .from('goat_mode_jobs')
          .select(
            'id, scope, status, readiness_level, created_at, finished_at, error_message',
          )
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .whereType<dynamic>()
          .map((r) =>
              GoatJobSummary.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList(growable: false);
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('[GOAT] jobs fetch failed: $e');
      if (e.code == '42P01') return const [];
    } catch (e) {
      if (kDebugMode) debugPrint('[GOAT] jobs fetch error: $e');
    }
    return const [];
  }

  static Future<void> updateRecommendationStatus(
    String id, {
    required String status,
    DateTime? snoozedUntil,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final patch = <String, dynamic>{
      'status': status,
      if (snoozedUntil != null) 'snoozed_until': snoozedUntil.toIso8601String(),
    };
    await _client
        .from('goat_mode_recommendations')
        .update(patch)
        .eq('id', id)
        .eq('user_id', uid);
  }
}
