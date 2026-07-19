typedef CareJson = Map<String, dynamic>;

/// A small typed facade over the role-workspace payloads returned by Supabase.
///
/// The presentation layer can continue using the raw lists while individual
/// detail screens opt into typed records as they are implemented.
class RoleWorkspace {
  const RoleWorkspace({
    required this.role,
    required this.consultations,
    required this.guestRequests,
    required this.patients,
    required this.medicalRecords,
    required this.diagnoses,
    required this.treatmentPlans,
    required this.laboratoryRequests,
    required this.laboratoryResults,
    required this.medicalDocuments,
    required this.consultationAttachments,
    required this.patientConsents,
    required this.prescriptions,
    required this.conversations,
    required this.notifications,
  });

  factory RoleWorkspace.fromJson(String role, CareJson json) => RoleWorkspace(
    role: role,
    consultations: _maps(
      json['consultations'],
    ).map(CareConsultation.fromJson).toList(growable: false),
    guestRequests: _maps(
      json['guest_requests'],
    ).map(GuestConsultationReview.fromJson).toList(growable: false),
    patients: _maps(
      json['patients'],
    ).map(CarePatient.fromJson).toList(growable: false),
    medicalRecords: _maps(
      json['medical_records'],
    ).map(CareMedicalRecord.fromJson).toList(growable: false),
    diagnoses: _maps(
      json['diagnoses'],
    ).map(CareDiagnosis.fromJson).toList(growable: false),
    treatmentPlans: _maps(
      json['treatment_plans'],
    ).map(CareTreatmentPlan.fromJson).toList(growable: false),
    laboratoryRequests: _maps(
      json['laboratory_requests'],
    ).map(CareLaboratoryRequest.fromJson).toList(growable: false),
    laboratoryResults: _maps(
      json['laboratory_results'],
    ).map(CareLaboratoryResult.fromJson).toList(growable: false),
    medicalDocuments: _maps(
      json['medical_documents'],
    ).map(CareMedicalDocument.fromJson).toList(growable: false),
    consultationAttachments: _maps(
      json['consultation_attachments'],
    ).map(CareConsultationAttachment.fromJson).toList(growable: false),
    patientConsents: _maps(
      json['patient_consents'],
    ).map(CarePatientConsent.fromJson).toList(growable: false),
    prescriptions: _maps(
      json['prescriptions'],
    ).map(CarePrescription.fromJson).toList(growable: false),
    conversations: _maps(
      json['conversations'],
    ).map(CareConversation.fromJson).toList(growable: false),
    notifications: _maps(
      json['notifications'],
    ).map(CareNotification.fromJson).toList(growable: false),
  );

  final String role;
  final List<CareConsultation> consultations;
  final List<GuestConsultationReview> guestRequests;
  final List<CarePatient> patients;
  final List<CareMedicalRecord> medicalRecords;
  final List<CareDiagnosis> diagnoses;
  final List<CareTreatmentPlan> treatmentPlans;
  final List<CareLaboratoryRequest> laboratoryRequests;
  final List<CareLaboratoryResult> laboratoryResults;
  final List<CareMedicalDocument> medicalDocuments;
  final List<CareConsultationAttachment> consultationAttachments;
  final List<CarePatientConsent> patientConsents;
  final List<CarePrescription> prescriptions;
  final List<CareConversation> conversations;
  final List<CareNotification> notifications;
}

class CareConsultation {
  const CareConsultation({
    required this.id,
    required this.status,
    required this.consultationType,
    required this.appointmentDate,
    required this.chiefComplaint,
    this.patientId,
    this.guestRequestId,
    this.doctorId,
    this.hospitalId,
    this.patientName,
    this.doctorName,
    this.hospitalName,
    this.doctorNotes,
    this.confirmedDiagnosis,
    this.treatmentPlan,
    this.meetingLink,
    this.completedAt,
  });

