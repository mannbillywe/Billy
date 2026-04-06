import 'package:flutter_test/flutter_test.dart';

import 'package:billy/core/utils/document_date_range.dart';
import 'package:billy/features/dashboard/utils/dashboard_spend_math.dart';

void main() {
  test('this week hero equals sum of daily series Mon through today', () {
    final monday = DateTime(2026, 4, 6); // Monday
    final docs = <Map<String, dynamic>>[
      {'status': 'saved', 'date': '2026-04-06', 'amount': 10},
      {'status': 'saved', 'date': '2026-04-07', 'amount': 25},
      {'status': 'draft', 'date': '2026-04-07', 'amount': 999},
      {'status': 'saved', 'date': '2026-04-08', 'amount': 5},
    ];
    const basis = WeekSpendBasis.invoiceDate;
    final series = DashboardSpendMath.thisWeekDailyDocumentSpend(docs, monday.add(const Duration(days: 2)), basis);
    final hero = DashboardSpendMath.thisWeekDocumentSpend(docs, monday.add(const Duration(days: 2)), basis);
    expect(series[0], 10);
    expect(series[1], 25);
    expect(series[2], 5);
    expect(series[3], 0);
    var sum = 0.0;
    for (var i = 0; i < 3; i++) {
      sum += series[i];
    }
    expect(sum, hero);
    expect(hero, 40);
    expect(
      DashboardSpendMath.debugSeriesMatchesHero(docs, monday.add(const Duration(days: 2))),
      isTrue,
    );
  });

  test('last calendar week excludes this week', () {
    final wed = DateTime(2026, 4, 8);
    final docs = <Map<String, dynamic>>[
      {'status': 'saved', 'date': '2026-03-30', 'amount': 100},
      {'status': 'saved', 'date': '2026-04-08', 'amount': 50},
    ];
    expect(DashboardSpendMath.lastCalendarWeekDocumentSpend(docs, wed, WeekSpendBasis.invoiceDate), 100);
  });

  test('this week uses created_at when invoice date is outside the week (OCR)', () {
    final wed = DateTime(2026, 4, 8);
    final docs = <Map<String, dynamic>>[
      {
        'status': 'saved',
        'date': '2024-01-15',
        'amount': 99,
        'created_at': '2026-04-07T12:00:00.000Z',
      },
    ];
    expect(DashboardSpendMath.thisWeekDocumentSpend(docs, wed), 99);
    expect(DashboardSpendMath.debugSeriesMatchesHero(docs, wed), isTrue);
  });

  test('thisWeekDailyLendBorrow buckets pending entries by created_at (viewer = creator)', () {
    final wed = DateTime(2026, 4, 9); // Thu week Mon 2026-04-06
    const viewer = '11111111-1111-1111-1111-111111111111';
    final entries = <Map<String, dynamic>>[
      {
        'status': 'pending',
        'user_id': viewer,
        'type': 'lent',
        'amount': 10,
        'created_at': '2026-04-06T10:00:00.000Z',
        'counterparty_user_id': null,
      },
      {
        'status': 'pending',
        'user_id': viewer,
        'type': 'borrowed',
        'amount': 4,
        'created_at': '2026-04-08T10:00:00.000Z',
        'counterparty_user_id': null,
      },
    ];
    final s = DashboardSpendMath.thisWeekDailyLendBorrow(entries, viewer, wed);
    expect(s.collect[0], 10);
    expect(s.pay[0], 0);
    expect(s.collect[2], 0);
    expect(s.pay[2], 4);
    expect(DashboardSpendMath.debugLendWeekSeriesMatchesTotals(entries, viewer, wed), isTrue);
  });
}
