import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/profile_repository.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:care_navigator_ph/src/routing/root_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <_DestinationCase>[
    const _DestinationCase(UserRole.patient, 'appointments'),
    const _DestinationCase(
      UserRole.patient,
      'consultations',
      expectedTitle: 'Consultations',
    ),
    const _DestinationCase(
      UserRole.patient,
      'medical-records',
      dataSections: ['records'],
    ),
    const _DestinationCase(UserRole.patient, 'labs'),
    const _DestinationCase(UserRole.patient, 'prescriptions'),
    const _DestinationCase(UserRole.patient, 'profile', profile: true),
    const _DestinationCase(UserRole.doctor, null),
    const _DestinationCase(
      UserRole.doctor,
      'scheduling',
      dataSections: ['schedule', 'appointments'],
      expectedTitle: 'Availability',
    ),
    const _DestinationCase(UserRole.doctor, 'patients'),
    const _DestinationCase(UserRole.doctor, 'consultations'),
    const _DestinationCase(UserRole.doctor, 'prescriptions'),
    const _DestinationCase(
      UserRole.doctor,
      'laboratory',
      dataSections: ['laboratory', 'results-review'],
    ),
    const _DestinationCase(UserRole.doctor, 'profile', profile: true),
    const _DestinationCase(UserRole.hospitalAdministrator, null),
    const _DestinationCase(UserRole.hospitalAdministrator, 'appointments'),
    const _DestinationCase(UserRole.hospitalAdministrator, 'availability'),
    const _DestinationCase(
      UserRole.hospitalAdministrator,
      'facility',
      dataSections: ['beds', 'rooms'],
    ),
    const _DestinationCase(UserRole.hospitalAdministrator, 'emergency-room'),
    const _DestinationCase(
      UserRole.hospitalAdministrator,
      'services-departments',
      dataSections: ['services', 'departments'],
    ),
    const _DestinationCase(UserRole.hospitalAdministrator, 'staff'),
    const _DestinationCase(
      UserRole.hospitalAdministrator,
      'audit-reports',
      dataSections: ['audit', 'reports'],
    ),
    const _DestinationCase(
      UserRole.hospitalAdministrator,
      'profile',
      profile: true,
    ),
    const _DestinationCase(UserRole.superAdministrator, null),
    const _DestinationCase(UserRole.superAdministrator, 'hospitals'),
    const _DestinationCase(UserRole.superAdministrator, 'approvals'),
    const _DestinationCase(UserRole.superAdministrator, 'accounts'),
    const _DestinationCase(
      UserRole.superAdministrator,
      'system',
      dataSections: [
        'permissions',
        'settings',
        'security',
        'maintenance',
        'audit',
      ],
    ),
    const _DestinationCase(UserRole.superAdministrator, 'analytics'),
    const _DestinationCase(
      UserRole.superAdministrator,
      'profile',
      profile: true,
    ),
  ];

  for (final destination in cases) {
    testWidgets(
      '${destination.role.name}/${destination.section ?? 'home'} renders',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final dataSections = destination.resolvedDataSections;
        final overrides = [
          for (final dataSection in dataSections)
            workspaceSnapshotProvider((
              role: destination.role,
              section: dataSection,
              itemId: null,
            )).overrideWith(
              (ref) async => WorkspaceSnapshot(
                title: _snapshotTitle(destination.role, dataSection),
                description: 'Verified destination render contract.',
                items: const [],
                loadedAt: DateTime(2026, 8, 15),
              ),
            ),
          careProfileProvider.overrideWith(
            (ref) async => _profileFor(destination.role),
          ),
        ];
        final container = ProviderContainer(overrides: overrides);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              navigatorKey: rootNavigatorKey,
              home: Scaffold(
                body: LiveWorkspaceView(
                  role: destination.role,
                  section: destination.section,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final expected = destination.profile
            ? 'Profile & preferences'
            : destination.expectedTitle ??
                  _snapshotTitle(destination.role, dataSections.first);
        expect(find.text(expected), findsWidgets);
        expect(find.textContaining('Workspace unavailable'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

String _snapshotTitle(UserRole role, String? section) =>
    '${role.label} ${section ?? 'overview'}';

CareProfile _profileFor(UserRole role) => CareProfile(
  userId: '${role.name}-user',
  firstName: 'Test',
  lastName: role.label,
  email: '${role.name}@demo.test',
  mobileNumber: '09171234567',
  birthDate: DateTime(1990, 1, 1),
  sex: 'male',
  address: '123 Test Street, Manila',
  patientId: role == UserRole.patient ? 'patient-id' : null,
  doctorDisplayName: role == UserRole.doctor ? 'Dr. Test Doctor' : null,
  specialization: role == UserRole.doctor ? 'Internal Medicine' : null,
  licenseNumber: role == UserRole.doctor ? 'LIC-TEST-001' : null,
  preferences: const NotificationPreferences(),
);

class _DestinationCase {
  const _DestinationCase(
    this.role,
    this.section, {
    this.dataSections,
    this.expectedTitle,
    this.profile = false,
  });

  final UserRole role;
  final String? section;
  final List<String?>? dataSections;
  final String? expectedTitle;
  final bool profile;

  List<String?> get resolvedDataSections => dataSections ?? [section];
}
