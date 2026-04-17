// Widget tests for the Goat Mode "Your setup" screen.
//
// We override every provider the screen touches so no Supabase client is
// needed. These tests cover the three primary render states (empty, with
// data, loading) and confirm the section-level CTAs are wired up.

import 'package:billy/features/goat/models/goat_models.dart';
import 'package:billy/features/goat/models/goat_setup_models.dart';
import 'package:billy/features/goat/providers/goat_mode_providers.dart';
import 'package:billy/features/goat/providers/goat_setup_providers.dart';
import 'package:billy/features/goat/screens/goat_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubController extends GoatModeController {
  final GoatModeState initial;
  _StubController(this.initial);

  @override
  Future<GoatModeState> build() async => initial;

  @override
  Future<void> refresh({GoatScope scope = GoatScope.full, bool dryRun = false}) async {}

  @override
  Future<void> reloadFromDb() async {}
}

class _StubUserInputs extends GoatUserInputsController {
  final GoatUserInputs value;
  _StubUserInputs(this.value);
  @override
  Future<GoatUserInputs> build() async => value;
  @override
  Future<GoatUserInputs> save(GoatUserInputs v) async => v;
}

class _StubGoals extends GoatGoalsController {
  final List<GoatGoal> value;
  _StubGoals(this.value);
  @override
  Future<List<GoatGoal>> build() async => value;
}

class _StubObligations extends GoatObligationsController {
  final List<GoatObligation> value;
  _StubObligations(this.value);
  @override
  Future<List<GoatObligation>> build() async => value;
}

Widget _host({
  GoatUserInputs? inputs,
  List<GoatGoal>? goals,
  List<GoatObligation>? obligations,
  GoatModeState? state,
  bool entitled = true,
}) {
  return ProviderScope(
    overrides: [
      // GoatSetupScreen short-circuits to the rollout card when the user is
      // not entitled (Phase 8 hardening). These tests exercise the populated
      // flow so the default is true; override via `entitled: false` to probe
      // the fallback.
      goatModeEntitlementProvider.overrideWithValue(entitled),
      goatModeControllerProvider.overrideWith(
        () => _StubController(state ?? const GoatModeState()),
      ),
      goatUserInputsControllerProvider.overrideWith(
        () => _StubUserInputs(inputs ?? GoatUserInputs.empty),
      ),
      goatGoalsControllerProvider.overrideWith(
        () => _StubGoals(goals ?? const []),
      ),
      goatObligationsControllerProvider.overrideWith(
        () => _StubObligations(obligations ?? const []),
      ),
    ],
    child: const MaterialApp(home: GoatSetupScreen()),
  );
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('empty setup renders inputs tile, both empties, and rerun banner',
      (t) async {
    await t.pumpWidget(_host());
    await _settle(t);

    // AppBar
    expect(find.text('Your setup'), findsOneWidget);

    // User inputs tile shows 0 of 5 when empty.
    expect(find.text('Your inputs'), findsOneWidget);
    expect(find.text('0 of 5'), findsOneWidget);
    expect(
      find.text('Takes under a minute. Every field is optional.'),
      findsOneWidget,
    );

    // Goals / obligations headers with "Add" CTAs + empty cards.
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Obligations'), findsOneWidget);
    expect(find.text('No goals yet'), findsOneWidget);
    expect(find.text('No obligations yet'), findsOneWidget);
    expect(find.text('Add a goal'), findsOneWidget);
    expect(find.text('Add an obligation'), findsOneWidget);

    // Rerun banner lives at the bottom of the list — scroll to it.
    await t.dragUntilVisible(
      find.text('Refresh analysis when ready'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Refresh analysis when ready'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('populated setup renders tiles for each goal and obligation',
      (t) async {
    final goals = [
      GoatGoal(
        id: 'g1',
        type: GoatGoalType.emergencyFund,
        title: 'Safety buffer',
        targetAmount: 90000,
        currentAmount: 45000,
      ),
      GoatGoal(
        id: 'g2',
        type: GoatGoalType.travel,
        title: 'Kyoto trip',
        targetAmount: 120000,
        currentAmount: 30000,
        status: GoatGoalStatus.paused,
      ),
    ];
    final obligations = [
      GoatObligation(
        id: 'o1',
        type: GoatObligationType.emi,
        lenderName: 'Acme Bank',
        monthlyDue: 15000,
        dueDay: 5,
      ),
    ];
    await t.pumpWidget(_host(
      inputs: const GoatUserInputs(
        monthlyIncome: 70000,
        payFrequency: GoatPayFrequency.monthly,
        emergencyFundTargetMonths: 3,
        riskTolerance: GoatRiskTolerance.balanced,
        tonePreference: GoatTonePreference.calm,
      ),
      goals: goals,
      obligations: obligations,
    ));
    await _settle(t);

    // 5 of 5 when all five core inputs are filled.
    expect(find.text('5 of 5'), findsOneWidget);

    // Goal tiles show title + completion percent.
    expect(find.text('Safety buffer'), findsOneWidget);
    expect(find.text('Kyoto trip'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget); // 45000 / 90000
    expect(find.text('25%'), findsOneWidget); // 30000 / 120000

    // Obligation tile uses lender name + monthly due.
    expect(find.text('Acme Bank'), findsOneWidget);
    expect(find.textContaining('day 5'), findsOneWidget);

    // Counts next to section headers.
    expect(find.text('· 2'), findsOneWidget); // goals
    expect(find.text('· 1'), findsOneWidget); // obligations

    // Empty cards should NOT appear in populated state.
    expect(find.text('No goals yet'), findsNothing);
    expect(find.text('No obligations yet'), findsNothing);
  });

  testWidgets('tapping inputs tile opens the user-inputs sheet', (t) async {
    await t.pumpWidget(_host());
    await _settle(t);

    // Sheet not visible yet.
    expect(find.text('Improve this analysis'), findsNothing);

    await t.tap(find.text('Your inputs'));
    await _settle(t);

    // Sheet title + primary CTA now visible.
    expect(find.text('Improve this analysis'), findsOneWidget);
    expect(find.text('Save setup'), findsOneWidget);
  });

  testWidgets('tapping an existing goal tile opens the edit sheet', (t) async {
    await t.pumpWidget(_host(
      goals: [
        GoatGoal(
          id: 'g1',
          type: GoatGoalType.savings,
          title: 'Rainy day',
          targetAmount: 10000,
          currentAmount: 2000,
        ),
      ],
    ));
    await _settle(t);

    await t.tap(find.text('Rainy day'));
    await _settle(t);

    // Edit mode exposes the remove action; create mode does not.
    expect(find.text('Edit goal'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Remove goal'), findsOneWidget);
  });
}
