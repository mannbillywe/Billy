// Models for GOAT setup AI JSON and editable review rows (app adds per-row `accepted` flags).

String? _s(dynamic v) => v is String ? v : null;
double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

bool _b(dynamic v, {bool fallback = false}) {
  if (v is bool) return v;
  return fallback;
}

Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
  if (v is Map) return Map<String, dynamic>.from(v.map((k, val) => MapEntry(k.toString(), val)));
  return {};
}

List<Map<String, dynamic>> _listOfMap(dynamic v) {
  if (v is! List) return [];
  return v
      .map((e) => _m(e))
      .where((m) => m.isNotEmpty)
      .toList();
}

class GoatSetupInterpretResult {
  GoatSetupInterpretResult({
    required this.raw,
    required this.profileDefaults,
    required this.accounts,
    required this.incomeStreams,
    required this.recurringItems,
    required this.plannedEvents,
    required this.goals,
    required this.sourcePreference,
    required this.missingQuestions,
    required this.readinessHints,
    required this.overallConfidence,
  });

  final Map<String, dynamic> raw;
  final Map<String, dynamic> profileDefaults;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> incomeStreams;
  final List<Map<String, dynamic>> recurringItems;
  final List<Map<String, dynamic>> plannedEvents;
  final List<Map<String, dynamic>> goals;
  final Map<String, dynamic> sourcePreference;
  final List<Map<String, dynamic>> missingQuestions;
  final Map<String, dynamic> readinessHints;
  final double overallConfidence;

  static GoatSetupInterpretResult fromJson(Map<String, dynamic> j) {
    return GoatSetupInterpretResult(
      raw: Map<String, dynamic>.from(j),
      profileDefaults: _m(j['profile_defaults']),
      accounts: _listOfMap(j['accounts']),
      incomeStreams: _listOfMap(j['income_streams']),
      recurringItems: _listOfMap(j['recurring_items']),
      plannedEvents: _listOfMap(j['planned_cashflow_events']),
      goals: _listOfMap(j['goals']),
      sourcePreference: _m(j['source_preference']),
      missingQuestions: _listOfMap(j['missing_questions']),
      readinessHints: _m(j['readiness_hints']),
      overallConfidence: _d(j['overall_confidence']),
    );
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(raw);

  static GoatSetupInterpretResult emptyTemplate() {
    return GoatSetupInterpretResult.fromJson({
      'profile_defaults': <String, dynamic>{},
      'accounts': <dynamic>[],
      'income_streams': <dynamic>[],
      'recurring_items': <dynamic>[],
      'planned_cashflow_events': <dynamic>[],
      'goals': <dynamic>[],
      'source_preference': <String, dynamic>{
        'statement_preference': 'unknown',
        'has_statement_data_already': false,
        'confidence': 1,
        'value_origin': 'defaulted',
        'accepted': true,
      },
      'missing_questions': <dynamic>[],
      'readiness_hints': <String, dynamic>{
        'critical_missing': <dynamic>[],
        'optional_missing': <dynamic>[],
        'summary': '',
      },
      'overall_confidence': 1,
    });
  }

  /// Blank rows for manual / form fallback.
  static Map<String, dynamic> templateAccountRow() => {
        'name': '',
        'account_type': 'bank',
        'current_balance': 0,
        'available_credit': 0,
        'is_primary': false,
        'include_in_safe_to_spend': true,
        'institution_name': null,
        'source': 'manual',
        'confidence': 1,
        'value_origin': 'user_provided',
        'warnings': <dynamic>[],
        'accepted': true,
      };

  static Map<String, dynamic> templateIncomeRow() => {
        'title': '',
        'frequency': 'monthly',
        'expected_amount': 0,
        'next_expected_date': null,
        'notes': null,
        'confidence': 1,
        'value_origin': 'user_provided',
        'warnings': <dynamic>[],
        'accepted': true,
      };

  static Map<String, dynamic> templateRecurringRow() => {
        'title': '',
        'kind': 'bill',
        'expected_amount': 0,
        'frequency': 'monthly',
        'next_due_date': null,
        'autopay_enabled': false,
        'autopay_method': null,
        'confidence': 1,
        'value_origin': 'user_provided',
        'warnings': <dynamic>[],
        'accepted': true,
      };

  static Map<String, dynamic> templatePlannedRow() => {
        'title': '',
        'event_date': null,
        'amount': 0,
        'direction': 'outflow',
        'notes': null,
        'confidence': 1,
        'value_origin': 'user_provided',
        'warnings': <dynamic>[],
        'accepted': true,
      };

  static Map<String, dynamic> templateGoalRow() => {
        'title': '',
        'goal_type': 'custom',
        'target_amount': 0,
        'target_date': null,
        'forecast_reserve': 'none',
        'confidence': 1,
        'value_origin': 'user_provided',
        'warnings': <dynamic>[],
        'accepted': true,
      };

  /// Deep copy for local editing; adds `accepted` to each list item when missing.
  GoatSetupInterpretResult copyForReview() {
    bool defAccepted(Map<String, dynamic> row) {
      final origin = _s(row['value_origin']) ?? '';
      final conf = _d(row['confidence']);
      if (origin == 'user_provided') return true;
      if (origin == 'defaulted' && conf < 0.35) return false;
      return conf >= 0.5;
    }

    List<Map<String, dynamic>> tag(List<Map<String, dynamic>> rows) {
      return rows.map((r) {
        final c = Map<String, dynamic>.from(r);
        c.putIfAbsent('accepted', () => defAccepted(c));
        return c;
      }).toList();
    }

    final sp = Map<String, dynamic>.from(sourcePreference);
    sp.putIfAbsent('accepted', () => _d(sp['confidence']) >= 0.45);

    final next = Map<String, dynamic>.from(raw);
    next['profile_defaults'] = Map<String, dynamic>.from(profileDefaults);
    next['accounts'] = tag(accounts);
    next['income_streams'] = tag(incomeStreams);
    next['recurring_items'] = tag(recurringItems);
    next['planned_cashflow_events'] = tag(plannedEvents);
    next['goals'] = tag(goals);
    next['source_preference'] = sp;
    next['missing_questions'] = missingQuestions.map((e) => Map<String, dynamic>.from(e)).toList();
    next['readiness_hints'] = Map<String, dynamic>.from(readinessHints);
    return GoatSetupInterpretResult.fromJson(next);
  }
}

bool rowAccepted(Map<String, dynamic> row) => _b(row['accepted'], fallback: true);

String rowOriginLabel(Map<String, dynamic> row) =>
    _s(row['value_origin']) ?? 'inferred';

double rowConfidence(Map<String, dynamic> row) => _d(row['confidence']);

String? rowWarningsLine(Map<String, dynamic> row) {
  final w = row['warnings'];
  if (w is! List || w.isEmpty) return null;
  return w.map((e) => e.toString()).where((s) => s.isNotEmpty).join(' · ');
}

bool sourcePreferenceAccepted(Map<String, dynamic> sp) => _b(sp['accepted'], fallback: true);
