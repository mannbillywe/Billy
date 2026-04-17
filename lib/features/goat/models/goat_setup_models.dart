import 'package:flutter/foundation.dart';

/// Setup-side view models mirroring `goat_user_inputs`, `goat_goals`,
/// `goat_obligations`. Kept separate from `goat_models.dart` (which holds
/// the analytics read-side view-models) so the form layer stays tight and
/// doesn't drag snapshot/recommendation parsing into every import.
///
/// All enums encode their wire value (matching the DB `check` constraint) plus
/// a user-visible label — the forms never show the raw wire token.

// ──────────────────────────────────────────────────────────────────────────
// goat_user_inputs
// ──────────────────────────────────────────────────────────────────────────

enum GoatPayFrequency {
  weekly,
  biweekly,
  semimonthly,
  monthly,
  other;

  String get wire => this == GoatPayFrequency.semimonthly ? 'semimonthly' : name;

  String get label => switch (this) {
        GoatPayFrequency.weekly => 'Weekly',
        GoatPayFrequency.biweekly => 'Every 2 weeks',
        GoatPayFrequency.semimonthly => 'Twice a month',
        GoatPayFrequency.monthly => 'Monthly',
        GoatPayFrequency.other => 'Something else',
      };

  static GoatPayFrequency? fromWire(String? v) {
    if (v == null) return null;
    for (final f in GoatPayFrequency.values) {
      if (f.wire == v) return f;
    }
    return null;
  }
}

enum GoatRiskTolerance {
  conservative,
  balanced,
  aggressive;

  String get wire => name;
  String get label => switch (this) {
        GoatRiskTolerance.conservative => 'Conservative',
        GoatRiskTolerance.balanced => 'Balanced',
        GoatRiskTolerance.aggressive => 'Aggressive',
      };
  String get hint => switch (this) {
        GoatRiskTolerance.conservative => 'Prefer safety over growth',
        GoatRiskTolerance.balanced => 'Mix of safety and growth',
        GoatRiskTolerance.aggressive => 'Prefer growth, handle swings',
      };

  static GoatRiskTolerance? fromWire(String? v) {
    if (v == null) return null;
    for (final r in GoatRiskTolerance.values) {
      if (r.wire == v) return r;
    }
    return null;
  }
}

enum GoatTonePreference {
  calm,
  direct,
  coaching;

  String get wire => name;
  String get label => switch (this) {
        GoatTonePreference.calm => 'Calm',
        GoatTonePreference.direct => 'Direct',
        GoatTonePreference.coaching => 'Coaching',
      };
  String get hint => switch (this) {
        GoatTonePreference.calm => 'Gentle and reassuring',
        GoatTonePreference.direct => 'Short and to the point',
        GoatTonePreference.coaching => 'Encouraging, with nudges',
      };

