import 'package:billy/features/lend_borrow/lend_borrow_perspective.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const creator = 'creator-uid';
  const counterparty = 'cp-uid';

  Map<String, dynamic> row(String type) => {
        'user_id': creator,
        'counterparty_user_id': counterparty,
        'type': type,
        'counterparty_name': 'Other',
        'counterparty_profile': {'display_name': 'Counterparty Name'},
        'creator_profile': {'display_name': 'Creator Name'},
      };

  group('effectiveTypeForViewer', () {
    test('creator sees stored type', () {
      expect(effectiveTypeForViewer(row('lent'), creator), 'lent');
      expect(effectiveTypeForViewer(row('borrowed'), creator), 'borrowed');
    });

    test('counterparty sees flipped type', () {
      expect(effectiveTypeForViewer(row('lent'), counterparty), 'borrowed');
      expect(effectiveTypeForViewer(row('borrowed'), counterparty), 'lent');
    });

    test('null viewer returns stored', () {
      expect(effectiveTypeForViewer(row('borrowed'), null), 'borrowed');
    });

    test('unrelated viewer keeps stored', () {
      expect(effectiveTypeForViewer(row('lent'), 'stranger'), 'lent');
    });
  });

  group('otherPartyDisplayName', () {
    test('creator sees counterparty profile name', () {
      expect(otherPartyDisplayName(row('lent'), creator), 'Counterparty Name');
    });

    test('counterparty sees creator profile name', () {
      expect(otherPartyDisplayName(row('lent'), counterparty), 'Creator Name');
    });

    test('null viewer uses counterparty_name from row', () {
      expect(otherPartyDisplayName(row('lent'), null), 'Other');
    });
  });

  group('lendBorrowRoleLine', () {
    test('matches effective type', () {
      expect(lendBorrowRoleLine(row('lent'), creator), 'You lent');
      expect(lendBorrowRoleLine(row('lent'), counterparty), 'You borrowed');
    });
  });
}
