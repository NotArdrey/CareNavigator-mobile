import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/models/hospitals/hospital_models.dart';
import 'package:care_navigator_ph/src/models/shared/page_result.dart';
import 'package:care_navigator_ph/src/providers/care_assistant_provider.dart';
import 'package:care_navigator_ph/src/repositories/hospital_repository.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';

class _TestAuthenticatedIdentityController extends AppIdentityController {
  @override
  AppIdentity build() => const AppIdentity(
    role: UserRole.patient,
    status: AccountStatus.active,
    userId: 'test-user-id',
    displayName: 'Test User',
  );
}

void main() {
  testWidgets('patient opens hospital discovery inside patient navigation', (
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
        appIdentityProvider.overrideWith(
          _TestAuthenticatedIdentityController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(480, 900));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );
    container.read(appRouterProvider).go('/hospitals');
    await tester.pumpAndSettle();

    expect(find.text('Find a hospital'), findsOneWidget);
    expect(find.text('Find care'), findsWidgets);
    expect(find.text('Appointments'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.byTooltip('Sign in'), findsNothing);
  });

  testWidgets('hospital directory exposes loading failure without records', (
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
    container.read(appRouterProvider).go('/hospitals');
    await tester.pumpAndSettle();

    expect(find.text('Published hospitals'), findsOneWidget);
    expect(find.text('Hospital directory unavailable'), findsOneWidget);
  });

  testWidgets('request care opens the patient reservation flow', (
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
        appIdentityProvider.overrideWith(
          _TestAuthenticatedIdentityController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );

    container
        .read(appRouterProvider)
        .go('/consultation/request?hospitalId=hospital-id&doctorId=doctor-id');
    await tester.pumpAndSettle();

    final location = container
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri;
    expect(location.path, '/patient/appointments');
    expect(location.queryParameters['reserve'], 'true');
    expect(location.queryParameters['hospitalId'], 'hospital-id');
    expect(location.queryParameters['doctorId'], 'doctor-id');
    expect(tester.takeException(), isNull);
  });

  testWidgets('map and unknown detail routes retain clear states', (
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );
    container.read(appRouterProvider).go('/hospitals/map');
    await tester.pumpAndSettle();
    expect(find.text('Hospital directory unavailable'), findsOneWidget);

    container.read(appRouterProvider).go('/hospitals/unknown-hospital');
    await tester.pumpAndSettle();
    expect(find.text('Hospital details unavailable'), findsOneWidget);
  });

  testWidgets('hospital details expose decision information on mobile', (
    tester,
  ) async {
    final hospital = _publishedHospital();
    final container = ProviderContainer(
      overrides: [
        publicConfigProvider.overrideWithValue(
          const PublicConfig(
            supabaseUrl: '',
            supabasePublishableKey: '',
            appBaseUrl: '',
          ),
        ),
        appIdentityProvider.overrideWith(
          _TestAuthenticatedIdentityController.new,
        ),
        hospitalRepositoryProvider.overrideWithValue(
          _PublishedHospitalRepository(hospital),
        ),
        careAssistantProvider.overrideWith(
          () => _RecommendedCareAssistant(hospital.id),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(482, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );

    container.read(appRouterProvider).go('/hospitals');
    await tester.pumpAndSettle();
    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    expect(searchField.decoration?.hintText, 'Search hospitals or services');
    expect(find.text('All locations'), findsOneWidget);
    expect(find.text('All care levels'), findsOneWidget);
    expect(find.text('Available now'), findsOneWidget);
    expect(find.text('1 hospital found'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('View details'), findsOneWidget);
    expect(find.byTooltip('View on hospital map'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton).last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open chat history'), findsOneWidget);
    expect(find.byTooltip('Minimize assistant'), findsNothing);
    await tester.tap(find.byTooltip('Open chat history'));
    await tester.pumpAndSettle();
    expect(find.text('New Chat'), findsOneWidget);
    expect(find.text('Recents'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Emergency Hospital Search'), findsOneWidget);
    expect(find.byTooltip('Pin conversation'), findsOneWidget);
    expect(find.byTooltip('Edit conversation title'), findsOneWidget);
    await tester.tap(find.byTooltip('Pin conversation'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unpin conversation'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit conversation title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Pinned ER Search');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pinned ER Search'), findsOneWidget);
    await tester.tap(find.text('New Chat'));
    await tester.pumpAndSettle();
    expect(find.text('ER accepting patients'), findsNothing);
    await tester.tap(find.byTooltip('Open chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pinned ER Search'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('care-assistant-messages')),
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tertiary Hospital'), findsWidgets);
    expect(find.text('ER accepting patients'), findsOneWidget);
    expect(find.text('Emergency Department: 24/7'), findsOneWidget);
    expect(find.text('ER beds: 6 available / 26 total'), findsOneWidget);
    expect(find.textContaining('Why recommended:'), findsOneWidget);
    expect(find.textContaining('Relevant published care:'), findsOneWidget);
    expect(find.textContaining('Balanga City, Bataan'), findsWidgets);
    expect(find.textContaining('Availability updated:'), findsOneWidget);
    expect(find.text('Show in Maps'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Show recommendations on map'), findsNothing);
    await tester.drag(
      find.byKey(const Key('care-assistant-messages')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show in Maps'));
    await tester.pumpAndSettle();
    expect(find.text('Hospital map'), findsOneWidget);
    expect(
      find.textContaining('Showing recommended hospital ${hospital.name}'),
      findsOneWidget,
    );

    container.read(appRouterProvider).go('/hospitals');
    await tester.pumpAndSettle();

    container.read(appRouterProvider).go('/hospitals/map');
    await tester.pumpAndSettle();
    expect(find.text('Hospital level'), findsOneWidget);
    expect(find.text('Tertiary Hospital'), findsWidgets);
    expect(find.text('Philippine facilities'), findsOneWidget);
    expect(find.byTooltip('Show my live location'), findsOneWidget);
    expect(tester.takeException(), isNull);

    container
        .read(appRouterProvider)
        .go(
          '/hospitals/map?hospitalId=${hospital.id}&source=location-recommendation',
        );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Focused on the nearest CareNavigator recommendation using your saved location.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Nearest recommendation from your saved location: ${hospital.name}',
      ),
      findsOneWidget,
    );

    container
        .read(appRouterProvider)
        .go(
          '/hospitals/map?hospitalId=${hospital.id}&source=current-location-recommendation&userLat=14.68&userLng=120.54',
        );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Focused on the nearest CareNavigator recommendation using your current location.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Nearest recommendation from your current location: ${hospital.name}',
      ),
      findsOneWidget,
    );
    expect(find.text('Navigate'), findsOneWidget);

    container.read(appRouterProvider).go('/hospitals/${hospital.id}');
    await tester.pumpAndSettle();

    expect(find.text('Back to hospitals'), findsOneWidget);
    expect(find.text('Back to map'), findsOneWidget);
    expect(find.text('View on map'), findsOneWidget);
    expect(find.text('Request care'), findsOneWidget);
    expect(find.text('Current status'), findsOneWidget);
    expect(find.text('Emergency beds'), findsOneWidget);
    expect(find.text('6 / 26 available'), findsOneWidget);
    expect(
      find.text('Why CareNavigator recommends this hospital'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Recommended because Emergency Medicine is published and emergency beds are available.',
      ),
      findsOneWidget,
    );
    expect(find.text('Full address'), findsOneWidget);
    expect(find.text('Facilities and equipment'), findsOneWidget);
    expect(find.text('Payment and insurance'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('View on map'));
    await tester.tap(find.text('View on map'));
    await tester.pumpAndSettle();
    expect(find.text('Hospital map'), findsOneWidget);
    expect(find.textContaining('Showing ${hospital.name}'), findsOneWidget);
    expect(find.byTooltip('Show my live location'), findsOneWidget);
  });

  testWidgets('expired emergency capacity is clearly marked stale', (
    tester,
  ) async {
    final hospital = _publishedHospital(
      emergencyLastUpdated: DateTime(2026, 7, 19, 20, 27),
    );
    final container = ProviderContainer(
      overrides: [
        publicConfigProvider.overrideWithValue(
          const PublicConfig(
            supabaseUrl: '',
            supabasePublishableKey: '',
            appBaseUrl: '',
          ),
        ),
        hospitalRepositoryProvider.overrideWithValue(
          _PublishedHospitalRepository(hospital),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(480, 900));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );

    container.read(appRouterProvider).go('/hospitals/${hospital.id}');
    await tester.pumpAndSettle();

    expect(find.text('ER capacity stale'), findsOneWidget);
    expect(find.text('Status unconfirmed'), findsOneWidget);
    expect(find.text('6 / 26 last reported'), findsOneWidget);
    expect(find.text('Stale information'), findsOneWidget);
    expect(
      find.textContaining(
        'Emergency capacity has not been confirmed in the last 15 minutes',
      ),
      findsOneWidget,
    );
  });
}

HospitalDirectoryEntry _publishedHospital({DateTime? emergencyLastUpdated}) =>
    HospitalDirectoryEntry(
      id: 'bataan-general',
      name: 'Bataan General Hospital and Medical Center',
      city: 'Balanga City',
      province: 'Bataan',
      careLevel: 'Tertiary Hospital',
      services: const ['Emergency Room', 'CT Scan', 'X-ray'],
      departments: const ['Emergency Medicine', 'Pediatrics', 'Surgery'],
      doctors: const [],
      isAvailable: true,
      estimatedWaitMinutes: null,
      availableBeds: 6,
      totalBeds: 26,
      latitude: 14.6762,
      longitude: 120.5364,
      address: 'Manahan Street, Tenejero, Balanga City, Bataan',
      emergencyContactNumber: '911',
      operatingHours: const {
        'emergency': '24/7',
        'outpatient': 'Monday-Friday',
      },
      operatingStatus: 'open',
      emergencyStatus: 'available',
      currentEmergencyPatients: 12,
      updatedAt: DateTime(2026, 8, 10, 14, 31),
      emergencyLastUpdated:
          emergencyLastUpdated ??
          DateTime.now().subtract(const Duration(minutes: 2)),
      facilities: const [
        HospitalFacilityAvailability(
          type: 'icu',
          status: 'available',
          availableUnits: 3,
        ),
        HospitalFacilityAvailability(
          type: 'laboratory',
          status: 'available',
          availableUnits: 1,
        ),
      ],
    );

class _PublishedHospitalRepository implements HospitalRepository {
  const _PublishedHospitalRepository(this.hospital);

  final HospitalDirectoryEntry hospital;

  @override
  Future<HospitalSummary> getHospital(String hospitalId) async =>
      _summary(hospital);

  @override
  Future<List<String>> listDepartments(String hospitalId) async =>
      hospital.departments;

  @override
  Future<List<String>> listServices(String hospitalId) async =>
      hospital.services;

  @override
  Future<List<HospitalDirectoryEntry>> loadPublicDirectory() async => [
    hospital,
  ];

  @override
  Stream<void> watchDirectoryUpdates() => const Stream.empty();

  @override
  Future<PageResult<HospitalSummary>> searchHospitals({
    required HospitalSearchCriteria criteria,
    required PageRequest page,
  }) async => PageResult(items: [_summary(hospital)]);

  @override
  Stream<HospitalSummary> watchPublicAvailability(String hospitalId) =>
      Stream.value(_summary(hospital));

  static HospitalSummary _summary(HospitalDirectoryEntry hospital) =>
      HospitalSummary(
        id: hospital.id,
        name: hospital.name,
        locationLabel: hospital.locationLabel,
        isVerified: true,
        latitude: hospital.latitude,
        longitude: hospital.longitude,
      );
}

class _RecommendedCareAssistant extends CareAssistantController {
  _RecommendedCareAssistant(this.hospitalId);

  final String hospitalId;

  @override
  CareAssistantState build() => CareAssistantState(
    messages: const [
      CareAssistantMessage(
        role: CareAssistantChatMessageRole.assistant,
        text: careAssistantWelcomeMessage,
      ),
    ],
    status: CareAssistantStatus.recommendationReady,
    recommendations: [
      CareAssistantRecommendation(
        hospitalId: hospitalId,
        distanceKm: 4.2,
        relevantServices: const ['Emergency Medicine', 'CT Scan', 'X-ray'],
        reasons: const [
          'Recommended because Emergency Medicine is published and emergency beds are available.',
        ],
      ),
    ],
    conversationId: 'recommended-chat',
    conversationTitle: 'Emergency Hospital Search',
  );
}
