import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/routing/root_overlay.dart';
import 'package:care_navigator_ph/src/widgets/app_shell/workspace_shell.dart';
import 'package:care_navigator_ph/src/widgets/navigation/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final role in const [
    UserRole.patient,
    UserRole.doctor,
    UserRole.hospitalAdministrator,
    UserRole.superAdministrator,
  ]) {
    testWidgets('${role.name} desktop shell navigates its sidebar', (
      tester,
    ) async {
      final destinations = workspaceDestinations(role);
      final target = destinations.firstWhere(
        (destination) => destination.location != role.homeLocation,
      );
      final harness = _ShellHarness(role);
      addTearDown(harness.dispose);
      await _pumpShell(tester, harness, const Size(1280, 900));

      await tester.tap(find.widgetWithText(ListTile, target.label));
      await tester.pumpAndSettle();
      expect(harness.router.state.path, target.location);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(harness.router.state.path, '${role.homeLocation}/notifications');

      if ({UserRole.patient, UserRole.doctor}.contains(role)) {
        await tester.tap(find.byTooltip('Messages'));
        await tester.pumpAndSettle();
        expect(harness.router.state.path, workspaceMessagesLocation(role));
      } else {
        expect(find.byTooltip('Messages'), findsNothing);
      }
    });
  }

  testWidgets('workspace keyboard search filters and opens a destination', (
    tester,
  ) async {
    final harness = _ShellHarness(UserRole.doctor);
    addTearDown(harness.dispose);
    await _pumpShell(tester, harness, const Size(1280, 900));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Search workspace sections'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'laboratory');
    await tester.pump();
    expect(find.text('1 section'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Laboratory').last);
    await tester.pumpAndSettle();
    expect(harness.router.state.path, '/doctor/laboratory');
  });

  testWidgets('mobile shell navigates primary bar, drawer, and utilities', (
    tester,
  ) async {
    final harness = _ShellHarness(UserRole.patient);
    addTearDown(harness.dispose);
    await _pumpShell(tester, harness, const Size(430, 850));

    await tester.tap(find.text('Appointments').last);
    await tester.pumpAndSettle();
    expect(harness.router.state.path, '/patient/appointments');

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Consultations'));
    await tester.pumpAndSettle();
    expect(harness.router.state.path, '/patient/consultations');

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(harness.router.state.path, '/patient/notifications');
  });

  testWidgets('mobile detail back and desktop sign-out callbacks execute', (
    tester,
  ) async {
    final harness = _ShellHarness(UserRole.patient, detail: true);
    addTearDown(harness.dispose);
    await _pumpShell(tester, harness, const Size(430, 850));

    await tester.tap(find.byTooltip('Back to appointments'));
    await tester.pump();
    expect(harness.backCount, 1);

    await _pumpShell(tester, harness, const Size(1280, 900));
    await tester.tap(find.widgetWithText(ListTile, 'Sign out'));
    await tester.pump();
    expect(harness.signOutCount, 1);
  });

  testWidgets('header actions show unread counts and cap large badges', (
    tester,
  ) async {
    final harness = _ShellHarness(
      UserRole.patient,
      unreadMessageCount: 7,
      unreadNotificationCount: 120,
    );
    addTearDown(harness.dispose);
    await _pumpShell(tester, harness, const Size(430, 850));

    expect(find.byKey(const Key('messages-unread-badge')), findsOneWidget);
    expect(find.byKey(const Key('notifications-unread-badge')), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });
}

Future<void> _pumpShell(
  WidgetTester tester,
  _ShellHarness harness,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp.router(routerConfig: harness.router));
  await tester.pumpAndSettle();
}

class _ShellHarness {
  _ShellHarness(
    this.role, {
    this.detail = false,
    this.unreadMessageCount = 0,
    this.unreadNotificationCount = 0,
  }) {
    final locations = <String>{
      role.homeLocation,
      for (final destination in workspaceDestinations(role))
        destination.location,
      if (workspaceMessagesLocation(role) != null)
        workspaceMessagesLocation(role)!,
      '${role.homeLocation}/notifications',
    };
    router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: role.homeLocation,
      routes: [
        for (final location in locations)
          GoRoute(
            path: location,
            builder: (context, state) => WorkspaceShell(
              identity: AppIdentity(
                role: role,
                status: AccountStatus.active,
                userId: '${role.name}-user',
                displayName: 'Test ${role.label}',
              ),
              location: state.uri.path,
              title: role.label,
              showAssistant: false,
              onBack: detail ? () => backCount++ : null,
              onSignOut: () => signOutCount++,
              onNotifications: () =>
                  context.go('${role.homeLocation}/notifications'),
              unreadMessageCount: unreadMessageCount,
              unreadNotificationCount: unreadNotificationCount,
              body: Center(child: Text('Body ${state.uri.path}')),
            ),
          ),
      ],
    );
  }

  final UserRole role;
  final bool detail;
  final int unreadMessageCount;
  final int unreadNotificationCount;
  late final GoRouter router;
  int backCount = 0;
  int signOutCount = 0;

  void dispose() => router.dispose();
}
