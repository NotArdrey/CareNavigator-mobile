import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/models/hospitals/hospital_models.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/consultation_repository.dart';
import 'package:care_navigator_ph/src/repositories/hospital_repository.dart';
import 'package:care_navigator_ph/src/repositories/profile_repository.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:care_navigator_ph/src/routing/root_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'request care preselects the hospital and filters its clinicians',
    (tester) async {
      const request = (
        role: UserRole.patient,
        section: 'appointments',
        itemId: null as String?,
      );
      final container = ProviderContainer(
        overrides: [
          workspaceSnapshotProvider(request).overrideWith(
            (ref) async => WorkspaceSnapshot(
              title: 'Appointments',
              description: 'Patient appointments.',
              items: const [],
              loadedAt: DateTime(2026, 8, 23),
            ),
          ),
          hospitalRepositoryProvider.overrideWithValue(
            const _ReservationHospitalRepository(),
          ),
          consultationRepositoryProvider.overrideWithValue(
            const _ReservationConsultationRepository(),
          ),
          careProfileProvider.overrideWith(
            (ref) async => const CareProfile(
              userId: 'patient-id',
              firstName: 'Maria',
              lastName: 'Santos',
              email: 'maria@example.com',
              mobileNumber: '09171234567',
              birthDate: null,
              sex: null,
              address: 'Bataan',
              preferences: NotificationPreferences(),
            ),
          ),
        ],
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(900, 900));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            home: const Scaffold(
              body: LiveWorkspaceView(
                role: UserRole.patient,
                section: 'appointments',
                requestReservation: true,
                initialReservationHospitalId: 'hospital-two',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hospitalDropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('reservation-hospital-dropdown')),
      );
      expect(hospitalDropdown.initialValue, 'hospital-two');

      expect(
        find.text('Records to share for this care relationship'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Consultations'),
        findsNothing,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Prescriptions'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Diagnostic results'),
        findsOneWidget,
      );

      var clinicianDropdown = tester
          .widget<DropdownButtonFormField<DoctorDirectoryEntry>>(
            find.byKey(const ValueKey('reservation-clinician-hospital-two')),
          );
      expect(clinicianDropdown.initialValue!.doctor.displayLabel, 'Dr. Two');

      await tester.tap(
        find.byKey(const ValueKey('reservation-clinician-hospital-two')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Dr. Two'), findsWidgets);
      expect(find.textContaining('Dr. Three'), findsOneWidget);
      expect(find.textContaining('Dr. One'), findsNothing);
      await tester.tap(find.textContaining('Dr. Two').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reservation-hospital-dropdown')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hospital One'), findsOneWidget);
      expect(find.textContaining('Hospital Two'), findsWidgets);
      await tester.tap(find.textContaining('Hospital One').last);
      await tester.pumpAndSettle();

      clinicianDropdown = tester
          .widget<DropdownButtonFormField<DoctorDirectoryEntry>>(
            find.byKey(const ValueKey('reservation-clinician-hospital-one')),
          );
      expect(clinicianDropdown.initialValue!.doctor.displayLabel, 'Dr. One');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
    },
  );
}

class _ReservationHospitalRepository implements HospitalRepository {
  const _ReservationHospitalRepository();

  @override
  Future<List<HospitalDirectoryEntry>> loadPublicDirectory() async => [
    _hospital(
      id: 'hospital-one',
      name: 'Hospital One',
      city: 'Balanga City',
      doctorId: 'doctor-one',
      doctorName: 'Dr. One',
    ),
    _hospital(
      id: 'hospital-two',
      name: 'Hospital Two',
      city: 'Orani',
      doctorId: 'doctor-two',
      doctorName: 'Dr. Two',
      secondDoctorId: 'doctor-three',
      secondDoctorName: 'Dr. Three',
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReservationConsultationRepository implements ConsultationRepository {
  const _ReservationConsultationRepository();

  @override
  Future<List<AvailableConsultationSlot>> listAvailableSlots({
    required String doctorId,
    required String consultationType,
    int horizonDays = 30,
  }) async {
    final startsAt = DateTime.now().add(const Duration(days: 2));
    return [
      AvailableConsultationSlot(
        startsAt: startsAt,
        endsAt: startsAt.add(const Duration(minutes: 30)),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HospitalDirectoryEntry _hospital({
  required String id,
  required String name,
  required String city,
  required String doctorId,
  required String doctorName,
  String? secondDoctorId,
  String? secondDoctorName,
}) => HospitalDirectoryEntry(
  id: id,
  name: name,
  city: city,
  province: 'Bataan',
  careLevel: 'General hospital',
  services: const ['Primary care'],
  departments: const ['General Medicine'],
  doctors: [
    DoctorAvailability(
      id: doctorId,
      displayLabel: doctorName,
      specialtyLabel: 'General Medicine',
      nextAvailableAt: DateTime(2026, 8, 25, 9),
      offersOnlineCare: doctorId == 'doctor-two',
      consultationTypes: doctorId == 'doctor-two'
          ? const ['online']
          : const ['face_to_face'],
    ),
    if (secondDoctorId != null && secondDoctorName != null)
      DoctorAvailability(
        id: secondDoctorId,
        displayLabel: secondDoctorName,
        specialtyLabel: 'Pediatrics',
        nextAvailableAt: DateTime(2026, 8, 25, 10),
        offersOnlineCare: false,
        consultationTypes: const ['face_to_face'],
      ),
  ],
  isAvailable: true,
  availableBeds: 4,
  totalBeds: 10,
  latitude: 14.67,
  longitude: 120.53,
  operatingStatus: 'open',
);
