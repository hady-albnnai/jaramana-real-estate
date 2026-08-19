import 'package:flutter_test/flutter_test.dart';
import 'package:sweeda_real_estate/core/utils/error_utils.dart';

void main() {
  group('ErrorUtils', () {
    test('normalizes known server error codes embedded in exceptions', () {
      expect(
        ErrorUtils.normalize(Exception('PostgrestException: ADMIN_SESSION_REQUIRED')),
        'ADMIN_SESSION_REQUIRED',
      );
    });

    test('returns Arabic message for invalid admin session', () {
      expect(
        ErrorUtils.arabicMessage('INVALID_SESSION'),
        contains('جلسة الإدارة'),
      );
    });

    test('generalizes pure-latin unknown errors to UNKNOWN_ERROR (I18N-ERR-001)', () {
      final longError = 'x' * 300;
      expect(ErrorUtils.normalize(longError), 'UNKNOWN_ERROR');
    });

    test('truncates long Arabic unknown errors to 220 chars', () {
      final longArabic = 'ع' * 300;
      expect(ErrorUtils.normalize(longArabic).length, 220);
    });
  });
}
