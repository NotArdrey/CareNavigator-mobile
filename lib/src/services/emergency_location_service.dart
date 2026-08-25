import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class EmergencyLocation {
  const EmergencyLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class EmergencyLocationFailure implements Exception {
  const EmergencyLocationFailure(this.message);

  final String message;
}

abstract interface class EmergencyLocationService {
  Future<EmergencyLocation?> currentLocation({required bool requestPermission});
}

final class GeolocatorEmergencyLocationService
    implements EmergencyLocationService {
  const GeolocatorEmergencyLocationService();

  @override
  Future<EmergencyLocation?> currentLocation({
    required bool requestPermission,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const EmergencyLocationFailure(
        'Turn on device location to find nearby emergency hospitals.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) return null;
    if (permission == LocationPermission.deniedForever) {
      throw const EmergencyLocationFailure(
        'Location access is blocked. Enable it in your device or browser settings.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: kIsWeb
          ? WebSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: const Duration(seconds: 12),
              maximumAge: const Duration(minutes: 5),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12),
            ),
    );
    return EmergencyLocation(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
