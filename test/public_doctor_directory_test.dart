import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/features/public/doctor_directory_screen.dart';
import 'package:care_navigator_ph/src/models/hospitals/hospital_models.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/hospital_repository.dart';

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

  testWidgets('patients see a clinician hospital and department', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hospitalRepositoryProvider.overrideWithValue(
            _PublishedDoctorRepository(),
          ),
        ],
        child: const MaterialApp(home: DoctorDirectoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dr. Ana Reyes'), findsOneWidget);
    expect(find.text('Department: Cardiology'), findsOneWidget);
    expect(
      find.textContaining('CareNavigator General Hospital'),
      findsOneWidget,
    );
    expect(find.textContaining('Quezon City, Metro Manila'), findsOneWidget);
  });
}

class _PublishedDoctorRepository implements HospitalRepository {
  @override
  Future<List<HospitalDirectoryEntry>> loadPublicDirectory() async => [
    HospitalDirectoryEntry(
      id: 'hospital-id',
      name: 'CareNavigator General Hospital',
      city: 'Quezon City',
      province: 'Metro Manila',
      careLevel: 'Tertiary hospital',
      services: const ['Cardiology'],
      departments: const ['Cardiology'],
      doctors: [
        DoctorAvailability(
          id: 'doctor-id',
          displayLabel: 'Dr. Ana Reyes',
          specialtyLabel: 'Cardiology',
          departmentLabel: 'Cardiology',
          nextAvailableAt: DateTime(2026, 8, 25, 9),
          offersOnlineCare: false,
          consultationTypes: const ['face_to_face'],
        ),
      ],
      isAvailable: true,
      availableBeds: 8,
      totalBeds: 20,
      latitude: 14.676,
      longitude: 121.0437,
      operatingStatus: 'open',
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
