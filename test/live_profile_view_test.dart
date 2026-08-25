import 'package:care_navigator_ph/src/features/workspaces/live_profile_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/profile_repository.dart';
import 'package:care_navigator_ph/src/routing/root_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('patient selects a blood type and saves the profile', (
    tester,
  ) async {
    final repository = _ProfileRepositoryFake();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(body: LiveProfileView(role: UserRole.patient)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blood type'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<String>),
      findsAtLeastNWidgets(2),
    );

    final bloodTypeDropdown = find.ancestor(
      of: find.text('Blood type'),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    expect(bloodTypeDropdown, findsOneWidget);
    await tester.ensureVisible(bloodTypeDropdown);
    await tester.tap(bloodTypeDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('AB-').last);
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Save changes');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.savedProfile?.bloodType, 'AB-');
    expect(repository.preferencesSaved, isTrue);
    expect(
      find.text('Profile and notification preferences saved.'),
      findsOneWidget,
    );
  });
}

class _ProfileRepositoryFake implements ProfileRepository {
  CareProfileUpdate? savedProfile;
  bool preferencesSaved = false;

  @override
  Future<CareProfile> loadProfile() async => CareProfile(
    userId: 'user-1',
    patientId: 'patient-1',
    firstName: 'Maria',
    lastName: 'Santos',
    email: 'maria@example.test',
    mobileNumber: '09171234567',
    birthDate: DateTime(1990, 1, 2),
    sex: 'female',
    address: 'Manila',
    bloodType: 'O+',
    emergencyContact: 'Juan Santos - 09181234567',
    allergies: 'Peanuts',
    existingConditions: 'Asthma',
    preferences: const NotificationPreferences(),
  );

  @override
  Future<void> updateProfile(CareProfileUpdate update) async {
    savedProfile = update;
  }

  @override
  Future<void> updateNotificationPreferences(
    NotificationPreferenceUpdate update,
  ) async {
    preferencesSaved = true;
  }

  @override
  Future<void> updateProfileImage({
    required List<int> bytes,
    required String fileName,
  }) async {}
}
