import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import '../models/clinical_checkup.dart';
import '../models/shared/patient_identity.dart';

abstract interface class CareRepository {
  Stream<List<CareMessage>> watchMessages(String conversationId);

  Stream<List<CareNotification>> watchNotifications();

  Future<void> markConversationRead(String conversationId);

  Future<void> markNotificationRead(String notificationId);

  Future<void> sendMessage({
    required String conversationId,
    required String body,
    String? patientId,
    ({List<int> bytes, String name})? attachment,
  });

  Future<Uri> createSignedFileUrl(String fileId);

  Future<String> currentPatientId();

  Future<void> bookAppointment({
    required String patientId,
    required DateTime appointmentDate,
    required String consultationType,
    required String chiefComplaint,
    ({List<int> bytes, String name})? attachment,
  });

  Future<void> recordPatientCheckup({
    required String patientId,
    required ClinicalCheckupDraft checkup,
    ({List<int> bytes, String name})? attachment,
  });

  Future<void> createPatientAccount({
    required String firstName,
    required String lastName,
    required DateTime birthDate,
    required String sex,
    required String mobileNumber,
    required String email,
    required String address,
    required String password,
  });

  Future<void> linkExistingPatient(String email);

  Future<void> requestConsultationAsPatient({
    required String hospitalId,
    required String departmentLabel,
    required String careMode,
    required DateTime preferredStart,
  });

  Future<void> analyzeMedicalResult(String resultId);

  Future<void> confirmMedicalResult({
    required String resultId,
    required String findings,
    String? interpretation,
  });

  Future<void> rejectMedicalResult({
    required String resultId,
    required String reason,
  });

  Future<void> createScheduleSlot({
    required int dayOfWeek,
    required String startsAt,
    required String endsAt,
    required String consultationType,
    required int slotMinutes,
  });

  Future<void> setScheduleActive({
    required String scheduleId,
    required bool active,
  });

  Future<void> deleteScheduleSlot({required String scheduleId});

  Future<List<ClinicalRelationship>> listClinicalRelationships();

  Future<void> createPrescription({
    required ClinicalRelationship relationship,
    required String medicationName,
    required String dosage,
    required String frequency,
    required String duration,
    String? instructions,
    ({List<int> bytes, String name})? attachment,
  });

  Future<void> createLaboratoryRequest({
    required ClinicalRelationship relationship,
    required String testName,
    required String priority,
    String? instructions,
    ({List<int> bytes, String name})? attachment,
  });

  Future<void> uploadMedicalFile({
    required String patientId,
    required String fileName,
    required String title,
    required String documentType,
    required List<int> bytes,
    String? referenceId,
    String? referenceType,
  });

  Future<void> deleteCareRecord({
    required String table,
    required String recordId,
  });
}

class CareMessage {
  const CareMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.message,
    required this.sentAt,
    this.messageType = 'text',
    this.readAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String? message;
  final DateTime sentAt;
  final String messageType;
  final DateTime? readAt;

  factory CareMessage.fromJson(Map<String, dynamic> json) => CareMessage(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    senderId: json['sender_id'] as String,
    message: json['message'] as String?,
    sentAt: DateTime.parse(json['sent_at'] as String),
    messageType: json['message_type'] as String? ?? 'text',
    readAt: _optionalDateTime(json['read_at']),
  );
}

class CareNotification {
  const CareNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.actionPath,
  });

  final String id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final String? actionPath;

  factory CareNotification.fromJson(Map<String, dynamic> json) =>
      CareNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        type: json['notification_type'] as String,
        isRead: json['is_read'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        actionPath: (json['action_path'] ?? json['action_url']) as String?,
      );
}

class ClinicalRelationship {
  const ClinicalRelationship({
    required this.patientId,
    required this.patientLabel,
    required this.consultationId,
    required this.consultationLabel,
  });

