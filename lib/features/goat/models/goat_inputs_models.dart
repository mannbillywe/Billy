// User-editable inputs consumed by GOAT Mode. Mirror the schema defined in
// supabase/migrations/20260423120000_goat_mode_v1.sql for:
//   - public.goat_user_inputs (one row per user)
//   - public.goat_goals       (many per user)
//   - public.goat_obligations (many per user)

class GoatUserInputs {
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
    this.notes = const {},
  });

  final double? monthlyIncome;
  final String incomeCurrency;
  final String? payFrequency; // weekly|biweekly|semimonthly|monthly|other
  final int? salaryDay; // 1..31
  final double? emergencyFundTargetMonths;
  final double? liquidityFloor;
  final int? householdSize;
  final int? dependents;
  final String? riskTolerance; // conservative|balanced|aggressive
  final int? planningHorizonMonths; // 1..60
  final String? tonePreference; // calm|direct|coaching
  final Map<String, dynamic> notes;

  static const empty = GoatUserInputs();

  factory GoatUserInputs.fromRow(Map<String, dynamic> m) => GoatUserInputs(
        monthlyIncome: _num(m['monthly_income']),
        incomeCurrency: (m['income_currency'] ?? 'INR') as String,
        payFrequency: m['pay_frequency'] as String?,
        salaryDay: _int(m['salary_day']),
        emergencyFundTargetMonths: _num(m['emergency_fund_target_months']),
        liquidityFloor: _num(m['liquidity_floor']),
        householdSize: _int(m['household_size']),
        dependents: _int(m['dependents']),
        riskTolerance: m['risk_tolerance'] as String?,
        planningHorizonMonths: _int(m['planning_horizon_months']),
        tonePreference: m['tone_preference'] as String?,
        notes: (m['notes'] is Map)
            ? Map<String, dynamic>.from(m['notes'] as Map)
            : const {},
      );

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'monthly_income': monthlyIncome,
        'income_currency': incomeCurrency,
        'pay_frequency': payFrequency,
        'salary_day': salaryDay,
        'emergency_fund_target_months': emergencyFundTargetMonths,
        'liquidity_floor': liquidityFloor,
        'household_size': householdSize,
        'dependents': dependents,
        'risk_tolerance': riskTolerance,
        'planning_horizon_months': planningHorizonMonths,
        'tone_preference': tonePreference,
        'notes': notes,
      };

  GoatUserInputs copyWith({
    double? monthlyIncome,
    String? incomeCurrency,
    String? payFrequency,
    int? salaryDay,
    double? emergencyFundTargetMonths,
    double? liquidityFloor,
    int? householdSize,
    int? dependents,
    String? riskTolerance,
    int? planningHorizonMonths,
    String? tonePreference,
    Map<String, dynamic>? notes,
    bool clearPayFrequency = false,
    bool clearRiskTolerance = false,
    bool clearTonePreference = false,
  }) {
    return GoatUserInputs(
      monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      incomeCurrency: incomeCurrency ?? this.incomeCurrency,
      payFrequency:
          clearPayFrequency ? null : (payFrequency ?? this.payFrequency),
      salaryDay: salaryDay ?? this.salaryDay,
      emergencyFundTargetMonths:
          emergencyFundTargetMonths ?? this.emergencyFundTargetMonths,
      liquidityFloor: liquidityFloor ?? this.liquidityFloor,
      householdSize: householdSize ?? this.householdSize,
      dependents: dependents ?? this.dependents,
      riskTolerance:
          clearRiskTolerance ? null : (riskTolerance ?? this.riskTolerance),
      planningHorizonMonths:
          planningHorizonMonths ?? this.planningHorizonMonths,
      tonePreference:
          clearTonePreference ? null : (tonePreference ?? this.tonePreference),
      notes: notes ?? this.notes,
    );
  }
}

class GoatGoal {
  const GoatGoal({
    required this.id,
    required this.goalType,
    required this.title,
    required this.targetAmount,
    required this.currentAmount,
    required this.priority,
    required this.status,
    this.targetDate,
    this.metadata = const {},
  });

  final String id;
  final String goalType; // emergency_fund|savings|purchase|travel|debt_payoff|investment|other
  final String title;
  final double targetAmount;
  final double currentAmount;
  final int priority; // 1..5
  final String status; // active|paused|completed|abandoned
  final DateTime? targetDate;
  final Map<String, dynamic> metadata;

