// Widget tests for the main Goat Mode surface.
//
// We override `goatModeControllerProvider` and `goatModeEntitlementProvider`
// with fixed states so we can exercise each render path without Supabase.
// These tests verify screen-level smoke behaviour for the key states — they
// are intentionally lightweight and focus on UX regressions (e.g. header,
// first-run CTA, recommendation cards, missing-inputs, scope switcher).

import 'package:billy/core/theme/billy_theme.dart';
import 'package:billy/features/goat/models/goat_models.dart';
import 'package:billy/features/goat/models/goat_setup_models.dart';
import 'package:billy/features/goat/providers/goat_mode_providers.dart';
import 'package:billy/features/goat/providers/goat_setup_providers.dart';
import 'package:billy/features/goat/screens/goat_mode_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubController extends GoatModeController {
  final GoatModeState initial;
  _StubController(this.initial);

  @override
  Future<GoatModeState> build() async {
    // ignore: unnecessary_overrides
    return initial;
  }

  @override
  Future<void> refresh({GoatScope scope = GoatScope.full, bool dryRun = false}) async {
    // no-op for widget tests
  }

  @override
  Future<void> reloadFromDb() async {
    // no-op
  }
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

Widget _host(
  GoatModeState state, {
  bool entitled = true,
  GoatUserInputs? inputs,
  List<GoatGoal>? goals,
  List<GoatObligation>? obligations,
}) {
  return ProviderScope(
    overrides: [
      goatModeEntitlementProvider.overrideWithValue(entitled),
      goatModeControllerProvider.overrideWith(() => _StubController(state)),
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
    child: const MaterialApp(
      home: GoatModeScreen(),
    ),
  );
}

Future<void> _settle(WidgetTester t) async {
  // Pump a few frames but avoid pumpAndSettle — several repeating shimmer /
  // pulsing animations never actually settle and would hang the test.
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

GoatSnapshot _snap({
  String status = 'completed',
  String readiness = 'L2',
  Map<String, dynamic>? coverage,
  Map<String, dynamic>? summary,
  Map<String, dynamic>? metrics,
  Map<String, dynamic>? aiLayer,
}) {
  return GoatSnapshot.fromRow({
    'id': 's',
    'user_id': 'u',
    'scope': 'full',
    'readiness_level': readiness,
    'snapshot_status': status,
    'data_fingerprint': 'fp',
    'generated_at': DateTime.now().toIso8601String(),
    'coverage_json': coverage ?? {'coverage_score': 0.6},
    'summary_json': summary ?? {},
    'metrics_json': metrics ?? {},
    'forecast_json': {},
    'anomalies_json': {},
    'risk_json': {},
    'recommendations_summary_json': {},
    'ai_layer': aiLayer ?? {},
  });
}

GoatRecommendation _rec({
  String id = 'r1',
  String fp = 'fp1',
  String severity = 'warn',
  int priority = 80,
  String title = 'Trim dining this week',
}) {
  return GoatRecommendation.fromRow({
    'id': id,
    'user_id': 'u',
    'recommendation_kind': 'budget_overrun',
    'severity': severity,
    'priority': priority,
    'rec_fingerprint': fp,
    'status': 'open',
    'observation_json': {'summary': 'Dining is trending 18% above usual.'},
    'recommendation_json': {'title': title},
  });
}

void main() {
  testWidgets('not-entitled renders the rollout message', (t) async {
    await t.pumpWidget(_host(const GoatModeState(), entitled: false));
    await _settle(t);

    expect(find.text('GOAT Mode is rolling out'), findsOneWidget);
    // Never shows the hero when not entitled
    expect(find.text('Refresh'), findsNothing);
  });

  testWidgets('first-run state shows the CTA button', (t) async {
    await t.pumpWidget(_host(const GoatModeState()));
    await _settle(t);

    expect(find.text('Run my first analysis'), findsOneWidget);
    expect(find.text('Your first GOAT snapshot'), findsOneWidget);
  });

  testWidgets('live surface renders hero + readiness when snapshot exists',
      (t) async {
    final snap = _snap(coverage: {
      'coverage_score': 0.65,
      'missing_inputs': [],
    });
    await t.pumpWidget(_host(GoatModeState(
      latestSnapshot: snap,
      lastRefreshedAt: snap.generatedAt,
    )));
    await _settle(t);

    expect(find.text('GOAT Mode'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    // Readiness strip title
    expect(find.text('Good coverage'), findsOneWidget);
  });

  testWidgets('recommendations list renders up to 3 cards', (t) async {
    final snap = _snap();
    await t.pumpWidget(_host(GoatModeState(
      latestSnapshot: snap,
      lastRefreshedAt: snap.generatedAt,
      recommendations: [
        _rec(id: 'a', fp: 'fa', title: 'Trim dining'),
        _rec(id: 'b', fp: 'fb', title: 'Review duplicates'),
        _rec(id: 'c', fp: 'fc', title: 'Watch runway'),
        _rec(id: 'd', fp: 'fd', title: 'Catch-up receipts'),
      ],
    )));
    await _settle(t);

    // "Top of mind" section lives below the setup card — scroll to it so
    // the ListView materializes its recommendation children.
    await t.dragUntilVisible(
      find.text('Top of mind'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await _settle(t);
    expect(find.text('Top of mind'), findsOneWidget);
    expect(find.text('Trim dining'), findsOneWidget);
    // 3rd+ cards may be below the 600px test viewport (lazy ListView) —
    // scroll to surface each before asserting.
    await t.dragUntilVisible(
      find.text('Review duplicates'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Review duplicates'), findsOneWidget);
    await t.dragUntilVisible(
      find.text('Watch runway'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await _settle(t);
    expect(find.text('Watch runway'), findsOneWidget);
    // 4th is behind the "See more" link — never rendered inline.
    expect(find.text('Catch-up receipts'), findsNothing);
  });

  testWidgets('tapping a recommendation expands the why-block', (t) async {
    final snap = _snap();
    await t.pumpWidget(_host(GoatModeState(
      latestSnapshot: snap,
      lastRefreshedAt: snap.generatedAt,
      recommendations: [
        GoatRecommendation.fromRow({
          'id': 'r1',
          'user_id': 'u',
          'recommendation_kind': 'budget_overrun',
          'severity': 'warn',
          'priority': 80,
          'rec_fingerprint': 'fp1',
          'status': 'open',
          'observation_json': {
            'summary': 'Dining is hot.',
            'why': 'Dining outpaced last 4 weeks by 18%.',
          },
          'recommendation_json': {'title': 'Trim dining'},
        }),
      ],
    )));
    await _settle(t);

    expect(find.text('Why this matters'), findsNothing);
    // Scroll the screen's vertical ListView (there's also a horizontal
    // scope switcher ListView) until the target recommendation is
    // comfortably inside the viewport, then tap via ensureVisible so the
    // tap offset is valid.
    final verticalList = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    await t.dragUntilVisible(
      find.text('Trim dining'),
      verticalList,
      const Offset(0, -200),
    );
    await t.ensureVisible(find.text('Trim dining'));
    await _settle(t);
    await t.tap(find.text('Trim dining'));
    await _settle(t);
    expect(find.text('Why this matters'), findsOneWidget);
    expect(find.textContaining('outpaced last 4 weeks'), findsOneWidget);
  });

  testWidgets('missing-input prompt renders and opens a sheet on tap',
      (t) async {
    final snap = _snap(coverage: {
      'coverage_score': 0.4,
      'missing_inputs': [
        {
          'key': 'income_declared',
          'label': 'Tell us your monthly income',
          'why': 'Unlocks cashflow projections and runway math.',
          'unlocks': ['cashflow', 'goals'],
          'severity': 'info',
        },
      ],
    });
    await t.pumpWidget(_host(GoatModeState(
      latestSnapshot: snap,
      lastRefreshedAt: snap.generatedAt,
    )));
    await _settle(t);

    final verticalList = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    await t.dragUntilVisible(
      find.text('Unlock more'),
      verticalList,
      const Offset(0, -200),
    );
    expect(find.text('Unlock more'), findsOneWidget);
    expect(find.text('Tell us your monthly income'), findsOneWidget);

    await t.ensureVisible(find.text('Tell us your monthly income'));
    await _settle(t);
    await t.tap(find.text('Tell us your monthly income'));
    await _settle(t);

    // Phase 7: the missing-input handoff opens the real user-inputs form
    // sheet. "Save setup" is a unique marker for the sheet's primary CTA.
    expect(find.text('Save setup'), findsOneWidget);
  });

  testWidgets('scope switcher swaps detail content', (t) async {
    final snap = _snap(
      metrics: {
        'overview': {
          'metrics': [
            {'key': 'overview_a', 'value': 12, 'unit': 'count'},
          ],
        },
        'budgets': {
          'metrics': [
            {'key': 'budgets_a', 'value': 34, 'unit': 'count'},
          ],
        },
      },
    );
    await t.pumpWidget(_host(GoatModeState(
      latestSnapshot: snap,
      lastRefreshedAt: snap.generatedAt,
    )));
    await _settle(t);

    // Scope switcher lives below the setup card — scroll the vertical
    // ListView (the horizontal scope strip is also a ListView) to bring
    // the detail row into view.
    final verticalList = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    await t.dragUntilVisible(
      find.text('Overview A'),
      verticalList,
      const Offset(0, -200),
    );
    await _settle(t);
    expect(find.text('Overview A'), findsOneWidget);
    expect(find.text('Budgets A'), findsNothing);

    await t.ensureVisible(find.text('Budgets'));
    await _settle(t);
    await t.tap(find.text('Budgets'));
    await _settle(t);

    expect(find.text('Budgets A'), findsOneWidget);
  });

  testWidgets('partial snapshot shows the soft partial stripe', (t) async {
    final snap = _snap(status: 'partial');
    await t.pumpWidget(_host(GoatModeState(
      latestSnapshot: snap,
      lastRefreshedAt: snap.generatedAt,
    )));
    await _settle(t);

    expect(
      find.textContaining('partial read'),
      findsOneWidget,
    );
  });

  testWidgets('error state shows retry and preserves prior snapshot',
      (t) async {
    final snap = _snap();
    await t.pumpWidget(_host(GoatModeState(
      latestSnapshot: snap,
      lastRefreshedAt: snap.generatedAt,
      errorMessage: 'Refresh is taking longer than usual.',
      pollingTimedOut: true,
    )));
    await _settle(t);

    // Snapshot still rendered underneath the banner
    expect(find.text('GOAT Mode'), findsOneWidget);
    expect(find.textContaining('taking longer'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  // Keeps the test set self-contained from theme tokens we reference.
  test('theme tokens referenced by Goat widgets compile', () {
    // Static references — if any constant is removed the file won't compile.
    expect(BillyTheme.emerald600, isA<Color>());
    expect(BillyTheme.gray100, isA<Color>());
  });
}
