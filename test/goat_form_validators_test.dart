// Validators for Goat Mode setup sheets. These are pure functions used by
// every TextFormField in the inputs/goal/obligation sheets — exhaustive
// coverage here means the forms can't ship a broken required/range check.

import 'package:billy/features/goat/widgets/goat_form_primitives.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('goatValidateRequiredText', () {
    test('null or blank rejects with field label', () {
      expect(
        goatValidateRequiredText(null, fieldLabel: 'A title'),
        contains('A title'),
      );
      expect(
        goatValidateRequiredText('   ', fieldLabel: 'Title'),
        contains('Title'),
      );
    });

    test('non-blank passes', () {
      expect(goatValidateRequiredText('Emergency fund'), isNull);
      expect(goatValidateRequiredText(' a '), isNull);
    });
  });

  group('goatValidatePositiveAmount', () {
    test('empty is rejected when required (default)', () {
      expect(goatValidatePositiveAmount(''), isNotNull);
      expect(goatValidatePositiveAmount('   '), isNotNull);
    });

    test('empty is allowed when required=false', () {
      expect(goatValidatePositiveAmount('', required: false), isNull);
      expect(goatValidatePositiveAmount(null, required: false), isNull);
    });

    test('non-numeric → "Enter a number"', () {
      expect(goatValidatePositiveAmount('abc'), 'Enter a number');
    });

    test('zero and negative are rejected', () {
      expect(goatValidatePositiveAmount('0'), isNotNull);
      expect(goatValidatePositiveAmount('-5'), isNotNull);
    });

    test('max bound is enforced', () {
      expect(goatValidatePositiveAmount('150', max: 100), 'Too large');
      expect(goatValidatePositiveAmount('99', max: 100), isNull);
    });

    test('positive decimals pass', () {
      expect(goatValidatePositiveAmount('0.5'), isNull);
      expect(goatValidatePositiveAmount('12345.67'), isNull);
    });
  });

  group('goatValidateNonNegativeAmount', () {
    test('empty passes by default (field is optional)', () {
      expect(goatValidateNonNegativeAmount(''), isNull);
      expect(goatValidateNonNegativeAmount(null), isNull);
    });

    test('empty fails when required=true', () {
      expect(
        goatValidateNonNegativeAmount('', required: true),
        isNotNull,
      );
    });

    test('negative is rejected; zero is fine', () {
      expect(goatValidateNonNegativeAmount('-1'), isNotNull);
      expect(goatValidateNonNegativeAmount('0'), isNull);
      expect(goatValidateNonNegativeAmount('0.0'), isNull);
    });

    test('max bound is enforced', () {
      expect(goatValidateNonNegativeAmount('200', max: 120), 'Too large');
    });

    test('non-numeric rejected', () {
      expect(goatValidateNonNegativeAmount('hello'), 'Enter a number');
    });
  });

  group('goatValidateIntRange', () {
    test('empty passes when optional, fails when required', () {
      expect(goatValidateIntRange('', min: 1, max: 31), isNull);
      expect(
        goatValidateIntRange('', min: 1, max: 31, required: true),
        isNotNull,
      );
    });

    test('non-integer is rejected', () {
      expect(
        goatValidateIntRange('1.5', min: 1, max: 31),
        'Enter a whole number',
      );
      expect(
        goatValidateIntRange('abc', min: 1, max: 31),
        'Enter a whole number',
      );
    });

    test('out-of-range values are rejected with the range in the message', () {
      expect(goatValidateIntRange('0', min: 1, max: 31), contains('1 and 31'));
      expect(goatValidateIntRange('32', min: 1, max: 31), contains('1 and 31'));
    });

    test('in-range boundaries pass', () {
      expect(goatValidateIntRange('1', min: 1, max: 31), isNull);
      expect(goatValidateIntRange('31', min: 1, max: 31), isNull);
      expect(goatValidateIntRange('16', min: 1, max: 31), isNull);
    });
  });
}
