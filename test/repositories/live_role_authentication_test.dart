@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/repositories/auth_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['CNPH_TEST_SUPABASE_URL'] ?? '';
  final key = Platform.environment['CNPH_TEST_SUPABASE_PUBLISHABLE_KEY'] ?? '';
  final password = Platform.environment['CNPH_TEST_PASSWORD'] ?? '';
  final encodedAccounts = Platform.environment['CNPH_TEST_ACCOUNTS'] ?? '';
  final configured = url.isNotEmpty && key.isNotEmpty && password.isNotEmpty;
  final accounts = encodedAccounts.isEmpty
      ? _demoAccounts
      : (jsonDecode(encodedAccounts) as List<dynamic>)
            .map(
              (entry) => _AccountExpectation(
                email: (entry as Map<String, dynamic>)['email'] as String,
                role: _roleFromName(entry['role'] as String),
              ),
            )
            .toList(growable: false);

  for (final account in accounts) {
    test(
      '${account.email} authenticates as ${account.role.name}',
      () async {
        final client = SupabaseClient(url, key);
        try {
          final identity = await SupabaseAuthRepository(
            client,
          ).signInWithPassword(email: account.email, password: password);

          expect(identity.isAuthenticated, isTrue);
          expect(identity.role, account.role);
          expect(identity.status, AccountStatus.active);
          expect(identity.userId, isNotEmpty);
          expect(identity.displayName, isNotEmpty);
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

const _demoAccounts = [
  _AccountExpectation(
    email: 'admin@demo.test',
    role: UserRole.superAdministrator,
  ),
  _AccountExpectation(
    email: 'hospital@demo.test',
    role: UserRole.hospitalAdministrator,
  ),
  _AccountExpectation(email: 'doctor@demo.test', role: UserRole.doctor),
  _AccountExpectation(email: 'patient@demo.test', role: UserRole.patient),
  _AccountExpectation(email: 'guest@demo.test', role: UserRole.guest),
];

class _AccountExpectation {
  const _AccountExpectation({required this.email, required this.role});

  final String email;
  final UserRole role;
}

UserRole _roleFromName(String value) => switch (value) {
  'patient' => UserRole.patient,
  'doctor' => UserRole.doctor,
  'hospital_admin' => UserRole.hospitalAdministrator,
  'super_admin' => UserRole.superAdministrator,
  _ => UserRole.guest,
};
