class GuestConsultationDraft {
  const GuestConsultationDraft({
    required this.fullName,
    required this.birthDate,
    required this.sex,
    required this.mobileNumber,
    required this.address,
    required this.symptoms,
    required this.symptomDuration,
    required this.consultationReason,
    required this.identificationFilePath,
    this.email,
    this.existingConditions = const [],
    this.allergies = const [],
    this.currentMedications = const [],
    this.preferredHospitalId,
    this.preferredDepartmentId,
    this.preferredSchedule,
    this.latitude,
    this.longitude,
  });

  final String fullName;
  final DateTime birthDate;
  final String sex;
  final String mobileNumber;
  final String? email;
  final String address;
  final String symptoms;
  final String symptomDuration;
  final String consultationReason;
  final List<String> existingConditions;
  final List<String> allergies;
  final List<String> currentMedications;
  final String? preferredHospitalId;
  final String? preferredDepartmentId;
  final DateTime? preferredSchedule;
  final double? latitude;
  final double? longitude;
  final String identificationFilePath;

  Map<String, dynamic> toJson(String authUserId) => {
    'submitted_by': authUserId,
    'full_name': fullName.trim(),
    'birth_date': birthDate.toIso8601String().split('T').first,
    'sex': sex,
    'mobile_number': mobileNumber.trim(),
    'email': _nullable(email),
    'address': address.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'symptoms': symptoms.trim(),
    'symptom_duration': symptomDuration.trim(),
    'consultation_reason': consultationReason.trim(),
    'existing_conditions': existingConditions,
    'allergies': allergies,
    'current_medications': currentMedications,
    'preferred_hospital_id': preferredHospitalId,
    'preferred_department_id': preferredDepartmentId,
    'preferred_schedule': preferredSchedule?.toUtc().toIso8601String(),
    'identification_file_path': identificationFilePath,
  };
}

String? _nullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
