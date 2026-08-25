import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'public-test-key');
  });

  group('SupabaseWorkspaceRepository account scoping validations', () {
    test('guest access to authenticated workspace throws StateError', () async {
      final repository = SupabaseWorkspaceRepository(client);
      expect(
        () => repository.load(role: UserRole.guest, section: 'appointments'),
        throwsStateError,
      );
    });

    test('unauthenticated workspace load throws session expiration StateError', () async {
      final repository = SupabaseWorkspaceRepository(client);
      expect(
        () => repository.load(role: UserRole.patient, section: 'appointments'),
        throwsStateError,
      );
      expect(
        () => repository.load(role: UserRole.doctor, section: 'schedule'),
        throwsStateError,
      );
      expect(
        () => repository.load(role: UserRole.doctor, section: 'appointments'),
        throwsStateError,
      );
    });
  });

  group('Workspace route ID encoding and decoding', () {
    test('online and guest requests encode with distinctive prefix', () {
      const onlineItem = WorkspaceItem(
        id: 'online-req-123',
        kind: 'online_consultation_requests',
        title: 'ONL-20260826-0001',
        subtitle: 'Fever',
      );
      const guestItem = WorkspaceItem(
        id: 'guest-req-456',
        kind: 'guest_consultation_requests',
        title: 'Jane Doe',
        subtitle: 'Headache',
      );
      const consultationItem = WorkspaceItem(
        id: 'consult-789',
        kind: 'consultations',
        title: 'Followup',
        subtitle: 'Online',
      );

      expect(
        workspaceItemRouteId(onlineItem),
        'online-request~online-req-123',
      );
      expect(
        workspaceItemRouteId(guestItem),
        'guest-request~guest-req-456',
      );
      expect(
        workspaceItemRouteId(consultationItem),
        'consult-789',
      );
    });
  });

  group('LiveWorkspaceView rendering for patient and doctor scopes', () {
    testWidgets('patient appointments view only displays patient-owned consultations and requests', (
      tester,
    ) async {
      const patientSnapshot = WorkspaceSnapshot(
        title: 'Appointments',
        description: 'View your past and upcoming consultations.',
        items: [
          WorkspaceItem(
            id: 'patient-consultation-1',
            kind: 'consultations',
            title: 'General Consultation',
            subtitle: 'Online · Aug 28, 2026 · 10:00 AM',
            status: 'approved',
            data: {
              'patient_id': 'patient-own-id',
              'appointment_date': '2026-08-28T02:00:00Z',
              'consultation_type': 'online',
            },
          ),
          WorkspaceItem(
            id: 'online-request-1',
            kind: 'online_consultation_requests',
            title: 'ONL-20260826-000001',
            subtitle: 'Flu symptoms',
            status: 'submitted',
            data: {
              'patient_id': 'patient-own-id',
              'reference_number': 'ONL-20260826-000001',
              'request_status': 'submitted',
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceSnapshotProvider.overrideWith((ref, request) async {
              return patientSnapshot;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: LiveWorkspaceView(
                role: UserRole.patient,
                section: 'appointments',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Appointments'), findsOneWidget);
      expect(find.text('General Consultation'), findsOneWidget);
      expect(find.text('ONL-20260826-000001'), findsOneWidget);
      expect(find.text('Reserve consultation'), findsOneWidget);
    });

    testWidgets('doctor availability tab displays doctor-owned schedule slots', (
      tester,
    ) async {
      const doctorScheduleSnapshot = WorkspaceSnapshot(
        title: 'Availability',
        description: 'Choose when patients can reserve a consultation with you.',
        items: [
          WorkspaceItem(
            id: 'schedule-slot-1',
            kind: 'doctor_schedules',
            title: 'Monday Slot',
            subtitle: '09:00:00 - 12:00:00',
            status: 'active',
            data: {
              'doctor_id': 'doctor-own-id',
              'day_of_week': 1,
              'starts_at': '09:00:00',
              'ends_at': '12:00:00',
              'consultation_type': 'online',
              'is_active': true,
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceSnapshotProvider.overrideWith((ref, request) async {
              return doctorScheduleSnapshot;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: LiveWorkspaceView(
                role: UserRole.doctor,
                section: 'schedule',
                isTab: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Availability'), findsOneWidget);
      expect(find.text('Your weekly hours'), findsOneWidget);
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('09:00:00 – 12:00:00'), findsOneWidget);
      expect(find.text('Add slot'), findsOneWidget);
    });

    testWidgets('doctor appointments tab displays doctor-owned consultations and active count', (
      tester,
    ) async {
      const doctorAppointmentsSnapshot = WorkspaceSnapshot(
        title: 'Appointments',
        description: 'Assigned consultations',
        metrics: [
          WorkspaceMetric(label: 'Visible consultations', value: '1'),
        ],
        items: [
          WorkspaceItem(
            id: 'doctor-consultation-1',
            kind: 'consultations',
            title: 'Cardiology Review',
            subtitle: 'Face To Face · Aug 30, 2026 · 2:00 PM',
            status: 'approved',
            data: {
              'doctor_id': 'doctor-own-id',
              'appointment_date': '2026-08-30T06:00:00Z',
              'consultation_type': 'face_to_face',
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceSnapshotProvider.overrideWith((ref, request) async {
              return doctorAppointmentsSnapshot;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: LiveWorkspaceView(
                role: UserRole.doctor,
                section: 'appointments',
                isTab: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Current appointments'), findsOneWidget);
      expect(find.text('Cardiology Review'), findsOneWidget);
      expect(find.text('Active appointments'), findsOneWidget);
    });
  });
}
