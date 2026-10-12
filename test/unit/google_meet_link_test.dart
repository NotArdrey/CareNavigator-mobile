import 'package:care_navigator_ph/src/models/google_meet_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google Meet links discard account and tracking parameters', () {
    expect(
      parseGoogleMeetLink(
        ' https://meet.google.com/abc-defg-hij/?authuser=1#ignored ',
      ).toString(),
      'https://meet.google.com/abc-defg-hij',
    );
  });
  for (final value in [
    '',
    'http://meet.google.com/abc-defg-hij',
    'https://meet.google.com.evil.test/abc-defg-hij',
    'https://meet.google.com@evil.test/abc-defg-hij',
    'https://user@meet.google.com/abc-defg-hij',
    'https://meet.google.com:443/abc-defg-hij',
    'https://meet.google.com/not-a-meeting',
    'javascript:alert(1)',
    'https://meet.google.com/abc-defg-hij/other',
    'https://meet.jit.si/abc-defg-hij',
  ]) {
    test('rejects an unsupported meeting address: $value', () {
      expect(() => parseGoogleMeetLink(value), throwsFormatException);
    });
  }
}
