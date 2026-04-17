// Pure-logic tests for Goat Mode view-model parsing.
// No Supabase / Flutter framework needed.

import 'package:billy/features/goat/models/goat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoatScope', () {
    test('parses valid wire values', () {
      expect(GoatScope.fromWire('cashflow'), GoatScope.cashflow);
      expect(GoatScope.fromWire('budgets'), GoatScope.budgets);
      expect(GoatScope.fromWire('full'), GoatScope.full);
    });

    test('falls back to overview on unknown', () {
      expect(GoatScope.fromWire(null), GoatScope.overview);
      expect(GoatScope.fromWire(''), GoatScope.overview);
      expect(GoatScope.fromWire('garbage'), GoatScope.overview);
    });

    test('userVisible never includes `full`', () {
      expect(GoatScope.userVisible.contains(GoatScope.full), isFalse);
    });
  });

  group('GoatJobStatus', () {
    test('isTerminal classification', () {
      expect(GoatJobStatus.queued.isTerminal, isFalse);
      expect(GoatJobStatus.running.isTerminal, isFalse);
      expect(GoatJobStatus.succeeded.isTerminal, isTrue);
      expect(GoatJobStatus.partial.isTerminal, isTrue);
      expect(GoatJobStatus.failed.isTerminal, isTrue);
      expect(GoatJobStatus.cancelled.isTerminal, isTrue);
    });

    test('unknown is not active and not terminal', () {
      expect(GoatJobStatus.unknown.isTerminal, isFalse);
      expect(GoatJobStatus.unknown.isActive, isFalse);
    });

    test('fromWire maps strings', () {
      expect(GoatJobStatus.fromWire('running'), GoatJobStatus.running);
      expect(GoatJobStatus.fromWire('succeeded'), GoatJobStatus.succeeded);
      expect(GoatJobStatus.fromWire('unknown_val'), GoatJobStatus.unknown);
    });
  });

  group('GoatReadiness', () {
    test('progress monotonic', () {
      expect(GoatReadiness.l1.progress, lessThan(GoatReadiness.l2.progress));
      expect(GoatReadiness.l2.progress, lessThan(GoatReadiness.l3.progress));
    });
  });

  group('GoatJob.fromRow', () {
    test('parses a minimal running row', () {
      final j = GoatJob.fromRow({
        'id': 'j1',
        'user_id': 'u1',
        'scope': 'full',
        'status': 'running',
        'readiness_level': null,
        'error_message': null,
        'started_at': '2026-04-17T10:00:00Z',
        'finished_at': null,
        'created_at': '2026-04-17T09:59:58Z',
      });
      expect(j.id, 'j1');
      expect(j.scope, GoatScope.full);
      expect(j.status, GoatJobStatus.running);
      expect(j.readiness, isNull);
      expect(j.startedAt, isNotNull);
      expect(j.finishedAt, isNull);
    });
  });

  group('GoatSnapshot.fromRow', () {
    test('decodes nested json columns safely', () {
      final snap = GoatSnapshot.fromRow({
        'id': 's1',
        'user_id': 'u1',
        'scope': 'full',
        'readiness_level': 'L2',
        'snapshot_status': 'completed',
        'data_fingerprint': 'fp-abc',
        'generated_at': '2026-04-17T10:05:00Z',
        'coverage_json': {
          'coverage_score': 0.72,
          'missing_inputs': [
            {
              'key': 'income_declared',
              'label': 'Add your monthly income',
              'why': 'Unlocks cashflow projections.',
              'unlocks': ['cashflow', 'goals'],
              'severity': 'info',
            },
          ],
        },
        'summary_json': {
          'narrative': ['Spend is within your usual range this month.'],
          'headline_metrics': [
            {'key': 'cashflow_30d_net', 'value': 120.5, 'unit': 'INR'},
          ],
        },
        'metrics_json': {
          'cashflow': {
            'metrics': [
              {'key': 'net_cash', 'value': 120.5, 'unit': 'INR'},
            ],
          },
        },
        'forecast_json': {},
        'anomalies_json': {},
        'risk_json': {},
        'recommendations_summary_json': {},
        'ai_layer': {},
      });

      expect(snap.id, 's1');
      expect(snap.readiness, GoatReadiness.l2);
      expect(snap.coverageScore, closeTo(0.72, 1e-9));
      expect(snap.missingInputs, hasLength(1));
      expect(snap.missingInputs.first.key, 'income_declared');
      expect(snap.narrativeBullets, hasLength(1));
      expect(snap.headlineMetrics, hasLength(1));
      expect(snap.metricsForScope(GoatScope.cashflow), hasLength(1));
      expect(snap.metricsForScope(GoatScope.budgets), isEmpty);
      expect(snap.ai, isNull);
    });

    test('isPartial/isFailed flags reflect snapshot_status', () {
      final partial = GoatSnapshot.fromRow(_minSnapRow(status: 'partial'));
      final failed = GoatSnapshot.fromRow(_minSnapRow(status: 'failed'));
      final ok = GoatSnapshot.fromRow(_minSnapRow(status: 'completed'));
      expect(partial.isPartial, isTrue);
      expect(failed.isFailed, isTrue);
      expect(ok.isPartial, isFalse);
      expect(ok.isFailed, isFalse);
    });
  });

  group('GoatRecommendation.fromRow', () {
    test('parses severity, priority, falls back gracefully', () {
      final r = GoatRecommendation.fromRow({
        'id': 'r1',
        'user_id': 'u1',
        'recommendation_kind': 'budget_overrun',
        'severity': 'warn',
        'priority': 82,
        'confidence': 0.7,
        'impact_score': 0.8,
        'effort_score': 0.2,
        'rec_fingerprint': 'fp1',
        'status': 'open',
        'observation_json': {'summary': 'Dining is trending hot.'},
        'recommendation_json': {'title': 'Trim dining by 20%'},
      });
      expect(r.severity, GoatRecSeverity.warn);
      expect(r.priority, 82);
      expect(r.confidence, 0.7);
      expect(r.titleFor(), 'Trim dining by 20%');
      expect(r.bodyFor(), 'Dining is trending hot.');
    });

    test('AI phrasing by fingerprint wins over deterministic copy', () {
      final r = GoatRecommendation.fromRow({
        'id': 'r1',
        'user_id': 'u1',
        'recommendation_kind': 'budget_overrun',
        'severity': 'info',
        'priority': 50,
        'rec_fingerprint': 'fp-ai',
        'status': 'open',
        'observation_json': {},
        'recommendation_json': {'title': 'Plain title'},
      });
      expect(
        r.titleFor(aiTitleByFingerprint: const {'fp-ai': 'Sharper title'}),
        'Sharper title',
      );
    });
  });

  group('GoatAIView.fromMap', () {
    test('returns an AI-less view when envelope missing', () {
      final v = GoatAIView.fromMap({'ai_validated': false, 'fallback_used': true});
      expect(v.narrativeSummary, isNull);
      expect(v.pillars, isEmpty);
      expect(v.fallbackUsed, isTrue);
      expect(v.validated, isFalse);
    });

    test('extracts phrasing maps keyed by fingerprint', () {
      final v = GoatAIView.fromMap({
        'ai_validated': true,
        'envelope': {
          'narrative_summary': 'You are on track.',
          'pillars': [
            {
              'pillar': 'cashflow',
              'observation': 'Income covered spend.',
              'inference': 'Runway looks healthy.',
              'confidence': 'medium',
            },
          ],
          'recommendation_phrasings': [
            {
              'rec_fingerprint': 'fp1',
              'title': 'Pay yourself first',
              'body': 'Automate 10% to savings.',
              'why_shown': 'Dining climbed 18% vs trend.',
            },
          ],
          'missing_input_prompts': [
            {
              'input_key': 'income_declared',
              'title': 'Add your income',
              'body': 'Unlocks runway math.',
            },
          ],
        },
      });
      expect(v.validated, isTrue);
      expect(v.narrativeSummary, 'You are on track.');
      expect(v.pillars, hasLength(1));
      expect(v.phrasingTitleByFingerprint['fp1'], 'Pay yourself first');
      expect(v.phrasingWhyByFingerprint['fp1'], contains('18%'));
      expect(v.missingPrompts, hasLength(1));
    });
  });
}

Map<String, dynamic> _minSnapRow({required String status}) => {
      'id': 's',
      'user_id': 'u',
      'scope': 'full',
      'readiness_level': 'L1',
      'snapshot_status': status,
      'data_fingerprint': 'fp',
      'generated_at': '2026-04-17T10:00:00Z',
      'coverage_json': {},
      'summary_json': {},
      'metrics_json': {},
      'forecast_json': {},
      'anomalies_json': {},
      'risk_json': {},
      'recommendations_summary_json': {},
      'ai_layer': {},
    };
