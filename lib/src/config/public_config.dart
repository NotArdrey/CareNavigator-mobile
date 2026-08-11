class PublicConfig {
  const PublicConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.appBaseUrl,
  });

  const PublicConfig.fromEnvironment()
    : supabaseUrl = const String.fromEnvironment(
        'NEXT_PUBLIC_SUPABASE_URL',
        defaultValue: 'https://crhsbpkuteyqbxjpozrp.supabase.co',
      ),
      supabasePublishableKey = const String.fromEnvironment(
        'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
        defaultValue: 'sb_publishable_4AW0f29vUx94_u709gmgJA_f33zUfUO',
      ),
      appBaseUrl = const String.fromEnvironment('APP_BASE_URL');

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String appBaseUrl;
  bool get hasSupabaseConfiguration =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;
}
