import 'package:care_navigator_ph/src/providers/care_assistant_provider.dart';
import 'package:care_navigator_ph/src/models/hospitals/hospital_models.dart';
import 'package:care_navigator_ph/src/repositories/care_assistant_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes nearest-facility requests', () {
    final profile = CareAssistantNeedProfile.fromText(
      'What is the nearest hospital for a headache?',
    );

    expect(profile.asksForNearest, isTrue);
  });

  test('reads distance facts returned by the assistant function', () {
    final reply = CareAssistantReply.fromMap({
      'message': 'I found nearby facilities.',
      'recommendation_ids': ['hospital-a'],
      'facility_distances': {
        'hospital-a': 4.25,
        'hospital-b': '8.5',
        'invalid': 'not-a-number',
      },
      'location_used': true,
    });

    expect(reply.locationUsed, isTrue);
    expect(reply.facilityDistances['hospital-a'], 4.25);
    expect(reply.facilityDistances['hospital-b'], 8.5);
    expect(reply.facilityDistances.containsKey('invalid'), isFalse);
  });

  test('selects the nearest recommendation for map navigation', () {
    const state = CareAssistantState(
      messages: [],
      status: CareAssistantStatus.recommendationReady,
      recommendations: [
        CareAssistantRecommendation(
          hospitalId: 'hospital-a',
          reasons: [],
          distanceKm: 8.5,
        ),
        CareAssistantRecommendation(
          hospitalId: 'hospital-b',
          reasons: [],
          distanceKm: 2.25,
        ),
        CareAssistantRecommendation(hospitalId: 'hospital-c', reasons: []),
      ],
    );

    expect(state.nearestRecommendedHospitalId, 'hospital-b');
    expect(state.hasLocationAwareRecommendations, isTrue);
  });

  test('falls back to the first recommendation without location distance', () {
    const state = CareAssistantState(
      messages: [],
      status: CareAssistantStatus.recommendationReady,
      recommendations: [
        CareAssistantRecommendation(hospitalId: 'hospital-a', reasons: []),
        CareAssistantRecommendation(hospitalId: 'hospital-b', reasons: []),
      ],
    );

    expect(state.nearestRecommendedHospitalId, 'hospital-a');
    expect(state.hasLocationAwareRecommendations, isFalse);
  });

  test('selects the recommendation nearest to current coordinates', () {
    const state = CareAssistantState(
      messages: [],
      status: CareAssistantStatus.recommendationReady,
      recommendations: [
        CareAssistantRecommendation(hospitalId: 'far', reasons: []),
        CareAssistantRecommendation(hospitalId: 'near', reasons: []),
      ],
    );
    final hospitals = [
      _hospital('far', latitude: 14.5995, longitude: 120.9842),
      _hospital('near', latitude: 15.4817, longitude: 120.5979),
    ];

    expect(
      state.nearestRecommendedHospitalIdFromCoordinates(
        hospitals,
        latitude: 15.48,
        longitude: 120.59,
      ),
      'near',
    );
  });
}

HospitalDirectoryEntry _hospital(
  String id, {
  required double latitude,
  required double longitude,
}) => HospitalDirectoryEntry(
  id: id,
  name: id,
  city: 'Test City',
  province: 'Test Province',
  careLevel: 'Primary',
  services: const [],
  departments: const [],
  doctors: const [],
  isAvailable: true,
  availableBeds: null,
  totalBeds: null,
  latitude: latitude,
  longitude: longitude,
);
