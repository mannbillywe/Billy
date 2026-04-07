import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase_service.dart';
import '../finance/finance_repository.dart';
import '../goals/goals_repository.dart';
import '../recurring/recurring_repository.dart';
import 'goat_setup_models.dart';
import 'goat_setup_readiness.dart';
import 'goat_setup_repository.dart';

/// Validates reviewed rows and writes to domain tables (deterministic).
class GoatSetupApplier {
  GoatSetupApplier._();

  static SupabaseClient get _c => Supabase.instance.client;
  static String? get _uid => _c.auth.currentUser?.id;

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static Future<void> applyInterpretation({
    required GoatSetupInterpretResult draft,
    String? draftId,
    String? preferredCurrencyFallback,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    final pd = draft.profileDefaults;
    final pc = pd['preferred_currency'] as String?;
    final lens = pd['goat_analysis_lens'] as String?;
    if ((pc != null && pc.isNotEmpty) || (lens != null && lens.isNotEmpty)) {
      await SupabaseService.updateProfile(
        preferredCurrency: (pc != null && pc.isNotEmpty) ? pc : null,
        goatAnalysisLens: (lens != null && lens.isNotEmpty) ? lens : null,
      );
    }

    final currency = pc ?? preferredCurrencyFallback ?? 'INR';

    for (final row in draft.accounts) {
      if (!rowAccepted(row)) continue;
      final name = (row['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      final type = (row['account_type'] as String?)?.trim() ?? 'bank';
      if (!const {'cash', 'bank', 'wallet', 'credit_card', 'loan', 'other'}.contains(type)) {
        continue;
      }
      final bal = (row['current_balance'] as num?)?.toDouble() ?? 0;
      final credit = row['available_credit'];
      final institution = (row['institution_name'] as String?)?.trim();
      final isPrimary = row['is_primary'] == true;
      final include = row['include_in_safe_to_spend'] != false;

      if (isPrimary) {
        await _c.from('financial_accounts').update({'is_primary': false}).eq('user_id', uid);
      }

      final ins = await _c
          .from('financial_accounts')
          .insert({
            'user_id': uid,
            'name': name,
            'account_type': type,
            'current_balance': bal,
            'currency': currency,
            'is_primary': isPrimary,
            'include_in_safe_to_spend': include,
            'source': 'manual',
            if (institution != null && institution.isNotEmpty) 'institution_name': institution,
            if (credit is num) 'available_credit': credit.toDouble(),
          })
          .select('id')
          .single();
      final accountId = ins['id'] as String;
      if (bal.abs() > 0.0001) {
        await _c.from('account_balance_snapshots').insert({
          'user_id': uid,
          'account_id': accountId,
          'balance': bal,
          'source': 'manual',
        });
      }
    }

    for (final row in draft.incomeStreams) {
      if (!rowAccepted(row)) continue;
      final title = (row['title'] as String?)?.trim();
      if (title == null || title.isEmpty) continue;
      var freq = (row['frequency'] as String?)?.trim() ?? 'monthly';
      if (!const {'weekly', 'biweekly', 'monthly', 'irregular', 'custom'}.contains(freq)) {
        freq = 'monthly';
      }
      final amount = (row['expected_amount'] as num?)?.toDouble() ?? 0;
      final next = _parseDate(row['next_expected_date'] as String?);
      final meta = <String, dynamic>{};
      if (amount <= 0) {
        meta['goat_setup_needs_amount'] = true;
      }
      await _c.from('income_streams').insert({
        'user_id': uid,
        'title': title,
        'frequency': freq,
        'expected_amount': amount <= 0 ? 0 : amount,
        'status': 'active',
        'source': 'manual',
        if (next != null) 'next_expected_date': _ymd(next),
        'confidence': (row['confidence'] as num?)?.toDouble(),
        if ((row['notes'] as String?)?.trim().isNotEmpty == true) 'notes': row['notes'],
        'metadata': meta,
      });
    }

    for (final row in draft.recurringItems) {
      if (!rowAccepted(row)) continue;
      final title = (row['title'] as String?)?.trim();
      if (title == null || title.isEmpty) continue;
      var kind = (row['kind'] as String?)?.trim() ?? 'bill';
      if (!const {'bill', 'subscription', 'income', 'transfer'}.contains(kind)) {
        kind = 'bill';
      }
      var freq = (row['frequency'] as String?)?.trim() ?? 'monthly';
      if (!const {'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly', 'custom'}.contains(freq)) {
        freq = 'monthly';
      }
      final amount = (row['expected_amount'] as num?)?.toDouble() ?? 0;
      final nextDue = _parseDate(row['next_due_date'] as String?) ?? DateTime.now();
      final autopay = row['autopay_enabled'] == true;
      final method = (row['autopay_method'] as String?)?.trim();
      await RecurringRepository.createManualSeries(
        title: title,
        kind: kind,
        frequency: freq,
        nextDue: nextDue,
        expectedAmount: amount,
        currency: currency,
        autopay: autopay,
        autopayMethod: (method != null && method.isNotEmpty) ? method : null,
      );
    }

    for (final row in draft.plannedEvents) {
      if (!rowAccepted(row)) continue;
      final title = (row['title'] as String?)?.trim();
      if (title == null || title.isEmpty) continue;
      final dt = _parseDate(row['event_date'] as String?);
      if (dt == null) continue;
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      var dir = (row['direction'] as String?)?.trim() ?? 'outflow';
      if (dir != 'inflow' && dir != 'outflow') dir = 'outflow';
      await FinanceRepository.insertPlannedEvent(
        title: title,
        eventDate: dt,
        amount: amount,
        direction: dir,
      );
    }

    for (final row in draft.goals) {
      if (!rowAccepted(row)) continue;
      final title = (row['title'] as String?)?.trim();
      if (title == null || title.isEmpty) continue;
      var gt = (row['goal_type'] as String?)?.trim() ?? 'custom';
      if (!const {
        'emergency_fund',
        'sinking_fund',
        'purchase',
        'travel',
        'bill_buffer',
        'debt_paydown',
        'custom',
      }.contains(gt)) {
        gt = 'custom';
      }
      final target = (row['target_amount'] as num?)?.toDouble() ?? 0;
      if (target <= 0) continue;
      final td = _parseDate(row['target_date'] as String?);
      var fr = (row['forecast_reserve'] as String?)?.trim() ?? 'none';
      if (!const {'none', 'soft', 'hard'}.contains(fr)) {
        fr = 'none';
      }
      await GoalsRepository.createGoal(
        title: title,
        goalType: gt,
        targetAmount: target,
        targetDate: td,
        forecastReserve: fr,
      );
    }

    final sp = draft.sourcePreference;
    if (sourcePreferenceAccepted(sp)) {
      final pref = sp['statement_preference'] as String? ?? 'unknown';
      await GoatSetupRepository.updateSetupState(
        metadataPatch: {
          'source_preference': pref,
          'has_statement_data_already': sp['has_statement_data_already'],
        },
      );
    }

    if (draftId != null) {
      await GoatSetupRepository.updateDraftStatus(draftId: draftId, parseStatus: 'applied');
    }

    final readiness = await GoatSetupReadinessEngine.compute(userId: uid);
    await GoatSetupRepository.updateSetupState(
      status: 'completed',
      readinessScore: readiness.score,
      criticalMissing: readiness.criticalMissing,
      optionalMissing: readiness.optionalMissing,
      currentStep: null,
    );
  }

  /// Saves readiness only (e.g. after skip / partial complete).
  static Future<void> syncReadinessToState() async {
    final uid = _uid;
    if (uid == null) return;
    final readiness = await GoatSetupReadinessEngine.compute(userId: uid);
    await GoatSetupRepository.updateSetupState(
      readinessScore: readiness.score,
      criticalMissing: readiness.criticalMissing,
      optionalMissing: readiness.optionalMissing,
    );
  }
}
