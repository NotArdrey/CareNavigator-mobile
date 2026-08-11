import 'package:supabase/supabase.dart';

import '../models/hospitals/hospital_models.dart';
import 'repository_failure.dart';

enum CareAssistantMessageRole { user, assistant }

enum CareAssistantIntent { medical, emergency, nonMedical, unclear }

enum CareAssistantUrgency { routine, soon, urgent, emergency }

class CareAssistantTurn {
  const CareAssistantTurn({required this.role, required this.content});

  final CareAssistantMessageRole role;
  final String content;

  Map<String, String> toJson() => {
    'role': role == CareAssistantMessageRole.user ? 'user' : 'assistant',
    'content': content,
  };
}

class CareAssistantFacilitySnapshot {
  const CareAssistantFacilitySnapshot({
    required this.id,
    required this.name,
    required this.location,
    required this.careLevel,
    required this.services,
    required this.departments,
    required this.isAvailable,
    required this.availableBeds,
    required this.totalBeds,
    required this.distanceKm,
    required this.hasCoordinates,
    required this.latitude,
    required this.longitude,
  });

  factory CareAssistantFacilitySnapshot.fromHospital(
    HospitalDirectoryEntry hospital,
  ) => CareAssistantFacilitySnapshot(
    id: hospital.id,
    name: hospital.name,
    location: hospital.locationLabel,
    careLevel: hospital.careLevel,
    services: hospital.services,
    departments: hospital.departments,
    isAvailable: hospital.isAvailable,
    availableBeds: hospital.availableBeds,
    totalBeds: hospital.totalBeds,
    distanceKm: null,
    hasCoordinates: hospital.hasCoordinates,
    latitude: hospital.latitude,
    longitude: hospital.longitude,
  );

  final String id;
  final String name;
  final String location;
  final String careLevel;
  final List<String> services;
  final List<String> departments;
  final bool isAvailable;
  final int? availableBeds;
  final int? totalBeds;
  final double? distanceKm;
  final bool hasCoordinates;
  final double? latitude;
  final double? longitude;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'location': location,
    'care_level': careLevel,
    'services': services,
    'departments': departments,
    'availability': isAvailable
        ? 'verified_available'
        : 'verified_not_available',
    'published_emergency_beds': availableBeds,
    'published_emergency_capacity': totalBeds,
    'distance_km': distanceKm,
    'has_coordinates': hasCoordinates,
    'latitude': latitude,
    'longitude': longitude,
  };
}

class CareAssistantReply {
  const CareAssistantReply({
    required this.message,
    this.intent = CareAssistantIntent.unclear,
    this.urgency = CareAssistantUrgency.routine,
    this.followUpQuestion,
    this.recommendationIds = const [],
    this.recommendationSummary,
    this.facilityDistances = const {},
    this.locationUsed = false,
  });

  final String message;
  final CareAssistantIntent intent;
  final CareAssistantUrgency urgency;
  final String? followUpQuestion;
  final List<String> recommendationIds;
  final String? recommendationSummary;
  final Map<String, double> facilityDistances;
  final bool locationUsed;

  static CareAssistantReply fromMap(Map<String, dynamic> value) {
    final message = value['message']?.toString().trim() ?? '';
    if (message.isEmpty) {
      throw const ContractUnavailableFailure(
        'The care assistant returned an empty response.',
      );
    }
    return CareAssistantReply(
      message: message,
      intent: _intent(value['intent'], legacyEmergency: value['emergency']),
      urgency: _urgency(value['urgency'], legacyEmergency: value['emergency']),
      followUpQuestion: _nullableString(value['follow_up_question']),
      recommendationIds: _stringList(value['recommendation_ids']),
      recommendationSummary: _nullableString(value['recommendation_summary']),
      facilityDistances: _numberMap(value['facility_distances']),
      locationUsed: value['location_used'] == true,
    );
  }

  static CareAssistantIntent _intent(
    Object? value, {
    required Object? legacyEmergency,
  }) => switch (value?.toString()) {
    'medical' => CareAssistantIntent.medical,
    'emergency' => CareAssistantIntent.emergency,
    'non_medical' => CareAssistantIntent.nonMedical,
    'unclear' => CareAssistantIntent.unclear,
    _ when legacyEmergency == true => CareAssistantIntent.emergency,
    _ => CareAssistantIntent.unclear,
  };

  static CareAssistantUrgency _urgency(
    Object? value, {
    required Object? legacyEmergency,
  }) => switch (value?.toString()) {
    'routine' => CareAssistantUrgency.routine,
    'soon' => CareAssistantUrgency.soon,
    'urgent' => CareAssistantUrgency.urgent,
    'emergency' => CareAssistantUrgency.emergency,
    _ when legacyEmergency == true => CareAssistantUrgency.emergency,
    _ => CareAssistantUrgency.routine,
  };

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<String> _stringList(Object? value) => value is List
      ? value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
      : const [];

  static Map<String, double> _numberMap(Object? value) {
    if (value is! Map) return const {};
    final result = <String, double>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      final number = entry.value is num
          ? (entry.value as num).toDouble()
          : double.tryParse(entry.value?.toString() ?? '');
      if (key.isEmpty || number == null || !number.isFinite) continue;
      result[key] = number;
    }
    return result;
  }
}

abstract interface class CareAssistantRepository {
  Future<CareAssistantReply> respond({
    required List<CareAssistantTurn> messages,
    required List<CareAssistantFacilitySnapshot> facilities,
  });
}

final class SupabaseCareAssistantRepository implements CareAssistantRepository {
  SupabaseCareAssistantRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<CareAssistantReply> respond({
    required List<CareAssistantTurn> messages,
    required List<CareAssistantFacilitySnapshot> facilities,
  }) async {
    await _ensureAnonymousSession();
    try {
      final response = await _client.functions.invoke(
        'care-navigator-chat',
        body: {
          'messages': messages.map((message) => message.toJson()).toList(),
          'facilities': facilities
              .map((facility) => facility.toJson())
              .toList(),
        },
      );
      return CareAssistantReply.fromMap(_map(response.data));
    } on FunctionException catch (error) {
      throw UnexpectedRepositoryFailure(
        error.details?.toString() ??
            'The care assistant is temporarily unavailable.',
        cause: error,
      );
    } on AuthException catch (error) {
      throw AuthenticationFailure(
        'A private care assistant session could not be started.',
        cause: error,
      );
    } on ContractUnavailableFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedRepositoryFailure(
        'The care assistant is temporarily unavailable.',
        cause: error,
      );
    }
  }

  Future<void> _ensureAnonymousSession() async {
    if (_client.auth.currentUser != null) return;
    try {
      await _client.auth.signInAnonymously();
    } on AuthException catch (error) {
      throw AuthenticationFailure(
        'A private care assistant session could not be started.',
        cause: error,
      );
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const ContractUnavailableFailure(
      'The care assistant returned an invalid response.',
    );
  }
}
