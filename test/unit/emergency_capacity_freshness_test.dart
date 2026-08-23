import 'package:care_navigator_ph/src/models/hospitals/hospital_models.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 8, 23, 12);

  test('capacity is live for the first five minutes', () {
    final hospital = _hospital(now.subtract(const Duration(minutes: 5)));

    expect(
      hospital.emergencyCapacityFreshness(now),
      EmergencyCapacityFreshness.live,
    );
    expect(hospital.hasCurrentEmergencyCapacity(now), isTrue);
  });

  test('capacity is delayed until the fifteen-minute expiry', () {
    final hospital = _hospital(now.subtract(const Duration(minutes: 10)));

    expect(
      hospital.emergencyCapacityFreshness(now),
      EmergencyCapacityFreshness.delayed,
    );
    expect(hospital.hasCurrentEmergencyCapacity(now), isTrue);
  });

  test('capacity expires after fifteen minutes', () {
    final hospital = _hospital(now.subtract(const Duration(minutes: 16)));

    expect(
      hospital.emergencyCapacityFreshness(now),
      EmergencyCapacityFreshness.stale,
    );
    expect(hospital.hasCurrentEmergencyCapacity(now), isFalse);
  });

  test('capacity without a confirmation timestamp is unpublished', () {
    final hospital = _hospital(null);

    expect(
      hospital.emergencyCapacityFreshness(now),
      EmergencyCapacityFreshness.unpublished,
    );
  });
}

HospitalDirectoryEntry _hospital(DateTime? updatedAt) => HospitalDirectoryEntry(
  id: 'hospital-id',
  name: 'Test Hospital',
  city: 'Tarlac City',
  province: 'Tarlac',
  careLevel: 'Tertiary Hospital',
  services: const [],
  departments: const [],
  doctors: const [],
  isAvailable: true,
  availableBeds: 9,
  totalBeds: 29,
  latitude: 15.47,
  longitude: 120.59,
  emergencyLastUpdated: updatedAt,
);
