import '../consultation_type.dart';

class HospitalSearchCriteria {
  const HospitalSearchCriteria({
    this.query = '',
    this.province,
    this.city,
    this.careLevel,
    this.service,
    this.onlyAvailable = false,
  });

  final String query;
  final String? province;
  final String? city;
  final String? careLevel;
  final String? service;
  final bool onlyAvailable;
}

class HospitalSummary {
  const HospitalSummary({
    required this.id,
    required this.name,
    required this.locationLabel,
    required this.isVerified,
    this.imageUrl,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String locationLabel;
  final bool isVerified;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
}

class DoctorAvailability {
  const DoctorAvailability({
    required this.id,
    required this.displayLabel,
    required this.specialtyLabel,
    required this.nextAvailableAt,
    required this.offersOnlineCare,
    this.departmentLabel,
    this.consultationTypes = const [],
  });

  final String id;
  final String displayLabel;
  final String specialtyLabel;
  final String? departmentLabel;
  final DateTime nextAvailableAt;
  final bool offersOnlineCare;
  final List<String> consultationTypes;

  List<String> get publishedConsultationTypes {
    final supportedTypes = consultationTypes
        .where(ConsultationType.supported.contains)
        .toList(growable: false);
    if (supportedTypes.isNotEmpty) return supportedTypes;
    if (consultationTypes.isNotEmpty) return const [];
    return [
      offersOnlineCare ? ConsultationType.online : ConsultationType.faceToFace,
    ];
  }
}

class DoctorDirectoryEntry {
  const DoctorDirectoryEntry({
    required this.doctor,
    required this.hospitalId,
    required this.hospitalName,
    required this.city,
    required this.province,
    required this.hospitalIsAvailable,
    this.hospitalImageUrl,
    this.distanceKm,
  });

  final DoctorAvailability doctor;
  final String hospitalId;
  final String hospitalName;
  final String city;
  final String province;
  final bool hospitalIsAvailable;
  final String? hospitalImageUrl;
  final double? distanceKm;

  String get locationLabel => '$city, $province';
}

enum DoctorDirectorySort { earliestAvailability, distance, name }

class DoctorDirectoryFilters {
  const DoctorDirectoryFilters({
    this.query = '',
    this.specialty,
    this.province,
    this.onlineOnly = false,
    this.availableFacilityOnly = false,
    this.sort = DoctorDirectorySort.earliestAvailability,
  });

  final String query;
  final String? specialty;
  final String? province;
  final bool onlineOnly;
  final bool availableFacilityOnly;
  final DoctorDirectorySort sort;

  DoctorDirectoryFilters copyWith({
    String? query,
    String? specialty,
    bool clearSpecialty = false,
    String? province,
    bool clearProvince = false,
    bool? onlineOnly,
    bool? availableFacilityOnly,
    DoctorDirectorySort? sort,
  }) => DoctorDirectoryFilters(
    query: query ?? this.query,
    specialty: clearSpecialty ? null : specialty ?? this.specialty,
    province: clearProvince ? null : province ?? this.province,
    onlineOnly: onlineOnly ?? this.onlineOnly,
    availableFacilityOnly: availableFacilityOnly ?? this.availableFacilityOnly,
    sort: sort ?? this.sort,
  );
}

class HospitalFacilityAvailability {
  const HospitalFacilityAvailability({
    required this.type,
    required this.status,
    this.availableUnits,
    this.notes,
    this.lastUpdated,
  });

  final String type;
  final String status;
  final int? availableUnits;
  final String? notes;
  final DateTime? lastUpdated;
}

class HospitalBedAvailability {
  const HospitalBedAvailability({
    required this.type,
    required this.totalBeds,
    required this.availableBeds,
    this.lastUpdated,
  });

  final String type;
  final int totalBeds;
  final int availableBeds;
  final DateTime? lastUpdated;
}

class HospitalDirectoryEntry {
  const HospitalDirectoryEntry({
    required this.id,
    required this.name,
    required this.city,
    required this.province,
    required this.careLevel,
    required this.services,
    required this.departments,
    required this.doctors,
    required this.isAvailable,
    required this.availableBeds,
    required this.totalBeds,
    required this.latitude,
    required this.longitude,
    this.departmentIds = const {},
    this.estimatedWaitMinutes,
    this.address,
    this.contactNumber,
    this.emergencyContactNumber,
    this.email,
    this.description,
    this.imageUrl,
    this.operatingHours = const {},
    this.operatingStatus = 'unknown',
    this.emergencyStatus,
    this.currentEmergencyPatients,
    this.occupiedEmergencyBeds,
    this.closedOrUnstaffedEmergencyBeds,
    this.reservedEmergencyBeds,
    this.emergencyCapacitySource,
    this.updatedAt,
    this.emergencyLastUpdated,
    this.facilities = const [],
    this.bedAvailability = const [],
  });

  final String id;
  final String name;
  final String city;
  final String province;
  final String careLevel;
  final List<String> services;
  final List<String> departments;
  final Map<String, String> departmentIds;
  final List<DoctorAvailability> doctors;
  final bool isAvailable;
  final int? estimatedWaitMinutes;
  final int? availableBeds;
  final int? totalBeds;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? contactNumber;
  final String? emergencyContactNumber;
  final String? email;
  final String? description;
  final String? imageUrl;
  final Map<String, String> operatingHours;
  final String operatingStatus;
  final String? emergencyStatus;
  final int? currentEmergencyPatients;
  final int? occupiedEmergencyBeds;
  final int? closedOrUnstaffedEmergencyBeds;
  final int? reservedEmergencyBeds;
  final String? emergencyCapacitySource;
  final DateTime? updatedAt;
  final DateTime? emergencyLastUpdated;
  final List<HospitalFacilityAvailability> facilities;
  final List<HospitalBedAvailability> bedAvailability;

  bool get hasCoordinates => latitude != null && longitude != null;

  String get locationLabel =>
      [city, province].where((part) => part.trim().isNotEmpty).join(', ');

  String get fullAddress {
    final publishedAddress = address?.trim() ?? '';
    return publishedAddress.isEmpty ? locationLabel : publishedAddress;
  }

  DateTime? get statusLastUpdated => emergencyLastUpdated ?? updatedAt;

  EmergencyCapacityFreshness emergencyCapacityFreshness([DateTime? now]) {
    final updated = emergencyLastUpdated;
    if (updated == null || availableBeds == null || totalBeds == null) {
      return EmergencyCapacityFreshness.unpublished;
    }
    final age = (now ?? DateTime.now()).difference(updated.toLocal());
    if (age.isNegative || age <= const Duration(minutes: 5)) {
      return EmergencyCapacityFreshness.live;
    }
    if (age <= const Duration(minutes: 15)) {
      return EmergencyCapacityFreshness.delayed;
    }
    return EmergencyCapacityFreshness.stale;
  }

  bool hasCurrentEmergencyCapacity([DateTime? now]) => {
    EmergencyCapacityFreshness.live,
    EmergencyCapacityFreshness.delayed,
  }.contains(emergencyCapacityFreshness(now));
}

enum EmergencyCapacityFreshness { unpublished, live, delayed, stale }

enum HospitalDirectorySort { relevance, distance, availability }

class HospitalDirectoryFilters {
  const HospitalDirectoryFilters({
    this.query = '',
    this.province,
    this.careLevel,
    this.service,
    this.onlyAvailable = false,
    this.sort = HospitalDirectorySort.relevance,
  });

  final String query;
  final String? province;
  final String? careLevel;
  final String? service;
  final bool onlyAvailable;
  final HospitalDirectorySort sort;

  HospitalDirectoryFilters copyWith({
    String? query,
    String? province,
    bool clearProvince = false,
    String? careLevel,
    bool clearCareLevel = false,
    String? service,
    bool clearService = false,
    bool? onlyAvailable,
    HospitalDirectorySort? sort,
  }) => HospitalDirectoryFilters(
    query: query ?? this.query,
    province: clearProvince ? null : province ?? this.province,
    careLevel: clearCareLevel ? null : careLevel ?? this.careLevel,
    service: clearService ? null : service ?? this.service,
    onlyAvailable: onlyAvailable ?? this.onlyAvailable,
    sort: sort ?? this.sort,
  );
}
