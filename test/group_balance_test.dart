import 'package:billy/features/groups/group_balance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expenseNetFromRows', () {
    test('payer credited, participants debited by share', () {
      const a = 'user-a';
      const b = 'user-b';
      final net = expenseNetFromRows([
        {
          'amount': 100.0,
          'paid_by_user_id': a,
          'group_expense_participants': [
            {'user_id': a, 'share_amount': 50.0},
            {'user_id': b, 'share_amount': 50.0},
          ],
        },
      ]);
      expect(net[a], closeTo(50.0, 0.001));
      expect(net[b], closeTo(-50.0, 0.001));
    });

    test('ignores zero amount expense', () {
      final net = expenseNetFromRows([
        {
          'amount': 0.0,
          'paid_by_user_id': 'u1',
          'group_expense_participants': <Map<String, dynamic>>[],
        },
      ]);
      expect(net, isEmpty);
    });
  });

  group('applySettlements', () {
    test('payer loses net, payee gains', () {
      final net = {'p1': 10.0, 'p2': -10.0};
      final after = applySettlements(net, [
        {'payer_user_id': 'p1', 'payee_user_id': 'p2', 'amount': 10.0},
      ]);
      expect(after['p1'], closeTo(0.0, 0.001));
      expect(after['p2'], closeTo(0.0, 0.001));
    });

    test('skips invalid rows', () {
      final net = <String, double>{'a': 1};
      expect(applySettlements(net, [{'payer_user_id': null, 'payee_user_id': 'b', 'amount': 5}]), net);
    });
  });

  group('netForMembers', () {
    test('fills missing ids with 0', () {
      final out = netForMembers({'x': 2.5}, ['x', 'y']);
      expect(out['x'], 2.5);
      expect(out['y'], 0.0);
    });
  });

  group('equalSharesForUsers', () {
    test('empty ids returns empty', () {
      expect(equalSharesForUsers([], 100), isEmpty);
    });

    test('shares sum to total with last taking remainder', () {
      const ids = ['a', 'b', 'c'];
      const total = 10.0;
      final shares = equalSharesForUsers(ids, total);
      expect(shares.length, 3);
      final sum = shares.fold<double>(
        0,
        (s, m) => s + ((m['share_amount'] as num).toDouble()),
      );
      expect(sum, closeTo(total, 0.001));
      expect(shares[0]['user_id'], 'a');
      expect(shares[2]['user_id'], 'c');
      expect((shares[2]['share_amount'] as num).toDouble(), closeTo(3.34, 0.001));
    });

    test('single user gets full amount', () {
      final shares = equalSharesForUsers(['only'], 42.12);
      expect(shares.single['share_amount'], closeTo(42.12, 0.001));
    });
  });
}
