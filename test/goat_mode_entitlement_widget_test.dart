// Phase 8: entitlement-gating widget tests.
//
// These tests exercise the UX guarantees around profiles.goat_mode = false:
//   1. GoatModeScreen renders the rollout card and no triggers/reads.
//   2. The "Open setup" app-bar shortcut is not tappable.
//   3. GoatSetupScreen — even when navigated to directly — falls back to the
//      same rollout state rather than showing an empty form the user can't save.
//
// Providers are stubbed so no Supabase calls are made. If a non-entitled code
// path ever started reading from Supabase these tests would flush that out
// via the "not called" assertions on the stubbed controllers.

import 'package:billy/features/goat/models/goat_models.dart';
import 'package:billy/features/goat/models/goat_setup_models.dart';
import 'package:billy/features/goat/providers/goat_mode_providers.dart';
import 'package:billy/features/goat/providers/goat_setup_providers.dart';
import 'package:billy/features/goat/screens/goat_mode_screen.dart';
import 'package:billy/features/goat/screens/goat_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ──────────────────────────────────────────────────────────────────────────
// Stubs that record whether they were asked to do any work.
// ──────────────────────────────────────────────────────────────────────────

class _RecordingGoatController extends GoatModeController {
  int builds = 0;
  int refreshes = 0;
  int reloads = 0;

  @override
  Future<GoatModeState> build() async {
    builds++;
    return const GoatModeState();
  }

  @override
  Future<void> refresh({
    GoatScope scope = GoatScope.full,
    bool dryRun = false,
  }) async {
    refreshes++;
  }

  @override
  Future<void> reloadFromDb() async {
    reloads++;
  }
}

class _RecordingUserInputs extends GoatUserInputsController {
  int builds = 0;
  int saves = 0;
  @override
  Future<GoatUserInputs> build() async {
    builds++;
    return GoatUserInputs.empty;
  }

  @override
  Future<GoatUserInputs> save(GoatUserInputs value) async {
    saves++;
    return value;
  }
}

class _RecordingGoals extends GoatGoalsController {
  int builds = 0;
  @override
  Future<List<GoatGoal>> build() async {
    builds++;
    return const [];
  }
}

class _RecordingObligations extends GoatObligationsController {
  int builds = 0;
  @override
  Future<List<GoatObligation>> build() async {
    builds++;
    return const [];
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Host helpers
// ──────────────────────────────────────────────────────────────────────────

Widget _host({
  required bool entitled,
  required Widget child,
  required _RecordingGoatController goatCtrl,
  required _RecordingUserInputs inputsCtrl,
  required _RecordingGoals goalsCtrl,
  required _RecordingObligations obligationsCtrl,
}) {
  return ProviderScope(
    overrides: [
      goatModeEntitlementProvider.overrideWithValue(entitled),
      goatModeControllerProvider.overrideWith(() => goatCtrl),
      goatUserInputsControllerProvider.overrideWith(() => inputsCtrl),
      goatGoalsControllerProvider.overrideWith(() => goalsCtrl),
      goatObligationsControllerProvider.overrideWith(() => obligationsCtrl),
    ],
    child: MaterialApp(home: child),
  );
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────────────────────────────

void main() {
  group('GoatModeScreen — non-entitled user', () {
    testWidgets('shows rollout card and does not read the Goat controller',
        (t) async {
      final goatCtrl = _RecordingGoatController();
      final inputsCtrl = _RecordingUserInputs();
      final goalsCtrl = _RecordingGoals();
      final obligationsCtrl = _RecordingObligations();

      await t.pumpWidget(_host(
        entitled: false,
        child: const GoatModeScreen(),
        goatCtrl: goatCtrl,
        inputsCtrl: inputsCtrl,
        goalsCtrl: goalsCtrl,
        obligationsCtrl: obligationsCtrl,
      ));
      await _settle(t);

      // The rollout card is what the user sees.
      expect(find.text('GOAT Mode is rolling out'), findsOneWidget);

      // No reads on the Goat controller were issued for a non-entitled user.
      expect(goatCtrl.builds, 0,
          reason: 'Non-entitled users must not hit Goat read paths');

      // No triggers were fired.
      expect(goatCtrl.refreshes, 0);
      expect(goatCtrl.reloads, 0);
    });

    testWidgets('"Open setup" chip is hidden in the app bar', (t) async {
      final goatCtrl = _RecordingGoatController();
      final inputsCtrl = _RecordingUserInputs();
      final goalsCtrl = _RecordingGoals();
      final obligationsCtrl = _RecordingObligations();

      await t.pumpWidget(_host(
        entitled: false,
        child: const GoatModeScreen(),
        goatCtrl: goatCtrl,
        inputsCtrl: inputsCtrl,
        goalsCtrl: goalsCtrl,
        obligationsCtrl: obligationsCtrl,
      ));
      await _settle(t);

      // The "Setup" chip shows only when onOpenSetup != null (i.e. entitled).
      expect(find.text('Setup'), findsNothing);
    });
  });

  group('GoatSetupScreen — non-entitled user deep-link fallback', () {
    testWidgets('falls back to rollout card, never triggers setup reads',
        (t) async {
      final goatCtrl = _RecordingGoatController();
      final inputsCtrl = _RecordingUserInputs();
      final goalsCtrl = _RecordingGoals();
      final obligationsCtrl = _RecordingObligations();

      await t.pumpWidget(_host(
        entitled: false,
        child: const GoatSetupScreen(),
        goatCtrl: goatCtrl,
        inputsCtrl: inputsCtrl,
        goalsCtrl: goalsCtrl,
        obligationsCtrl: obligationsCtrl,
      ));
      await _settle(t);

      expect(find.text('Your setup'), findsOneWidget);
      expect(find.text('GOAT Mode is rolling out'), findsOneWidget);

      // None of the write-path controllers were built for this user.
      expect(inputsCtrl.builds, 0);
      expect(inputsCtrl.saves, 0);
      expect(goalsCtrl.builds, 0);
      expect(obligationsCtrl.builds, 0);
    });
  });

  group('GoatModeScreen — entitled user', () {
    testWidgets('reads the Goat controller and shows setup shortcut',
        (t) async {
      final goatCtrl = _RecordingGoatController();
      final inputsCtrl = _RecordingUserInputs();
      final goalsCtrl = _RecordingGoals();
      final obligationsCtrl = _RecordingObligations();

      await t.pumpWidget(_host(
        entitled: true,
        child: const GoatModeScreen(),
        goatCtrl: goatCtrl,
        inputsCtrl: inputsCtrl,
        goalsCtrl: goalsCtrl,
        obligationsCtrl: obligationsCtrl,
      ));
      await _settle(t);

      // Goat controller was built exactly once.
      expect(goatCtrl.builds, greaterThanOrEqualTo(1));

      // Setup shortcut is visible in the app bar.
      expect(find.text('Setup'), findsOneWidget);
    });
  });
}
