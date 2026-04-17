import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/goat_setup_models.dart';
import 'goat_mode_service.dart';

/// Write-path Supabase service for the Goat Mode setup tables and
/// recommendation lifecycle actions. Kept separate from [GoatModeService]
/// (which is read/trigger only) so the read surface stays lean.
///
/// All writes are user-scoped via RLS (`auth.uid() = user_id`); we inject
/// `user_id` from the JWT on inserts/upserts and never trust the client.
class GoatSetupService {
  GoatSetupService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  // ──────────────────────────────────────────────────────────────────────
  // goat_user_inputs (one row per user, PK = user_id → upsert)
  // ──────────────────────────────────────────────────────────────────────

  static Future<GoatUserInputs?> fetchUserInputs() async {
    final uid = _uid;
    if (uid == null) return null;
    final rows = await _client
        .from('goat_user_inputs')
        .select()
        .eq('user_id', uid)
        .limit(1);
    if (rows.isEmpty) return GoatUserInputs.empty;
    return GoatUserInputs.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Upsert the single `goat_user_inputs` row for the signed-in user.
  ///
  /// We merge in-place: existing values stay unless [value] provides a new
  /// one. The table's PK is `user_id` so onConflict:user_id guarantees a
  /// single row per user even if the call races with itself.
  static Future<GoatUserInputs> upsertUserInputs(GoatUserInputs value) async {
    final uid = _uid;
    if (uid == null) {
      throw GoatModeException('Sign in to save setup.', status: 401);
    }
    final payload = {
      'user_id': uid,
      ...value.toUpsertPayload(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final row = await _client
          .from('goat_user_inputs')
          .upsert(payload, onConflict: 'user_id')
          .select()
          .single();
      return GoatUserInputs.fromRow(Map<String, dynamic>.from(row));
    } catch (e) {
      if (kDebugMode) debugPrint('[GOAT] upsertUserInputs error: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // goat_goals
  // ──────────────────────────────────────────────────────────────────────

  /// All active goals for this user, newest first.
  static Future<List<GoatGoal>> fetchGoals({bool includeInactive = false}) async {
    final uid = _uid;
    if (uid == null) return const [];
    var q = _client.from('goat_goals').select().eq('user_id', uid);
    if (!includeInactive) q = q.eq('status', 'active');
    final rows = await q.order('priority', ascending: true).order(
          'created_at',
          ascending: false,
        );
    return rows
        .map((r) => GoatGoal.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  static Future<GoatGoal> createGoal(GoatGoal goal) async {
    final uid = _uid;
    if (uid == null) {
      throw GoatModeException('Sign in to save this goal.', status: 401);
    }
    final payload = {
      'user_id': uid,
      ...goal.toInsertPayload(),
    };
    final row = await _client
        .from('goat_goals')
        .insert(payload)
        .select()
        .single();
    return GoatGoal.fromRow(Map<String, dynamic>.from(row));
  }

  static Future<GoatGoal> updateGoal(GoatGoal goal) async {
    final uid = _uid;
    final id = goal.id;
    if (uid == null) {
      throw GoatModeException('Sign in to update this goal.', status: 401);
    }
    if (id == null) throw StateError('updateGoal requires a persisted id');
    final payload = {
      ...goal.toUpdatePayload(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row = await _client
        .from('goat_goals')
        .update(payload)
        .eq('id', id)
        .eq('user_id', uid)
        .select()
        .single();
    return GoatGoal.fromRow(Map<String, dynamic>.from(row));
  }

  static Future<void> deleteGoal(String goalId) async {
    final uid = _uid;
    if (uid == null) {
      throw GoatModeException('Sign in to remove this goal.', status: 401);
    }
    await _client
        .from('goat_goals')
        .delete()
        .eq('id', goalId)
        .eq('user_id', uid);
  }

  // ──────────────────────────────────────────────────────────────────────
  // goat_obligations
  // ──────────────────────────────────────────────────────────────────────

  static Future<List<GoatObligation>> fetchObligations({
    bool includeInactive = false,
  }) async {
    final uid = _uid;
    if (uid == null) return const [];
    var q = _client.from('goat_obligations').select().eq('user_id', uid);
    if (!includeInactive) q = q.eq('status', 'active');
    final rows = await q.order('created_at', ascending: false);
    return rows
        .map((r) => GoatObligation.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  static Future<GoatObligation> createObligation(GoatObligation o) async {
    final uid = _uid;
    if (uid == null) {
      throw GoatModeException('Sign in to save this obligation.', status: 401);
    }
    final payload = {
      'user_id': uid,
      ...o.toInsertPayload(),
    };
    final row = await _client
        .from('goat_obligations')
        .insert(payload)
        .select()
        .single();
    return GoatObligation.fromRow(Map<String, dynamic>.from(row));
  }

  static Future<GoatObligation> updateObligation(GoatObligation o) async {
    final uid = _uid;
    final id = o.id;
    if (uid == null) {
      throw GoatModeException('Sign in to update this obligation.',
          status: 401);
    }
    if (id == null) {
      throw StateError('updateObligation requires a persisted id');
    }
    final payload = {
      ...o.toUpdatePayload(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final row = await _client
        .from('goat_obligations')
        .update(payload)
        .eq('id', id)
        .eq('user_id', uid)
        .select()
        .single();
    return GoatObligation.fromRow(Map<String, dynamic>.from(row));
  }

  static Future<void> deleteObligation(String obligationId) async {
    final uid = _uid;
    if (uid == null) {
      throw GoatModeException('Sign in to remove this obligation.',
          status: 401);
    }
    await _client
        .from('goat_obligations')
        .delete()
        .eq('id', obligationId)
        .eq('user_id', uid);
  }

  // ──────────────────────────────────────────────────────────────────────
  // goat_mode_recommendations — lifecycle actions
  // ──────────────────────────────────────────────────────────────────────
  //
  // RLS allows UPDATE scoped to auth.uid() = user_id (see migration). We only
  // ever change status + snoozed_until from the client. Dedupe is preserved
  // by the partial unique index: `(user_id, rec_fingerprint) WHERE status =
  // 'open'` — moving a row out of 'open' frees the fingerprint for the next
  // compute pass. Moving back to 'open' is not a client operation.

  /// Mark a recommendation as dismissed by the user. Irreversible from the
  /// client in v1 (backend can re-create it on the next run, which is fine).
  static Future<void> dismissRecommendation(String recId) async {
    final uid = _uid;
    if (uid == null) {
      throw GoatModeException('Sign in to manage recommendations.',
          status: 401);
    }
    await _client
        .from('goat_mode_recommendations')
        .update({
          'status': 'dismissed',
          'snoozed_until': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', recId)
        .eq('user_id', uid);
  }

  /// Snooze a recommendation for [duration]. It stays out of the "open"
  /// surface until `snoozed_until` is in the past; compute keeps the row
  /// but the UI hides it.
  static Future<void> snoozeRecommendation(
    String recId, {
    required Duration duration,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw GoatModeException('Sign in to manage recommendations.',
          status: 401);
    }
    final until = DateTime.now().toUtc().add(duration);
    await _client
        .from('goat_mode_recommendations')
        .update({
          'status': 'snoozed',
          'snoozed_until': until.toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', recId)
        .eq('user_id', uid);
  }

  /// Optional: mark a recommendation as resolved (the user acted on it).
  /// Included because the schema supports it and it's a single column flip —
  /// the UI only exposes it when it clearly helps.
  static Future<void> resolveRecommendation(String recId) async {
    final uid = _uid;
    if (uid == null) {
      throw GoatModeException('Sign in to manage recommendations.',
          status: 401);
    }
    await _client
        .from('goat_mode_recommendations')
        .update({
          'status': 'resolved',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', recId)
        .eq('user_id', uid);
  }
}
