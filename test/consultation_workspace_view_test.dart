import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('consultation detail uses patient-friendly presentation', (
    tester,
  ) async {
    final request = (
      role: UserRole.patient,
      section: 'consultations',
      itemId: 'consultation-1',
    );
    final snapshot = WorkspaceSnapshot(
      title: 'Consultations',
      description: 'Legacy description',
      metrics: const [WorkspaceMetric(label: 'Visible records', value: '1')],
      items: [
        WorkspaceItem(
          id: 'consultation-1',
          kind: 'consultations',
          title: 'Annual blood pressure assessment',
          subtitle: 'face_to_face · 2025-05-19T14:00:00+00:00',
          status: 'completed',
          timestamp: DateTime.parse('2025-05-19T14:00:00+00:00'),
          data: {
            'chief_complaint': 'Annual blood pressure assessment',
            'consultation_type': 'face_to_face',
            'appointment_date': '2025-05-19T14:00:00+00:00',
            'status': 'completed',
            'doctor_display_name': 'Dr. Juan Dela Cruz',
            'doctor_profile_image_url':
                'https://example.test/doctor-profile.png',
            'hospital_name': 'Example Medical Center',
            'doctor_notes': 'Blood pressure remains above target.',
            'confirmed_diagnosis': 'Elevated blood pressure',
            'treatment_plan': 'Continue home blood pressure monitoring.',
            'known_medical_conditions': <String>[],
            'allergies': '[]',
            'current_medications': <String>[],
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceSnapshotProvider(
            request,
          ).overrideWith((ref) async => snapshot),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LiveWorkspaceView(
              role: UserRole.patient,
              section: 'consultations',
              itemId: 'consultation-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Appointment Details'), findsOneWidget);
    expect(find.text('Annual Blood Pressure Assessment'), findsOneWidget);
    expect(find.text('Face-to-face · May 19, 2025 · 10:00 PM'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Appointment'), findsOneWidget);
    expect(find.text('Reason for visit'), findsOneWidget);
    expect(find.text('Dr. Juan Dela Cruz'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.semanticLabel == 'Dr. Juan Dela Cruz profile photo',
      ),
      findsOneWidget,
    );
    expect(find.text('Example Medical Center'), findsOneWidget);
    expect(find.text('Clinical Notes'), findsOneWidget);
    expect(find.text('Clinical Summary'), findsOneWidget);
    expect(find.text('Health Information'), findsOneWidget);
    expect(find.text('None recorded'), findsNWidgets(3));
    expect(find.text('[]'), findsNothing);
    expect(find.text('Supabase'), findsNothing);
    expect(find.text('Visible records'), findsNothing);
    expect(find.text('Record detail'), findsNothing);
    expect(find.text('face_to_face'), findsNothing);
    expect(find.text('2025-05-19T14:00:00+00:00'), findsNothing);
  });

  testWidgets('consultation actions reflow before the summary gets squeezed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final request = (
      role: UserRole.patient,
      section: 'consultations',
      itemId: null,
    );
    final snapshot = WorkspaceSnapshot(
      title: 'Consultations',
      description: 'Consultations',
      items: [
        WorkspaceItem(
          id: 'consultation-1',
          kind: 'consultations',
          title: 'Demo follow-up for blood pressure monitoring',
          subtitle: 'face_to_face · 2026-08-11T10:00:00+00:00',
          status: 'scheduled',
          data: {
            'consultation_type': 'face_to_face',
            'appointment_date': '2026-08-11T10:00:00+00:00',
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceSnapshotProvider(
            request,
          ).overrideWith((ref) async => snapshot),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LiveWorkspaceView(
              role: UserRole.patient,
              section: 'consultations',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Reschedule'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Past'), findsOneWidget);
    final titleSize = tester.getSize(
      find.text('Demo Follow-up For Blood Pressure Monitoring'),
    );
    expect(titleSize.width, greaterThan(200));
    expect(find.textContaining('authorized'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
