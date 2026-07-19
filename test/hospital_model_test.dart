import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hospital aggregates public availability data', () {
    final hospital = Hospital.fromJson({
      'id': 'hospital-id',
      'hospital_name': 'Care General Hospital',
      'address': 'Manila',
      'operating_status': 'open',
      'verification_status': 'verified',
      'hospital_classifications': {'classification_name': 'Tertiary Hospital'},
      'emergency_room_status': [
        {'status': 'available', 'available_beds': 3},
      ],
      'hospital_beds': [
        {'available_beds': 3},
        {'available_beds': 4},
      ],
      'hospital_rooms': [
        {'available_rooms': 2},
      ],
      'hospital_services': [
        {
          'service_name': 'Cardiology Consultation',
          'tags': ['heart', 'cardiac'],
        },
      ],
    });

    expect(hospital.classification, 'Tertiary Hospital');
    expect(hospital.availableBeds, 7);
    expect(hospital.availableRooms, 2);
    expect(hospital.isEmergencyAvailable, isTrue);
    expect(hospital.matches('cardiology'), isTrue);
    expect(hospital.matches('cardiac'), isTrue);
    expect(hospital.matches('orthopedic'), isFalse);
    expect(hospital.capabilityLevel, 3);
    expect(hospital.capabilityLabel, 'Level 3');
    expect(hospital.meetsCapabilityLevel(3), isTrue);
    expect(
      hospital.fallbackImageAsset,
      'assets/images/hospitals/hospital-level-3.jpg',
    );
  });

  test('Hospital normalizes primary and secondary classifications', () {
    Hospital hospital(String classification) => Hospital.fromJson({
      'id': classification,
      'hospital_name': classification,
      'address': 'Central Luzon',
      'operating_status': 'open',
      'verification_status': 'verified',
      'hospital_classifications': {'classification_name': classification},
    });

    expect(hospital('Primary Hospital').capabilityLevel, 1);
    expect(hospital('Secondary Hospital').capabilityLevel, 2);
    expect(
      hospital('Tertiary Hospital').classificationLabel,
      contains('Level 3'),
    );
  });
}
