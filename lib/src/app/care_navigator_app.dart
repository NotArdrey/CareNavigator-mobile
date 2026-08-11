import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../routing/app_router.dart';
import '../theme/app_theme.dart';

class CareNavigatorApp extends ConsumerWidget {
  const CareNavigatorApp({
    super.key,
    this.themeOverride,
    this.captureBoundaryKey,
  });

  final ThemeData? themeOverride;
  final Key? captureBoundaryKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'CareNavigator PH',
      debugShowCheckedModeBanner: false,
      theme: themeOverride ?? AppTheme.light,
      routerConfig: router,
      builder: (context, child) {
        final content = MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.textScalerOf(
              context,
            ).clamp(minScaleFactor: 0.9, maxScaleFactor: 2.0),
          ),
          child: child ?? const SizedBox.shrink(),
        );
        return captureBoundaryKey == null
            ? content
            : RepaintBoundary(key: captureBoundaryKey, child: content);
      },
    );
  }
}
