import 'package:care_navigator_ph/src/features/auth/auth_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email validation', () {
    test('accepts a conventional address and trims surrounding whitespace', () {
      expect(isValidEmailAddress(' patient@example.com '), isTrue);
    });

    test('rejects incomplete addresses', () {
      expect(isValidEmailAddress('patient'), isFalse);
      expect(isValidEmailAddress('patient@example'), isFalse);
      expect(isValidEmailAddress('@example.com'), isFalse);
    });
  });

  group('password validation', () {
    test('requires length, lowercase, uppercase, and a number', () {
      expect(passwordValidationError('Short1'), 'Use at least 10 characters.');
      expect(
        passwordValidationError('UPPERCASE12'),
        'Add at least one lowercase letter.',
      );
      expect(
        passwordValidationError('lowercase12'),
        'Add at least one uppercase letter.',
      );
      expect(
        passwordValidationError('NoNumberHere'),
        'Add at least one number.',
      );
    });

    test('accepts a qualifying password', () {
      expect(passwordValidationError('PatientPass1'), isNull);
    });

    test(
      'sign-in accepts an existing password without enforcing reset rules',
      () {
        expect(signInPasswordValidationError('pass123'), isNull);
        expect(signInPasswordValidationError(''), 'Enter your password.');
      },
    );
  });
}