  factory GoatGoal.fromRow(Map<String, dynamic> m) => GoatGoal(
        id: (m['id'] ?? '') as String,
        goalType: (m['goal_type'] ?? 'other') as String,
        title: (m['title'] ?? '') as String,
        targetAmount: _num(m['target_amount']) ?? 0,
        currentAmount: _num(m['current_amount']) ?? 0,
        priority: _int(m['priority']) ?? 3,
        status: (m['status'] ?? 'active') as String,
        targetDate: m['target_date'] is String && (m['target_date'] as String).isNotEmpty
            ? DateTime.tryParse(m['target_date'] as String)
            : null,
        metadata: (m['metadata'] is Map)
            ? Map<String, dynamic>.from(m['metadata'] as Map)
            : const {},
      );

  Map<String, dynamic> toInsertRow(String userId) => {
        if (id.isNotEmpty) 'id': id,
        'user_id': userId,
        'goal_type': goalType,
        'title': title,
        'target_amount': targetAmount,
        'current_amount': currentAmount,
        if (targetDate != null)
          'target_date': _yyyyMmDd(targetDate!),
        'priority': priority,
        'status': status,
        'metadata': metadata,
      };

  double get progress =>
      targetAmount <= 0 ? 0 : (currentAmount / targetAmount).clamp(0.0, 1.0);
}

class GoatObligation {
  const GoatObligation({
    required this.id,
    required this.obligationType,
    required this.cadence,
    required this.status,
    this.lenderName,
    this.currentOutstanding,
    this.monthlyDue,
    this.dueDay,
    this.interestRate,
    this.metadata = const {},
  });

  final String id;
  final String obligationType; // emi|credit_card_min|rent|insurance|loan|student_loan|other
  final String cadence; // weekly|biweekly|monthly|quarterly|yearly
  final String status; // active|paid_off|defaulted|cancelled
  final String? lenderName;
  final double? currentOutstanding;
  final double? monthlyDue;
  final int? dueDay; // 1..31
  final double? interestRate;
  final Map<String, dynamic> metadata;

  factory GoatObligation.fromRow(Map<String, dynamic> m) => GoatObligation(
        id: (m['id'] ?? '') as String,
        obligationType: (m['obligation_type'] ?? 'other') as String,
        cadence: (m['cadence'] ?? 'monthly') as String,
        status: (m['status'] ?? 'active') as String,
        lenderName: m['lender_name'] as String?,
        currentOutstanding: _num(m['current_outstanding']),
        monthlyDue: _num(m['monthly_due']),
        dueDay: _int(m['due_day']),
        interestRate: _num(m['interest_rate']),
        metadata: (m['metadata'] is Map)
            ? Map<String, dynamic>.from(m['metadata'] as Map)
            : const {},
      );

  Map<String, dynamic> toInsertRow(String userId) => {
        if (id.isNotEmpty) 'id': id,
        'user_id': userId,
        'obligation_type': obligationType,
        'lender_name': lenderName,
        'current_outstanding': currentOutstanding,
        'monthly_due': monthlyDue,
        'due_day': dueDay,
        'interest_rate': interestRate,
        'cadence': cadence,
        'status': status,
        'metadata': metadata,
      };
}

// ─── helpers ────────────────────────────────────────────────────────────────

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String _yyyyMmDd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ─── labels for dropdowns/chips ─────────────────────────────────────────────

const goatPayFrequencies = <String, String>{
  'monthly': 'Monthly',
  'semimonthly': 'Twice a month',
  'biweekly': 'Every 2 weeks',
  'weekly': 'Weekly',
  'other': 'Other',
};

const goatRiskToleranceLabels = <String, String>{
  'conservative': 'Conservative',
  'balanced': 'Balanced',
  'aggressive': 'Aggressive',
};

const goatToneLabels = <String, String>{
  'calm': 'Calm',
  'direct': 'Direct',
  'coaching': 'Coaching',
};

const goatGoalTypeLabels = <String, String>{
  'emergency_fund': 'Emergency fund',
  'savings': 'General savings',
  'purchase': 'Planned purchase',
  'travel': 'Travel',
  'debt_payoff': 'Debt payoff',
  'investment': 'Investment',
  'other': 'Other',
};

const goatObligationTypeLabels = <String, String>{
  'rent': 'Rent',
  'emi': 'EMI / loan',
  'credit_card_min': 'Credit card minimum',
  'insurance': 'Insurance premium',
  'loan': 'Personal loan',
  'student_loan': 'Student loan',
  'other': 'Other',
};

const goatCadenceLabels = <String, String>{
  'monthly': 'Monthly',
  'weekly': 'Weekly',
  'biweekly': 'Every 2 weeks',
  'quarterly': 'Quarterly',
  'yearly': 'Yearly',
};
