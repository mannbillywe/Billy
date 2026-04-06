import 'package:supabase_flutter/supabase_flutter.dart';

class GoalsRepository {
  GoalsRepository._();

  static SupabaseClient get _c => Supabase.instance.client;
  static String? get _uid => _c.auth.currentUser?.id;

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<List<Map<String, dynamic>>> fetchGoals({String? status}) async {
    if (_uid == null) return [];
    var q = _c.from('goals').select().eq('user_id', _uid!);
    if (status != null) {
      q = q.eq('status', status);
    }
    final rows = await q.order('priority', ascending: true).order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<Map<String, dynamic>?> fetchGoalById(String id) async {
    if (_uid == null) return null;
    final row = await _c.from('goals').select().eq('id', id).eq('user_id', _uid!).maybeSingle();
    return row;
  }

  static Future<String> createGoal({
    required String title,
    required String goalType,
    required double targetAmount,
    double currentAmount = 0,
    DateTime? targetDate,
    double? monthlyTarget,
    double? weeklyTarget,
    int priority = 3,
    String? linkedCategoryId,
    String? linkedRecurringSeriesId,
    String? linkedAccountId,
    bool autoAllocate = false,
    String? notes,
    String? color,
    String? icon,
    String forecastReserve = 'none',
    String status = 'active',
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final row = await _c
        .from('goals')
        .insert({
          'user_id': uid,
          'title': title,
          'goal_type': goalType,
          'status': status,
          'target_amount': targetAmount,
          'current_amount': currentAmount,
          if (targetDate != null) 'target_date': _ymd(targetDate),
          if (monthlyTarget != null) 'monthly_target': monthlyTarget,
          if (weeklyTarget != null) 'weekly_target': weeklyTarget,
          'priority': priority,
          if (linkedCategoryId != null) 'linked_category_id': linkedCategoryId,
          if (linkedRecurringSeriesId != null) 'linked_recurring_series_id': linkedRecurringSeriesId,
          if (linkedAccountId != null) 'linked_account_id': linkedAccountId,
          'auto_allocate': autoAllocate,
          if (notes != null) 'notes': notes,
          if (color != null) 'color': color,
          if (icon != null) 'icon': icon,
          'forecast_reserve': forecastReserve,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> updateGoal({
    required String id,
    String? title,
    String? goalType,
    String? status,
    double? targetAmount,
    double? currentAmount,
    DateTime? targetDate,
    double? monthlyTarget,
    double? weeklyTarget,
    int? priority,
    bool? autoAllocate,
    String? notes,
    String? color,
    String? icon,
    String? forecastReserve,
    bool clearTargetDate = false,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (goalType != null) updates['goal_type'] = goalType;
    if (status != null) updates['status'] = status;
    if (targetAmount != null) updates['target_amount'] = targetAmount;
    if (currentAmount != null) updates['current_amount'] = currentAmount;
    if (clearTargetDate) {
      updates['target_date'] = null;
    } else if (targetDate != null) {
      updates['target_date'] = _ymd(targetDate);
    }
    if (monthlyTarget != null) updates['monthly_target'] = monthlyTarget;
    if (weeklyTarget != null) updates['weekly_target'] = weeklyTarget;
    if (priority != null) updates['priority'] = priority;
    if (autoAllocate != null) updates['auto_allocate'] = autoAllocate;
    if (notes != null) updates['notes'] = notes;
    if (color != null) updates['color'] = color;
    if (icon != null) updates['icon'] = icon;
    if (forecastReserve != null) updates['forecast_reserve'] = forecastReserve;
    if (updates.isEmpty) return;
    await _c.from('goals').update(updates).eq('id', id).eq('user_id', uid);
  }

  static Future<void> addContribution({
    required String goalId,
    required double amount,
    String type = 'manual',
    String? note,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final g = await fetchGoalById(goalId);
    if (g == null) throw StateError('Goal not found');
    final cur = (g['current_amount'] as num?)?.toDouble() ?? 0;
    await _c.from('goal_contributions').insert({
      'goal_id': goalId,
      'user_id': uid,
      'amount': amount,
      'contribution_type': type,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    await _c.from('goals').update({'current_amount': cur + amount}).eq('id', goalId).eq('user_id', uid);
  }

  static Future<List<Map<String, dynamic>>> fetchContributions(String goalId, {int limit = 100}) async {
    if (_uid == null) return [];
    final rows = await _c
        .from('goal_contributions')
        .select()
        .eq('goal_id', goalId)
        .eq('user_id', _uid!)
        .order('contributed_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<List<Map<String, dynamic>>> fetchRulesForGoal(String goalId) async {
    if (_uid == null) return [];
    final rows = await _c.from('goal_rules').select().eq('goal_id', goalId).eq('user_id', _uid!);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> insertRule({
    required String goalId,
    required String ruleType,
    required double ruleValue,
    bool enabled = true,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    await _c.from('goal_rules').insert({
      'goal_id': goalId,
      'user_id': uid,
      'rule_type': ruleType,
      'rule_value': ruleValue,
      'enabled': enabled,
    });
  }

  static Future<void> deleteGoal(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await _c.from('goals').delete().eq('id', id).eq('user_id', uid);
  }

  static Future<List<Map<String, dynamic>>> fetchRecommendations({String status = 'pending'}) async {
    if (_uid == null) return [];
    final rows =
        await _c.from('goal_recommendations').select().eq('user_id', _uid!).eq('status', status).order('created_at');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Inserts only if no row exists for this key (does not resurrect dismissed items).
  static Future<void> ensurePendingRecommendation({
    required String suggestionKey,
    required String title,
    required String suggestionType,
    String? body,
    String? refTable,
    String? refId,
    double? suggestedTargetAmount,
    DateTime? suggestedTargetDate,
    Map<String, dynamic> payload = const {},
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final existing = await _c
        .from('goal_recommendations')
        .select('id')
        .eq('user_id', uid)
        .eq('suggestion_key', suggestionKey)
        .maybeSingle();
    if (existing != null) return;
    await _c.from('goal_recommendations').insert({
      'user_id': uid,
      'suggestion_key': suggestionKey,
      'title': title,
      'body': body,
      'suggestion_type': suggestionType,
      if (refTable != null) 'ref_table': refTable,
      if (refId != null) 'ref_id': refId,
      if (suggestedTargetAmount != null) 'suggested_target_amount': suggestedTargetAmount,
      if (suggestedTargetDate != null) 'suggested_target_date': _ymd(suggestedTargetDate),
      'status': 'pending',
      'payload': payload,
    });
  }

  static Future<void> setRecommendationStatus(String id, String status) async {
    final uid = _uid;
    if (uid == null) return;
    await _c.from('goal_recommendations').update({'status': status}).eq('id', id).eq('user_id', uid);
  }

  static Future<Map<String, dynamic>?> fetchRecommendationById(String id) async {
    if (_uid == null) return null;
    return _c.from('goal_recommendations').select().eq('id', id).eq('user_id', _uid!).maybeSingle();
  }

  /// Creates a goal from a pending recommendation and marks it accepted.
  static Future<String> acceptRecommendationAsGoal(String recommendationId) async {
    final rec = await fetchRecommendationById(recommendationId);
    if (rec == null) throw StateError('Recommendation not found');
    final t = rec['suggested_target_amount'];
    final target = (t as num?)?.toDouble() ?? 1000;
    final title = rec['title'] as String? ?? 'Goal';
    final st = rec['suggestion_type'] as String? ?? 'custom';
    String goalType = 'sinking_fund';
    if (st == 'emergency_fund') goalType = 'emergency_fund';
    if (st == 'planned_event') goalType = 'bill_buffer';
    final sd = rec['suggested_target_date'] as String?;
    DateTime? td;
    if (sd != null) td = DateTime.tryParse(sd);
    final goalId = await createGoal(
      title: title,
      goalType: goalType,
      targetAmount: target,
      targetDate: td,
      forecastReserve: 'soft',
    );
    await setRecommendationStatus(recommendationId, 'accepted');
    return goalId;
  }
}
