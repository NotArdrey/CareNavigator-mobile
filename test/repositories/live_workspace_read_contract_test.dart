@Tags(['live'])
library;

import 'dart:io';

import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/repositories/profile_repository.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['CNPH_TEST_SUPABASE_URL'] ?? '';
  final key = Platform.environment['CNPH_TEST_SUPABASE_PUBLISHABLE_KEY'] ?? '';
  final password = Platform.environment['CNPH_TEST_PASSWORD'] ?? '';
  final configured = url.isNotEmpty && key.isNotEmpty && password.isNotEmpty;

  for (final account in _workspaceAccounts) {
    test(
      '${account.role.name} reads every workspace data section',
      () async {
        final client = SupabaseClient(url, key);
        try {
          await client.auth.signInWithPassword(
            email: account.email,
            password: password,
          );
          final repository = SupabaseWorkspaceRepository(client);

          final dashboard = await repository.load(role: account.role);
          expect(dashboard.loadedAt, isNotNull);
          expect(dashboard.title, isNotEmpty);

          for (final section in account.sections) {
            final snapshot = await repository.load(
              role: account.role,
              section: section,
            );
            expect(snapshot.loadedAt, isNotNull, reason: section);
            expect(snapshot.title, isNotEmpty, reason: section);
            if (account.role == UserRole.doctor && section == 'patients') {
              final patientWithHistory = snapshot.items
                  .where(
                    (item) =>
                        item.data['checkup_history'] is List &&
                        (item.data['checkup_history'] as List).isNotEmpty,
                  )
                  .firstOrNull;
              if (patientWithHistory != null) {
                final detail = await repository.load(
                  role: account.role,
                  section: section,
                  itemId: patientWithHistory.id,
                );
                expect(detail.items, hasLength(1));
                expect(
                  detail.items.single.data['checkup_history'],
                  isNotEmpty,
                  reason:
                      'A saved checkup shown in the patient list must remain visible in patient detail.',
                );
              }
            }
          }

          final profile = await SupabaseProfileRepository(client).loadProfile();
          expect(profile.userId, isNotEmpty);
        } finally {
          await client.auth.signOut();
          client.dispose();
        }
      },
      skip: configured
          ? false
          : 'Live Supabase configuration and password were not supplied.',
    );
  }
}

const _workspaceAccounts = [
  _WorkspaceAccount(
    email: 'patient@demo.test',
    role: UserRole.patient,
    sections: [
      'appointments',
      'consultations',
      'records',
      'labs',
      'prescriptions',
      'messages',
      'notifications',
    ],
  ),
  _WorkspaceAccount(
    email: 'doctor@demo.test',
    role: UserRole.doctor,
    sections: [
      'schedule',
      'appointments',
      'consultations',
      'patients',
      'results-review',
      'prescriptions',
      'laboratory',
      'messages',
      'notifications',
    ],
  ),
  _WorkspaceAccount(
    email: 'hospital@demo.test',
    role: UserRole.hospitalAdministrator,
    sections: [
      'appointments',
      'availability',
      'beds',
      'rooms',
      'emergency-room',
      'services',
      'departments',
      'staff',
      'audit',
      'reports',
      'notifications',
    ],
  ),
  _WorkspaceAccount(
    email: 'admin@demo.test',
    role: UserRole.superAdministrator,
    sections: [
      'hospitals',
      'approvals',
      'accounts',
      'permissions',
      'settings',
      'analytics',
      'security',
      'maintenance',
      'audit',
      'notifications',
    ],
  ),
];

class _WorkspaceAccount {
  const _WorkspaceAccount({
    required this.email,
    required this.role,
    required this.sections,
  });

  final String email;
  final UserRole role;
  final List<String> sections;
}
