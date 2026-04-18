// CRUD for the three user-editable GOAT tables. RLS guarantees users can only
// touch their own rows; nothing here bypasses that.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/goat_inputs_models.dart';

class GoatInputsService {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  // ── goat_user_inputs (singleton per user) ────────────────────────────────

  static Future<GoatUserInputs?> fetchUserInputs() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final row = await _client
          .from('goat_user_inputs')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return GoatUserInputs.fromRow(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('[GOAT] inputs fetch failed: $e');
      if (e.code == '42P01') return null;
      rethrow;
    }
  }

  static Future<void> upsertUserInputs(GoatUserInputs inputs) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    await _client
        .from('goat_user_inputs')
        .upsert(inputs.toRow(uid), onConflict: 'user_id');
  }

  // ── goat_goals (many per user) ───────────────────────────────────────────

  static Future<List<GoatGoal>> fetchGoals() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _client
          .from('goat_goals')
          .select()
          .eq('user_id', uid)
          .order('priority', ascending: true)
          .order('created_at', ascending: false);
      return rows
          .whereType<dynamic>()
          .map((r) => GoatGoal.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList(growable: false);
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('[GOAT] goals fetch failed: $e');
      if (e.code == '42P01') return const [];
      rethrow;
    }
  }

  static Future<GoatGoal> saveGoal(GoatGoal goal) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final row = await _client
        .from('goat_goals')
        .upsert(goal.toInsertRow(uid))
        .select()
        .single();
    return GoatGoal.fromRow(Map<String, dynamic>.from(row));
  }

  static Future<void> deleteGoal(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('goat_goals').delete().eq('id', id).eq('user_id', uid);
  }

  // ── goat_obligations (many per user) ─────────────────────────────────────

  static Future<List<GoatObligation>> fetchObligations() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _client
          .from('goat_obligations')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return rows
          .whereType<dynamic>()
          .map((r) =>
              GoatObligation.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList(growable: false);
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('[GOAT] obligations fetch failed: $e');
      if (e.code == '42P01') return const [];
      rethrow;
    }
  }

  static Future<GoatObligation> saveObligation(GoatObligation o) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final row = await _client
        .from('goat_obligations')
        .upsert(o.toInsertRow(uid))
        .select()
        .single();
    return GoatObligation.fromRow(Map<String, dynamic>.from(row));
  }

  static Future<void> deleteObligation(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _client
        .from('goat_obligations')
        .delete()
        .eq('id', id)
        .eq('user_id', uid);
  }
}
