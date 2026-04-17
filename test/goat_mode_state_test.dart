// Pure-logic tests for GoatModeState — the immutable struct the screen reads.

import 'package:billy/features/goat/models/goat_models.dart';
import 'package:billy/features/goat/providers/goat_mode_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoatModeState', () {
    test('default is first-load state', () {
      const s = GoatModeState();
      expect(s.isFirstLoad, isTrue);
      expect(s.hasSnapshot, isFalse);
      expect(s.isRefreshing, isFalse);
      expect(s.effectiveStatus, GoatJobStatus.unknown);
    });

    test('isRefreshing implies queued status when no job yet', () {
      const s = GoatModeState(isRefreshing: true);
      expect(s.effectiveStatus, GoatJobStatus.queued);
    });

    test('copyWith preserves non-provided fields and allows null-error reset', () {
      final snap = _snapshot();
      final s = const GoatModeState().copyWith(
        latestSnapshot: snap,
        errorMessage: 'something',
      );
      expect(s.latestSnapshot, isNotNull);
      expect(s.errorMessage, 'something');

      final cleared = s.copyWith(errorMessage: null);
      expect(cleared.latestSnapshot, isNotNull); // preserved
      expect(cleared.errorMessage, isNull);
    });

    test('copyWith keeps old error if errorMessage omitted', () {
      final s = const GoatModeState()
          .copyWith(errorMessage: 'boom')
          .copyWith(isRefreshing: true);
      expect(s.errorMessage, 'boom'); // still there
      expect(s.isRefreshing, isTrue);
    });

    test('hasSnapshot becomes true with a snapshot', () {
      final s = const GoatModeState().copyWith(latestSnapshot: _snapshot());
      expect(s.hasSnapshot, isTrue);
      expect(s.isFirstLoad, isFalse);
    });
  });
}

GoatSnapshot _snapshot() => GoatSnapshot.fromRow({
      'id': 's',
      'user_id': 'u',
      'scope': 'full',
      'readiness_level': 'L2',
      'snapshot_status': 'completed',
      'data_fingerprint': 'fp',
      'generated_at': DateTime.now().toIso8601String(),
      'coverage_json': {'coverage_score': 0.6},
      'summary_json': {},
      'metrics_json': {},
      'forecast_json': {},
      'anomalies_json': {},
      'risk_json': {},
      'recommendations_summary_json': {},
      'ai_layer': {},
    });
