import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/consultation_repository.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:care_navigator_ph/src/routing/root_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final role in [UserRole.patient, UserRole.hospitalAdministrator]) {
    testWidgets('$role cannot edit the doctor meeting link', (tester) async {
      await _pump(tester, role, _MeetRepository());
      expect(find.text('Set Google Meet link'), findsNothing);
      expect(
        find.text('Join Google Meet'),
        role == UserRole.patient ? findsOneWidget : findsNothing,
      );
    });
  }
  testWidgets(
    'doctor validates and saves against the official consultation id',
    (tester) async {
      final repository = _MeetRepository();
      await _pump(tester, UserRole.doctor, repository);
      await tester.tap(find.text('Set Google Meet link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'https://evil.test/abc-defg-hij',
      );
      await tester.tap(find.text('Save meeting link'));
      await tester.pumpAndSettle();
      expect(repository.savedId, isNull);
      expect(find.textContaining('Enter a Google Meet link'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'https://meet.google.com/abc-defg-hij',
      );
      await tester.tap(find.text('Save meeting link'));
      await tester.pumpAndSettle();
      expect(repository.savedId, 'official-consultation');
      expect(repository.savedUrl, 'https://meet.google.com/abc-defg-hij');
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  UserRole role,
  _MeetRepository repository,
) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final request = (role: role, section: 'appointments', itemId: null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consultationRepositoryProvider.overrideWithValue(repository),
        workspaceSnapshotProvider(request).overrideWith(
          (ref) async => WorkspaceSnapshot(
            title: 'Meeting test',
            description: 'Synthetic appointment',
            items: [
              WorkspaceItem(
                id: 'online-request',
                kind: 'online_consultation_requests',
                title: 'Synthetic confirmed appointment',
                subtitle: 'Online video',
                status: 'confirmed',
                data: {
                  'official_consultation_id': 'official-consultation',
                  'consultation_channel': 'video',
                  'confirmed_schedule': DateTime.now()
                      .toUtc()
                      .toIso8601String(),
                },
              ),
            ],
            loadedAt: DateTime.now(),
          ),
        ),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: Scaffold(
          body: LiveWorkspaceView(role: role, section: 'appointments'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _MeetRepository implements ConsultationRepository {
  String? savedId;
  String? savedUrl;
  @override
  Future<void> setGoogleMeetLink({
    required String consultationId,
    required String meetingUrl,
  }) async {
    savedId = consultationId;
    savedUrl = meetingUrl;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