  factory CareConsultation.fromJson(CareJson json) {
    final patient = _relation(json['patients']);
    final patientUser = _relation(patient?['users']);
    final doctor = _relation(json['doctors']);
    final hospital = _relation(json['hospitals']);
    return CareConsultation(
      id: _requiredId(json),
      status: _string(json['status'], fallback: 'pending'),
      consultationType: _string(json['consultation_type'], fallback: 'online'),
      appointmentDate: _date(json['appointment_date']),
      chiefComplaint: _string(json['chief_complaint']),
      patientId: _nullableString(json['patient_id']),
      guestRequestId: _nullableString(json['guest_request_id']),
      doctorId: _nullableString(json['doctor_id']),
      hospitalId: _nullableString(json['hospital_id']),
      patientName: _displayName(patientUser),
      doctorName: _nullableString(doctor?['display_name']),
      hospitalName: _nullableString(hospital?['hospital_name']),
      doctorNotes: _nullableString(json['doctor_notes']),
      confirmedDiagnosis: _nullableString(json['confirmed_diagnosis']),
      treatmentPlan: _nullableString(json['treatment_plan']),
      meetingLink: _nullableString(json['meeting_link']),
      completedAt: _nullableDate(json['completed_at']),
    );
  }

  final String id;
  final String status;
  final String consultationType;
  final DateTime appointmentDate;
  final String chiefComplaint;
  final String? patientId;
  final String? guestRequestId;
  final String? doctorId;
  final String? hospitalId;
  final String? patientName;
  final String? doctorName;
  final String? hospitalName;
  final String? doctorNotes;
  final String? confirmedDiagnosis;
  final String? treatmentPlan;
  final String? meetingLink;
  final DateTime? completedAt;
}

class GuestConsultationReview {
  const GuestConsultationReview({
    required this.id,
    required this.referenceNumber,
    required this.fullName,
    required this.status,
    required this.symptoms,
    required this.createdAt,
    this.urgencyLevel,
    this.preferredSchedule,
    this.assignedDoctorId,
    this.preferredHospitalId,
    this.preferredDepartmentId,
  });

  factory GuestConsultationReview.fromJson(CareJson json) =>
      GuestConsultationReview(
        id: _requiredId(json),
        referenceNumber: _string(json['reference_number']),
        fullName: _string(json['full_name']),
        status: _string(json['request_status'], fallback: 'otp_verified'),
        symptoms: _string(json['symptoms']),
        urgencyLevel: _nullableString(json['urgency_level']),
        preferredSchedule: _nullableDate(json['preferred_schedule']),
        assignedDoctorId: _nullableString(json['assigned_doctor_id']),
        preferredHospitalId: _nullableString(json['preferred_hospital_id']),
        preferredDepartmentId: _nullableString(json['preferred_department_id']),
        createdAt: _date(json['created_at']),
      );

  final String id;
  final String referenceNumber;
  final String fullName;
  final String status;
  final String symptoms;
  final String? urgencyLevel;
  final DateTime? preferredSchedule;
  final String? assignedDoctorId;
  final String? preferredHospitalId;
  final String? preferredDepartmentId;
  final DateTime createdAt;
}

class CarePatient {
  const CarePatient({
    required this.id,
    required this.patientNumber,
    required this.displayName,
    required this.activationStatus,
    this.userId,
    this.primaryHospitalId,
    this.bloodType,
    this.allergies = const [],
    this.existingConditions = const [],
  });

  factory CarePatient.fromJson(CareJson json) {
    final user = _relation(json['users']);
    return CarePatient(
      id: _requiredId(json),
      patientNumber: _string(json['patient_number']),
      displayName: _displayName(user) ?? 'Patient',
      activationStatus: _string(
        json['account_activation_status'],
        fallback: 'pending',
      ),
      userId: _nullableString(json['user_id']),
      primaryHospitalId: _nullableString(json['primary_hospital_id']),
      bloodType: _nullableString(json['blood_type']),
      allergies: _strings(json['allergies']),
      existingConditions: _strings(json['existing_conditions']),
    );
  }

  final String id;
  final String patientNumber;
  final String displayName;
  final String activationStatus;
  final String? userId;
  final String? primaryHospitalId;
  final String? bloodType;
  final List<String> allergies;
  final List<String> existingConditions;
}

class CareMedicalRecord {
  const CareMedicalRecord({
    required this.id,
    required this.patientId,
    required this.recordType,
    required this.title,
    required this.recordDate,
    this.consultationId,
    this.description,
    this.confirmedDiagnosis,
    this.treatmentPlan,
    this.doctorName,
    this.hospitalName,
  });

