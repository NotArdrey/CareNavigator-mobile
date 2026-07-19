class Hospital {
  const Hospital({
    required this.id,
    required this.name,
    required this.address,
    required this.operatingStatus,
    required this.verificationStatus,
    required this.availableBeds,
    required this.availableRooms,
    this.serviceNames = const [],
    this.serviceTags = const [],
    this.classification,
    this.city,
    this.province,
    this.description,
    this.contactNumber,
    this.emergencyContactNumber,
    this.email,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.emergencyRoomStatus,
    this.emergencyBeds = 0,
    this.operatingHours = const {},
  });

  factory Hospital.fromJson(Map<String, dynamic> json) {
    final classification = json['hospital_classifications'];
    final emergency = _firstMap(json['emergency_room_status']);
    final beds = _maps(json['hospital_beds']);
    final rooms = _maps(json['hospital_rooms']);
    final services = _maps(json['hospital_services']);

    return Hospital(
      id: json['id'] as String,
      name: json['hospital_name'] as String? ?? 'Unnamed hospital',
      classification: classification is Map<String, dynamic>
          ? classification['classification_name'] as String?
          : null,
      address: json['address'] as String? ?? '',
      city: json['city'] as String?,
      province: json['province'] as String?,
      description: json['description'] as String?,
      contactNumber: json['contact_number'] as String?,
      emergencyContactNumber: json['emergency_contact_number'] as String?,
      email: json['email'] as String?,
      imageUrl: json['image_url'] as String?,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      operatingStatus: json['operating_status'] as String? ?? 'closed',
      operatingHours: json['operating_hours'] is Map
          ? Map<String, dynamic>.from(json['operating_hours'] as Map)
          : const {},
      verificationStatus: json['verification_status'] as String? ?? 'pending',
      emergencyRoomStatus: emergency?['status'] as String?,
      emergencyBeds: _toInt(emergency?['available_beds']),
      availableBeds: beds.fold<int>(
        0,
        (total, item) => total + _toInt(item['available_beds']),
      ),
      availableRooms: rooms.fold<int>(
        0,
        (total, item) => total + _toInt(item['available_rooms']),
      ),
      serviceNames: services
          .map((item) => item['service_name']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      serviceTags: services
          .expand(
            (item) => (item['tags'] as List? ?? const []).map(
              (value) => value.toString(),
            ),
          )
          .toSet()
          .toList(growable: false),
    );
  }

  final String id;
  final String name;
  final String? classification;
  final String address;
  final String? city;
  final String? province;
  final String? description;
  final String? contactNumber;
  final String? emergencyContactNumber;
  final String? email;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final String operatingStatus;
  final Map<String, dynamic> operatingHours;
  final String verificationStatus;
  final String? emergencyRoomStatus;
  final int emergencyBeds;
  final int availableBeds;
  final int availableRooms;
  final List<String> serviceNames;
  final List<String> serviceTags;

  String get locationLabel => [
    city,
    province,
  ].whereType<String>().where((value) => value.trim().isNotEmpty).join(', ');

  bool get isEmergencyAvailable =>
      emergencyRoomStatus == 'available' || emergencyRoomStatus == 'limited';

  /// The three general-hospital capability levels used by CareNavigator.
  ///
  /// Existing Primary/Secondary/Tertiary classifications are normalized to
  /// DOH-style Level 1/2/3 labels. Specialty hospitals are treated as Level 3
  /// for matching because they provide advanced referral care in their field.
  int get capabilityLevel {
    final value = classification?.trim().toLowerCase() ?? '';
    if (value.contains('tertiary') ||
        value.contains('specialty') ||
        value.contains('level 3') ||
        value.contains('level iii')) {
      return 3;
    }
    if (value.contains('secondary') ||
        value.contains('level 2') ||
        value.contains('level ii')) {
      return 2;
    }
    return 1;
  }

  String get capabilityLabel => 'Level $capabilityLevel';

  String get classificationLabel {
    final value = classification?.trim();
    return value == null || value.isEmpty
        ? capabilityLabel
        : '$capabilityLabel • $value';
  }

  String get fallbackImageAsset =>
      'assets/images/hospitals/hospital-level-$capabilityLevel.jpg';

  bool meetsCapabilityLevel(int minimumLevel) =>
      capabilityLevel >= minimumLevel;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return [
      name,
      address,
      city,
      province,
      classification,
      ...serviceNames,
      ...serviceTags,
    ].whereType<String>().join(' ').toLowerCase().contains(normalized);
  }
}

List<Map<String, dynamic>> _maps(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().toList();
}

Map<String, dynamic>? _firstMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  final values = _maps(value);
  return values.isEmpty ? null : values.first;
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
