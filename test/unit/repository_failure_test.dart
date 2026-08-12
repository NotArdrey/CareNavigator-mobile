import 'package:care_navigator_ph/src/repositories/repository_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  test('maps the consultation enum error to actionable copy', () {
    final error = PostgrestException(
      message: 'invalid input value for enum consultation_type: "in_person"',
      code: '22P02',
      details: '',
      hint: '',
    );

    expect(
      userFacingRepositoryError(error),
      'The selected care mode is no longer supported. Refresh and try again.',
    );
  });

  test('preserves actionable database details through wrapped failures', () {
    final error = PermissionFailure(
      'The appointment could not be booked.',
      cause: PostgrestException(
        message: 'invalid input value for enum consultation_type: "in_person"',
        code: '22P02',
      ),
    );

    expect(
      userFacingRepositoryError(error),
      'The selected care mode is no longer supported. Refresh and try again.',
    );
  });
}
