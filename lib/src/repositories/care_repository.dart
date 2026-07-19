import 'dart:typed_data';

import 'package:care_navigator_ph/src/models/care_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class CareRepository {
  CareRepository(this._client);

  final SupabaseClient _client;

  static const _consultationSelect = '''
    *,
    patients(patient_number, users(first_name, last_name, email)),
    guest_consultation_requests(reference_number, full_name),
    doctors(display_name, specialization),
    hospitals(hospital_name)
  ''';

  static const _patientSelect = '''
    *,
    users(first_name, last_name, email, mobile_number, birth_date, sex, address),
    hospitals(hospital_name)
  ''';

  /// Loads only the modules used by the signed-in role. PostgreSQL RLS remains
  /// the row-level authority, while this role allowlist prevents a client from
  /// fetching sensitive modules it never renders (notably hospital admins).
  Future<CareJson> loadWorkspace(String role) async {
    const roles = {
      'guest',
      'patient',
      'doctor',
      'hospital_admin',
      'super_admin',
    };
    if (!roles.contains(role)) throw ArgumentError.value(role, 'role');
    _requireSession();

    final queries = <String, Future<dynamic>>{
      'consultations': _client
          .from('consultations')
          .select(_consultationSelect)
          .order('appointment_date', ascending: false),
      'conversations': _client
          .from('chat_conversations')
          .select(
            '*, doctors(display_name, specialization), '
            'consultations(appointment_date, status), '
            'patients(patient_number, users(first_name, last_name)), '
            'guest_consultation_requests(reference_number, full_name)',
          )
          .order('updated_at', ascending: false),
      'notifications': _client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(100),
    };

    if (role == 'guest' || role == 'doctor') {
      queries['guest_requests'] = _client
          .from('guest_consultation_requests')
          .select(
            '*, hospitals!preferred_hospital_id(hospital_name), '
            'hospital_departments!preferred_department_id(department_name), '
            'doctors!assigned_doctor_id(display_name, specialization)',
          )
          .order('created_at', ascending: false);
    }
    if (role == 'patient' || role == 'doctor' || role == 'hospital_admin') {
      queries['patients'] = _client
          .from('patients')
          .select(_patientSelect)
          .order('created_at', ascending: false);
    }
    if (role == 'patient' || role == 'doctor') {
      queries.addAll({
        'medical_records': _client
            .from('medical_records')
            .select(
              '*, doctors!medical_records_doctor_id_fkey(display_name), '
              'hospitals(hospital_name), '
              'consultations(appointment_date, consultation_type)',
            )
            .order('record_date', ascending: false),
        'diagnoses': _client
            .from('diagnoses')
            .select(
              '*, doctors(display_name), hospitals(hospital_name), '
              'consultations(appointment_date, status)',
            )
            .order('confirmed_at', ascending: false),
        'treatment_plans': _client
            .from('treatment_plans')
            .select(
              '*, doctors(display_name), hospitals(hospital_name), '
              'consultations(appointment_date, status)',
            )
            .order('created_at', ascending: false),
        'laboratory_requests': _client
            .from('laboratory_requests')
            .select(
              '*, doctors(display_name), hospitals(hospital_name), '
              'consultations(appointment_date)',
            )
            .order('requested_at', ascending: false),
        'laboratory_results': _client
            .from('laboratory_results')
            .select(
              '*, doctors!laboratory_results_doctor_id_fkey(display_name), '
              'hospitals(hospital_name), '
              'consultations(appointment_date)',
            )
            .order('uploaded_at', ascending: false),
        'prescriptions': _client
            .from('prescriptions')
            .select(
              '*, doctors(display_name), '
              'consultations(appointment_date, status)',
            )
            .order('created_at', ascending: false),
        'medical_documents': _client
            .from('medical_documents')
            .select(
              '*, users!medical_documents_uploaded_by_fkey(first_name, last_name), '
              'hospitals(hospital_name), '
              'consultations(appointment_date, status)',
            )
            .order('created_at', ascending: false),
        'consultation_attachments': _client
            .from('consultation_attachments')
            .select(
              '*, consultations(appointment_date, status, patient_id, '
              'guest_request_id, doctors(display_name))',
            )
            .order('created_at', ascending: false),
      });
    }
    if (role == 'patient') {
      queries['patient_consents'] = _client
          .from('patient_consents')
          .select()
          .order('updated_at', ascending: false);
    }

    final entries = queries.entries.toList(growable: false);
    final results = await Future.wait<dynamic>(
      entries.map((entry) => entry.value),
    );
    final workspace = <String, dynamic>{
      'role': role,
      for (final key in const [
        'consultations',
        'guest_requests',
        'patients',
        'medical_records',
        'diagnoses',
        'treatment_plans',
        'laboratory_requests',
        'laboratory_results',
        'prescriptions',
        'medical_documents',
        'consultation_attachments',
        'patient_consents',
        'conversations',
        'notifications',
      ])
        key: <CareJson>[],
    };
    for (var index = 0; index < entries.length; index++) {
      workspace[entries[index].key] = _rows(results[index]);
    }
    return workspace;
  }

  Future<RoleWorkspace> loadTypedWorkspace(String role) async =>
      RoleWorkspace.fromJson(role, await loadWorkspace(role));

  Future<List<CareJson>> listAvailableDoctorSlots({
    required String doctorId,
    required DateTime date,
    required String consultationType,
  }) async {
    _requireSession();
    const supportedTypes = {'online', 'face_to_face'};
    if (!supportedTypes.contains(consultationType)) {
      throw ArgumentError.value(consultationType, 'consultationType');
    }
    final result = await _client.rpc(
      'available_doctor_slots',
      params: {
        'target_doctor_id': doctorId,
        'target_date': _dateOnly(date),
        'target_type': consultationType,
      },
    );
    return _rows(result)
        .where(
          (slot) =>
              DateTime.tryParse(slot['slot_start']?.toString() ?? '') != null &&
              DateTime.tryParse(slot['slot_end']?.toString() ?? '') != null,
        )
        .toList(growable: false);
  }

  Future<CareJson> bookConsultation({
    required String doctorId,
    required String hospitalId,
    required String consultationType,
    required DateTime appointmentDate,
    required String chiefComplaint,
    String? patientId,
    String? guestRequestId,
  }) async {
    final result = await _client.rpc(
      'book_consultation',
      params: {
        'booking_payload': {
          'doctor_id': doctorId,
          'hospital_id': hospitalId,
          'consultation_type': consultationType,
          'appointment_date': appointmentDate.toUtc().toIso8601String(),
          'chief_complaint': chiefComplaint.trim(),
          'patient_id': ?patientId,
          'guest_request_id': ?guestRequestId,
        },
      },
    );
    return _resultMap(result, idKey: 'consultation_id');
  }

  Future<CareJson> reviewGuestConsultation({
    required String requestId,
    required String decision,
    String? assignedDoctorId,
    DateTime? appointmentDate,
    String? notes,
  }) async {
    final normalizedDecision = switch (decision) {
      'approve' => 'approved',
      'reject' => 'rejected',
      _ => decision,
    };
    final result = await _client.rpc(
      'review_guest_consultation',
      params: {
        'target_request_id': requestId,
        'decision': normalizedDecision,
        'target_doctor_id': assignedDoctorId,
        'target_appointment_date': appointmentDate?.toUtc().toIso8601String(),
        'review_notes': _nullable(notes),
      },
    );
    return _resultMap(result, idKey: 'guest_request_id');
  }

  Future<CareJson> transitionConsultation({
    required String consultationId,
    required String status,
    String? doctorNotes,
    String? confirmedDiagnosis,
    String? treatmentPlan,
    String? meetingLink,
    DateTime? scheduledFor,
  }) async {
    final clinicalPayload = <String, dynamic>{
      'doctor_notes': ?_nullable(doctorNotes),
      'confirmed_diagnosis': ?_nullable(confirmedDiagnosis),
      'treatment_plan': ?_nullable(treatmentPlan),
      'meeting_link': ?_nullable(meetingLink),
    };
    final result = await _client.rpc(
      'transition_consultation',
      params: {
        'target_consultation_id': consultationId,
        'target_status': status,
        'transition_notes': _nullable(doctorNotes),
        'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
        'clinical_payload': clinicalPayload,
      },
    );
    return _resultMap(result, idKey: 'consultation_id');
  }

  /// Creates the official auth/patient account after a doctor has approved a
  /// verified guest request. The service never returns the supplied password.
  Future<CareJson> createPatientAccount({
    required String guestRequestId,
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    String? assignedDoctorId,
  }) async {
    final response = await _client.functions.invoke(
      'care-workflows',
      body: {
        'action': 'create_patient_account',
        'guest_request_id': guestRequestId,
        'email': email.trim(),
        'password': password,
        'first_name': _nullable(firstName),
        'last_name': _nullable(lastName),
        'assigned_doctor_id': assignedDoctorId,
      },
    );
    return _functionMap(response, 'Patient account creation failed.');
  }

  Future<CareJson> createDirectPatientAccount({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? middleName,
    DateTime? birthDate,
    String? sex,
    String? mobileNumber,
    String? address,
  }) async {
    _requireSession();
    final response = await _client.functions.invoke(
      'care-workflows',
      body: {
        'action': 'create_direct_patient_account',
        'first_name': firstName.trim(),
        'middle_name': _nullable(middleName),
        'last_name': lastName.trim(),
        'email': email.trim(),
        'password': password,
        'birth_date': _dateOnly(birthDate),
        'sex': _nullable(sex),
        'mobile_number': _nullable(mobileNumber),
        'address': _nullable(address),
      },
    );
    return _functionMap(response, 'Direct patient account creation failed.');
  }

  Future<CareJson> uploadMedicalResult({
    required String patientId,
    required String hospitalId,
    required String testName,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? consultationId,
    String? extractedText,
  }) async {
    _requireSession();
    final doctorId = await _currentDoctorId(hospitalId: hospitalId);
    final extension = _safeExtension(fileName);
    final path = '$patientId/${const Uuid().v4()}.$extension';
    await _client.storage
        .from('laboratory-results')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    try {
      final result = await _client
          .from('laboratory_results')
          .insert({
            'patient_id': patientId,
            'doctor_id': doctorId,
            'hospital_id': hospitalId,
            'consultation_id': consultationId,
            'test_name': testName.trim(),
            'extracted_text': _nullable(extractedText),
            'file_path': path,
            'verification_status': extractedText == null
                ? 'uploaded'
                : 'ai_analysis_pending',
          })
          .select()
          .single();
      return CareJson.from(result);
    } catch (_) {
      await _client.storage.from('laboratory-results').remove([path]);
      rethrow;
    }
  }

  Future<CareJson> analyzeMedicalResult(String id) async {
    final response = await _client.functions.invoke(
      'analyze-medical-result',
      body: {'laboratory_result_id': id},
    );
    return _functionMap(response, 'Medical-result analysis failed.');
  }

  Future<CareJson> confirmMedicalResult({
    required String resultId,
    required String confirmedFindings,
    String? professionalInterpretation,
    bool saveToRecord = true,
  }) async {
    final result = await _client.rpc(
      'confirm_medical_result',
      params: {
        'target_result_id': resultId,
        'confirmed_findings': confirmedFindings.trim(),
        'interpretation': _nullable(professionalInterpretation),
        'create_record': saveToRecord,
      },
    );
    return _resultMap(result, idKey: 'laboratory_result_id');
  }

  Future<CareJson> saveMedicalRecord({
    String? id,
    required String patientId,
    required String hospitalId,
    required String recordType,
    required String title,
    String? consultationId,
    String? description,
    String? confirmedDiagnosis,
    String? treatmentPlan,
    DateTime? recordDate,
  }) async {
    final doctorId = await _currentDoctorId(hospitalId: hospitalId);
    final values = {
      'patient_id': patientId,
      'doctor_id': doctorId,
      'hospital_id': hospitalId,
      'consultation_id': consultationId,
      'record_type': recordType.trim(),
      'title': title.trim(),
      'description': _nullable(description),
      'confirmed_diagnosis': _nullable(confirmedDiagnosis),
      'treatment_plan': _nullable(treatmentPlan),
      'record_date': (recordDate ?? DateTime.now())
          .toIso8601String()
          .split('T')
          .first,
    };
    final query = id == null
        ? _client.from('medical_records').insert(values)
        : _client.from('medical_records').update(values).eq('id', id);
    return CareJson.from(await query.select().single());
  }

  /// Records a diagnosis as an immutable, doctor-confirmed clinical fact.
  /// The database intentionally exposes insert-only access for diagnoses.
  Future<CareJson> createDiagnosis({
    required String patientId,
    required String consultationId,
    required String diagnosis,
    String? diagnosisCode,
    bool isPrimary = false,
  }) async {
    final context = await _doctorConsultationContext(
      consultationId,
      expectedPatientId: patientId,
    );
    _requireClinicalStage(context);
    final value = diagnosis.trim();
    if (value.length < 2) {
      throw ArgumentError.value(diagnosis, 'diagnosis', 'Too short.');
    }
    final result = await _client
        .from('diagnoses')
        .insert({
          'patient_id': patientId,
          'consultation_id': consultationId,
          'doctor_id': context['doctor_id'],
          'hospital_id': context['hospital_id'],
          'diagnosis': value,
          'diagnosis_code': _nullable(diagnosisCode),
          'is_primary': isPrimary,
        })
        .select()
        .single();
    return CareJson.from(result);
  }

  Future<CareJson> saveTreatmentPlan({
    String? id,
    required String patientId,
    required String consultationId,
    required String plan,
    String status = 'active',
    DateTime? startsOn,
    DateTime? endsOn,
  }) async {
    final context = await _doctorConsultationContext(
      consultationId,
      expectedPatientId: patientId,
    );
    _requireClinicalStage(context);
    final value = plan.trim();
    if (value.length < 2) {
      throw ArgumentError.value(plan, 'plan', 'Too short.');
    }
    if (startsOn != null && endsOn != null && endsOn.isBefore(startsOn)) {
      throw ArgumentError('The treatment-plan end date precedes its start.');
    }
    const allowedStatuses = {'planned', 'active', 'completed', 'cancelled'};
    if (!allowedStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final values = {
      'patient_id': patientId,
      'consultation_id': consultationId,
      'doctor_id': context['doctor_id'],
      'hospital_id': context['hospital_id'],
      'plan': value,
      'status': status,
      'starts_on': _dateOnly(startsOn),
      'ends_on': _dateOnly(endsOn),
    };
    final query = id == null
        ? _client.from('treatment_plans').insert(values)
        : _client.from('treatment_plans').update(values).eq('id', id);
    return CareJson.from(await query.select().single());
  }

  Future<void> deleteTreatmentPlan(String id) async {
    _requireSession();
    await _client.from('treatment_plans').delete().eq('id', id);
  }

  Future<CareJson> uploadMedicalDocument({
    required String patientId,
    required String hospitalId,
    required String documentType,
    required String title,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? consultationId,
  }) async {
    _validateClinicalUpload(bytes, mimeType);
    await _currentDoctorId(hospitalId: hospitalId);
    if (consultationId != null) {
      await _doctorConsultationContext(
        consultationId,
        expectedPatientId: patientId,
      );
    }
    final appUserId = await _currentAppUserId();
    final path =
        '$patientId/medical-documents/${const Uuid().v4()}.${_safeExtension(fileName)}';
    await _client.storage
        .from('medical-documents')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    try {
      final result = await _client
          .from('medical_documents')
          .insert({
            'patient_id': patientId,
            'consultation_id': consultationId,
            'uploaded_by': appUserId,
            'hospital_id': hospitalId,
            'document_type': documentType.trim(),
            'title': title.trim(),
            'storage_bucket': 'medical-documents',
            'storage_path': path,
            'mime_type': mimeType,
            'size_bytes': bytes.length,
          })
          .select()
          .single();
      return CareJson.from(result);
    } catch (_) {
      await _client.storage.from('medical-documents').remove([path]);
      rethrow;
    }
  }

  Future<CareJson> uploadConsultationAttachment({
    required String patientId,
    required String consultationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    _validateClinicalUpload(bytes, mimeType);
    await _doctorConsultationContext(
      consultationId,
      expectedPatientId: patientId,
    );
    final authUserId = _requireSession().user.id;
    final path =
        '$consultationId/clinical/${const Uuid().v4()}.${_safeExtension(fileName)}';
    await _client.storage
        .from('consultation-attachments')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    try {
      final result = await _client
          .from('consultation_attachments')
          .insert({
            'consultation_id': consultationId,
            'patient_id': patientId,
            'guest_request_id': null,
            'uploaded_by': authUserId,
            'storage_path': path,
            'file_name': fileName.trim(),
            'mime_type': mimeType,
            'size_bytes': bytes.length,
          })
          .select()
          .single();
      return CareJson.from(result);
    } catch (_) {
      await _client.storage.from('consultation-attachments').remove([path]);
      rethrow;
    }
  }

  Future<CareJson> uploadPatientConsultationAttachment({
    required String consultationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    _validateClinicalUpload(bytes, mimeType);
    final patientId = await _currentPatientId();
    final consultation = await _client
        .from('consultations')
        .select('id, patient_id, guest_request_id, status')
        .eq('id', consultationId)
        .single();
    if (consultation['patient_id']?.toString() != patientId ||
        consultation['guest_request_id'] != null) {
      throw StateError(
        'Attachments can only be added to your own patient consultation.',
      );
    }
    const eligibleStatuses = {'approved', 'scheduled', 'in_progress'};
    if (!eligibleStatuses.contains(consultation['status']?.toString())) {
      throw StateError(
        'This consultation is not currently accepting patient attachments.',
      );
    }
    final authUserId = _requireSession().user.id;
    final path =
        '$consultationId/patient/${const Uuid().v4()}.${_safeExtension(fileName)}';
    await _client.storage
        .from('consultation-attachments')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    try {
      final result = await _client
          .from('consultation_attachments')
          .insert({
            'consultation_id': consultationId,
            'patient_id': patientId,
            'guest_request_id': null,
            'uploaded_by': authUserId,
            'storage_path': path,
            'file_name': fileName.trim(),
            'mime_type': mimeType,
            'size_bytes': bytes.length,
          })
          .select()
          .single();
      return CareJson.from(result);
    } catch (_) {
      await _client.storage.from('consultation-attachments').remove([path]);
      rethrow;
    }
  }

  Future<CareJson> savePatientConsent({
    required String consentType,
    required String consentVersion,
    required bool isGranted,
    required String policyTitle,
  }) async {
    const standardTypes = {
      'care_delivery',
      'telemedicine',
      'medical_record_sharing',
      'ai_assisted_document_analysis',
      'care_notifications',
    };
    if (!standardTypes.contains(consentType)) {
      throw ArgumentError.value(consentType, 'consentType');
    }
    final version = consentVersion.trim();
    if (version.isEmpty || version.length > 40) {
      throw ArgumentError.value(consentVersion, 'consentVersion');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final result = await _client
        .from('patient_consents')
        .upsert({
          'patient_id': await _currentPatientId(),
          'consent_type': consentType,
          'consent_version': version,
          'is_granted': isGranted,
          'granted_at': isGranted ? now : null,
          'revoked_at': isGranted ? null : now,
          'captured_by': _requireSession().user.id,
          'metadata': {
            'policy_title': policyTitle.trim(),
            'policy_version': version,
            'capture_channel': 'patient_care_workspace',
            'patient_decision_recorded_at': now,
          },
        }, onConflict: 'patient_id,consent_type,consent_version')
        .select()
        .single();
    return CareJson.from(result);
  }

  Future<CareJson> savePrescription({
    String? id,
    required String patientId,
    required String consultationId,
    required String medicationName,
    required String dosage,
    required String frequency,
    required String duration,
    String? instructions,
  }) async {
    final consultation = await _client
        .from('consultations')
        .select('doctor_id, hospital_id')
        .eq('id', consultationId)
        .single();
    final values = {
      'patient_id': patientId,
      'doctor_id': consultation['doctor_id'],
      'hospital_id': consultation['hospital_id'],
      'consultation_id': consultationId,
      'medication_name': medicationName.trim(),
      'dosage': dosage.trim(),
      'frequency': frequency.trim(),
      'duration': duration.trim(),
      'instructions': _nullable(instructions),
    };
    final query = id == null
        ? _client.from('prescriptions').insert(values)
        : _client.from('prescriptions').update(values).eq('id', id);
    return CareJson.from(await query.select().single());
  }

  Future<CareJson> ensureConversation(String consultationId) async {
    final result = await _client.rpc(
      'ensure_consultation_conversation',
      params: {'target_consultation_id': consultationId},
    );
    return _resultMap(result, idKey: 'conversation_id');
  }

  Future<List<CareJson>> listMessages(String conversationId) async => _rows(
    await _client
        .from('chat_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('sent_at'),
  );

  Stream<List<CareJson>> watchMessages(String conversationId) => _client
      .from('chat_messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .order('sent_at')
      .map(_rows);

  Future<CareJson> sendMessage({
    required String conversationId,
    String? message,
    Uint8List? attachmentBytes,
    String? attachmentName,
    String? attachmentMimeType,
  }) async {
    final cleanMessage = _nullable(message);
    final hasAttachment = attachmentBytes != null;
    if (cleanMessage == null && !hasAttachment) {
      throw ArgumentError('A message or attachment is required.');
    }
    if (hasAttachment &&
        (attachmentName == null || attachmentMimeType == null)) {
      throw ArgumentError('Attachment name and MIME type are required.');
    }

    String? attachmentPath;
    if (attachmentBytes != null) {
      final conversation = await _client
          .from('chat_conversations')
          .select('consultation_id')
          .eq('id', conversationId)
          .single();
      final consultationId = conversation['consultation_id'].toString();
      attachmentPath =
          '$consultationId/chat/${const Uuid().v4()}.${_safeExtension(attachmentName!)}';
      await _client.storage
          .from('consultation-attachments')
          .uploadBinary(
            attachmentPath,
            attachmentBytes,
            fileOptions: FileOptions(
              contentType: attachmentMimeType,
              upsert: false,
            ),
          );
    }

    try {
      final result = await _client.rpc(
        'send_chat_message',
        params: {
          'target_conversation_id': conversationId,
          'message_body': cleanMessage,
          'attachment_paths': attachmentPath == null
              ? const <String>[]
              : <String>[attachmentPath],
        },
      );
      return _resultMap(result, idKey: 'message_id');
    } catch (_) {
      if (attachmentPath != null) {
        await _client.storage.from('consultation-attachments').remove([
          attachmentPath,
        ]);
      }
      rethrow;
    }
  }

  Future<void> markConversationRead(String conversationId) async {
    await _client.rpc(
      'mark_conversation_read',
      params: {'target_conversation_id': conversationId},
    );
  }

  Future<List<CareJson>> listNotifications() async => _rows(
    await _client
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(100),
  );

  Stream<List<CareJson>> watchNotifications() {
    final userId = _requireSession().user.id;
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map(_rows);
  }

  Future<void> markNotificationRead(String id) async {
    await _client.rpc(
      'mark_notification_read',
      params: {'target_notification_id': id},
    );
  }

  Future<CareJson> getNotificationPreferences() async {
    final userId = _requireSession().user.id;
    final result = await _client
        .from('notification_preferences')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return result == null ? {'user_id': userId} : CareJson.from(result);
  }

  Future<CareJson> saveNotificationPreferences(CareJson values) async {
    final userId = _requireSession().user.id;
    final result = await _client
        .from('notification_preferences')
        .upsert({...values, 'user_id': userId}, onConflict: 'user_id')
        .select()
        .single();
    return CareJson.from(result);
  }

  Future<CareJson> getVideoSession(String consultationId) async {
    final session = await _client
        .from('video_sessions')
        .select(
          '*, consultations(appointment_date, status, consultation_type, '
          'doctors(display_name), hospitals(hospital_name))',
        )
        .eq('consultation_id', consultationId)
        .maybeSingle();
    if (session != null) return CareJson.from(session);

    final consultation = await _client
        .from('consultations')
        .select('id, status, consultation_type, appointment_date, meeting_link')
        .eq('id', consultationId)
        .single();
    return {
      'consultation_id': consultation['id'],
      'provider': 'external',
      'join_url': consultation['meeting_link'],
      'status': consultation['status'],
      'starts_at': consultation['appointment_date'],
    };
  }

  Future<CareJson> saveVideoSession({
    String? id,
    required String consultationId,
    required String provider,
    required String roomName,
    required String joinUrl,
    String status = 'ready',
    DateTime? startsAt,
    DateTime? expiresAt,
  }) async {
    final values = <String, dynamic>{
      'consultation_id': consultationId,
      'provider': provider.trim(),
      'room_name': roomName.trim(),
      'join_url': joinUrl.trim(),
      'status': status,
      'starts_at': startsAt?.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      if (id == null) 'created_by': _requireSession().user.id,
    };
    final query = id == null
        ? _client.from('video_sessions').insert(values)
        : _client.from('video_sessions').update(values).eq('id', id);
    return CareJson.from(await query.select().single());
  }

  Future<CareJson> ensureVideoSession(
    String consultationId, {
    String provider = 'jitsi',
  }) async {
    final result = await _client.rpc(
      'ensure_video_session',
      params: {
        'target_consultation_id': consultationId,
        'target_provider': provider,
      },
    );
    final sessionId = _resultMap(result, idKey: 'video_session_id');
    final session = await getVideoSession(consultationId);
    return {...session, ...sessionId};
  }

  Future<List<CareJson>> listLaboratoryRequests({String? patientId}) async {
    var query = _client
        .from('laboratory_requests')
        .select(
          '*, patients(patient_number, users(first_name, last_name)), '
          'doctors(display_name), consultations(appointment_date)',
        );
    if (patientId != null) query = query.eq('patient_id', patientId);
    return _rows(await query.order('created_at', ascending: false));
  }

  Future<CareJson> saveLaboratoryRequest({
    String? id,
    required String patientId,
    required String hospitalId,
    required String testName,
    String? consultationId,
    String? instructions,
    String priority = 'routine',
    String status = 'requested',
    DateTime? dueAt,
  }) async {
    final doctorId = await _currentDoctorId(hospitalId: hospitalId);
    final values = {
      'patient_id': patientId,
      'doctor_id': doctorId,
      'hospital_id': hospitalId,
      'consultation_id': consultationId,
      'test_name': testName.trim(),
      'instructions': _nullable(instructions),
      'priority': priority,
      'status': status,
      'due_at': dueAt?.toUtc().toIso8601String(),
    };
    final query = id == null
        ? _client.from('laboratory_requests').insert(values)
        : _client.from('laboratory_requests').update(values).eq('id', id);
    return CareJson.from(await query.select().single());
  }

  Future<CareJson> getHospitalAnalytics() async {
    final result = await _client.rpc('hospital_analytics');
    return _resultMap(result);
  }

  Future<CareJson> getPlatformAnalytics() async {
    final result = await _client.rpc('platform_analytics');
    return _resultMap(result);
  }

  Future<List<CareJson>> recommendHospitals({
    String? symptoms,
    String? urgencyLevel,
    String? department,
    List<String> requiredServices = const [],
    String? requiredSpecialization,
    double? latitude,
    double? longitude,
    double radiusKm = 100,
    int limit = 10,
  }) async {
    final result = await _client.rpc(
      'recommend_hospitals',
      params: {
        'user_latitude': latitude,
        'user_longitude': longitude,
        'required_department': _nullable(department),
        'required_services': requiredServices,
        'required_specialization': _nullable(requiredSpecialization),
        'requires_emergency': urgencyLevel == 'emergency',
        'radius_km': radiusKm,
        'result_limit': limit,
      },
    );
    return _rows(result);
  }

  Future<List<CareJson>> listSystemSettings() async =>
      _rows(await _client.from('system_settings').select().order('key'));

  Future<CareJson> saveSystemSetting({
    required String key,
    required dynamic value,
    String? description,
    bool isPublic = false,
  }) async {
    final result = await _client
        .from('system_settings')
        .upsert({
          'key': key.trim(),
          'value': value,
          'description': _nullable(description),
          'is_public': isPublic,
          'updated_by': await _currentAppUserId(),
        }, onConflict: 'key')
        .select()
        .single();
    return CareJson.from(result);
  }

  Future<String> createSignedMedicalUrl({
    required String bucket,
    required String path,
    int expiresInSeconds = 300,
  }) {
    const allowedBuckets = {
      'laboratory-results',
      'scanned-medical-results',
      'medical-documents',
      'prescriptions',
      'consultation-attachments',
    };
    if (!allowedBuckets.contains(bucket)) {
      throw ArgumentError.value(bucket, 'bucket');
    }
    return _client.storage.from(bucket).createSignedUrl(path, expiresInSeconds);
  }

  Future<String> createAuditedSignedMedicalUrl({
    required String resourceType,
    required String resourceId,
    required String bucket,
    required String path,
    String action = 'view',
    int expiresInSeconds = 300,
  }) async {
    const resourceTypes = {
      'laboratory_result',
      'medical_document',
      'consultation_attachment',
      'medical_record',
      'prescription',
    };
    if (!resourceTypes.contains(resourceType)) {
      throw ArgumentError.value(resourceType, 'resourceType');
    }
    if (!{'view', 'download'}.contains(action)) {
      throw ArgumentError.value(action, 'action');
    }
    if (resourceId.trim().isEmpty) {
      throw ArgumentError.value(resourceId, 'resourceId');
    }
    await _client.rpc(
      'record_clinical_access',
      params: {
        'target_resource_type': resourceType,
        'target_resource_id': resourceId,
        'target_action': action,
      },
    );
    return createSignedMedicalUrl(
      bucket: bucket,
      path: path,
      expiresInSeconds: expiresInSeconds,
    );
  }

  Session _requireSession() {
    final session = _client.auth.currentSession;
    if (session == null) throw const AuthException('Sign-in is required.');
    return session;
  }

  Future<CareJson> _doctorConsultationContext(
    String consultationId, {
    required String expectedPatientId,
  }) async {
    final consultation = CareJson.from(
      await _client
          .from('consultations')
          .select('id, patient_id, doctor_id, hospital_id, status')
          .eq('id', consultationId)
          .single(),
    );
    if (consultation['patient_id']?.toString() != expectedPatientId) {
      throw StateError('The consultation does not belong to this patient.');
    }
    final doctorId = await _currentDoctorId(
      hospitalId: consultation['hospital_id']?.toString(),
    );
    if (consultation['doctor_id']?.toString() != doctorId) {
      throw StateError(
        'Only the assigned doctor can add this clinical content.',
      );
    }
    return consultation;
  }

  Future<String> _currentDoctorId({String? hospitalId}) async {
    final appUserId = await _currentAppUserId();
    var query = _client.from('doctors').select('id').eq('user_id', appUserId);
    if (hospitalId != null) query = query.eq('hospital_id', hospitalId);
    final doctor = await query.single();
    return doctor['id'] as String;
  }

  Future<String> _currentPatientId() async {
    final appUserId = await _currentAppUserId();
    final patient = await _client
        .from('patients')
        .select('id')
        .eq('user_id', appUserId)
        .single();
    return patient['id'] as String;
  }

  Future<String> _currentAppUserId() async {
    final authUserId = _requireSession().user.id;
    final appUser = await _client
        .from('users')
        .select('id')
        .eq('auth_user_id', authUserId)
        .single();
    return appUser['id'] as String;
  }
}

List<CareJson> _rows(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => CareJson.from(row))
      .toList(growable: false);
}

CareJson _resultMap(dynamic value, {String idKey = 'id'}) {
  if (value is Map) return CareJson.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return CareJson.from(value.first as Map);
  }
  if (value == null) return const {};
  return {idKey: value};
}

CareJson _functionMap(FunctionResponse response, String fallbackMessage) {
  if (response.status < 200 || response.status >= 300) {
    final data = response.data;
    final message = data is Map ? data['error']?.toString() : null;
    throw Exception(message ?? fallbackMessage);
  }
  if (response.data is! Map) throw FormatException(fallbackMessage);
  return CareJson.from(response.data as Map);
}

String? _nullable(String? value) {
  final result = value?.trim();
  return result == null || result.isEmpty ? null : result;
}

String _safeExtension(String fileName) {
  final value = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : 'bin';
  return RegExp(r'^[a-z0-9]{1,10}$').hasMatch(value) ? value : 'bin';
}

void _validateClinicalUpload(Uint8List bytes, String mimeType) {
  const maxBytes = 20 * 1024 * 1024;
  const allowedMimeTypes = {'image/jpeg', 'image/png', 'application/pdf'};
  if (bytes.isEmpty) throw ArgumentError('The selected file is empty.');
  if (bytes.length > maxBytes) {
    throw ArgumentError('Clinical documents must be 20 MB or smaller.');
  }
  if (!allowedMimeTypes.contains(mimeType)) {
    throw ArgumentError.value(
      mimeType,
      'mimeType',
      'Only JPEG, PNG, and PDF files are supported.',
    );
  }
}

String? _dateOnly(DateTime? value) =>
    value?.toLocal().toIso8601String().split('T').first;

void _requireClinicalStage(CareJson consultation) {
  const clinicalStatuses = {'in_progress', 'completed'};
  final status = consultation['status']?.toString();
  if (!clinicalStatuses.contains(status)) {
    throw StateError(
      'Diagnoses and treatment plans require an in-progress or completed consultation.',
    );
  }
}
