import 'package:flutter_test/flutter_test.dart';

import 'package:billy/core/utils/document_date_range.dart';
import 'package:billy/features/dashboard/utils/dashboard_spend_math.dart';

void main() {
  test('rolling 7-day hero equals sum of daily series (matches Analytics 1W)', () {
    final wed = DateTime(2026, 4, 8); // rolling window Apr 2 … Apr 8
    final docs = <Map<String, dynamic>>[
      {'status': 'saved', 'date': '2026-04-06', 'amount': 10},
      {'status': 'saved', 'date': '2026-04-07', 'amount': 25},
      {'status': 'draft', 'date': '2026-04-07', 'amount': 999},
      {'status': 'saved', 'date': '2026-04-08', 'amount': 5},
    ];
    const basis = WeekSpendBasis.invoiceDate;
    final series = DashboardSpendMath.rollingSevenDayDailyDocumentSpend(docs, wed, basis);
    final hero = DashboardSpendMath.rollingSevenDayDocumentSpend(docs, wed, basis);
    expect(series.length, 7);
    expect(series[4], 10); // Apr 6
    expect(series[5], 25); // Apr 7
    expect(series[6], 5); // Apr 8
    expect(hero, 40);
    expect(DashboardSpendMath.debugRollingSeriesMatchesHero(docs, wed, basis), isTrue);
    expect(
      hero,
      DocumentDateRange.totalRollingSevenDaySpend(docs, DateTime(2026, 4, 8), basis),
    );
  });

  test('last calendar week excludes this week (legacy helper still used elsewhere)', () {
    final wed = DateTime(2026, 4, 8);
    final docs = <Map<String, dynamic>>[
      {'status': 'saved', 'date': '2026-03-30', 'amount': 100},
      {'status': 'saved', 'date': '2026-04-08', 'amount': 50},
    ];
    expect(DashboardSpendMath.lastCalendarWeekDocumentSpend(docs, wed, WeekSpendBasis.invoiceDate), 100);
  });

  test('rolling 7 days uses created_at when invoice date is outside window (OCR)', () {
    final wed = DateTime(2026, 4, 8);
    final docs = <Map<String, dynamic>>[
      {
        'status': 'saved',
        'date': '2024-01-15',
        'amount': 99,
        'created_at': '2026-04-07T12:00:00.000Z',
      },
    ];
    expect(DashboardSpendMath.rollingSevenDayDocumentSpend(docs, wed), 99);
    expect(DashboardSpendMath.debugRollingSeriesMatchesHero(docs, wed), isTrue);
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
