import 'package:supabase/supabase.dart';

sealed class RepositoryFailure implements Exception {
  const RepositoryFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class AuthenticationFailure extends RepositoryFailure {
  const AuthenticationFailure(super.message, {super.cause});
}

final class PermissionFailure extends RepositoryFailure {
  const PermissionFailure(super.message, {super.cause});
}

final class ValidationFailure extends RepositoryFailure {
  const ValidationFailure(super.message, {super.cause});
}

final class ContractUnavailableFailure extends RepositoryFailure {
  const ContractUnavailableFailure(super.message, {super.cause});
}

final class UnexpectedRepositoryFailure extends RepositoryFailure {
  const UnexpectedRepositoryFailure(super.message, {super.cause});
}

String userFacingRepositoryError(Object error) {
  if (error is RepositoryFailure) {
    final cause = error.cause;
    if (cause is PostgrestException) {
      return userFacingRepositoryError(cause);
    }
    if (cause is AuthException) {
      return _mapAuthException(cause);
    }
    return error.message;
  }
  if (error is PostgrestException) {
    return switch (error.code) {
      '22P02' =>
        error.message.toLowerCase().contains('consultation_type')
            ? 'The selected care mode is no longer supported. Refresh and try again.'
            : 'One of the selected values is no longer supported. Refresh and try again.',
      '23505' => 'This record already exists.',
      '23503' => 'This action is blocked by a related record.',
      '23502' => 'A required field is missing. Review the form and try again.',
      '23514' => 'The submitted values are not valid for this record.',
      '22001' => 'One of the submitted values is too long.',
      '42501' => 'You do not have permission to perform this action.',
      'PGRST116' => 'The requested record could not be found.',
      'PGRST204' =>
        'The live database contract has changed. Refresh and try again.',
      _ => _mapRepositoryMessage(error.message),
    };
  }
  if (error is AuthException) return _mapAuthException(error);
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'The submitted information is invalid.';
  }
  if (error is StateError) return _mapRepositoryMessage(error.message);
  final message = error.toString();
  return _mapRepositoryMessage(
    message
        .replaceFirst(
          RegExp(r'^[A-Za-z0-9_.$]+(?:Exception|Error)(?:\([^)]*\))?:\s*'),
          '',
        )
        .trim(),
  );
}

String _mapAuthException(AuthException error) {
  if (error.code == 'over_email_send_rate_limit') {
    return 'Too many account emails were requested. Please wait before trying again.';
  }
  return error.message;
}

String _mapRepositoryMessage(String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('invalid input value for enum consultation_type')) {
    return 'The selected care mode is no longer supported. Refresh and try again.';
  }
  if (normalized.contains('invalid input value for enum')) {
    return 'One of the selected values is no longer supported. Refresh and try again.';
  }
  if (normalized.contains('jwt') || normalized.contains('session')) {
    return 'Your secure session is no longer valid. Sign in again and retry.';
  }
  if (normalized.contains('permission') || normalized.contains('policy')) {
    return 'You do not have permission to access this information.';
  }
  if (normalized.contains('violates check constraint') ||
      normalized.contains('check constraint')) {
    return 'The submitted values are not valid for this record.';
  }
  if (normalized.contains('null value in column') ||
      normalized.contains('not-null constraint')) {
    return 'A required field is missing. Review the form and try again.';
  }
  if (normalized.contains('duplicate key') ||
      normalized.contains('already exists')) {
    return 'This record already exists.';
  }
  if (normalized.contains('foreign key constraint') ||
      normalized.contains('is still referenced')) {
    return 'This action is blocked by a related record.';
  }
  return message.isEmpty
      ? 'The database request could not be completed.'
      : message;
}
