import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/care_repository.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:care_navigator_ph/src/routing/root_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/test_typography.dart';

const _captureKey = Key('crud-evidence-boundary');

void main() {
  setUpAll(loadDeterministicTestFonts);

  testWidgets('create schedule slot form', (tester) async {
    await _pumpSchedule(tester, items: const []);
    await tester.tap(find.widgetWithText(FilledButton, 'Add slot'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('create_operation.png'),
    );
  });

  testWidgets('read schedule slot list', (tester) async {
    await _pumpSchedule(tester, items: const [_scheduleItem]);
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('read_operation.png'),
    );
  });

  testWidgets('update schedule slot confirmation', (tester) async {
    await _pumpSchedule(tester, items: const [_scheduleItem]);
    await tester.tap(find.widgetWithText(TextButton, 'Publish'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('update_operation.png'),
    );
  });

  testWidgets('delete schedule slot confirmation', (tester) async {
    await _pumpSchedule(tester, items: const [_scheduleItem]);
    await tester.tap(find.byTooltip('Delete availability'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('delete_operation.png'),
    );
  });
}

const _scheduleItem = WorkspaceItem(
  id: 'schedule-evidence-id',
  kind: 'doctor_schedules',
  title: 'Monday, 9:00 AM - 12:00 PM',
  subtitle: 'Online consultation - 30 minute slots',
  status: 'inactive',
  data: {
    'day_of_week': 1,
    'starts_at': '09:00:00',
    'ends_at': '12:00:00',
    'consultation_type': 'online',
    'slot_minutes': 30,
    'is_active': false,
    'booked_consultation_count': 0,
  },
);

Future<void> _pumpSchedule(
  WidgetTester tester, {
  required List<WorkspaceItem> items,
}) async {
  // Phone-sized capture matching a modern 390 x 844 logical-pixel viewport.
  tester.view.physicalSize = const Size(390, 844);
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
          title: 'Schedule slots',
          description:
              'Create, review, publish, and safely delete doctor availability.',
          metrics: [
            WorkspaceMetric(label: 'Schedule slots', value: '${items.length}'),
          ],
          items: items,
          loadedAt: DateTime.utc(2026, 8, 15, 6),
        ),
      ),
      careRepositoryProvider.overrideWithValue(_NoopCareRepository()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          theme: deterministicTestTheme(),
          home: const Scaffold(
            body: LiveWorkspaceView(
              role: UserRole.doctor,
              section: 'schedule',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _NoopCareRepository implements CareRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
