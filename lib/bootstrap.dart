import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/widgets.dart';

import 'src/app/care_navigator_app.dart';
import 'src/config/public_config.dart';
import 'src/providers/core_providers.dart';

Future<void> bootstrap() async {
  const config = PublicConfig.fromEnvironment();

  if (config.hasSupabaseConfiguration) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    );
  }

  runApp(
    ProviderScope(
      overrides: [publicConfigProvider.overrideWithValue(config)],
      child: const CareNavigatorApp(),
    ),
  );
}
