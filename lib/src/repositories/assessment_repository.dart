import 'package:care_navigator_ph/src/models/ai_assessment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AssessmentRepository {
  AssessmentRepository(this._client);

  final SupabaseClient _client;

  Future<AiAssessment> analyze({
    required String symptoms,
    String? duration,
    int? age,
    List<String> existingConditions = const [],
    List<String> allergies = const [],
    List<String> currentMedications = const [],
  }) async {
    // Supabase anonymous authentication gives an unauthenticated visitor a
    // rate-limited, RLS-scoped guest session without exposing the Groq key or
    // opening the Edge Function to unauthenticated traffic.
    if (_client.auth.currentSession == null) {
      await _client.auth.signInAnonymously(
        data: const {'access_purpose': 'guest_symptom_assessment'},
      );
    }
    final response = await _client.functions.invoke(
      'analyze-symptoms',
      body: {
        'symptoms': symptoms.trim(),
        'symptom_duration': duration?.trim(),
        'age': age,
        'existing_conditions': existingConditions,
        'allergies': allergies,
        'current_medications': currentMedications,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error']?.toString() : null;
      throw Exception(message ?? 'The assessment service is unavailable.');
    }
    if (response.data is! Map) {
      throw const FormatException('The assessment response was invalid.');
    }
    return AiAssessment.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}
