import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('schedule always renders a standard Monday to Sunday week', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const request = (
      role: UserRole.doctor,
      section: 'schedule',
      itemId: null as String?,
    );
    final container = ProviderContainer(
      overrides: [
        workspaceSnapshotProvider(request).overrideWith(
          (ref) async => WorkspaceSnapshot(
            title: 'Schedule',
            description: 'Doctor availability.',
            items: const [
              WorkspaceItem(
                id: 'friday-online',
                kind: 'doctor_schedules',
                title: 'Friday',
                subtitle: '09:00:00 - 12:00:00 - Online',
                status: 'active',
                data: {
                  'day_of_week': 5,
                  'starts_at': '09:00:00',
                  'ends_at': '12:00:00',
                  'consultation_type': 'online',
                  'is_active': true,
                  'reserved_consultation_count': 0,
                },
              ),
              WorkspaceItem(
                id: 'thursday-clinic',
                kind: 'doctor_schedules',
                title: 'Thursday',
                subtitle: '13:00:00 - 16:00:00 - Face-to-face',
                status: 'inactive',
                data: {
                  'day_of_week': 4,
                  'starts_at': '13:00:00',
                  'ends_at': '16:00:00',
                  'consultation_type': 'face_to_face',
                  'is_active': false,
                  'reserved_consultation_count': 0,
                },
              ),
            ],
            loadedAt: DateTime(2026, 8, 23),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: LiveWorkspaceView(role: UserRole.doctor, section: 'schedule'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final day in const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ]) {
      expect(find.text(day), findsOneWidget);
    }
    expect(find.text('No available time slots'), findsNWidgets(5));
    expect(find.text('No time slots open for reservation'), findsOneWidget);
    expect(find.text('1 time slot open for reservation'), findsOneWidget);
    expect(find.text('Current records'), findsNothing);
    expect(find.text('Search visible records'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