  factory CareMedicalRecord.fromJson(CareJson json) => CareMedicalRecord(
    id: _requiredId(json),
    patientId: _string(json['patient_id']),
    recordType: _string(json['record_type']),
    title: _string(json['title']),
    recordDate: _date(json['record_date']),
    consultationId: _nullableString(json['consultation_id']),
    description: _nullableString(json['description']),
    confirmedDiagnosis: _nullableString(json['confirmed_diagnosis']),
    treatmentPlan: _nullableString(json['treatment_plan']),
    doctorName: _nullableString(_relation(json['doctors'])?['display_name']),
    hospitalName: _nullableString(
      _relation(json['hospitals'])?['hospital_name'],
    ),
  );

  final String id;
  final String patientId;
  final String recordType;
  final String title;
  final DateTime recordDate;
  final String? consultationId;
  final String? description;
  final String? confirmedDiagnosis;
  final String? treatmentPlan;
  final String? doctorName;
  final String? hospitalName;
}

class CareDiagnosis {
  const CareDiagnosis({
    required this.id,
    required this.patientId,
    required this.consultationId,
    required this.diagnosis,
    required this.isPrimary,
    required this.confirmedAt,
    this.diagnosisCode,
    this.doctorName,
    this.hospitalName,
  });

  factory CareDiagnosis.fromJson(CareJson json) => CareDiagnosis(
    id: _requiredId(json),
    patientId: _string(json['patient_id']),
    consultationId: _string(json['consultation_id']),
    diagnosis: _string(json['diagnosis']),
    diagnosisCode: _nullableString(json['diagnosis_code']),
    isPrimary: json['is_primary'] == true,
    confirmedAt: _date(json['confirmed_at']),
    doctorName: _nullableString(_relation(json['doctors'])?['display_name']),
    hospitalName: _nullableString(
      _relation(json['hospitals'])?['hospital_name'],
    ),
  );

  final String id;
  final String patientId;
  final String consultationId;
  final String diagnosis;
  final String? diagnosisCode;
  final bool isPrimary;
  final DateTime confirmedAt;
  final String? doctorName;
  final String? hospitalName;
}

class CareTreatmentPlan {
  const CareTreatmentPlan({
    required this.id,
    required this.patientId,
    required this.consultationId,
    required this.plan,
    required this.status,
    required this.createdAt,
    this.startsOn,
    this.endsOn,
    this.doctorName,
    this.hospitalName,
  });

  factory CareTreatmentPlan.fromJson(CareJson json) => CareTreatmentPlan(
    id: _requiredId(json),
    patientId: _string(json['patient_id']),
    consultationId: _string(json['consultation_id']),
    plan: _string(json['plan']),
    status: _string(json['status'], fallback: 'active'),
    startsOn: _nullableDate(json['starts_on']),
    endsOn: _nullableDate(json['ends_on']),
    createdAt: _date(json['created_at']),
    doctorName: _nullableString(_relation(json['doctors'])?['display_name']),
    hospitalName: _nullableString(
      _relation(json['hospitals'])?['hospital_name'],
    ),
  );

  final String id;
  final String patientId;
  final String consultationId;
  final String plan;
  final String status;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final DateTime createdAt;
  final String? doctorName;
  final String? hospitalName;
}

class CareMedicalDocument {
  const CareMedicalDocument({
    required this.id,
    required this.patientId,
    required this.documentType,
    required this.title,
    required this.storageBucket,
    required this.storagePath,
    required this.createdAt,
    this.consultationId,
    this.mimeType,
    this.sizeBytes,
  });

  factory CareMedicalDocument.fromJson(CareJson json) => CareMedicalDocument(
    id: _requiredId(json),
    patientId: _string(json['patient_id']),
    consultationId: _nullableString(json['consultation_id']),
    documentType: _string(json['document_type']),
    title: _string(json['title']),
    storageBucket: _string(json['storage_bucket']),
    storagePath: _string(json['storage_path']),
    mimeType: _nullableString(json['mime_type']),
    sizeBytes: _nullableInt(json['size_bytes']),
    createdAt: _date(json['created_at']),
  );

  final String id;
  final String patientId;
  final String? consultationId;
  final String documentType;
  final String title;
  final String storageBucket;
  final String storagePath;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime createdAt;
}

