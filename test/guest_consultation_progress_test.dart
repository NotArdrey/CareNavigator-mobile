import 'package:care_navigator_ph/src/features/guest_consultation/consultation_request_screen.dart';
import 'package:care_navigator_ph/src/models/hospitals/hospital_models.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/consultation_repository.dart';
import 'package:care_navigator_ph/src/repositories/hospital_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guest intake stepper stays aligned at compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(508, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hospitalRepositoryProvider.overrideWithValue(
            _GuestIntakeHospitalRepository(),
          ),
          consultationRepositoryProvider.overrideWithValue(
            _GuestIntakeConsultationRepository(),
          ),
        ],
        child: const MaterialApp(home: ConsultationRequestScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Identity'), findsOneWidget);
    expect(find.text('Care'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      expect(
        find.byKey(ValueKey('intake-progress-segment-$index')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });
}

class _GuestIntakeConsultationRepository implements ConsultationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GuestIntakeHospitalRepository implements HospitalRepository {
  @override
  Future<List<HospitalDirectoryEntry>> loadPublicDirectory() async => [
    const HospitalDirectoryEntry(
      id: 'hospital-id',
      name: 'CareNavigator General Hospital',
      city: 'Quezon City',
      province: 'Metro Manila',
      careLevel: 'Tertiary hospital',
      services: ['General consultation'],
      departments: ['Internal Medicine'],
      departmentIds: {'Internal Medicine': 'department-id'},
      doctors: [],
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
