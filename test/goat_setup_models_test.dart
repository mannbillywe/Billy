// Pure-Dart tests for the Goat Mode setup view-models. These pin the
// wire contracts (enum ↔ DB `check` constraint, payload shape, row parse)
// so future schema tweaks don't silently break the form layer.
//
// No Flutter bindings are needed — we only touch models + enums.

import 'package:billy/features/goat/models/goat_setup_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoatPayFrequency', () {
    test('wire values match the DB check constraint', () {
      expect(GoatPayFrequency.weekly.wire, 'weekly');
      expect(GoatPayFrequency.biweekly.wire, 'biweekly');
      expect(GoatPayFrequency.semimonthly.wire, 'semimonthly');
      expect(GoatPayFrequency.monthly.wire, 'monthly');
      expect(GoatPayFrequency.other.wire, 'other');
    });

    test('fromWire round-trips known values and handles null/unknown', () {
      for (final f in GoatPayFrequency.values) {
        expect(GoatPayFrequency.fromWire(f.wire), f);
      }
      expect(GoatPayFrequency.fromWire(null), isNull);
      expect(GoatPayFrequency.fromWire('bogus'), isNull);
    });
  });

  group('GoatRiskTolerance', () {
    test('wire/label/hint are complete and unique', () {
      final wires = GoatRiskTolerance.values.map((e) => e.wire).toSet();
      expect(wires, equals({'conservative', 'balanced', 'aggressive'}));
      for (final r in GoatRiskTolerance.values) {
        expect(r.label, isNotEmpty);
        expect(r.hint, isNotEmpty);
        expect(GoatRiskTolerance.fromWire(r.wire), r);
      }
    });
  });

  group('GoatTonePreference', () {
    test('wire round-trips', () {
      for (final t in GoatTonePreference.values) {
        expect(GoatTonePreference.fromWire(t.wire), t);
      }
      expect(GoatTonePreference.fromWire('???'), isNull);
    });
  });

  group('GoatUserInputs', () {
    test('empty has no values and zero filled core', () {
      expect(GoatUserInputs.empty.hasAnyValue, isFalse);
      expect(GoatUserInputs.empty.filledCoreCount, 0);
      expect(GoatUserInputs.empty.coreTotal, 5);
      expect(GoatUserInputs.empty.incomeCurrency, 'INR');
    });

    test('filledCoreCount weights the five "core" fields', () {
      const v = GoatUserInputs(
        monthlyIncome: 50000,
        payFrequency: GoatPayFrequency.monthly,
        emergencyFundTargetMonths: 3,
        riskTolerance: GoatRiskTolerance.balanced,
        tonePreference: GoatTonePreference.calm,
        // non-core fields — should NOT bump the count:
        salaryDay: 1,
        liquidityFloor: 1000,
        householdSize: 2,
        dependents: 0,
        planningHorizonMonths: 12,
      );
      expect(v.filledCoreCount, 5);
      expect(v.hasAnyValue, isTrue);
    });

    test('toUpsertPayload includes only non-null fields and uses wire tokens',
        () {
      const v = GoatUserInputs(
        monthlyIncome: 42000,
        payFrequency: GoatPayFrequency.semimonthly,
        salaryDay: 15,
        emergencyFundTargetMonths: 4,
        riskTolerance: GoatRiskTolerance.aggressive,
        tonePreference: GoatTonePreference.direct,
      );
      final p = v.toUpsertPayload();
      expect(p['monthly_income'], 42000);
      expect(p['pay_frequency'], 'semimonthly');
      expect(p['salary_day'], 15);
      expect(p['emergency_fund_target_months'], 4);
      expect(p['risk_tolerance'], 'aggressive');
      expect(p['tone_preference'], 'direct');
      expect(p['income_currency'], 'INR');
      // Untouched fields must not appear so we never clobber server values.
      expect(p.containsKey('liquidity_floor'), isFalse);
      expect(p.containsKey('household_size'), isFalse);
      expect(p.containsKey('dependents'), isFalse);
      expect(p.containsKey('planning_horizon_months'), isFalse);
    });

    test('fromRow tolerates missing/null fields and coerces num types', () {
      final v = GoatUserInputs.fromRow({
        'monthly_income': 40000, // int → double
        'income_currency': 'USD',
        'pay_frequency': 'weekly',
        'risk_tolerance': 'balanced',
      });
      expect(v.monthlyIncome, 40000.0);
      expect(v.incomeCurrency, 'USD');
      expect(v.payFrequency, GoatPayFrequency.weekly);
      expect(v.riskTolerance, GoatRiskTolerance.balanced);
      expect(v.salaryDay, isNull);
      expect(v.tonePreference, isNull);
    });

    test('copyWith preserves existing non-null values', () {
      const base = GoatUserInputs(
        monthlyIncome: 10000,
        payFrequency: GoatPayFrequency.monthly,
      );
      final next = base.copyWith(
        emergencyFundTargetMonths: 3,
      );
      expect(next.monthlyIncome, 10000);
      expect(next.payFrequency, GoatPayFrequency.monthly);
      expect(next.emergencyFundTargetMonths, 3);
    });
  });

  group('GoatGoal', () {
    test('wire tokens match DB check constraint for type+status', () {
      expect(GoatGoalType.emergencyFund.wire, 'emergency_fund');
      expect(GoatGoalType.debtPayoff.wire, 'debt_payoff');
      expect(GoatGoalType.other.wire, 'other');

      final statuses = GoatGoalStatus.values.map((e) => e.wire).toSet();
      expect(
        statuses,
        equals({'active', 'paused', 'completed', 'abandoned'}),
      );
    });

    test('progress is clamped to [0,1] and handles zero target', () {
      expect(
        const GoatGoal(
          type: GoatGoalType.savings,
          title: 'x',
          targetAmount: 0,
        ).progress,
        0.0,
      );
      expect(
        const GoatGoal(
          type: GoatGoalType.savings,
          title: 'x',
          targetAmount: 100,
          currentAmount: 50,
        ).progress,
        0.5,
      );
      expect(
        const GoatGoal(
          type: GoatGoalType.savings,
          title: 'x',
          targetAmount: 100,
          currentAmount: 9999,
        ).progress,
        1.0,
      );
    });

    test('toInsertPayload trims title and emits ymd for targetDate', () {
      final g = GoatGoal(
        type: GoatGoalType.travel,
        title: '  Trip to Goa  ',
        targetAmount: 20000,
        currentAmount: 5000,
        targetDate: DateTime(2027, 1, 15),
        priority: 2,
        status: GoatGoalStatus.paused,
      );
      final p = g.toInsertPayload();
      expect(p['title'], 'Trip to Goa');
      expect(p['goal_type'], 'travel');
      expect(p['target_amount'], 20000);
      expect(p['current_amount'], 5000);
      expect(p['target_date'], '2027-01-15');
      expect(p['priority'], 2);
      expect(p['status'], 'paused');
    });

    test('toInsertPayload omits target_date when null', () {
      const g = GoatGoal(
        type: GoatGoalType.savings,
        title: 'rainy day',
        targetAmount: 1000,
      );
      expect(g.toInsertPayload().containsKey('target_date'), isFalse);
    });

    test('fromRow parses string date, enums, and defaults', () {
      final g = GoatGoal.fromRow({
        'id': 'g1',
        'goal_type': 'emergency_fund',
        'title': 'Buffer',
        'target_amount': 30000,
        'current_amount': null,
        'target_date': '2027-03-01',
        'priority': 1,
        'status': 'active',
        'created_at': '2026-04-17T10:00:00Z',
      });
      expect(g.id, 'g1');
      expect(g.type, GoatGoalType.emergencyFund);
      expect(g.currentAmount, 0); // null coerces to 0
      expect(g.targetDate, DateTime(2027, 3, 1));
      expect(g.status, GoatGoalStatus.active);
      expect(g.createdAt, isNotNull);
    });

    test('copyWith clearTargetDate nulls the date', () {
      final g = GoatGoal(
        type: GoatGoalType.savings,
        title: 'x',
        targetAmount: 100,
        targetDate: DateTime(2027, 1, 1),
      );
      expect(g.copyWith(clearTargetDate: true).targetDate, isNull);
      expect(g.copyWith().targetDate, DateTime(2027, 1, 1));
    });
  });

  group('GoatObligation', () {
    test('type wire tokens match DB check constraint', () {
      expect(GoatObligationType.emi.wire, 'emi');
      expect(GoatObligationType.creditCardMin.wire, 'credit_card_min');
      expect(GoatObligationType.studentLoan.wire, 'student_loan');
      expect(GoatObligationType.rent.wire, 'rent');

      final cadences = GoatObligationCadence.values.map((e) => e.wire).toSet();
      expect(
        cadences,
        equals({'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'}),
      );

      final statuses = GoatObligationStatus.values.map((e) => e.wire).toSet();
      expect(
        statuses,
        equals({'active', 'paid_off', 'defaulted', 'cancelled'}),
      );
    });

    test('toInsertPayload only includes optional fields when set', () {
      const minimal = GoatObligation(type: GoatObligationType.rent);
      final p = minimal.toInsertPayload();
      expect(p['obligation_type'], 'rent');
      expect(p['cadence'], 'monthly'); // default
      expect(p['status'], 'active'); // default
      expect(p.containsKey('lender_name'), isFalse);
      expect(p.containsKey('monthly_due'), isFalse);
      expect(p.containsKey('due_day'), isFalse);
      expect(p.containsKey('interest_rate'), isFalse);
    });

    test('toInsertPayload trims lender_name and drops it when blank', () {
      const blank = GoatObligation(
        type: GoatObligationType.loan,
        lenderName: '   ',
      );
      expect(blank.toInsertPayload().containsKey('lender_name'), isFalse);

      const set = GoatObligation(
        type: GoatObligationType.loan,
        lenderName: '  Acme Bank  ',
      );
      expect(set.toInsertPayload()['lender_name'], 'Acme Bank');
    });

    test('fromRow handles mixed types and defaults unknown enums', () {
      final o = GoatObligation.fromRow({
        'id': 'o1',
        'obligation_type': 'credit_card_min',
        'lender_name': 'AMEX',
        'current_outstanding': 1234.5,
        'monthly_due': 800,
        'due_day': 15,
        'interest_rate': 18.5,
        'cadence': 'unknown-cadence',
        'status': 'paid_off',
      });
      expect(o.type, GoatObligationType.creditCardMin);
      expect(o.lenderName, 'AMEX');
      expect(o.currentOutstanding, 1234.5);
      expect(o.monthlyDue, 800);
      expect(o.dueDay, 15);
      expect(o.interestRate, 18.5);
      expect(o.cadence, GoatObligationCadence.monthly); // unknown → default
      expect(o.status, GoatObligationStatus.paidOff);
    });
  });
}
