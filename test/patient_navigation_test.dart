import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:care_navigator_ph/src/widgets/navigation/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('patient record navigation is flat without Documents', () {
    final destinations = workspaceDestinations(UserRole.patient);
    final primaryDestinations = destinations
        .where((destination) => destination.isPrimary)
        .toList(growable: false);
    final drawerDestinations = destinations
        .where((destination) => !destination.isPrimary)
        .toList(growable: false);

    expect(primaryDestinations.map((destination) => destination.label), const [
      'Home',
      'Find care',
      'Appointments',
      'Profile',
    ]);
    expect(
      primaryDestinations
          .singleWhere((destination) => destination.label == 'Find care')
          .location,
      '/hospitals',
    );
    expect(drawerDestinations.map((destination) => destination.label), const [
      'Consultations',
      'Medical Overview',
      'Diagnostics',
      'Prescriptions',
    ]);
    expect(workspaceMessagesLocation(UserRole.patient), '/patient/messages');
    expect(
      drawerDestinations.every((destination) => destination.children.isEmpty),
      isTrue,
    );
    expect(
      destinations
          .expand((destination) => [destination, ...destination.children])
          .any((destination) => destination.label == 'Documents'),
      isFalse,
    );
  });

  for (final page in const [
    (section: 'labs', title: 'Diagnostics'),
    (section: 'prescriptions', title: 'Prescriptions'),
  ]) {
    testWidgets('${page.title} is read-only and has no Refresh', (
      tester,
    ) async {
      final request = (
        role: UserRole.patient,
        section: page.section,
        itemId: null as String?,
      );
      final snapshot = WorkspaceSnapshot(
        title: page.title,
        description: 'Authorized records',
        metrics: const [WorkspaceMetric(label: 'Records', value: '0')],
        items: const [],
        loadedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceSnapshotProvider(
              request,
            ).overrideWith((ref) async => snapshot),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LiveWorkspaceView(
                role: UserRole.patient,
                section: page.section,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Upload diagnostic result'), findsNothing);
      expect(find.text('Upload Prescription'), findsNothing);
      expect(find.text('Refresh'), findsNothing);
      expect(find.byTooltip('Refresh consultations'), findsNothing);
    });
  }
}
