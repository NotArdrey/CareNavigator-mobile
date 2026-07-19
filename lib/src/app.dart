import 'package:care_navigator_ph/src/config/app_config.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CareNavigatorApp extends ConsumerWidget {
  const CareNavigatorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);

    if (!config.isConfigured) {
      return MaterialApp(
        title: 'CareNavigator PH',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _MissingConfigurationScreen(),
      );
    }

    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'CareNavigator PH',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}

class _MissingConfigurationScreen extends StatelessWidget {
  const _MissingConfigurationScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.health_and_safety,
                    size: 52,
                    color: AppColors.blue,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'CareNavigator PH needs its public Supabase configuration.',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The public client configuration could not be loaded. Rebuild the app and try again. Administrative credentials are never compiled into Flutter.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
