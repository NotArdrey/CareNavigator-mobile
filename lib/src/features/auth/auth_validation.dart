import '../../models/shared/patient_identity.dart';

bool isValidEmailAddress(String value) => validateEmailAddress(value) == null;

String? passwordValidationError(String? value) {
  final password = value ?? '';
  if (password.length < 10) return 'Use at least 10 characters.';
  if (!RegExp('[a-z]').hasMatch(password)) {
    return 'Add at least one lowercase letter.';
  }
  if (!RegExp('[A-Z]').hasMatch(password)) {
    return 'Add at least one uppercase letter.';
  }
  if (!RegExp(r'\d').hasMatch(password)) {
    return 'Add at least one number.';
  }
  return null;
}

String? signInPasswordValidationError(String? value) =>
    (value?.isNotEmpty ?? false) ? null : 'Enter your password.';
