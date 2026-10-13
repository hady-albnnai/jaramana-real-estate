import 'package:flutter_test/flutter_test.dart';
import 'package:jaramana_real_estate/core/validation/input_validators.dart';

void main() {
  group('InputValidators', () {
    test('validates username format', () {
      expect(InputValidators.validateUsername('valid_user.1'), isNull);
      expect(InputValidators.validateUsername('bad user'), isNotNull);
      expect(InputValidators.validateUsername('ab'), isNotNull);
    });

    test('validates Syrian phone formats', () {
      expect(InputValidators.validateSyrianPhone('0912345678'), isNull);
      expect(InputValidators.validateSyrianPhone('+963912345678'), isNull);
      expect(InputValidators.validateSyrianPhone('123'), isNotNull);
    });

    test('cleans control characters and trims spaces', () {
      expect(InputValidators.cleanText('  hello\n world  '), 'hello world');
    });

    test('requires stronger password length', () {
      expect(InputValidators.validatePassword('1234567'), isNotNull);
      expect(InputValidators.validatePassword('12345678'), isNull);
    });
  });
}
