@Tags(['live'])
library;

import 'dart:io';

import 'package:care_navigator_ph/src/repositories/care_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['CNPH_TEST_SUPABASE_URL'] ?? '';
  final key = Platform.environment['CNPH_TEST_SUPABASE_PUBLISHABLE_KEY'] ?? '';
  final password = Platform.environment['CNPH_TEST_PASSWORD'] ?? '';
  final configured = url.isNotEmpty && key.isNotEmpty && password.isNotEmpty;

  test(
    'doctor creates and cancels a laboratory request in the live database',
    () async {
      final client = SupabaseClient(url, key);
      String? requestId;
      try {
        final response = await client.auth.signInWithPassword(
          email: 'doctor@demo.test',
          password: password,
        );
        expect(response.user, isNotNull);

        final repository = SupabaseCareRepository(client);
        final relationships = await repository.listClinicalRelationships();
        expect(
          relationships,
          isNotEmpty,
          reason: 'The demo doctor needs an assigned relationship.',
        );
        final relationship = relationships.firstWhere(
          (item) => item.consultationId.isNotEmpty,
          orElse: () => relationships.first,
        );
        if (relationship.consultationId.isEmpty) {
          return;
        }
        final testName =
            'Codex cancellation audit ${DateTime.now().toUtc().microsecondsSinceEpoch}';

        await repository.createLaboratoryRequest(
          relationship: relationship,
          testName: testName,
          priority: 'routine',
          instructions: 'Automated live contract test; safe to remove.',
        );

        final before = await client
            .from('laboratory_requests')
            .select('id,status,test_name,patient_id,doctor_id,consultation_id')
            .eq('test_name', testName)
            .single();
        requestId = before['id'] as String;
        expect(before['status'], 'requested');
        expect(before['patient_id'], relationship.patientId);
        expect(before['consultation_id'], relationship.consultationId);

        await repository.deleteCareRecord(
          table: 'laboratory_requests',
          recordId: requestId,
        );

        final after = await client
            .from('laboratory_requests')
            .select('id,status,test_name')
            .eq('id', requestId)
            .single();
        expect(after['status'], 'cancelled');
        expect(after['test_name'], testName);
      } finally {
        if (requestId != null) {
          await client.from('laboratory_requests').delete().eq('id', requestId);
        }
        await client.auth.signOut();
        client.dispose();
      }
    },
    skip: configured
        ? false
        : 'Live Supabase configuration and password were not supplied.',
  );
}
