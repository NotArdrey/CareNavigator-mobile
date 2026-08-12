import 'package:care_navigator_ph/src/models/consultation_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes every supported in-person alias to the live enum value', () {
    for (final value in const [
      'face_to_face',
      'in_person',
      'in-person',
      'in person',
      'inPerson',
    ]) {
      expect(ConsultationType.normalize(value), ConsultationType.faceToFace);
    }
  });

  test('preserves online and rejects unsupported consultation types', () {
    expect(ConsultationType.normalize('online'), ConsultationType.online);
    expect(() => ConsultationType.normalize('telephone'), throwsArgumentError);
  });
}