  static GoatTonePreference? fromWire(String? v) {
    if (v == null) return null;
    for (final t in GoatTonePreference.values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

@immutable
class GoatUserInputs {
  final double? monthlyIncome;
  final String incomeCurrency;
  final GoatPayFrequency? payFrequency;
  final int? salaryDay; // 1..31
  final double? emergencyFundTargetMonths;
  final double? liquidityFloor;
  final int? householdSize;
  final int? dependents;
  final GoatRiskTolerance? riskTolerance;
  final int? planningHorizonMonths; // 1..60
  final GoatTonePreference? tonePreference;

  const GoatUserInputs({
    this.monthlyIncome,
    this.incomeCurrency = 'INR',
    this.payFrequency,
    this.salaryDay,
    this.emergencyFundTargetMonths,
    this.liquidityFloor,
    this.householdSize,
    this.dependents,
    this.riskTolerance,
    this.planningHorizonMonths,
    this.tonePreference,
  });

  static const GoatUserInputs empty = GoatUserInputs();

  /// True iff at least one declared field is present. Drives the "Your setup"
  /// summary chip ("Not set yet" vs actual values).
  bool get hasAnyValue =>
      monthlyIncome != null ||
      payFrequency != null ||
      salaryDay != null ||
      emergencyFundTargetMonths != null ||
      liquidityFloor != null ||
      householdSize != null ||
      dependents != null ||
      riskTolerance != null ||
      planningHorizonMonths != null ||
      tonePreference != null;

  /// Count of "core" fields answered — used for a soft progress hint on the
  /// setup card. We keep the weighted set small so the bar feels achievable.
  int get filledCoreCount {
    var n = 0;
    if (monthlyIncome != null) n++;
    if (payFrequency != null) n++;
    if (emergencyFundTargetMonths != null) n++;
    if (riskTolerance != null) n++;
    if (tonePreference != null) n++;
    return n;
  }

  int get coreTotal => 5;

  factory GoatUserInputs.fromRow(Map<String, dynamic> row) {
    double? asD(Object? v) => v is num ? v.toDouble() : null;
    int? asI(Object? v) => v is num ? v.toInt() : null;
    return GoatUserInputs(
      monthlyIncome: asD(row['monthly_income']),
      incomeCurrency: (row['income_currency'] as String?) ?? 'INR',
      payFrequency: GoatPayFrequency.fromWire(row['pay_frequency'] as String?),
      salaryDay: asI(row['salary_day']),
      emergencyFundTargetMonths: asD(row['emergency_fund_target_months']),
      liquidityFloor: asD(row['liquidity_floor']),
      householdSize: asI(row['household_size']),
      dependents: asI(row['dependents']),
      riskTolerance:
          GoatRiskTolerance.fromWire(row['risk_tolerance'] as String?),
      planningHorizonMonths: asI(row['planning_horizon_months']),
      tonePreference:
          GoatTonePreference.fromWire(row['tone_preference'] as String?),
    );
  }

  /// Build the row payload used by the Supabase upsert. Only non-null fields
  /// are included so PATCH-style updates don't clobber values the user has
  /// already set. `user_id` is added by the service layer from the JWT.
  Map<String, dynamic> toUpsertPayload() {
    final m = <String, dynamic>{
      'income_currency': incomeCurrency,
    };
    if (monthlyIncome != null) m['monthly_income'] = monthlyIncome;
    if (payFrequency != null) m['pay_frequency'] = payFrequency!.wire;
    if (salaryDay != null) m['salary_day'] = salaryDay;
    if (emergencyFundTargetMonths != null) {
      m['emergency_fund_target_months'] = emergencyFundTargetMonths;
    }
    if (liquidityFloor != null) m['liquidity_floor'] = liquidityFloor;
    if (householdSize != null) m['household_size'] = householdSize;
    if (dependents != null) m['dependents'] = dependents;
    if (riskTolerance != null) m['risk_tolerance'] = riskTolerance!.wire;
    if (planningHorizonMonths != null) {
      m['planning_horizon_months'] = planningHorizonMonths;
    }
    if (tonePreference != null) m['tone_preference'] = tonePreference!.wire;
    return m;
  }

  GoatUserInputs copyWith({
    double? monthlyIncome,
    String? incomeCurrency,
    GoatPayFrequency? payFrequency,
    int? salaryDay,
    double? emergencyFundTargetMonths,
    double? liquidityFloor,
    int? householdSize,
    int? dependents,
    GoatRiskTolerance? riskTolerance,
    int? planningHorizonMonths,
    GoatTonePreference? tonePreference,
  }) {
    return GoatUserInputs(
      monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      incomeCurrency: incomeCurrency ?? this.incomeCurrency,
      payFrequency: payFrequency ?? this.payFrequency,
      salaryDay: salaryDay ?? this.salaryDay,
      emergencyFundTargetMonths:
          emergencyFundTargetMonths ?? this.emergencyFundTargetMonths,
      liquidityFloor: liquidityFloor ?? this.liquidityFloor,
      householdSize: householdSize ?? this.householdSize,
      dependents: dependents ?? this.dependents,
      riskTolerance: riskTolerance ?? this.riskTolerance,
      planningHorizonMonths:
          planningHorizonMonths ?? this.planningHorizonMonths,
      tonePreference: tonePreference ?? this.tonePreference,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// goat_goals
// ──────────────────────────────────────────────────────────────────────────

enum GoatGoalType {
  emergencyFund,
  savings,
  purchase,
  travel,
  debtPayoff,
  investment,
  other;

  String get wire => switch (this) {
        GoatGoalType.emergencyFund => 'emergency_fund',
        GoatGoalType.savings => 'savings',
        GoatGoalType.purchase => 'purchase',
        GoatGoalType.travel => 'travel',
        GoatGoalType.debtPayoff => 'debt_payoff',
        GoatGoalType.investment => 'investment',
        GoatGoalType.other => 'other',
      };

  String get label => switch (this) {
        GoatGoalType.emergencyFund => 'Emergency fund',
        GoatGoalType.savings => 'Savings',
        GoatGoalType.purchase => 'Purchase',
        GoatGoalType.travel => 'Travel',
        GoatGoalType.debtPayoff => 'Pay off debt',
        GoatGoalType.investment => 'Invest',
        GoatGoalType.other => 'Other',
      };

  static GoatGoalType fromWire(String? v) {
    for (final g in GoatGoalType.values) {
      if (g.wire == v) return g;
    }
    return GoatGoalType.other;
  }
}

enum GoatGoalStatus {
  active,
  paused,
  completed,
  abandoned;

  String get wire => name;
  String get label => switch (this) {
        GoatGoalStatus.active => 'Active',
        GoatGoalStatus.paused => 'Paused',
        GoatGoalStatus.completed => 'Completed',
        GoatGoalStatus.abandoned => 'Abandoned',
      };
  static GoatGoalStatus fromWire(String? v) {
    for (final s in GoatGoalStatus.values) {
      if (s.wire == v) return s;
    }
    return GoatGoalStatus.active;
  }
}

@immutable
class GoatGoal {
  /// Null for new goals that haven't been persisted yet.
  final String? id;
  final GoatGoalType type;
  final String title;
  final double targetAmount;
  final double currentAmount;
  final DateTime? targetDate;
  final int priority; // 1..5
  final GoatGoalStatus status;
  final DateTime? createdAt;

  const GoatGoal({
    this.id,
    required this.type,
    required this.title,
    required this.targetAmount,
    this.currentAmount = 0,
    this.targetDate,
    this.priority = 3,
    this.status = GoatGoalStatus.active,
    this.createdAt,
  });

  double get progress {
    if (targetAmount <= 0) return 0;
    return (currentAmount / targetAmount).clamp(0.0, 1.0);
  }

  factory GoatGoal.fromRow(Map<String, dynamic> row) {
    double asD(Object? v) => v is num ? v.toDouble() : 0;
    return GoatGoal(
      id: row['id'] as String?,
      type: GoatGoalType.fromWire(row['goal_type'] as String?),
      title: (row['title'] as String?) ?? '',
      targetAmount: asD(row['target_amount']),
      currentAmount: asD(row['current_amount']),
      targetDate: _ymd(row['target_date']),
      priority: (row['priority'] as num?)?.toInt() ?? 3,
      status: GoatGoalStatus.fromWire(row['status'] as String?),
      createdAt: _ts(row['created_at']),
    );
  }

  Map<String, dynamic> toInsertPayload() => _payload();
  Map<String, dynamic> toUpdatePayload() => _payload();

  Map<String, dynamic> _payload() {
    return {
      'goal_type': type.wire,
      'title': title.trim(),
      'target_amount': targetAmount,
      'current_amount': currentAmount,
      if (targetDate != null) 'target_date': _fmtYmd(targetDate!),
      'priority': priority,
      'status': status.wire,
    };
  }

  GoatGoal copyWith({
    String? id,
    GoatGoalType? type,
    String? title,
    double? targetAmount,
    double? currentAmount,
    DateTime? targetDate,
    bool clearTargetDate = false,
    int? priority,
    GoatGoalStatus? status,
  }) {
    return GoatGoal(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// goat_obligations
// ──────────────────────────────────────────────────────────────────────────

enum GoatObligationType {
  emi,
  creditCardMin,
  rent,
  insurance,
  loan,
  studentLoan,
  other;

  String get wire => switch (this) {
        GoatObligationType.emi => 'emi',
        GoatObligationType.creditCardMin => 'credit_card_min',
        GoatObligationType.rent => 'rent',
        GoatObligationType.insurance => 'insurance',
        GoatObligationType.loan => 'loan',
        GoatObligationType.studentLoan => 'student_loan',
        GoatObligationType.other => 'other',
      };

  String get label => switch (this) {
        GoatObligationType.emi => 'EMI',
        GoatObligationType.creditCardMin => 'Credit card minimum',
        GoatObligationType.rent => 'Rent',
        GoatObligationType.insurance => 'Insurance',
        GoatObligationType.loan => 'Loan',
        GoatObligationType.studentLoan => 'Student loan',
        GoatObligationType.other => 'Other',
      };

  static GoatObligationType fromWire(String? v) {
    for (final o in GoatObligationType.values) {
      if (o.wire == v) return o;
    }
    return GoatObligationType.other;
  }
}

enum GoatObligationCadence {
  weekly,
  biweekly,
  monthly,
  quarterly,
  yearly;

  String get wire => name;
  String get label => switch (this) {
        GoatObligationCadence.weekly => 'Weekly',
        GoatObligationCadence.biweekly => 'Every 2 weeks',
        GoatObligationCadence.monthly => 'Monthly',
        GoatObligationCadence.quarterly => 'Quarterly',
        GoatObligationCadence.yearly => 'Yearly',
      };

  static GoatObligationCadence fromWire(String? v) {
    for (final c in GoatObligationCadence.values) {
      if (c.wire == v) return c;
    }
    return GoatObligationCadence.monthly;
  }
}

enum GoatObligationStatus {
  active,
  paidOff,
  defaulted,
  cancelled;

  String get wire => switch (this) {
        GoatObligationStatus.active => 'active',
        GoatObligationStatus.paidOff => 'paid_off',
        GoatObligationStatus.defaulted => 'defaulted',
        GoatObligationStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        GoatObligationStatus.active => 'Active',
        GoatObligationStatus.paidOff => 'Paid off',
        GoatObligationStatus.defaulted => 'Defaulted',
        GoatObligationStatus.cancelled => 'Cancelled',
      };

  static GoatObligationStatus fromWire(String? v) {
    for (final s in GoatObligationStatus.values) {
      if (s.wire == v) return s;
    }
    return GoatObligationStatus.active;
  }
}

@immutable
class GoatObligation {
  final String? id;
  final GoatObligationType type;
  final String? lenderName;
  final double? currentOutstanding;
  final double? monthlyDue;
  final int? dueDay; // 1..31
  final double? interestRate; // annual %, e.g. 12.5
  final GoatObligationCadence cadence;
  final GoatObligationStatus status;
  final DateTime? createdAt;

  const GoatObligation({
    this.id,
    required this.type,
    this.lenderName,
    this.currentOutstanding,
    this.monthlyDue,
    this.dueDay,
    this.interestRate,
    this.cadence = GoatObligationCadence.monthly,
    this.status = GoatObligationStatus.active,
    this.createdAt,
  });

  factory GoatObligation.fromRow(Map<String, dynamic> row) {
    double? asD(Object? v) => v is num ? v.toDouble() : null;
    int? asI(Object? v) => v is num ? v.toInt() : null;
    return GoatObligation(
      id: row['id'] as String?,
      type: GoatObligationType.fromWire(row['obligation_type'] as String?),
      lenderName: row['lender_name'] as String?,
      currentOutstanding: asD(row['current_outstanding']),
      monthlyDue: asD(row['monthly_due']),
      dueDay: asI(row['due_day']),
      interestRate: asD(row['interest_rate']),
      cadence: GoatObligationCadence.fromWire(row['cadence'] as String?),
      status: GoatObligationStatus.fromWire(row['status'] as String?),
      createdAt: _ts(row['created_at']),
    );
  }

  Map<String, dynamic> toInsertPayload() => _payload();
  Map<String, dynamic> toUpdatePayload() => _payload();

  Map<String, dynamic> _payload() {
    return {
      'obligation_type': type.wire,
      if (lenderName != null && lenderName!.trim().isNotEmpty)
        'lender_name': lenderName!.trim(),
      if (currentOutstanding != null) 'current_outstanding': currentOutstanding,
      if (monthlyDue != null) 'monthly_due': monthlyDue,
      if (dueDay != null) 'due_day': dueDay,
      if (interestRate != null) 'interest_rate': interestRate,
      'cadence': cadence.wire,
      'status': status.wire,
    };
  }

  GoatObligation copyWith({
    String? id,
    GoatObligationType? type,
    String? lenderName,
    double? currentOutstanding,
    double? monthlyDue,
    int? dueDay,
    double? interestRate,
    GoatObligationCadence? cadence,
    GoatObligationStatus? status,
  }) {
    return GoatObligation(
      id: id ?? this.id,
      type: type ?? this.type,
      lenderName: lenderName ?? this.lenderName,
      currentOutstanding: currentOutstanding ?? this.currentOutstanding,
      monthlyDue: monthlyDue ?? this.monthlyDue,
      dueDay: dueDay ?? this.dueDay,
      interestRate: interestRate ?? this.interestRate,
      cadence: cadence ?? this.cadence,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// helpers
// ──────────────────────────────────────────────────────────────────────────

DateTime? _ts(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

DateTime? _ymd(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return DateTime(v.year, v.month, v.day);
  if (v is String) {
    final d = DateTime.tryParse(v);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }
  return null;
}

String _fmtYmd(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
