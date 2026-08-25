import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('appointment request opens its specific record details', (
    tester,
  ) async {
    const item = WorkspaceItem(
      id: 'online-request-id',
      kind: 'online_consultation_requests',
      title: 'ONL-20260825-000001',
      subtitle: 'Persistent cough',
      status: 'submitted',
      data: {
        'reference_number': 'ONL-20260825-000001',
        'medical_concern': 'Persistent cough',
        'symptom_duration': 'Three days',
        'consultation_channel': 'online',
        'preferred_schedule': '2026-08-28T10:00:00+08:00',
      },
    );
    final router = GoRouter(
      initialLocation: '/patient/appointments',
      routes: [
        GoRoute(
          path: '/patient/appointments',
          builder: (context, state) => const Scaffold(
            body: LiveWorkspaceView(
              role: UserRole.patient,
              section: 'appointments',
            ),
          ),
          routes: [
            GoRoute(
              path: ':itemId',
              builder: (context, state) => Scaffold(
                body: LiveWorkspaceView(
                  role: UserRole.patient,
                  section: 'appointments',
                  itemId: state.pathParameters['itemId'],
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceSnapshotProvider.overrideWith((ref, request) async {
            return WorkspaceSnapshot(
              title: request.itemId == null
                  ? 'Appointments'
                  : 'Appointment Details',
              description: 'Appointment records',
              items: const [item],
            );
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ONL-20260825-000001'));
    await tester.pumpAndSettle();

    expect(
      router.state.uri.path,
      '/patient/appointments/online-request~online-request-id',
    );
    expect(find.text('Appointment Details'), findsOneWidget);
    expect(find.text('Medical Concern'), findsOneWidget);
    expect(find.text('Persistent cough'), findsWidgets);
    expect(find.text('Symptom Duration'), findsOneWidget);
    expect(find.text('Three days'), findsOneWidget);
  });

  testWidgets('doctor appointments separate current records from history', (
    tester,
  ) async {
    final request = (
      role: UserRole.doctor,
      section: 'appointments',
      itemId: null,
    );
    final snapshot = WorkspaceSnapshot(
      title: 'Appointments',
      description: 'Assigned consultations',
      metrics: const [
        WorkspaceMetric(label: 'Visible consultations', value: '2'),
      ],
      items: [
        WorkspaceItem(
          id: 'request-1',
          kind: 'online_consultation_requests',
          title: 'ONL-20260823-000030',
          subtitle: 'New consultation request',
          status: 'submitted',
          timestamp: DateTime.parse('2026-08-23T15:05:00+08:00'),
          data: const {'request_status': 'submitted'},
        ),
        WorkspaceItem(
          id: 'consultation-1',
          kind: 'consultations',
          title: 'Completed follow-up',
          subtitle: 'Online consultation',
          status: 'completed',
          timestamp: DateTime.parse('2026-08-22T15:05:00+08:00'),
          data: const {
            'status': 'completed',
            'appointment_date': '2026-08-22T15:05:00+08:00',
          },
        ),
      ],
      loadedAt: DateTime.parse('2026-08-23T15:05:00+08:00'),
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
              role: UserRole.doctor,
              section: 'appointments',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active appointments'), findsOneWidget);
    expect(find.text('Current appointments'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('ONL-20260823-000030'), findsOneWidget);
    expect(find.text('Completed Follow-up'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('doctor-current-appointments-panel')),
        matching: find.text('ONL-20260823-000030'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('doctor-current-appointments-panel')),
        matching: find.text('Completed Follow-up'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('doctor-appointment-history-panel')),
        matching: find.text('Completed Follow-up'),
      ),
      findsOneWidget,
    );
    expect(find.text('Current records'), findsNothing);
  });

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
