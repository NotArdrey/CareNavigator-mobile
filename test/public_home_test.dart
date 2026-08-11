import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/public_settings_repository.dart';

void main() {
  ProviderContainer createContainer() => ProviderContainer(
    overrides: [
      publicConfigProvider.overrideWithValue(
        const PublicConfig(
          supabaseUrl: '',
          supabasePublishableKey: '',
          appBaseUrl: '',
        ),
      ),
      publicAppSettingsProvider.overrideWith(
        (ref) async => const PublicAppSettings(
          emergencyNumber: '911',
          emergencyRegion: 'the Philippines',
        ),
      ),
    ],
  );

  Future<void> pumpHome(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home reports unavailable directory data without local records', (
    tester,
  ) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, container);

    expect(find.text('Published facilities'), findsOneWidget);
    expect(find.text('Hospital directory unavailable'), findsOneWidget);
  });

  testWidgets('home search routes to the hospital directory', (tester) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, container);

    await tester.enterText(find.byType(TextField), 'cardiology');
    await tester.tap(find.byTooltip('Search care'));
    await tester.pumpAndSettle();

    final uri = container
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri;
    expect(uri.path, '/hospitals');
    expect(uri.queryParameters['q'], 'cardiology');
  });
}
