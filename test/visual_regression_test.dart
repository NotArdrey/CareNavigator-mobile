@Tags(['golden'])
library;

import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/public_settings_repository.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_typography.dart';

const _publicConfig = PublicConfig(
  supabaseUrl: '',
  supabasePublishableKey: '',
  appBaseUrl: '',
);

const _publicSettings = PublicAppSettings(
  emergencyNumber: '911',
  emergencyRegion: 'the Philippines',
  medicalDisclaimer:
      'CareNavigator supports informed care decisions and does not replace emergency services.',
);

void main() {
  setUpAll(loadDeterministicTestFonts);

  final cases = <_GoldenCase>[
    const _GoldenCase(name: 'guest', role: UserRole.guest, route: '/'),
    const _GoldenCase(
      name: 'patient',
      role: UserRole.patient,
      route: '/patient',
    ),
    const _GoldenCase(name: 'doctor', role: UserRole.doctor, route: '/doctor'),
    _GoldenCase(
      name: 'doctor_prescriptions',
      role: UserRole.doctor,
      route: '/doctor/prescriptions',
      section: 'prescriptions',
      snapshot: _doctorPrescriptionsSnapshot(),
    ),
    const _GoldenCase(
      name: 'hospital_admin',
      role: UserRole.hospitalAdministrator,
      route: '/hospital-admin',
    ),
    _GoldenCase(
      name: 'hospital_availability',
      role: UserRole.hospitalAdministrator,
      route: '/hospital-admin/availability',
      section: 'availability',
      snapshot: _hospitalAvailabilitySnapshot(),
    ),
    const _GoldenCase(
      name: 'super_admin',
      role: UserRole.superAdministrator,
      route: '/super-admin',
    ),
    _GoldenCase(
      name: 'super_admin_hospitals',
      role: UserRole.superAdministrator,
      route: '/super-admin/hospitals',
      section: 'hospitals',
      snapshot: _superAdminHospitalsSnapshot(),
    ),
  ];

  for (final goldenCase in cases) {
    for (final viewport in const [
      (name: 'mobile', size: Size(430, 850)),
      (name: 'web', size: Size(1440, 1000)),
    ]) {
      testWidgets('${goldenCase.name} ${viewport.name} visual regression', (
        tester,
      ) async {
        await _pumpGolden(tester, goldenCase: goldenCase, size: viewport.size);

        await expectLater(
          find.byKey(const Key('golden-boundary')),
          matchesGoldenFile(
            'visual_catalog/${goldenCase.name}_${viewport.name}.png',
          ),
        );
      });
    }
  }
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required _GoldenCase goldenCase,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final overrides = [
    publicConfigProvider.overrideWithValue(_publicConfig),
    publicAppSettingsProvider.overrideWith((ref) async => _publicSettings),
    if (goldenCase.role != UserRole.guest)
      appIdentityProvider.overrideWith(
        () => _GoldenIdentityController(goldenCase.role),
      ),
    if (goldenCase.role != UserRole.guest)
      workspaceSnapshotProvider((
        role: goldenCase.role,
        section: goldenCase.section,
        itemId: null,
      )).overrideWith(
        (ref) async => goldenCase.snapshot ?? _snapshotFor(goldenCase.role),
      ),
  ];
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  container.read(appRouterProvider).go(goldenCase.route);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CareNavigatorApp(
        themeOverride: deterministicTestTheme(),
        captureBoundaryKey: const Key('golden-boundary'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

WorkspaceSnapshot _snapshotFor(UserRole role) => WorkspaceSnapshot(
  title: switch (role) {
    UserRole.doctor => 'Doctor workspace',
    UserRole.hospitalAdministrator => 'Hospital operations',
    UserRole.superAdministrator => 'Platform governance',
    UserRole.patient => 'Your care',
    UserRole.guest => 'CareNavigator PH',
  },
  description: switch (role) {
    UserRole.doctor => 'Today\'s care responsibilities and patient activity.',
    UserRole.hospitalAdministrator =>
      'Live staffing, capacity, and service operations.',
    UserRole.superAdministrator =>
      'Account, hospital, security, and platform oversight.',
    UserRole.patient => 'Your current appointments and care information.',
    UserRole.guest => 'Find verified care near you.',
  },
  metrics: const [
    WorkspaceMetric(label: 'Active', value: '12'),
    WorkspaceMetric(label: 'Pending', value: '3'),
    WorkspaceMetric(label: 'Updated today', value: '8'),
  ],
  items: [
    WorkspaceItem(
      id: 'visual-item-1',
      kind: 'summary',
      title: 'Current care activity',
      subtitle: 'Verified operational information',
      status: 'active',
      timestamp: DateTime.utc(2026, 8, 14, 8),
    ),
    WorkspaceItem(
      id: 'visual-item-2',
      kind: 'summary',
      title: 'Upcoming review',
      subtitle: 'Scheduled for the next available care window',
      status: 'scheduled',
      timestamp: DateTime.utc(2026, 8, 15, 9, 30),
    ),
  ],
  loadedAt: DateTime.utc(2026, 8, 14, 8),
);

WorkspaceSnapshot _doctorPrescriptionsSnapshot() => WorkspaceSnapshot(
  title: 'Prescriptions',
  description:
      'Live clinical information limited to assigned and consultation relationships.',
  metrics: const [WorkspaceMetric(label: 'Prescriptions', value: '2')],
  items: [
    WorkspaceItem(
      id: 'prescription-1',
      kind: 'prescriptions',
      title: 'Losartan 50 mg',
      subtitle: 'Once daily for 30 days',
      status: 'active',
      timestamp: DateTime.utc(2026, 8, 14, 8),
    ),
    WorkspaceItem(
      id: 'prescription-2',
      kind: 'prescriptions',
      title: 'Amlodipine 5 mg',
      subtitle: 'Once daily after breakfast',
      status: 'completed',
      timestamp: DateTime.utc(2026, 8, 10, 8),
    ),
  ],
  loadedAt: DateTime.utc(2026, 8, 14, 8),
);

WorkspaceSnapshot _hospitalAvailabilitySnapshot() => WorkspaceSnapshot(
  title: 'Availability',
  description:
      'Live operational information limited to your assigned hospital.',
  metrics: const [
    WorkspaceMetric(label: 'Facility status records', value: '2'),
  ],
  items: [
    WorkspaceItem(
      id: 'facility-status-1',
      kind: 'hospital_facility_status',
      title: 'Intensive care unit',
      subtitle: '3 units currently available',
      status: 'available',
      timestamp: DateTime.utc(2026, 8, 14, 8),
      data: const {
        'facility_type': 'icu',
        'available_units': 3,
        'notes': 'Operational visual regression fixture.',
      },
    ),
    WorkspaceItem(
      id: 'facility-status-2',
      kind: 'hospital_facility_status',
      title: 'Operating room',
      subtitle: '1 unit currently available',
      status: 'limited',
      timestamp: DateTime.utc(2026, 8, 14, 7, 30),
      data: const {
        'facility_type': 'operating_room',
        'available_units': 1,
        'notes': 'Operational visual regression fixture.',
      },
    ),
  ],
  loadedAt: DateTime.utc(2026, 8, 14, 8),
);

WorkspaceSnapshot _superAdminHospitalsSnapshot() => WorkspaceSnapshot(
  title: 'Hospitals',
  description: 'Live platform governance information with authorized access.',
  metrics: const [WorkspaceMetric(label: 'Hospitals', value: '2')],
  items: [
    WorkspaceItem(
      id: 'hospital-1',
      kind: 'hospitals',
      title: 'Central Luzon Medical Center',
      subtitle: 'San Fernando City, Pampanga',
      status: 'verified',
      timestamp: DateTime.utc(2026, 8, 14, 8),
    ),
    WorkspaceItem(
      id: 'hospital-2',
      kind: 'hospitals',
      title: 'Provincial Community Hospital',
      subtitle: 'Tarlac City, Tarlac',
      status: 'pending verification',
      timestamp: DateTime.utc(2026, 8, 13, 9),
    ),
  ],
  loadedAt: DateTime.utc(2026, 8, 14, 8),
);

class _GoldenCase {
  const _GoldenCase({
    required this.name,
    required this.role,
    required this.route,
    this.section,
    this.snapshot,
  });

  final String name;
  final UserRole role;
  final String route;
  final String? section;
  final WorkspaceSnapshot? snapshot;
}

class _GoldenIdentityController extends AppIdentityController {
  _GoldenIdentityController(this.role);

  final UserRole role;

  @override
  AppIdentity build() => AppIdentity(
    role: role,
    status: AccountStatus.active,
    userId: 'golden-${role.name}-user',
    displayName: switch (role) {
      UserRole.patient => 'Maria Santos',
      UserRole.doctor => 'Dr. Ana Reyes',
      UserRole.hospitalAdministrator => 'Hospital Administrator',
      UserRole.superAdministrator => 'Platform Administrator',
      UserRole.guest => 'Guest',
    },
  );
}