  final String patientId;
  final String patientLabel;
  final String consultationId;
  final String consultationLabel;
}

class SupabaseCareRepository implements CareRepository {
  SupabaseCareRepository(this._client);

  static const _medicalBucket = 'medical-documents';
  static const _maximumMedicalFileSize = 20 * 1024 * 1024;
  static const _allowedMedicalTypes = <String, String>{
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
  };

  final SupabaseClient _client;

  @override
  Stream<List<CareMessage>> watchMessages(String conversationId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: const ['id'])
        .eq('conversation_id', conversationId)
        .order('sent_at')
        .map(
          (rows) => rows
              .map((row) => CareMessage.fromJson(row))
              .toList(growable: false),
        );
  }

  @override
  Stream<List<CareNotification>> watchNotifications() {
    return _client
        .from('notifications')
        .stream(primaryKey: const ['id'])
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => CareNotification.fromJson(row))
              .toList(growable: false),
        );
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    await _client.rpc<int>(
      'mark_conversation_read',
      params: {'target_conversation_id': conversationId},
    );
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    await _client.rpc<void>(
      'mark_notification_read',
      params: {'target_notification_id': notificationId},
    );
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String body,
    String? patientId,
    ({List<int> bytes, String name})? attachment,
  }) async {
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) {
      throw ArgumentError.value(body, 'body', 'A message cannot be empty.');
    }
    final messageId = await _client.rpc<String>(
      'send_chat_message',
      params: {
        'target_conversation_id': conversationId,
        'message_body': normalizedBody,
      },
    );

    if (attachment != null && messageId != null && patientId != null) {
      await uploadMedicalFile(
        patientId: patientId,
        fileName: attachment.name,
        title: 'Message Attachment',
        documentType: 'chat_message',
        bytes: attachment.bytes,
        referenceId: messageId,
        referenceType: 'chat_message',
      );
    }
  }

  @override
  Future<Uri> createSignedFileUrl(String fileId) async {
    final row = await _client
        .from('medical_documents')
        .select('storage_bucket,storage_path')
        .eq('id', fileId)
        .single();
    await _client.rpc<int>(
      'record_clinical_access',
      params: {
        'target_resource_type': 'medical_document',
        'target_resource_id': fileId,
        'target_action': 'download',
      },
    );
    final url = await _client.storage
        .from(row['storage_bucket'] as String)
        .createSignedUrl(row['storage_path'] as String, 60);
    return Uri.parse(url);
  }

  @override
  Future<String> currentPatientId() async {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('An authenticated patient account is required.');
    }
    final appUser = await _client
        .from('users')
        .select('id')
        .eq('auth_user_id', user.id)
        .single();
    final patient = await _client
        .from('patients')
        .select('id')
        .eq('user_id', appUser['id'])
        .single();
    return patient['id'] as String;
  }

  @override
  Future<void> bookAppointment({
    required String patientId,
    required DateTime appointmentDate,
    required String consultationType,
    required String chiefComplaint,
    ({List<int> bytes, String name})? attachment,
  }) async {
    final doctor = await _currentDoctor();
    final result = await _client.from('consultations').insert({
      'patient_id': patientId,
      'doctor_id': doctor['id'],
      'hospital_id': doctor['hospital_id'],
      'appointment_date': appointmentDate.toIso8601String(),
      'consultation_type': consultationType,
      'chief_complaint': chiefComplaint.trim(),
      'status': 'scheduled',
    }).select('id').single();

    if (attachment != null) {
      await uploadMedicalFile(
        patientId: patientId,
        fileName: attachment.name,
        title: 'Appointment Attachment',
        documentType: 'appointment',
        bytes: attachment.bytes,
        referenceId: result['id'].toString(),
        referenceType: 'consultation',
      );
    }
  }

  @override
  Future<void> recordPatientCheckup({
    required String patientId,
    required ClinicalCheckupDraft checkup,
    ({List<int> bytes, String name})? attachment,
  }) async {
    if (patientId.trim().isEmpty) {
      throw ArgumentError('A patient is required for a checkup.');
    }
    if (!checkup.hasAnyData) {
      throw ArgumentError('Add at least one checkup detail before saving.');
    }
    try {
      final result = await _client.rpc<Map<String, dynamic>>(
        'record_patient_checkup',
        params: {
          'target_patient_id': patientId,
          'checkup_payload': checkup.toPayload(),
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (attachment != null && result != null && result['id'] != null) {
        await uploadMedicalFile(
          patientId: patientId,
          fileName: attachment.name,
          title: 'Checkup Attachment',
          documentType: 'medical_record',
          bytes: attachment.bytes,
          referenceId: result['id'].toString(),
          referenceType: 'medical_record',
        );
      }
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> createPatientAccount({
    required String firstName,
    required String lastName,
    required DateTime birthDate,
    required String sex,
    required String mobileNumber,
    required String email,
    required String address,
    required String password,
  }) async {
    final identity = PatientIdentity(
      firstName: firstName,
      lastName: lastName,
      birthDate: birthDate,
      sex: sex,
      mobileNumber: mobileNumber,
      email: email,
      address: address,
    );
    if (!identity.isComplete) {
      throw ArgumentError('Complete every patient identity field.');
    }
    if (password.length < 12 ||
        !RegExp('[a-z]').hasMatch(password) ||
        !RegExp('[A-Z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      throw ArgumentError(
        'Use at least 12 characters with upper-case, lower-case, number, and symbol characters.',
      );
    }
    final response = await _client.functions.invoke(
      'care-workflows',
      body: {
        'action': 'create_direct_patient_account',
        'first_name': identity.firstName.trim(),
        'last_name': identity.lastName.trim(),
        'birth_date': patientDateValue(birthDate),
        'sex': identity.sex!.trim(),
        'mobile_number': identity.mobileNumber.trim(),
        'email': identity.email.trim().toLowerCase(),
        'address': identity.address.trim(),
        'password': password,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError(
        message?.toString() ?? 'Could not create the patient account.',
      );
    }
  }

  @override
  Future<void> linkExistingPatient(String email) async {
    final user = await _client
        .from('users')
        .select('id')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
    if (user == null) throw StateError('No patient account found with that email.');

    final patient = await _client
        .from('patients')
        .select('id')
        .eq('user_id', user['id'])
        .maybeSingle();
    if (patient == null) throw StateError('The user is not registered as a patient.');

    final authUser = _client.auth.currentUser;
    if (authUser == null) throw StateError('Doctor session not found.');

    final doctorUser = await _client
        .from('users')
        .select('id')
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    if (doctorUser == null) throw StateError('Doctor account not found.');

    final doctor = await _client
        .from('doctors')
        .select('id')
        .eq('user_id', doctorUser['id'])
        .maybeSingle();
    if (doctor == null) throw StateError('Doctor profile not found.');

    try {
      await _client.from('doctor_patient_assignments').insert({
        'doctor_id': doctor['id'],
        'patient_id': patient['id'],
        'assigned_by': doctorUser['id'],
      });
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw StateError('This patient is already linked to your account.');
      }
      throw StateError(error.message);
    }
  }

  @override
  Future<void> requestConsultationAsPatient({
    required String hospitalId,
    required String departmentLabel,
    required String careMode,
    required DateTime preferredStart,
  }) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) throw StateError('User session not found.');

    final user = await _client
        .from('users')
        .select('id')
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    if (user == null) throw StateError('Account not found.');

    final patient = await _client
        .from('patients')
        .select('id')
        .eq('user_id', user['id'])
        .maybeSingle();
    if (patient == null) throw StateError('The user is not registered as a patient.');

    final department = await _client
        .from('hospital_departments')
        .select('id')
        .eq('hospital_id', hospitalId)
        .ilike('department_name', departmentLabel)
        .maybeSingle();
    if (department == null) throw StateError('Department not found in this hospital.');

    try {
      await _client.from('consultations').insert({
        'hospital_id': hospitalId,
        'department_id': department['id'],
        'patient_id': patient['id'],
        'consultation_type': careMode.toLowerCase().contains('online') ? 'online' : 'in-person',
        'appointment_date': preferredStart.toIso8601String(),
        'status': 'pending',
      });
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> analyzeMedicalResult(String resultId) async {
    final response = await _client.functions.invoke(
      'analyze-medical-result',
      body: {'laboratory_result_id': resultId},
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError(
        message?.toString() ?? 'Preliminary result analysis could not start.',
      );
    }
  }

  @override
  Future<void> confirmMedicalResult({
    required String resultId,
    required String findings,
    String? interpretation,
  }) async {
    final normalizedFindings = findings.trim();
    if (normalizedFindings.length < 5) {
      throw ArgumentError('Doctor-confirmed findings are required.');
    }
    await _client.rpc<Map<String, dynamic>>(
      'confirm_medical_result',
      params: {
        'target_result_id': resultId,
        'confirmed_findings': normalizedFindings,
        'interpretation': interpretation?.trim(),
        'create_record': true,
      },
    );
  }

  @override
  Future<void> rejectMedicalResult({
    required String resultId,
    required String reason,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.length < 5) {
      throw ArgumentError('A clinical rejection reason is required.');
    }
    final doctor = await _currentDoctor();
    await _client
        .from('laboratory_results')
        .update({
          'verification_status': 'rejected',
          'reviewed_by': doctor['id'],
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'rejection_reason': normalizedReason,
        })
        .eq('id', resultId)
        .select('id')
        .single();
  }

  @override
  Future<void> createScheduleSlot({
    required int dayOfWeek,
    required String startsAt,
    required String endsAt,
    required String consultationType,
    required int slotMinutes,
  }) async {
    if (dayOfWeek < 0 || dayOfWeek > 6) {
      throw ArgumentError('Day of week must be between 0 and 6.');
    }
    if (!{'online', 'in_person'}.contains(consultationType)) {
      throw ArgumentError('Unsupported consultation type.');
    }
    if (slotMinutes < 10 || slotMinutes > 240) {
      throw ArgumentError('Slot duration must be between 10 and 240 minutes.');
    }
    final doctor = await _currentDoctor();
    await _client.from('doctor_schedules').insert({
      'doctor_id': doctor['id'],
      'day_of_week': dayOfWeek,
      'starts_at': startsAt,
      'ends_at': endsAt,
      'consultation_type': consultationType,
      'slot_minutes': slotMinutes,
      'is_active': true,
    });
  }

  @override
  Future<void> setScheduleActive({
    required String scheduleId,
    required bool active,
  }) async {
    await _client
        .from('doctor_schedules')
        .update({'is_active': active})
        .eq('id', scheduleId)
        .select('id')
        .single();
  }

  @override
  Future<void> deleteScheduleSlot({required String scheduleId}) async {
    final doctor = await _currentDoctor();
    final schedule = await _client
        .from('doctor_schedules')
        .select('id,doctor_id,day_of_week,starts_at,ends_at,consultation_type')
        .eq('id', scheduleId)
        .eq('doctor_id', doctor['id'])
        .single();
    final consultations = await _client
        .from('consultations')
        .select('appointment_date,consultation_type,status')
        .eq('doctor_id', doctor['id'])
        .neq('status', 'rejected')
        .neq('status', 'cancelled');
    final booked = consultations.any(
      (row) => _appointmentMatchesSchedule(row, schedule),
    );
    if (booked) {
      throw StateError(
        'This availability protects an existing appointment and cannot be deleted.',
      );
    }
    await _client
        .from('doctor_schedules')
        .delete()
        .eq('id', scheduleId)
        .eq('doctor_id', doctor['id'])
        .select('id')
        .single();
  }

  bool _appointmentMatchesSchedule(
    Map<String, dynamic> consultation,
    Map<String, dynamic> schedule,
  ) {
    final appointment = DateTime.tryParse(
      consultation['appointment_date']?.toString() ?? '',
    );
    if (appointment == null) return false;
    if (consultation['consultation_type']?.toString() !=
        schedule['consultation_type']?.toString()) {
      return false;
    }
    final local = appointment.toLocal();
    final databaseDay = local.weekday % 7;
    if (databaseDay != (schedule['day_of_week'] as num).toInt()) return false;
    final appointmentMinutes = local.hour * 60 + local.minute;
    final start = _timeMinutes(schedule['starts_at']?.toString());
    final end = _timeMinutes(schedule['ends_at']?.toString());
    return start != null &&
        end != null &&
        appointmentMinutes >= start &&
        appointmentMinutes < end;
  }

  int? _timeMinutes(String? value) {
    final parts = (value ?? '').split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  @override
  Future<List<ClinicalRelationship>> listClinicalRelationships() async {
    final doctor = await _currentDoctor();
    final consultationRows = await _client
        .from('consultations')
        .select('id,patient_id,chief_complaint,status,appointment_date')
        .eq('doctor_id', doctor['id'])
        .order('appointment_date', ascending: false)
        .limit(100);
    final eligible = consultationRows
        .where((row) => row['patient_id'] != null)
        .toList(growable: false);
    final patientIds = eligible
        .map((row) => row['patient_id'].toString())
        .toSet()
        .toList(growable: false);
    final patientRows = patientIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
              .from('patients')
              .select('id,patient_number')
              .inFilter('id', patientIds);
    final patientLabels = {
      for (final row in patientRows)
        row['id'].toString():
            row['patient_number']?.toString() ??
            'Patient ${_shortId(row['id'].toString())}',
    };
    return eligible
        .map(
          (row) => ClinicalRelationship(
            patientId: row['patient_id'].toString(),
            patientLabel:
                patientLabels[row['patient_id'].toString()] ??
                'Patient ${_shortId(row['patient_id'].toString())}',
            consultationId: row['id'].toString(),
            consultationLabel:
                '${row['chief_complaint'] ?? 'Consultation'} · ${row['status']}',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> createPrescription({
    required ClinicalRelationship relationship,
    required String medicationName,
    required String dosage,
    required String frequency,
    required String duration,
    String? instructions,
    ({List<int> bytes, String name})? attachment,
  }) async {
    final values = [medicationName, dosage, frequency, duration];
    if (values.any((value) => value.trim().isEmpty)) {
      throw ArgumentError(
        'Medication, dosage, frequency, and duration are required.',
      );
    }
    final doctor = await _currentDoctor();
    final result = await _client.from('prescriptions').insert({
      'patient_id': relationship.patientId,
      'doctor_id': doctor['id'],
      'consultation_id': relationship.consultationId,
      'hospital_id': doctor['hospital_id'],
      'medication_name': medicationName.trim(),
      'dosage': dosage.trim(),
      'frequency': frequency.trim(),
      'duration': duration.trim(),
      'instructions': _nullableText(instructions),
    }).select('id').single();

    if (attachment != null) {
      await uploadMedicalFile(
        patientId: relationship.patientId,
        fileName: attachment.name,
        title: 'Prescription Attachment',
        documentType: 'prescription',
        bytes: attachment.bytes,
        referenceId: result['id'] as String,
        referenceType: 'prescription',
      );
    }
  }

  @override
  Future<void> createLaboratoryRequest({
    required ClinicalRelationship relationship,
    required String testName,
    required String priority,
    String? instructions,
    ({List<int> bytes, String name})? attachment,
  }) async {
    final normalizedTest = testName.trim();
    if (normalizedTest.isEmpty) {
      throw ArgumentError('A laboratory test name is required.');
    }
    if (!{'routine', 'urgent', 'stat'}.contains(priority)) {
      throw ArgumentError('Unsupported laboratory priority.');
    }
    final doctor = await _currentDoctor();
    final result = await _client.from('laboratory_requests').insert({
      'patient_id': relationship.patientId,
      'consultation_id': relationship.consultationId,
      'doctor_id': doctor['id'],
      'hospital_id': doctor['hospital_id'],
      'test_name': normalizedTest,
      'priority': priority,
      'instructions': _nullableText(instructions),
    }).select('id').single();

    if (attachment != null) {
      await uploadMedicalFile(
        patientId: relationship.patientId,
        fileName: attachment.name,
        title: 'Laboratory Request Attachment',
        documentType: 'laboratory_request',
        bytes: attachment.bytes,
        referenceId: result['id'] as String,
        referenceType: 'laboratory_request',
      );
    }
  }

  @override
  Future<void> uploadMedicalFile({
    required String patientId,
    required String fileName,
    required String title,
    required String documentType,
    required List<int> bytes,
    String? referenceId,
    String? referenceType,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('An authenticated account is required to upload files.');
    }
    if (bytes.isEmpty || bytes.length > _maximumMedicalFileSize) {
      throw ArgumentError('Medical files must be between 1 byte and 20 MB.');
    }
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    final mimeType = _allowedMedicalTypes[extension];
    if (mimeType == null) {
      throw ArgumentError(
        'Only PDF, JPEG, and PNG medical files are supported.',
      );
    }
    final normalizedTitle = title.trim();
    final normalizedType = documentType.trim();
    if (normalizedTitle.isEmpty || normalizedType.isEmpty) {
      throw ArgumentError('A title and document type are required.');
    }

    final appUser = await _client
        .from('users')
        .select('id')
        .eq('auth_user_id', user.id)
        .single();
    final safeName = _safeFileName(fileName);
    final storagePath =
        '$patientId/${user.id}/${DateTime.now().toUtc().microsecondsSinceEpoch}-$safeName';

    await _client.storage
        .from(_medicalBucket)
        .uploadBinary(
          storagePath,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    try {
      await _client.from('medical_documents').insert({
        'patient_id': patientId,
        'uploaded_by': appUser['id'],
        'document_type': normalizedType,
        'title': normalizedTitle,
        'storage_bucket': _medicalBucket,
        'storage_path': storagePath,
        'mime_type': mimeType,
        'size_bytes': bytes.length,
        if (referenceId != null) 'reference_id': referenceId,
        if (referenceType != null) 'reference_type': referenceType,
      });
    } catch (_) {
      await _client.storage.from(_medicalBucket).remove([storagePath]);
      rethrow;
    }
  }

  @override
  Future<void> deleteCareRecord({
    required String table,
    required String recordId,
  }) async {
    final validTables = {'prescriptions', 'laboratory_results', 'medical_records', 'laboratory_requests'};
    if (!validTables.contains(table)) {
      throw ArgumentError('Invalid table for care record deletion.');
    }
    await _client.from(table).delete().eq('id', recordId);
  }

  Future<Map<String, dynamic>> _currentDoctor() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('An authenticated doctor is required.');
    final appUser = await _client
        .from('users')
        .select('id')
        .eq('auth_user_id', user.id)
        .single();
    return _client
        .from('doctors')
        .select('id,hospital_id')
        .eq('user_id', appUser['id'])
        .single();
  }
}

DateTime? _optionalDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

String _safeFileName(String fileName) {
  final leaf = fileName.replaceAll('\\', '/').split('/').last;
  final safe = leaf.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return safe.isEmpty ? 'medical-document' : safe;
}

String _shortId(String value) =>
    value.length <= 8 ? value : value.substring(0, 8).toUpperCase();

String? _nullableText(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
