import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/models/hospitals/hospital_models.dart';
import 'package:care_navigator_ph/src/providers/hospital_directory_provider.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:care_navigator_ph/src/widgets/data_display/hospital_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/public_settings_repository.dart';

void main() {
  ProviderContainer createContainer({bool withPublishedFacilities = false}) =>
      ProviderContainer(
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
          if (withPublishedFacilities)
            hospitalDirectoryProvider.overrideWith(
              _PublishedFacilitiesController.new,
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

  testWidgets('home previews five published facilities', (tester) async {
    final container = createContainer(withPublishedFacilities: true);
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, container);

    for (var index = 1; index <= 5; index++) {
      expect(find.text('Published Hospital $index'), findsOneWidget);
    }
    expect(find.text('Published Hospital 6'), findsNothing);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('published facility image fills the summary content height', (
    tester,
  ) async {
    final container = createContainer(withPublishedFacilities: true);
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, container);

    expect(
      tester.getSize(find.byType(HospitalImage).first),
      const Size(76, 88),
    );
  });
}

class _PublishedFacilitiesController extends HospitalDirectoryController {
  @override
  HospitalDirectoryState build() => HospitalDirectoryState(
    entries: List.generate(6, _publishedHospital),
    filters: const HospitalDirectoryFilters(),
  );
}

HospitalDirectoryEntry _publishedHospital(int index) => HospitalDirectoryEntry(
  id: 'published-$index',
  name: 'Published Hospital ${index + 1}',
  city: 'City ${index + 1}',
  province: 'Province ${index + 1}',
  careLevel: 'General Hospital',
  services: const ['Emergency Room'],
  departments: const ['Emergency Medicine'],
  doctors: const [],
  isAvailable: true,
  estimatedWaitMinutes: null,
  availableBeds: index + 1,
  totalBeds: 20,
  latitude: 14.5,
  longitude: 121.0,
);
