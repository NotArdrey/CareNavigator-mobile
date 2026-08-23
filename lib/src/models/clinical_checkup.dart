class ClinicalCheckupDraft {
  const ClinicalCheckupDraft({
    this.reasonForVisit,
    this.heightCm,
    this.weightKg,
    this.bloodPressureSystolic,
    this.bloodPressureDiastolic,
    this.bodyTemperatureC,
    this.heartRateBpm,
    this.respiratoryRateBpm,
    this.oxygenSaturationPercent,
    this.currentSymptoms,
    this.knownMedicalConditions = const [],
    this.allergies = const [],
    this.currentMedications = const [],
    this.relevantMedicalHistory,
    this.previousSurgeries,
    this.smokingStatus,
    this.alcoholUse,
    this.pregnancyStatus,
    this.doctorNotes,
  });

  final String? reasonForVisit;
  final double? heightCm;
  final double? weightKg;
  final int? bloodPressureSystolic;
  final int? bloodPressureDiastolic;
  final double? bodyTemperatureC;
  final int? heartRateBpm;
  final int? respiratoryRateBpm;
  final double? oxygenSaturationPercent;
  final String? currentSymptoms;
  final List<String> knownMedicalConditions;
  final List<String> allergies;
  final List<String> currentMedications;
  final String? relevantMedicalHistory;
  final String? previousSurgeries;
  final String? smokingStatus;
  final String? alcoholUse;
  final String? pregnancyStatus;
  final String? doctorNotes;

  factory ClinicalCheckupDraft.fromPayload(
    Map<dynamic, dynamic> payload,
  ) => ClinicalCheckupDraft(
    reasonForVisit: _payloadText(payload['reason_for_visit']),
    heightCm: _payloadDouble(payload['height_cm']),
    weightKg: _payloadDouble(payload['weight_kg']),
    bloodPressureSystolic: _payloadInt(payload['blood_pressure_systolic']),
    bloodPressureDiastolic: _payloadInt(payload['blood_pressure_diastolic']),
    bodyTemperatureC: _payloadDouble(payload['body_temperature_c']),
    heartRateBpm: _payloadInt(payload['heart_rate_bpm']),
    respiratoryRateBpm: _payloadInt(payload['respiratory_rate_bpm']),
    oxygenSaturationPercent: _payloadDouble(
      payload['oxygen_saturation_percent'],
    ),
    currentSymptoms: _payloadText(payload['current_symptoms']),
    knownMedicalConditions: _payloadList(payload['known_medical_conditions']),
    allergies: _payloadList(payload['allergies']),
    currentMedications: _payloadList(payload['current_medications']),
    relevantMedicalHistory: _payloadText(payload['relevant_medical_history']),
    previousSurgeries: _payloadText(payload['previous_surgeries']),
    smokingStatus: _payloadText(payload['smoking_status']),
    alcoholUse: _payloadText(payload['alcohol_use']),
    pregnancyStatus: _payloadText(payload['pregnancy_status']),
    doctorNotes: _payloadText(payload['doctor_notes']),
  );

  double? get bmi {
    if (heightCm == null || weightKg == null || heightCm! <= 0) return null;
    final heightInMetres = heightCm! / 100;
    return weightKg! / (heightInMetres * heightInMetres);
  }

  bool get hasAnyData =>
      reasonForVisit?.trim().isNotEmpty == true ||
      heightCm != null ||
      weightKg != null ||
      bloodPressureSystolic != null ||
      bloodPressureDiastolic != null ||
      bodyTemperatureC != null ||
      heartRateBpm != null ||
      respiratoryRateBpm != null ||
      oxygenSaturationPercent != null ||
      currentSymptoms?.trim().isNotEmpty == true ||
      knownMedicalConditions.isNotEmpty ||
      allergies.isNotEmpty ||
      currentMedications.isNotEmpty ||
      relevantMedicalHistory?.trim().isNotEmpty == true ||
      previousSurgeries?.trim().isNotEmpty == true ||
      smokingStatus?.trim().isNotEmpty == true ||
      alcoholUse?.trim().isNotEmpty == true ||
      pregnancyStatus?.trim().isNotEmpty == true ||
      doctorNotes?.trim().isNotEmpty == true;

  Map<String, Object?> toPayload() => {
    'reason_for_visit': _text(reasonForVisit),
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'bmi': bmi,
    'blood_pressure_systolic': bloodPressureSystolic,
    'blood_pressure_diastolic': bloodPressureDiastolic,
    'body_temperature_c': bodyTemperatureC,
    'heart_rate_bpm': heartRateBpm,
    'respiratory_rate_bpm': respiratoryRateBpm,
    'oxygen_saturation_percent': oxygenSaturationPercent,
    'current_symptoms': _text(currentSymptoms),
    'known_medical_conditions': knownMedicalConditions,
    'allergies': allergies,
    'current_medications': currentMedications,
    'relevant_medical_history': _text(relevantMedicalHistory),
    'previous_surgeries': _text(previousSurgeries),
    'smoking_status': _text(smokingStatus),
    'alcohol_use': _text(alcoholUse),
    'pregnancy_status': _text(pregnancyStatus),
    'doctor_notes': _text(doctorNotes),
  };
}

List<String> clinicalListValues(String value) => value
    .split(RegExp(r'[,;\n]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

String? _text(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String? _payloadText(Object? value) => value is String ? _text(value) : null;

double? _payloadDouble(Object? value) {
  if (value is num) return value.toDouble();
  return value is String ? double.tryParse(value.trim()) : null;
}

int? _payloadInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return value is String ? int.tryParse(value.trim()) : null;
}

List<String> _payloadList(Object? value) {
  if (value is String) return clinicalListValues(value);
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
