import 'package:care_navigator_ph/src/repositories/public_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emergency guidance uses database-provided values', () {
    const settings = PublicAppSettings(
      emergencyNumber: '911',
      emergencyRegion: 'the Philippines',
    );

    expect(settings.emergencyCallInstruction, 'Call 911 in the Philippines');
    expect(
      settings.emergencyHelpText,
      'Call 911 in the Philippines or go to the nearest emergency department.',
    );
  });

  test('missing database settings never invent a regional number', () {
    const settings = PublicAppSettings();

    expect(
      settings.emergencyCallInstruction,
      'Contact your local emergency services',
    );
  });
}
