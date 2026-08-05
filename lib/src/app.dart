import 'package:care_navigator_ph/src/config/app_config.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
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
      body: const SafeArea(
        child: Column(
          children: [
            AppPageHeader(
              eyebrow: 'STARTUP DIAGNOSTIC',
              title: 'Care network connection unavailable',
              subtitle:
                  'The application is protecting access until configuration is restored',
              icon: AppIcons.healthAndSafetyRounded,
            ),
            Expanded(
              child: ResponsivePageContainer(
                child: AppCard(
                  tone: AppCardTone.coral,
                  child: AppEmptyState(
                    kind: AppStateKind.error,
                    icon: AppIcons.settingsSuggestOutlined,
                    title: 'Configuration unavailable',
                    message:
                        'The public client configuration could not be loaded. Rebuild the app and try again. Administrative credentials are never compiled into Flutter.',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
