import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/consultation_repository.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:care_navigator_ph/src/routing/root_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'cancelling from details refreshes the retained appointment list',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Appointments();
      final container = ProviderContainer(
        overrides: [
          workspaceRepositoryProvider.overrideWithValue(repository),
          consultationRepositoryProvider.overrideWithValue(
            _Cancellation(repository),
          ),
        ],
      );
      addTearDown(container.dispose);
      const listRequest = (
        role: UserRole.patient,
        section: 'appointments',
        itemId: null,
      );
      // The list is retained beneath the detail route in the application shell.
      final subscription = container.listen(
        workspaceSnapshotProvider(listRequest),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(workspaceSnapshotProvider(listRequest).future);
      final router = GoRouter(
        navigatorKey: rootNavigatorKey,
        initialLocation: '/patient/appointments/appointment-id',
        routes: [
          GoRoute(
            path: '/patient/appointments',
            builder: (_, _) => const Scaffold(
              body: LiveWorkspaceView(
                role: UserRole.patient,
                section: 'appointments',
              ),
            ),
            routes: [
              GoRoute(
                path: ':itemId',
                builder: (_, _) => const Scaffold(
                  body: LiveWorkspaceView(
                    role: UserRole.patient,
                    section: 'appointments',
                    itemId: 'appointment-id',
                  ),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel consultation'));
      await tester.pumpAndSettle();
      expect(repository.cancelled, isTrue);
      await tester.tap(find.text('Back to list'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Demo Appointment'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Appointments implements WorkspaceRepository {
  bool cancelled = false;

  @override
  Future<WorkspaceSnapshot> load({
    required UserRole role,
    String? section,
    String? itemId,
    int limit = 100,
  }) async => WorkspaceSnapshot(
    title: 'Appointments',
    description: 'View your past and upcoming consultations.',
    loadedAt: DateTime.now(),
    items: [
      WorkspaceItem(
        id: 'appointment-id',
        kind: 'consultations',
        title: 'Demo appointment',
        subtitle: 'In person',
        status: cancelled ? 'cancelled' : 'pending',
        data: const {'doctor_display_name': 'Dr. Demo Available'},
      ),
    ],
  );
}

class _Cancellation implements ConsultationRepository {
  _Cancellation(this.appointments);
  final _Appointments appointments;

  @override
  Future<void> cancelConsultation(String consultationId) async {
    appointments.cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
