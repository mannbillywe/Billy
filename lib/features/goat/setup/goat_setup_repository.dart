import 'package:supabase_flutter/supabase_flutter.dart';

class GoatSetupRepository {
  GoatSetupRepository._();

  static SupabaseClient get _c => Supabase.instance.client;
  static String? get _uid => _c.auth.currentUser?.id;

  static Future<Map<String, dynamic>?> fetchSetupState() async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _c.from('goat_setup_state').select().eq('user_id', uid).maybeSingle();
    return row != null ? Map<String, dynamic>.from(row) : null;
  }

  /// Ensures a row exists for the signed-in user (client-side; safe with RLS).
  static Future<Map<String, dynamic>> ensureSetupState() async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final existing = await fetchSetupState();
    if (existing != null) return existing;
    final inserted = await _c
        .from('goat_setup_state')
        .insert({
          'user_id': uid,
          'status': 'not_started',
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  static Future<void> touchLastSeen() async {
    final uid = _uid;
    if (uid == null) return;
    await _c.from('goat_setup_state').update({
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', uid);
  }

  static Future<void> updateSetupState({
    String? status,
    String? currentStep,
    List<dynamic>? completedSteps,
    List<dynamic>? skippedSteps,
    int? readinessScore,
    List<dynamic>? criticalMissing,
    List<dynamic>? optionalMissing,
    Map<String, dynamic>? metadataPatch,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (status != null) updates['status'] = status;
    if (currentStep != null) updates['current_step'] = currentStep;
    if (completedSteps != null) updates['completed_steps'] = completedSteps;
    if (skippedSteps != null) updates['skipped_steps'] = skippedSteps;
    if (readinessScore != null) updates['readiness_score'] = readinessScore;
    if (criticalMissing != null) updates['critical_missing'] = criticalMissing;
    if (optionalMissing != null) updates['optional_missing'] = optionalMissing;

    if (metadataPatch != null && metadataPatch.isNotEmpty) {
      final row = await _c.from('goat_setup_state').select('metadata').eq('user_id', uid).maybeSingle();
      final prev = (row?['metadata'] is Map) ? Map<String, dynamic>.from(row!['metadata'] as Map) : <String, dynamic>{};
      prev.addAll(metadataPatch);
      updates['metadata'] = prev;
    }

    if (status == 'in_progress') {
      updates['started_at'] ??= DateTime.now().toUtc().toIso8601String();
    }
    if (status == 'completed' || status == 'skipped') {
      updates['completed_at'] = DateTime.now().toUtc().toIso8601String();
    }

    await _c.from('goat_setup_state').update(updates).eq('user_id', uid);
  }

  static Future<Map<String, dynamic>?> fetchLatestDraft() async {
    final uid = _uid;
    if (uid == null) return null;
    final rows = await _c
        .from('goat_setup_drafts')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows as List);
    if (list.isEmpty) return null;
    return list.first;
  }

  static Future<void> updateDraftStatus({
    required String draftId,
    required String parseStatus,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _c
        .from('goat_setup_drafts')
        .update({
          'parse_status': parseStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', draftId)
        .eq('user_id', uid);
  }

  static Future<Map<String, dynamic>> fetchSetupPrefillSnapshot() async {
    final uid = _uid;
    if (uid == null) return {};
    final profile = await _c.from('profiles').select('preferred_currency, goat_analysis_lens').eq('id', uid).maybeSingle();

    Future<int> count(String table) async {
      final r = await _c.from(table).select('id').eq('user_id', uid);
      return (r as List).length;
    }

    return {
      'existing_profile': {
        'preferred_currency': profile?['preferred_currency'],
        'goat_analysis_lens': profile?['goat_analysis_lens'],
      },
      'counts': {
        'accounts': await count('financial_accounts'),
        'income_streams': await count('income_streams'),
        'recurring_series': await count('recurring_series'),
        'goals': await count('goals'),
        'planned_cashflow_events': await count('planned_cashflow_events'),
        'statement_imports': await count('statement_imports'),
      },
    };
  }
}