class CareConsultationAttachment {
  const CareConsultationAttachment({
    required this.id,
    required this.consultationId,
    required this.fileName,
    required this.storagePath,
    required this.createdAt,
    this.patientId,
    this.guestRequestId,
    this.mimeType,
    this.sizeBytes,
  });

  factory CareConsultationAttachment.fromJson(CareJson json) =>
      CareConsultationAttachment(
        id: _requiredId(json),
        consultationId: _string(json['consultation_id']),
        patientId: _nullableString(json['patient_id']),
        guestRequestId: _nullableString(json['guest_request_id']),
        fileName: _string(json['file_name']),
        storagePath: _string(json['storage_path']),
        mimeType: _nullableString(json['mime_type']),
        sizeBytes: _nullableInt(json['size_bytes']),
        createdAt: _date(json['created_at']),
      );

  final String id;
  final String consultationId;
  final String? patientId;
  final String? guestRequestId;
  final String fileName;
  final String storagePath;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime createdAt;
}

class CarePatientConsent {
  const CarePatientConsent({
    required this.id,
    required this.patientId,
    required this.consentType,
    required this.consentVersion,
    required this.isGranted,
    required this.metadata,
    required this.updatedAt,
    this.grantedAt,
    this.revokedAt,
  });

  factory CarePatientConsent.fromJson(CareJson json) => CarePatientConsent(
    id: _requiredId(json),
    patientId: _string(json['patient_id']),
    consentType: _string(json['consent_type']),
    consentVersion: _string(json['consent_version'], fallback: '1'),
    isGranted: json['is_granted'] == true,
    grantedAt: _nullableDate(json['granted_at']),
    revokedAt: _nullableDate(json['revoked_at']),
    metadata: json['metadata'] is Map
        ? CareJson.from(json['metadata'] as Map)
        : const {},
    updatedAt: _date(json['updated_at']),
  );

  final String id;
  final String patientId;
  final String consentType;
  final String consentVersion;
  final bool isGranted;
  final DateTime? grantedAt;
  final DateTime? revokedAt;
  final CareJson metadata;
  final DateTime updatedAt;
}

class CareLaboratoryResult {
  const CareLaboratoryResult({
    required this.id,
    required this.patientId,
    required this.testName,
    required this.status,
    required this.filePath,
    required this.uploadedAt,
    this.consultationId,
    this.extractedText,
    this.aiSummary,
    this.aiPossibleFindings,
    this.doctorConfirmedFindings,
    this.professionalInterpretation,
  });

  factory CareLaboratoryResult.fromJson(CareJson json) => CareLaboratoryResult(
    id: _requiredId(json),
    patientId: _string(json['patient_id']),
    testName: _string(json['test_name']),
    status: _string(json['verification_status'], fallback: 'uploaded'),
    filePath: _string(json['file_path']),
    uploadedAt: _date(json['uploaded_at']),
    consultationId: _nullableString(json['consultation_id']),
    extractedText: _nullableString(json['extracted_text']),
    aiSummary: _nullableString(json['ai_summary']),
    aiPossibleFindings: json['ai_possible_findings'],
    doctorConfirmedFindings: _nullableString(json['doctor_confirmed_findings']),
    professionalInterpretation: _nullableString(
      json['professional_interpretation'],
    ),
  );

  final String id;
  final String patientId;
  final String testName;
  final String status;
  final String filePath;
  final DateTime uploadedAt;
  final String? consultationId;
  final String? extractedText;
  final String? aiSummary;
  final dynamic aiPossibleFindings;
  final String? doctorConfirmedFindings;
  final String? professionalInterpretation;
}

class CareLaboratoryRequest {
  const CareLaboratoryRequest({
    required this.id,
    required this.patientId,
    required this.testName,
    required this.priority,
    required this.status,
    required this.requestedAt,
    this.consultationId,
    this.instructions,
    this.dueAt,
    this.completedAt,
  });

