import 'package:care_navigator_ph/src/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('accepts a Supabase URL and modern publishable key', () {
      const config = AppConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
      );
      expect(config.isConfigured, isTrue);
    });

    test('rejects missing or server-side credentials', () {
      const config = AppConfig(
        supabaseUrl: '',
        supabasePublishableKey: 'service-role-secret',
      );
      expect(config.isConfigured, isFalse);
    });

    test('parses the bundled public client configuration', () {
      final config = AppConfig.fromPublicEnvironmentFile('''
# Only public client values are allowed here.
NEXT_PUBLIC_SUPABASE_URL=https://example.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_example
''');

      expect(config.supabaseUrl, 'https://example.supabase.co');
      expect(config.supabasePublishableKey, 'sb_publishable_example');
      expect(config.isConfigured, isTrue);
    });
  });
}
