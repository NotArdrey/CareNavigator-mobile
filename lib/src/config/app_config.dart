import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => throw StateError('AppConfig must be provided at startup.'),
);

class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      supabaseUrl: String.fromEnvironment('NEXT_PUBLIC_SUPABASE_URL'),
      supabasePublishableKey: String.fromEnvironment(
        'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
      ),
    );
  }

  factory AppConfig.fromPublicEnvironmentFile(String contents) {
    final values = <String, String>{};
    for (final rawLine in contents.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      values[line.substring(0, separator).trim()] = line
          .substring(separator + 1)
          .trim();
    }
    return AppConfig(
      supabaseUrl: values['NEXT_PUBLIC_SUPABASE_URL'] ?? '',
      supabasePublishableKey:
          values['NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY'] ?? '',
    );
  }

  static Future<AppConfig> load() async {
    final buildConfig = AppConfig.fromEnvironment();
    if (buildConfig.isConfigured) return buildConfig;

    try {
      final contents = await rootBundle.loadString('assets/config/public.env');
      return AppConfig.fromPublicEnvironmentFile(contents);
    } catch (_) {
      return buildConfig;
    }
  }

  final String supabaseUrl;
  final String supabasePublishableKey;

  bool get isConfigured =>
      Uri.tryParse(supabaseUrl)?.hasScheme == true &&
      supabasePublishableKey.startsWith('sb_publishable_');
}