  factory CareLaboratoryRequest.fromJson(CareJson json) =>
      CareLaboratoryRequest(
        id: _requiredId(json),
        patientId: _string(json['patient_id']),
        testName: _string(json['test_name']),
        priority: _string(json['priority'], fallback: 'routine'),
        status: _string(json['status'], fallback: 'requested'),
        requestedAt: _date(json['requested_at'] ?? json['created_at']),
        consultationId: _nullableString(json['consultation_id']),
        instructions: _nullableString(json['instructions']),
        dueAt: _nullableDate(json['due_at']),
        completedAt: _nullableDate(json['completed_at']),
      );

  final String id;
  final String patientId;
  final String testName;
  final String priority;
  final String status;
  final DateTime requestedAt;
  final String? consultationId;
  final String? instructions;
  final DateTime? dueAt;
  final DateTime? completedAt;
}

class CarePrescription {
  const CarePrescription({
    required this.id,
    required this.patientId,
    required this.consultationId,
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.createdAt,
    this.instructions,
  });

  factory CarePrescription.fromJson(CareJson json) => CarePrescription(
    id: _requiredId(json),
    patientId: _string(json['patient_id']),
    consultationId: _string(json['consultation_id']),
    medicationName: _string(json['medication_name']),
    dosage: _string(json['dosage']),
    frequency: _string(json['frequency']),
    duration: _string(json['duration']),
    instructions: _nullableString(json['instructions']),
    createdAt: _date(json['created_at']),
  );

  final String id;
  final String patientId;
  final String consultationId;
  final String medicationName;
  final String dosage;
  final String frequency;
  final String duration;
  final String? instructions;
  final DateTime createdAt;
}

class CareConversation {
  const CareConversation({
    required this.id,
    required this.consultationId,
    required this.status,
    required this.updatedAt,
    this.patientId,
    this.guestRequestId,
    this.doctorId,
    this.doctorName,
  });

  factory CareConversation.fromJson(CareJson json) => CareConversation(
    id: _requiredId(json),
    consultationId: _string(json['consultation_id']),
    status: _string(json['status'], fallback: 'pending'),
    updatedAt: _date(json['updated_at'] ?? json['created_at']),
    patientId: _nullableString(json['patient_id']),
    guestRequestId: _nullableString(json['guest_request_id']),
    doctorId: _nullableString(json['doctor_id']),
    doctorName: _nullableString(_relation(json['doctors'])?['display_name']),
  );

  final String id;
  final String consultationId;
  final String status;
  final DateTime updatedAt;
  final String? patientId;
  final String? guestRequestId;
  final String? doctorId;
  final String? doctorName;
}

class CareMessage {
  const CareMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.sentAt,
    this.message,
    this.attachmentPath,
    this.deliveredAt,
    this.readAt,
  });

  factory CareMessage.fromJson(CareJson json) => CareMessage(
    id: _requiredId(json),
    conversationId: _string(json['conversation_id']),
    senderId: _string(json['sender_id']),
    message: _nullableString(json['message']),
    attachmentPath: _nullableString(json['attachment_path']),
    sentAt: _date(json['sent_at']),
    deliveredAt: _nullableDate(json['delivered_at']),
    readAt: _nullableDate(json['read_at']),
  );

  final String id;
  final String conversationId;
  final String senderId;
  final String? message;
  final String? attachmentPath;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
}

class CareNotification {
  const CareNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.referenceId,
  });

  factory CareNotification.fromJson(CareJson json) => CareNotification(
    id: _requiredId(json),
    title: _string(json['title']),
    message: _string(json['message']),
    type: _string(json['notification_type']),
    isRead: json['is_read'] == true,
    createdAt: _date(json['created_at']),
    referenceId: _nullableString(json['reference_id']),
  );

  final String id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final String? referenceId;
}

