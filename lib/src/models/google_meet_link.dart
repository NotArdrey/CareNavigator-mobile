Uri parseGoogleMeetLink(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (trimmed.length > 2048 ||
      !trimmed.toLowerCase().startsWith('https://meet.google.com/') ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.host.toLowerCase() != 'meet.google.com' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      !RegExp(
        r'^/[a-z]{3}-[a-z]{4}-[a-z]{3}/?$',
      ).hasMatch(uri.path.toLowerCase())) {
    throw const FormatException(
      'Enter a Google Meet link such as https://meet.google.com/abc-defg-hij.',
    );
  }
  return Uri.https(
    'meet.google.com',
    uri.path.toLowerCase().replaceFirst(RegExp(r'/$'), ''),
  );
}
