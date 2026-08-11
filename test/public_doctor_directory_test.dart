import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_navigator_ph/src/providers/core_providers.dart';

void main() {
  testWidgets('clinician directory exposes the live unavailable state', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        publicConfigProvider.overrideWithValue(
          const PublicConfig(
            supabaseUrl: '',
            supabasePublishableKey: '',
            appBaseUrl: '',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );
    container.read(appRouterProvider).go('/doctors?q=cardiology');
    await tester.pumpAndSettle();

    expect(find.text('Find a clinician'), findsOneWidget);
    expect(find.text('Clinician directory unavailable'), findsOneWidget);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/doctors',
    );
  });
}