class CareNotificationPreferences {
  const CareNotificationPreferences({
    required this.userId,
    required this.consultationUpdates,
    required this.appointmentReminders,
    required this.medicalResults,
    required this.prescriptions,
    required this.messages,
    required this.hospitalAlerts,
    required this.emailEnabled,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  factory CareNotificationPreferences.fromJson(CareJson json) =>
      CareNotificationPreferences(
        userId: _string(json['user_id']),
        consultationUpdates: json['consultation_updates'] != false,
        appointmentReminders: json['appointment_reminders'] != false,
        medicalResults: json['medical_results'] != false,
        prescriptions: json['prescriptions'] != false,
        messages: json['messages'] != false,
        hospitalAlerts: json['hospital_alerts'] != false,
        emailEnabled: json['email_enabled'] == true,
        quietHoursStart: _nullableString(json['quiet_hours_start']),
        quietHoursEnd: _nullableString(json['quiet_hours_end']),
      );

  final String userId;
  final bool consultationUpdates;
  final bool appointmentReminders;
  final bool medicalResults;
  final bool prescriptions;
  final bool messages;
  final bool hospitalAlerts;
  final bool emailEnabled;
  final String? quietHoursStart;
  final String? quietHoursEnd;
}

class CareVideoSession {
  const CareVideoSession({
    required this.consultationId,
    required this.status,
    this.id,
    this.provider,
    this.meetingUrl,
    this.startsAt,
    this.endsAt,
  });

  factory CareVideoSession.fromJson(CareJson json) => CareVideoSession(
    id: _nullableString(json['id']),
    consultationId: _string(json['consultation_id']),
    provider: _nullableString(json['provider']),
    meetingUrl: _nullableString(
      json['join_url'] ?? json['meeting_url'] ?? json['meeting_link'],
    ),
    status: _string(json['status'], fallback: 'scheduled'),
    startsAt: _nullableDate(json['starts_at'] ?? json['appointment_date']),
    endsAt: _nullableDate(json['ends_at']),
  );

  final String? id;
  final String consultationId;
  final String? provider;
  final String? meetingUrl;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
}

class HospitalRecommendation {
  const HospitalRecommendation({
    required this.hospitalId,
    required this.hospitalName,
    required this.score,
    this.distanceKm,
    this.reason,
    this.raw = const {},
  });

  factory HospitalRecommendation.fromJson(CareJson json) =>
      HospitalRecommendation(
        hospitalId: _string(json['hospital_id'] ?? json['id']),
        hospitalName: _string(json['hospital_name'], fallback: 'Hospital'),
        score: _number(
          json['score'] ?? json['match_score'] ?? json['recommendation_score'],
        ),
        distanceKm: _nullableNumber(json['distance_km']),
        reason: _nullableString(json['reason']),
        raw: json,
      );

  final String hospitalId;
  final String hospitalName;
  final double score;
  final double? distanceKm;
  final String? reason;
  final CareJson raw;
}

class AnalyticsSnapshot {
  const AnalyticsSnapshot({required this.values, required this.generatedAt});

  factory AnalyticsSnapshot.fromJson(CareJson json) => AnalyticsSnapshot(
    values: json,
    generatedAt: _nullableDate(json['generated_at']) ?? DateTime.now().toUtc(),
  );

  final CareJson values;
  final DateTime generatedAt;
}

class SystemSetting {
  const SystemSetting({
    required this.key,
    required this.value,
    this.description,
    this.updatedAt,
  });

  factory SystemSetting.fromJson(CareJson json) => SystemSetting(
    key: _string(json['key'] ?? json['setting_key']),
    value: json['value'] ?? json['setting_value'],
    description: _nullableString(json['description']),
    updatedAt: _nullableDate(json['updated_at']),
  );

  final String key;
  final dynamic value;
  final String? description;
  final DateTime? updatedAt;
}

List<CareJson> _maps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => CareJson.from(item))
      .toList(growable: false);
}

CareJson? _relation(dynamic value) {
  if (value is Map) return CareJson.from(value);
  final values = _maps(value);
  return values.isEmpty ? null : values.first;
}

String _requiredId(CareJson json) {
  final value = _string(json['id']);
  if (value.isEmpty) throw const FormatException('Record id is missing.');
  return value;
}

String _string(dynamic value, {String fallback = ''}) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

String? _nullableString(dynamic value) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? null : result;
}

List<String> _strings(dynamic value) => value is List
    ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
    : const [];

DateTime _date(dynamic value) =>
    _nullableDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _nullableDate(dynamic value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

double _number(dynamic value) => _nullableNumber(value) ?? 0;

double? _nullableNumber(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _nullableInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String? _displayName(CareJson? user) {
  if (user == null) return null;
  final fullName = [
    _nullableString(user['first_name']),
    _nullableString(user['last_name']),
  ].whereType<String>().join(' ').trim();
  return fullName.isEmpty ? _nullableString(user['email']) : fullName;
}
