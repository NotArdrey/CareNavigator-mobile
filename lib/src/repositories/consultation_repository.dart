import 'dart:typed_data';

import 'package:care_navigator_ph/src/models/guest_consultation_draft.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ConsultationRepository {
  ConsultationRepository(this._client);

  final SupabaseClient _client;

  Future<String> uploadGuestIdentification({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw const AuthException('Email verification is required.');
    }

    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : 'bin';
    final path = '${authUser.id}/${const Uuid().v4()}.$extension';
    await _client.storage
        .from('valid-identification')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return path;
  }

  Future<void> deleteGuestIdentification(String path) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null || !path.startsWith('${authUser.id}/')) return;
    await _client.storage.from('valid-identification').remove([path]);
  }

  Future<GuestConsultationSubmission> submitGuestRequest(
    GuestConsultationDraft draft,
  ) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw const AuthException('Email verification is required.');
    }
    final response = await _client
        .from('guest_consultation_requests')
        .insert(draft.toJson(authUser.id))
        .select('id, reference_number')
        .single();
    Map<String, dynamic>? assessment;
    String? assessmentWarning;
    try {
      final result = await _client.functions.invoke(
        'analyze-symptoms',
        body: {
          'symptoms': draft.symptoms.trim(),
          'symptom_duration': draft.symptomDuration.trim(),
          'existing_conditions': draft.existingConditions,
          'allergies': draft.allergies,
          'current_medications': draft.currentMedications,
          'guest_request_id': response['id'],
        },
      );
      if (result.status >= 200 && result.status < 300 && result.data is Map) {
        assessment = Map<String, dynamic>.from(result.data as Map);
      } else {
        assessmentWarning =
            'The request was saved, but preliminary AI guidance is temporarily unavailable.';
      }
    } catch (_) {
      assessmentWarning =
          'The request was saved, but preliminary AI guidance is temporarily unavailable.';
    }
    return GuestConsultationSubmission(
      requestId: response['id'] as String,
      referenceNumber: response['reference_number'] as String,
      assessment: assessment,
      assessmentWarning: assessmentWarning,
    );
  }
}

class GuestConsultationSubmission {
  const GuestConsultationSubmission({
    required this.requestId,
    required this.referenceNumber,
    this.assessment,
    this.assessmentWarning,
  });

  final String requestId;
  final String referenceNumber;
  final Map<String, dynamic>? assessment;
  final String? assessmentWarning;

  bool get isEmergency => assessment?['urgency_level'] == 'emergency';
}
