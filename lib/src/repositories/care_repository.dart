import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import '../models/clinical_checkup.dart';
import '../models/consultation_scheduling.dart';
import '../models/consultation_type.dart';
import '../models/shared/patient_identity.dart';

abstract interface class CareRepository {
  Stream<List<CareMessage>> watchMessages(String conversationId);

  Stream<int> watchUnreadMessageCount(String currentUserId);

  Stream<List<CareNotification>> watchNotifications();

  Future<void> markConversationRead(String conversationId);

  Future<void> markNotificationRead(String notificationId);

  Future<void> decidePatientConnectionRequest({
    required String requestId,
    required bool approve,
  });

  Future<String> ensurePatientConversation(String patientId);

  Future<void> sendMessage({
    required String conversationId,
    required String body,
    ({List<int> bytes, String name})? attachment,
  });

  Future<Uri> createSignedMessageAttachmentUrl(String messageId);

  Future<Uri> createSignedFileUrl(String fileId);

  Future<String> currentPatientId();

  Future<void> reserveAppointment({
    required String patientId,
    required DateTime appointmentDate,
    required String consultationType,
    required String chiefComplaint,
    ({List<int> bytes, String name})? attachment,
  });

  Future<void> recordPatientCheckup({
    required String patientId,
    required ClinicalCheckupDraft checkup,
    required List<({List<int> bytes, String name})> attachments,
  });

  Future<ClinicalCheckupDraft> extractCheckupFromAttachments({
    required List<({List<int> bytes, String name})> attachments,
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

  Future<List<ExistingPatientMatch>> searchExistingPatients(String query);

  Future<void> linkExistingPatient(String patientId);

  Future<void> requestConsultationAsPatient({
    required String hospitalId,
    required String departmentLabel,
    required String careMode,
    required DateTime preferredStart,
    String? doctorId,
    String chiefComplaint = 'Consultation request',
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

  Future<PrescriberDetails> currentPrescriberDetails();

  Future<PrescriptionScanDraft> extractPrescriptionFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  });

  Future<List<PrescriptionScanDraft>> extractPrescriptionsFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  });

  Future<DiagnosticResultScanDraft> extractDiagnosticResultFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  });

  Future<List<DiagnosticResultScanDraft>>
  extractDiagnosticResultsFromAttachments({
    required List<({List<int> bytes, String name})> attachments,
  });

  Future<void> createPrescription({
    required ClinicalRelationship relationship,
    required String medicationName,
    required String dosage,
    required String frequency,
    required String duration,
    String? diagnosisReason,
    String? medicationFormStrength,
    String? route,
    String? exactDose,
    String? quantityToDispense,
    int refills = 0,
    DateTime? startDate,
    DateTime? endDate,
    bool isPrn = false,
    String? prnReason,
    String? maximumDailyDose,
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
    DiagnosticResultDetails? diagnosticResult,
  });

  Future<void> renameOwnMedicalFile({
    required String fileId,
    required String title,
  });

  Future<void> deleteOwnMedicalFile({required String fileId});

  Future<void> deleteCareRecord({
    required String table,
    required String recordId,
  });
}

class PrescriberDetails {
  const PrescriberDetails({
    required this.name,
    required this.licenseNumber,
    this.specialization,
  });

  final String name;
  final String licenseNumber;
  final String? specialization;
}

class PrescriptionScanDraft {
  const PrescriptionScanDraft({
    this.diagnosisReason,
    this.medicationName,
    this.medicationFormStrength,
    this.route,
    this.exactDose,
    this.frequency,
    this.duration,
    this.quantityToDispense,
    this.refills,
    this.startDate,
    this.endDate,
    this.isPrn = false,
    this.prnReason,
    this.maximumDailyDose,
    this.instructions,
  });

  final String? diagnosisReason;
  final String? medicationName;
  final String? medicationFormStrength;
  final String? route;
  final String? exactDose;
  final String? frequency;
  final String? duration;
  final String? quantityToDispense;
  final int? refills;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isPrn;
  final String? prnReason;
  final String? maximumDailyDose;
  final String? instructions;

  factory PrescriptionScanDraft.fromPayload(Map<dynamic, dynamic> payload) {
    String? text(String key) {
      final value = payload[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    final refillsValue = payload['refills'];
    final parsedRefills = refillsValue is num
        ? refillsValue.toInt()
        : int.tryParse(refillsValue?.toString() ?? '');
    return PrescriptionScanDraft(
      diagnosisReason: text('diagnosis_reason'),
      medicationName: text('medication_name'),
      medicationFormStrength: text('medication_form_strength'),
      route: text('route'),
      exactDose: text('exact_dose'),
      frequency: text('frequency'),
      duration: text('duration'),
      quantityToDispense: text('quantity_to_dispense'),
      refills: parsedRefills,
      startDate: DateTime.tryParse(text('start_date') ?? ''),
      endDate: DateTime.tryParse(text('end_date') ?? ''),
      isPrn: payload['is_prn'] == true,
      prnReason: text('prn_reason'),
      maximumDailyDose: text('maximum_daily_dose'),
      instructions: text('instructions'),
    );
  }

  static List<PrescriptionScanDraft> listFromPayload(
    Map<dynamic, dynamic> payload,
  ) {
    final prescriptions = payload['prescriptions'];
    if (prescriptions is List) {
      final drafts = prescriptions
          .whereType<Map>()
          .map(PrescriptionScanDraft.fromPayload)
          .toList(growable: false);
      if (drafts.isNotEmpty) return drafts;
    }

    final prescription = payload['prescription'];
    if (prescription is! Map) return const [];
    final medications = prescription['medications'];
    if (medications is List) {
      final diagnosisReason = prescription['diagnosis_reason'];
      final drafts = medications
          .whereType<Map>()
          .map((medication) {
            return PrescriptionScanDraft.fromPayload({
              'diagnosis_reason': diagnosisReason,
              ...medication,
            });
          })
          .toList(growable: false);
      if (drafts.isNotEmpty) return drafts;
    }
    return [PrescriptionScanDraft.fromPayload(prescription)];
  }
}

class DiagnosticResultScanDraft {
  const DiagnosticResultScanDraft({
    this.sourceFileName,
    this.patientName,
    this.category,
    this.testProcedureName,
    this.testProcedureNameAiGenerated = false,
    this.performedOrCollectedDate,
    this.performedOrCollectedDateText,
    this.resultDate,
    this.resultDateText,
    this.facility,
    this.requestingDoctor,
    this.procedureDetails,
    this.resultDetails,
    this.officialFindingsImpression,
    this.recommendations,
    this.technicalSummary,
    this.patientFriendlySummary,
    this.verificationNotes,
    this.findingsImpression,
    this.notes,
  });

  final String? sourceFileName;
  final String? patientName;
  final String? category;
  final String? testProcedureName;
  final bool testProcedureNameAiGenerated;
  final DateTime? performedOrCollectedDate;
  final String? performedOrCollectedDateText;
  final DateTime? resultDate;
  final String? resultDateText;
  final String? facility;
  final String? requestingDoctor;
  final String? procedureDetails;
  final String? resultDetails;
  final String? officialFindingsImpression;
  final String? recommendations;
  final String? technicalSummary;
  final String? patientFriendlySummary;
  final String? verificationNotes;
  // Kept for compatibility with older scan responses and callers.
  final String? findingsImpression;
  final String? notes;

  factory DiagnosticResultScanDraft.fromPayload(Map<dynamic, dynamic> payload) {
    String? text(String key) {
      final value = payload[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    final parsedCategory = text('result_category');
    final category =
        parsedCategory != null &&
            DiagnosticResultDetails.supportedCategories.contains(parsedCategory)
        ? parsedCategory
        : null;
    final resultDetails =
        text('results_text') ?? _formatDiagnosticResultRows(payload['results']);
    final officialFindingsImpression =
        text('official_findings_impression') ?? text('official_findings');
    final extractedFindings = text('findings_impression');
    final legacyLaboratorySummary =
        category == 'laboratory' &&
            extractedFindings != null &&
            resultDetails == null &&
            officialFindingsImpression == null &&
            text('technical_summary') == null
        ? _summarizeLaboratoryFindings(extractedFindings)
        : null;
    return DiagnosticResultScanDraft(
      sourceFileName: text('source_file_name'),
      patientName: text('patient_name'),
      category: category,
      testProcedureName: text('test_procedure_name'),
      testProcedureNameAiGenerated:
          payload['test_procedure_name_ai_generated'] == true,
      performedOrCollectedDate: DateTime.tryParse(
        text('performed_or_collected_date') ?? '',
      ),
      performedOrCollectedDateText: text('performed_or_collected_date_text'),
      resultDate: DateTime.tryParse(text('result_date') ?? ''),
      resultDateText: text('result_date_text'),
      facility: text('facility'),
      requestingDoctor: text('requesting_doctor'),
      procedureDetails: text('procedure_details'),
      resultDetails: resultDetails,
      officialFindingsImpression:
          officialFindingsImpression ?? extractedFindings,
      recommendations: text('recommendations'),
      technicalSummary: text('technical_summary') ?? legacyLaboratorySummary,
      patientFriendlySummary: text('patient_friendly_summary'),
      verificationNotes: _formatVerificationNotes(
        payload['needs_verification'],
      ),
      findingsImpression:
          legacyLaboratorySummary ??
          officialFindingsImpression ??
          extractedFindings,
      notes: text('notes'),
    );
  }
}

String? _formatDiagnosticResultRows(Object? value) {
  if (value is! Iterable) return null;
  final rows = <String>[];
  for (final item in value) {
    if (item is! Map) continue;
    String cell(String key) => item[key]?.toString().trim() ?? '';
    final name = cell('test_or_measurement');
    final result = cell('value');
    if (name.isEmpty && result.isEmpty) continue;
    rows.add(
      [
        name,
        result,
        cell('unit'),
        cell('reference_range'),
        cell('status'),
      ].join(' | '),
    );
  }
  if (rows.isEmpty) return null;
  return 'Test or measurement | Result | Unit | Reference range | Status\n${rows.join('\n')}';
}

String? _formatVerificationNotes(Object? value) {
  if (value is String) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
  if (value is! Iterable) return null;
  final notes = value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return notes.isEmpty ? null : notes.join('\n');
}

enum _LabResultStatus { low, high, withinRange }

class _ComparableLabResult {
  const _ComparableLabResult({
    required this.name,
    required this.value,
    required this.unit,
    required this.reference,
    required this.status,
  });

  final String name;
  final String value;
  final String unit;
  final String reference;
  final _LabResultStatus status;
}

String _summarizeLaboratoryFindings(String source) {
  if (RegExp(
    r'^\s*key findings\s*:',
    caseSensitive: false,
    multiLine: true,
  ).hasMatch(source)) {
    return source;
  }

  final results = source
      .split(RegExp(r'\r?\n'))
      .map(_parseComparableLabResult)
      .whereType<_ComparableLabResult>()
      .toList(growable: false);
  if (results.isEmpty) return source;

  final abnormal = results
      .where((result) => result.status != _LabResultStatus.withinRange)
      .toList(growable: false);
  final withinRange = results
      .where((result) => result.status == _LabResultStatus.withinRange)
      .map((result) => result.name)
      .toList(growable: false);

  final summaryParts = <String>[];
  if (abnormal.isNotEmpty) {
    summaryParts.add(
      abnormal
          .map((result) {
            final status = result.status == _LabResultStatus.low
                ? 'Low'
                : 'High';
            final measured = result.unit.isEmpty
                ? result.value
                : '${result.value} ${result.unit}';
            return '$status ${result.name} ($measured; stated reference ${result.reference})';
          })
          .join('; '),
    );
  }
  if (withinRange.isNotEmpty) {
    final subject = _naturalLanguageList(withinRange);
    summaryParts.add(
      abnormal.isEmpty && withinRange.length == results.length
          ? 'All comparable listed results ($subject) are within their stated reference ranges'
          : '$subject ${withinRange.length == 1 ? 'is' : 'are'} within ${withinRange.length == 1 ? 'its' : 'their'} stated reference ${withinRange.length == 1 ? 'range' : 'ranges'}',
    );
  }

  final summary = 'Key findings: ${summaryParts.join('. ')}.';
  const supportingHeading = '\n\nSupporting results:\n';
  final availableSourceLength =
      4000 - summary.length - supportingHeading.length;
  if (availableSourceLength <= 3) return summary.substring(0, 4000);
  final supporting = source.length <= availableSourceLength
      ? source
      : '${source.substring(0, availableSourceLength - 3).trimRight()}...';
  return '$summary$supportingHeading$supporting';
}

_ComparableLabResult? _parseComparableLabResult(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  String name;
  String resultText;
  String unit;
  String reference;
  String flagText;
  if (trimmed.contains('|')) {
    final cells = trimmed
        .split('|')
        .map((cell) => cell.trim())
        .toList(growable: false);
    if (cells.length < 3 ||
        RegExp(
          r'^(examination|test|analyte)$',
          caseSensitive: false,
        ).hasMatch(cells.first)) {
      return null;
    }
    name = cells[0];
    resultText = cells[1];
    if (cells.length == 3) {
      unit = '';
      reference = cells[2];
      flagText = '';
    } else {
      unit = cells[2];
      reference = cells[3];
      flagText = cells.skip(4).join(' ');
    }
  } else {
    final match = RegExp(
      r'^\s*([^:]+?)\s*:\s*([+-]?\d+(?:[.,]\d+)?)\s*([^([]*?)\s*[([]\s*(?:normal|reference(?:\s+range)?|ref\.?)\s*:?\s*([^\])]+)[\])]\s*$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) return null;
    name = match.group(1)!.trim();
    resultText = match.group(2)!.trim();
    unit = match.group(3)!.trim();
    reference = match.group(4)!.trim();
    flagText = '';
  }

  if (name.isEmpty || reference.isEmpty) return null;
  final value = _exactNumber(resultText);
  if (value == null) return null;
  final status = _labResultStatus(
    value: value,
    resultText: '$resultText $flagText',
    reference: reference,
  );
  if (status == null) return null;
  return _ComparableLabResult(
    name: name,
    value: resultText,
    unit: unit,
    reference: reference,
    status: status,
  );
}

double? _exactNumber(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^[+-]?\d+(?:\.\d+)?$').hasMatch(normalized)) return null;
  return double.tryParse(normalized);
}

_LabResultStatus? _labResultStatus({
  required double value,
  required String resultText,
  required String reference,
}) {
  if (RegExp(r'\b(?:h|high)\b', caseSensitive: false).hasMatch(resultText)) {
    return _LabResultStatus.high;
  }
  if (RegExp(r'\b(?:l|low)\b', caseSensitive: false).hasMatch(resultText)) {
    return _LabResultStatus.low;
  }

  final normalizedReference = reference
      .replaceAll(',', '.')
      .replaceAll('\u2264', '<=')
      .replaceAll('\u2265', '>=')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2014', '-')
      .trim();
  final range = RegExp(
    r'^([+-]?\d+(?:\.\d+)?)\s*(?:-|to)\s*([+-]?\d+(?:\.\d+)?)$',
    caseSensitive: false,
  ).firstMatch(normalizedReference);
  if (range != null) {
    final first = double.parse(range.group(1)!);
    final second = double.parse(range.group(2)!);
    final lower = first <= second ? first : second;
    final upper = first <= second ? second : first;
    if (value < lower) return _LabResultStatus.low;
    if (value > upper) return _LabResultStatus.high;
    return _LabResultStatus.withinRange;
  }

  final comparator = RegExp(
    r'^(<=|>=|<|>)\s*([+-]?\d+(?:\.\d+)?)$',
  ).firstMatch(normalizedReference);
  if (comparator == null) return null;
  final limit = double.parse(comparator.group(2)!);
  return switch (comparator.group(1)) {
    '<' => value < limit ? _LabResultStatus.withinRange : _LabResultStatus.high,
    '<=' =>
      value <= limit ? _LabResultStatus.withinRange : _LabResultStatus.high,
    '>' => value > limit ? _LabResultStatus.withinRange : _LabResultStatus.low,
    '>=' =>
      value >= limit ? _LabResultStatus.withinRange : _LabResultStatus.low,
    _ => null,
  };
}

String _naturalLanguageList(List<String> values) {
  if (values.length == 1) return values.single;
  if (values.length == 2) return '${values[0]} and ${values[1]}';
  return '${values.take(values.length - 1).join(', ')}, and ${values.last}';
}

class CareMessage {
  const CareMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.message,
    required this.sentAt,
    this.messageType = 'text',
    this.attachmentPath,
    this.readAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String? message;
  final DateTime sentAt;
  final String messageType;
  final String? attachmentPath;
  final DateTime? readAt;

  factory CareMessage.fromJson(Map<String, dynamic> json) => CareMessage(
    id: json['id'] as String,
    conversationId: json['conversation_id'] as String,
    senderId: json['sender_id'] as String,
    message: json['message'] as String?,
    sentAt: DateTime.parse(json['sent_at'] as String),
    messageType: json['message_type'] as String? ?? 'text',
    attachmentPath: _nullableText(json['attachment_path']),
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
    this.referenceId,
    this.data = const {},
  });

  final String id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final String? actionPath;
  final String? referenceId;
  final Map<String, Object?> data;

  factory CareNotification.fromJson(Map<String, dynamic> json) =>
      CareNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        type: json['notification_type'] as String,
        isRead: json['is_read'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        actionPath: (json['action_path'] ?? json['action_url']) as String?,
        referenceId: _nullableText(json['reference_id']),
        data: json['data'] is Map
            ? Map<String, Object?>.from(json['data'] as Map)
            : const {},
      );
}

class ClinicalRelationship {
  const ClinicalRelationship({
    required this.patientId,
    required this.patientLabel,
    required this.consultationId,
    required this.consultationLabel,
    this.assignmentId,
  });

  final String patientId;
  final String patientLabel;
  final String consultationId;
  final String consultationLabel;
  final String? assignmentId;

  bool get hasConsultation => consultationId.trim().isNotEmpty;

  String? get clinicalReferenceId =>
      hasConsultation ? consultationId : _nullableText(assignmentId);

  String? get clinicalReferenceType => hasConsultation
      ? 'consultation'
      : (_nullableText(assignmentId) == null
            ? null
            : 'doctor_patient_assignment');
}

class DiagnosticResultDetails {
  const DiagnosticResultDetails({
    required this.category,
    required this.testProcedureName,
    this.testProcedureNameAiGenerated = false,
    this.performedOrCollectedDate,
    this.performedOrCollectedDateText,
    this.resultDate,
    this.resultDateText,
    this.facility,
    this.requestingDoctor,
    this.patientNameOnReport,
    this.procedureDetails,
    this.resultDetails,
    this.officialFindingsImpression,
    this.recommendations,
    this.technicalSummary,
    this.patientFriendlySummary,
    this.verificationNotes,
    this.findingsImpression,
    this.notes,
  });

  static const supportedCategories = {
    'laboratory',
    'x_ray',
    'ct_scan',
    'mri',
    'ultrasound',
    'ecg',
    'pathology',
    'other',
  };

  final String category;
  final String testProcedureName;
  final bool testProcedureNameAiGenerated;
  final DateTime? performedOrCollectedDate;
  final String? performedOrCollectedDateText;
  final DateTime? resultDate;
  final String? resultDateText;
  final String? facility;
  final String? requestingDoctor;
  final String? patientNameOnReport;
  final String? procedureDetails;
  final String? resultDetails;
  final String? officialFindingsImpression;
  final String? recommendations;
  final String? technicalSummary;
  final String? patientFriendlySummary;
  final String? verificationNotes;
  final String? findingsImpression;
  final String? notes;
}

class ExistingPatientMatch {
  const ExistingPatientMatch({
    required this.patientId,
    required this.displayName,
    required this.email,
  });

  final String patientId;
  final String displayName;
  final String email;

  factory ExistingPatientMatch.fromJson(Map<String, dynamic> json) =>
      ExistingPatientMatch(
        patientId: json['patient_id'] as String,
        displayName: json['display_name'] as String,
        email: json['email'] as String,
      );
}

class SupabaseCareRepository implements CareRepository {
  SupabaseCareRepository(this._client);

  static const _medicalBucket = 'medical-documents';
  static const _consultationAttachmentBucket = 'consultation-attachments';
  static const _maximumMedicalFileSize = 20 * 1024 * 1024;
  static const _aiSummarizedDocumentTypes = {
    'lab_result',
    'diagnostic_result',
    'prescription',
  };

  final SupabaseClient _client;

  @override
  Stream<List<CareMessage>> watchMessages(String conversationId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: const ['id'])
        .eq('conversation_id', conversationId)
        .order('sent_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => CareMessage.fromJson(row))
              .toList(growable: false),
        );
  }

  @override
  Stream<int> watchUnreadMessageCount(String currentUserId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: const ['id'])
        .neq('sender_id', currentUserId)
        .map(
          (rows) => rows
              .where(
                (row) => row['read_at'] == null && row['deleted_at'] == null,
              )
              .length,
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
    if (conversationId.trim().isEmpty) {
      throw ArgumentError('A conversation is required to mark messages read.');
    }
    await _client.rpc<int>(
      'mark_conversation_read',
      params: {'target_conversation_id': conversationId},
    );
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    if (notificationId.trim().isEmpty) {
      throw ArgumentError('A notification is required to mark it as read.');
    }
    await _client.rpc<void>(
      'mark_notification_read',
      params: {'target_notification_id': notificationId},
    );
  }

  @override
  Future<void> decidePatientConnectionRequest({
    required String requestId,
    required bool approve,
  }) async {
    if (requestId.trim().isEmpty) {
      throw ArgumentError('A connection request is required.');
    }
    await _client.rpc<Object?>(
      'decide_patient_connection_request',
      params: {'target_request_id': requestId, 'approve_request': approve},
    );
  }

  @override
  Future<String> ensurePatientConversation(String patientId) async {
    if (patientId.trim().isEmpty) {
      throw ArgumentError('A patient is required to start a conversation.');
    }
    return _client.rpc<String>(
      'ensure_patient_conversation',
      params: {'target_patient_id': patientId},
    );
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String body,
    ({List<int> bytes, String name})? attachment,
  }) async {
    final normalizedBody = body.trim();
    if (conversationId.trim().isEmpty) {
      throw ArgumentError('A conversation is required to send a message.');
    }
    if (normalizedBody.isEmpty && attachment == null) {
      throw ArgumentError.value(
        body,
        'body',
        'A message or attachment is required.',
      );
    }
    String? attachmentPath;
    if (attachment != null) {
      final mimeType = _medicalMimeType(attachment.name, attachment.bytes);
      final user = _client.auth.currentUser;
      if (user == null || user.isAnonymous) {
        throw StateError(
          'An authenticated account is required to attach files.',
        );
      }
      final conversation = await _client
          .from('chat_conversations')
          .select('consultation_id,patient_id')
          .eq('id', conversationId)
          .single();
      final consultationId = conversation['consultation_id']?.toString() ?? '';
      final patientId = conversation['patient_id']?.toString() ?? '';
      if (consultationId.isEmpty && patientId.isEmpty) {
        throw StateError('The conversation is missing its care relationship.');
      }
      final conversationFolder = consultationId.isNotEmpty
          ? consultationId
          : 'direct/$patientId/$conversationId';
      attachmentPath =
          '$conversationFolder/${user.id}/${DateTime.now().toUtc().microsecondsSinceEpoch}-${_safeFileName(attachment.name)}';
      await _client.storage
          .from(_consultationAttachmentBucket)
          .uploadBinary(
            attachmentPath,
            Uint8List.fromList(attachment.bytes),
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
    }

    try {
      await _client.rpc<String>(
        'send_chat_message',
        params: {
          'target_conversation_id': conversationId,
          'message_body': normalizedBody.isEmpty ? null : normalizedBody,
          if (attachmentPath != null) 'attachment_paths': [attachmentPath],
        },
      );
    } catch (_) {
      if (attachmentPath != null) {
        try {
          await _client.storage.from(_consultationAttachmentBucket).remove([
            attachmentPath,
          ]);
        } catch (_) {
          // Preserve the original send failure; storage cleanup is best effort.
        }
      }
      rethrow;
    }
  }

  @override
  Future<Uri> createSignedMessageAttachmentUrl(String messageId) async {
    if (messageId.trim().isEmpty) {
      throw ArgumentError('A message is required to download its attachment.');
    }
    final row = await _client
        .from('chat_message_attachments')
        .select('storage_path')
        .eq('message_id', messageId)
        .order('created_at')
        .limit(1)
        .single();
    final url = await _client.storage
        .from(_consultationAttachmentBucket)
        .createSignedUrl(row['storage_path'] as String, 60);
    return Uri.parse(url);
  }

  @override
  Future<Uri> createSignedFileUrl(String fileId) async {
    if (fileId.trim().isEmpty) {
      throw ArgumentError('A medical document is required to download a file.');
    }
    final access = await _client.rpc<Map<String, dynamic>>(
      'get_authorized_medical_document_download',
      params: {'target_document_id': fileId},
    );
    final bucket = access['storage_bucket']?.toString() ?? '';
    final path = access['storage_path']?.toString() ?? '';
    final expiresIn = access['expires_in_seconds'] is int
        ? access['expires_in_seconds'] as int
        : int.tryParse('${access['expires_in_seconds']}') ?? 60;
    if (bucket.isEmpty || path.isEmpty) {
      throw StateError('The authorized document has no secure file location.');
    }
    final url = await _client.storage
        .from(bucket)
        .createSignedUrl(path, expiresIn.clamp(30, 300));
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
  Future<void> reserveAppointment({
    required String patientId,
    required DateTime appointmentDate,
    required String consultationType,
    required String chiefComplaint,
    ({List<int> bytes, String name})? attachment,
  }) async {
    final normalizedConsultationType = ConsultationType.normalize(
      consultationType,
    );
    if (patientId.trim().isEmpty) {
      throw ArgumentError('A patient is required for an appointment.');
    }
    if (!meetsReservationLeadTime(appointmentDate)) {
      throw ArgumentError(reservationLeadTimeMessage);
    }
    final complaint = chiefComplaint.trim();
    if (complaint.length < 5) {
      throw ArgumentError(
        'Describe the care concern in at least 5 characters.',
      );
    }
    final result = await _client.rpc<String>(
      'book_doctor_consultation',
      params: {
        'target_patient_id': patientId,
        'target_appointment_date': appointmentDate.toUtc().toIso8601String(),
        'target_type': normalizedConsultationType,
        'target_chief_complaint': complaint,
      },
    );

    if (attachment != null) {
      await uploadMedicalFile(
        patientId: patientId,
        fileName: attachment.name,
        title: 'Appointment Attachment',
        documentType: 'appointment',
        bytes: attachment.bytes,
        referenceId: result,
        referenceType: 'consultation',
      );
    }
  }

  @override
  Future<void> recordPatientCheckup({
    required String patientId,
    required ClinicalCheckupDraft checkup,
    required List<({List<int> bytes, String name})> attachments,
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
      if (result['id'] != null) {
        for (final attachment in attachments) {
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
      }
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<ClinicalCheckupDraft> extractCheckupFromAttachments({
    required List<({List<int> bytes, String name})> attachments,
  }) async {
    if (attachments.isEmpty) {
      throw ArgumentError('Attach at least one medical file to scan.');
    }
    if (attachments.length > 5) {
      throw ArgumentError('Scan up to 5 medical files at a time.');
    }

    var encodedCharacters = 0;
    final encodedAttachments = <Map<String, String>>[];
    for (final attachment in attachments) {
      final mimeType = _medicalMimeType(attachment.name, attachment.bytes);
      final encoded = base64Encode(attachment.bytes);
      encodedCharacters += encoded.length;
      if (encodedCharacters > 2800000) {
        throw ArgumentError(
          'The selected files are too large to scan together. Use fewer files or files under 2 MB total.',
        );
      }
      encodedAttachments.add({
        'data': encoded,
        'mime_type': mimeType,
        'file_name': attachment.name,
      });
    }

    late final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'care-navigator-chat',
        body: {'action': 'extract_checkup', 'attachments': encodedAttachments},
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error'] : null;
      throw StateError(
        message?.toString() ?? 'The checkup files could not be scanned.',
      );
    }
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError(
        message?.toString() ?? 'The checkup files could not be scanned.',
      );
    }
    final data = response.data;
    final checkup = data is Map ? data['checkup'] : null;
    if (checkup is! Map) {
      throw StateError('The AI scan returned an invalid checkup draft.');
    }
    return ClinicalCheckupDraft.fromPayload(checkup);
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
  Future<List<ExistingPatientMatch>> searchExistingPatients(
    String query,
  ) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) return const [];
    try {
      final response = await _client.rpc<List<dynamic>>(
        'search_existing_patients',
        params: {'search_query': normalizedQuery},
      );
      return response
          .map(
            (row) => ExistingPatientMatch.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> linkExistingPatient(String patientId) async {
    final normalizedPatientId = patientId.trim();
    if (normalizedPatientId.isEmpty) {
      throw ArgumentError('Select an existing patient account.');
    }
    try {
      await _client.rpc<dynamic>(
        'link_existing_patient',
        params: {'target_patient_id': normalizedPatientId},
      );
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> requestConsultationAsPatient({
    required String hospitalId,
    required String departmentLabel,
    required String careMode,
    required DateTime preferredStart,
    String? doctorId,
    String chiefComplaint = 'Consultation request',
  }) async {
    final normalizedConsultationType = ConsultationType.normalize(careMode);
    if (hospitalId.trim().isEmpty || departmentLabel.trim().isEmpty) {
      throw ArgumentError('A hospital and department are required.');
    }
    if (!meetsReservationLeadTime(preferredStart)) {
      throw ArgumentError(reservationLeadTimeMessage);
    }
    final complaint = chiefComplaint.trim();
    if (complaint.length < 5) {
      throw ArgumentError(
        'Describe the care concern in at least 5 characters.',
      );
    }
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
    if (patient == null) {
      throw StateError('The user is not registered as a patient.');
    }

    final department = await _client
        .from('hospital_departments')
        .select('id')
        .eq('hospital_id', hospitalId)
        .ilike('department_name', departmentLabel)
        .maybeSingle();
    if (department == null) {
      throw StateError('Department not found in this hospital.');
    }

    final normalizedDoctorId = doctorId?.trim();
    final doctor = normalizedDoctorId == null || normalizedDoctorId.isEmpty
        ? await _client
              .from('doctors')
              .select('id')
              .eq('hospital_id', hospitalId)
              .eq('department_id', department['id'])
              .neq('availability_status', 'unavailable')
              .limit(1)
              .maybeSingle()
        : await _client
              .from('doctors')
              .select('id')
              .eq('id', normalizedDoctorId)
              .eq('hospital_id', hospitalId)
              .eq('department_id', department['id'])
              .maybeSingle();
    if (doctor == null) {
      throw StateError('No published doctor is available for this department.');
    }

    try {
      await _client.rpc<String>(
        'book_consultation',
        params: {
          'booking_payload': {
            'doctor_id': doctor['id'],
            'hospital_id': hospitalId,
            'consultation_type': normalizedConsultationType,
            'appointment_date': preferredStart.toUtc().toIso8601String(),
            'chief_complaint': complaint,
          },
        },
      );
    } on PostgrestException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> analyzeMedicalResult(String resultId) async {
    if (resultId.trim().isEmpty) {
      throw ArgumentError('A laboratory result is required for analysis.');
    }
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
    if (resultId.trim().isEmpty) {
      throw ArgumentError('A laboratory result is required for confirmation.');
    }
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
    if (resultId.trim().isEmpty) {
      throw ArgumentError('A laboratory result is required for rejection.');
    }
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
    final normalizedConsultationType = ConsultationType.normalize(
      consultationType,
    );
    if (dayOfWeek < 0 || dayOfWeek > 6) {
      throw ArgumentError('Day of week must be between 0 and 6.');
    }
    final startMinutes = _timeMinutes(startsAt);
    final endMinutes = _timeMinutes(endsAt);
    if (startMinutes == null || endMinutes == null) {
      throw ArgumentError('Schedule times must use HH:mm format.');
    }
    if (endMinutes <= startMinutes) {
      throw ArgumentError('Schedule end time must be later than its start.');
    }
    if (slotMinutes < 10 || slotMinutes > 240) {
      throw ArgumentError('Slot duration must be between 10 and 240 minutes.');
    }
    final doctor = await _currentDoctor();
    await _client
        .from('doctor_schedules')
        .insert({
          'doctor_id': doctor['id'],
          'day_of_week': dayOfWeek,
          'starts_at': startsAt,
          'ends_at': endsAt,
          'consultation_type': normalizedConsultationType,
          'slot_minutes': slotMinutes,
          'is_active': true,
        })
        .select('id')
        .single();
  }

  @override
  Future<void> setScheduleActive({
    required String scheduleId,
    required bool active,
  }) async {
    if (scheduleId.trim().isEmpty) {
      throw ArgumentError('A schedule slot is required for this update.');
    }
    await _client
        .from('doctor_schedules')
        .update({'is_active': active})
        .eq('id', scheduleId)
        .select('id')
        .single();
  }

  @override
  Future<void> deleteScheduleSlot({required String scheduleId}) async {
    if (scheduleId.trim().isEmpty) {
      throw ArgumentError('A schedule slot is required for deletion.');
    }
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
    final reserved = consultations.any(
      (row) => _appointmentMatchesSchedule(row, schedule),
    );
    if (reserved) {
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
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value ?? '')) {
      return null;
    }
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
    final assignmentRows = await _client
        .from('doctor_patient_assignments')
        .select('id,patient_id,consultation_id,assigned_at')
        .eq('doctor_id', doctor['id'])
        .eq('assignment_status', 'active')
        .isFilter('ended_at', null)
        .order('assigned_at', ascending: false)
        .limit(100);
    final consultationRows = await _client
        .from('consultations')
        .select('id,patient_id,chief_complaint,status,appointment_date')
        .eq('doctor_id', doctor['id'])
        // Clinical write grants are active only while the consultation is in
        // one of these states. Returning historical consultations here made
        // the UI offer cancelled/completed records that storage and RLS then
        // correctly rejected during prescription and result uploads.
        .inFilter('status', const ['approved', 'scheduled', 'in_progress'])
        .order('appointment_date', ascending: false)
        .limit(100);
    final eligibleConsultations = consultationRows
        .where((row) => row['patient_id'] != null)
        .toList(growable: false);
    final eligibleAssignments = assignmentRows
        .where((row) => row['patient_id'] != null)
        .toList(growable: false);
    final patientIds = [...eligibleAssignments, ...eligibleConsultations]
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
    String patientLabel(String patientId) =>
        patientLabels[patientId] ?? 'Patient ${_shortId(patientId)}';
    final consultationsById = {
      for (final row in eligibleConsultations) row['id'].toString(): row,
    };
    final relationships = <ClinicalRelationship>[];
    final representedConsultations = <String>{};
    for (final assignment in eligibleAssignments) {
      final patientId = assignment['patient_id'].toString();
      final linkedConsultationId =
          _nullableText(assignment['consultation_id']?.toString()) ?? '';
      final activeConsultation = consultationsById[linkedConsultationId];
      final consultationId = activeConsultation == null
          ? ''
          : linkedConsultationId;
      if (consultationId.isNotEmpty) {
        representedConsultations.add(consultationId);
      }
      relationships.add(
        ClinicalRelationship(
          patientId: patientId,
          patientLabel: patientLabel(patientId),
          consultationId: consultationId,
          consultationLabel: activeConsultation == null
              ? 'Assigned care relationship'
              : '${activeConsultation['chief_complaint'] ?? 'Consultation'} · ${activeConsultation['status']}',
          assignmentId: assignment['id'].toString(),
        ),
      );
    }
    for (final consultation in eligibleConsultations) {
      final consultationId = consultation['id'].toString();
      if (representedConsultations.contains(consultationId)) continue;
      final patientId = consultation['patient_id'].toString();
      relationships.add(
        ClinicalRelationship(
          patientId: patientId,
          patientLabel: patientLabel(patientId),
          consultationId: consultationId,
          consultationLabel:
              '${consultation['chief_complaint'] ?? 'Consultation'} · ${consultation['status']}',
        ),
      );
    }
    return relationships;
  }

  @override
  Future<PrescriberDetails> currentPrescriberDetails() async {
    final doctor = await _currentDoctor();
    final name = doctor['display_name']?.toString().trim() ?? '';
    final licenseNumber = doctor['license_number']?.toString().trim() ?? '';
    if (name.isEmpty || licenseNumber.isEmpty) {
      throw StateError(
        'Complete your prescriber name and license number in your profile before issuing a prescription.',
      );
    }
    final specialization = doctor['specialization']?.toString().trim();
    return PrescriberDetails(
      name: name,
      licenseNumber: licenseNumber,
      specialization: specialization == null || specialization.isEmpty
          ? null
          : specialization,
    );
  }

  @override
  Future<PrescriptionScanDraft> extractPrescriptionFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  }) async =>
      (await extractPrescriptionsFromAttachment(attachment: attachment)).first;

  @override
  Future<List<PrescriptionScanDraft>> extractPrescriptionsFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  }) async {
    final mimeType = _medicalMimeType(attachment.name, attachment.bytes);
    if (!{'application/pdf', 'image/jpeg', 'image/png'}.contains(mimeType)) {
      throw ArgumentError(
        'Prescription scanning supports PDF, JPG, and PNG files.',
      );
    }
    final encoded = base64Encode(attachment.bytes);
    if (encoded.length > 2800000) {
      throw ArgumentError(
        'The selected file is too large to scan. Use a file under 2 MB.',
      );
    }

    late final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'care-navigator-chat',
        body: {
          'action': 'extract_prescription',
          'attachments': [
            {
              'data': encoded,
              'mime_type': mimeType,
              'file_name': attachment.name,
            },
          ],
        },
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error'] : null;
      throw StateError(
        message?.toString() ?? 'The prescription file could not be scanned.',
      );
    }
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError(
        message?.toString() ?? 'The prescription file could not be scanned.',
      );
    }
    final data = response.data;
    final drafts = data is Map
        ? PrescriptionScanDraft.listFromPayload(data)
        : const <PrescriptionScanDraft>[];
    if (drafts.isEmpty) {
      throw StateError('The AI scan returned no valid medication drafts.');
    }
    return drafts;
  }

  @override
  Future<DiagnosticResultScanDraft> extractDiagnosticResultFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  }) async => (await extractDiagnosticResultsFromAttachments(
    attachments: [attachment],
  )).first;

  @override
  Future<List<DiagnosticResultScanDraft>>
  extractDiagnosticResultsFromAttachments({
    required List<({List<int> bytes, String name})> attachments,
  }) async {
    if (attachments.isEmpty || attachments.length > 5) {
      throw ArgumentError('Attach between 1 and 5 diagnostic result files.');
    }
    final encodedAttachments = <Map<String, String>>[];
    var encodedLength = 0;
    for (final attachment in attachments) {
      final mimeType = _medicalMimeType(attachment.name, attachment.bytes);
      if (!{'application/pdf', 'image/jpeg', 'image/png'}.contains(mimeType)) {
        throw ArgumentError(
          'Diagnostic result scanning supports PDF, JPG, and PNG files.',
        );
      }
      final encoded = base64Encode(attachment.bytes);
      encodedLength += encoded.length;
      encodedAttachments.add({
        'data': encoded,
        'mime_type': mimeType,
        'file_name': attachment.name,
      });
    }
    if (encodedLength > 2800000) {
      throw ArgumentError(
        'The selected files are too large to scan together. Use up to 2 MB total.',
      );
    }

    late final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'care-navigator-chat',
        body: {
          'action': 'extract_diagnostic_result',
          'attachments': encodedAttachments,
        },
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map ? details['error'] : null;
      throw StateError(
        message?.toString() ??
            'The diagnostic result file could not be scanned.',
      );
    }
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError(
        message?.toString() ??
            'The diagnostic result file could not be scanned.',
      );
    }
    final data = response.data;
    final diagnosticResults = data is Map ? data['diagnostic_results'] : null;
    if (diagnosticResults is List) {
      final drafts = diagnosticResults
          .whereType<Map>()
          .map(DiagnosticResultScanDraft.fromPayload)
          .toList(growable: false);
      if (drafts.isNotEmpty) return drafts;
    }
    final diagnosticResult = data is Map ? data['diagnostic_result'] : null;
    if (diagnosticResult is! Map) {
      throw StateError(
        'The AI scan returned no valid diagnostic result drafts.',
      );
    }
    return [DiagnosticResultScanDraft.fromPayload(diagnosticResult)];
  }

  @override
  Future<void> createPrescription({
    required ClinicalRelationship relationship,
    required String medicationName,
    required String dosage,
    required String frequency,
    required String duration,
    String? diagnosisReason,
    String? medicationFormStrength,
    String? route,
    String? exactDose,
    String? quantityToDispense,
    int refills = 0,
    DateTime? startDate,
    DateTime? endDate,
    bool isPrn = false,
    String? prnReason,
    String? maximumDailyDose,
    String? instructions,
    ({List<int> bytes, String name})? attachment,
  }) async {
    final values = [medicationName, dosage, frequency, duration];
    if (relationship.patientId.trim().isEmpty ||
        relationship.clinicalReferenceId == null) {
      throw ArgumentError(
        'An active doctor-patient relationship is required to prescribe.',
      );
    }
    if (values.any((value) => value.trim().isEmpty)) {
      throw ArgumentError(
        'Medication, dosage, frequency, and duration are required.',
      );
    }
    final clinicalValues = {
      'diagnosis or reason': diagnosisReason,
      'medication form and strength': medicationFormStrength,
      'route': route,
      'exact dose': exactDose,
      'quantity to dispense': quantityToDispense,
    };
    final missingClinicalValue = clinicalValues.entries
        .where((entry) => entry.value == null || entry.value!.trim().isEmpty)
        .map((entry) => entry.key)
        .firstOrNull;
    if (missingClinicalValue != null) {
      throw ArgumentError('A $missingClinicalValue is required.');
    }
    if (refills < 0 || refills > 99) {
      throw ArgumentError('Refills must be between 0 and 99.');
    }
    if (startDate == null) {
      throw ArgumentError('A prescription start date is required.');
    }
    if (endDate != null && endDate.isBefore(startDate)) {
      throw ArgumentError('The end date cannot be before the start date.');
    }
    if (isPrn &&
        ((prnReason?.trim().isEmpty ?? true) ||
            (maximumDailyDose?.trim().isEmpty ?? true))) {
      throw ArgumentError(
        'PRN prescriptions require a reason and maximum daily dose.',
      );
    }
    final doctor = await _currentDoctor();
    final prescriberName = doctor['display_name']?.toString().trim() ?? '';
    final prescriberLicense = doctor['license_number']?.toString().trim() ?? '';
    if (prescriberName.isEmpty || prescriberLicense.isEmpty) {
      throw StateError(
        'Complete your prescriber name and license number in your profile before issuing a prescription.',
      );
    }
    final result = await _client
        .from('prescriptions')
        .insert({
          'patient_id': relationship.patientId,
          'doctor_id': doctor['id'],
          'consultation_id': relationship.hasConsultation
              ? relationship.consultationId
              : null,
          'assignment_id': relationship.assignmentId,
          'hospital_id': doctor['hospital_id'],
          'medication_name': medicationName.trim(),
          'dosage': dosage.trim(),
          'frequency': frequency.trim(),
          'duration': duration.trim(),
          'diagnosis_reason': diagnosisReason!.trim(),
          'medication_form_strength': medicationFormStrength!.trim(),
          'route': route!.trim(),
          'exact_dose': exactDose!.trim(),
          'quantity_to_dispense': quantityToDispense!.trim(),
          'refills': refills,
          'start_date': _dateOnly(startDate),
          'end_date': endDate == null ? null : _dateOnly(endDate),
          'is_prn': isPrn,
          'prn_reason': isPrn ? _nullableText(prnReason) : null,
          'maximum_daily_dose': isPrn ? _nullableText(maximumDailyDose) : null,
          'prescriber_name': prescriberName,
          'prescriber_license_number': prescriberLicense,
          'prescriber_specialization': _nullableText(
            doctor['specialization']?.toString(),
          ),
          'instructions': _nullableText(instructions),
        })
        .select('id')
        .single();

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
    if (relationship.patientId.trim().isEmpty ||
        relationship.consultationId.trim().isEmpty) {
      throw ArgumentError(
        'A patient consultation is required for a laboratory request.',
      );
    }
    if (normalizedTest.isEmpty) {
      throw ArgumentError('A laboratory test name is required.');
    }
    if (!{'routine', 'urgent', 'stat'}.contains(priority)) {
      throw ArgumentError('Unsupported laboratory priority.');
    }
    final doctor = await _currentDoctor();
    final result = await _client
        .from('laboratory_requests')
        .insert({
          'patient_id': relationship.patientId,
          'consultation_id': relationship.consultationId,
          'doctor_id': doctor['id'],
          'hospital_id': doctor['hospital_id'],
          'test_name': normalizedTest,
          'priority': priority,
          'instructions': _nullableText(instructions),
        })
        .select('id')
        .single();

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
    DiagnosticResultDetails? diagnosticResult,
  }) async {
    if (patientId.trim().isEmpty) {
      throw ArgumentError('A patient is required to upload a medical file.');
    }
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('An authenticated account is required to upload files.');
    }
    if (bytes.isEmpty || bytes.length > _maximumMedicalFileSize) {
      throw ArgumentError('Medical files must be between 1 byte and 20 MB.');
    }
    final mimeType = _medicalMimeType(fileName, bytes);
    final normalizedTitle = title.trim();
    final normalizedType = documentType.trim();
    if (normalizedTitle.isEmpty || normalizedType.isEmpty) {
      throw ArgumentError('A title and document type are required.');
    }
    DateTime? effectiveDiagnosticResultDate;
    if (normalizedType == 'diagnostic_result') {
      if (diagnosticResult == null) {
        throw ArgumentError('Diagnostic result details are required.');
      }
      if (!DiagnosticResultDetails.supportedCategories.contains(
        diagnosticResult.category,
      )) {
        throw ArgumentError('Unsupported diagnostic result category.');
      }
      if (diagnosticResult.testProcedureName.trim().isEmpty) {
        throw ArgumentError('A test or procedure name is required.');
      }
      effectiveDiagnosticResultDate =
          diagnosticResult.resultDate ?? DateTime.now();
      if (diagnosticResult.performedOrCollectedDate != null &&
          _dateOnly(effectiveDiagnosticResultDate).compareTo(
                _dateOnly(diagnosticResult.performedOrCollectedDate!),
              ) <
              0) {
        throw ArgumentError(
          'The result date cannot be before the performed or collected date.',
        );
      }
    } else if (diagnosticResult != null) {
      throw ArgumentError(
        'Diagnostic result details require a diagnostic result document type.',
      );
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
      final document = await _client
          .from('medical_documents')
          .insert({
            'patient_id': patientId,
            'uploaded_by': appUser['id'],
            'document_type': normalizedType,
            'title': normalizedTitle,
            'storage_bucket': _medicalBucket,
            'storage_path': storagePath,
            'mime_type': mimeType,
            'size_bytes': bytes.length,
            'reference_id': ?referenceId,
            'reference_type': ?referenceType,
            if (diagnosticResult != null) ...{
              'result_category': diagnosticResult.category,
              'test_procedure_name': diagnosticResult.testProcedureName.trim(),
              'test_procedure_name_ai_generated':
                  diagnosticResult.testProcedureNameAiGenerated,
              'performed_or_collected_date':
                  diagnosticResult.performedOrCollectedDate == null
                  ? null
                  : _dateOnly(diagnosticResult.performedOrCollectedDate!),
              'performed_or_collected_date_text': _nullableText(
                diagnosticResult.performedOrCollectedDateText,
              ),
              'result_date': _dateOnly(effectiveDiagnosticResultDate!),
              'result_date_text': _nullableText(
                diagnosticResult.resultDateText,
              ),
              'facility': _nullableText(diagnosticResult.facility),
              'requesting_doctor': _nullableText(
                diagnosticResult.requestingDoctor,
              ),
              'patient_name_on_report': _nullableText(
                diagnosticResult.patientNameOnReport,
              ),
              'procedure_details': _nullableText(
                diagnosticResult.procedureDetails,
              ),
              'result_details': _nullableText(diagnosticResult.resultDetails),
              'official_findings_impression': _nullableText(
                diagnosticResult.officialFindingsImpression,
              ),
              'report_recommendations': _nullableText(
                diagnosticResult.recommendations,
              ),
              'technical_summary': _nullableText(
                diagnosticResult.technicalSummary,
              ),
              'patient_friendly_summary': _nullableText(
                diagnosticResult.patientFriendlySummary,
              ),
              'verification_notes': _nullableText(
                diagnosticResult.verificationNotes,
              ),
              'findings_impression': _nullableText(
                diagnosticResult.findingsImpression,
              ),
              'notes': _nullableText(diagnosticResult.notes),
            },
          })
          .select('id')
          .single();
      if (_aiSummarizedDocumentTypes.contains(normalizedType)) {
        await _requestMedicalDocumentSummary(document['id'].toString());
      }
    } catch (error, stackTrace) {
      try {
        await _client.storage.from(_medicalBucket).remove([storagePath]);
      } catch (_) {
        // Preserve the original database failure if best-effort cleanup also
        // fails. The first error identifies the actual upload problem.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _requestMedicalDocumentSummary(String documentId) async {
    try {
      await _client.functions.invoke(
        'care-navigator-chat',
        body: {
          'action': 'summarize_medical_document',
          'medical_document_id': documentId,
        },
      );
    } catch (_) {
      // The document is the clinical source of truth and must remain available
      // even when the optional preliminary AI summary is temporarily offline.
    }
  }

  @override
  Future<void> renameOwnMedicalFile({
    required String fileId,
    required String title,
  }) async {
    final normalizedId = fileId.trim();
    final normalizedTitle = title.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError('A medical document is required for editing.');
    }
    if (normalizedTitle.isEmpty || normalizedTitle.length > 180) {
      throw ArgumentError(
        'The medical document title must be between 1 and 180 characters.',
      );
    }
    await _client.rpc<void>(
      'rename_own_medical_document',
      params: {
        'target_document_id': normalizedId,
        'target_title': normalizedTitle,
      },
    );
  }

  @override
  Future<void> deleteOwnMedicalFile({required String fileId}) async {
    final normalizedId = fileId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError('A medical document is required for deletion.');
    }
    final deleted = await _client.rpc<Map<String, dynamic>>(
      'delete_own_medical_document',
      params: {'target_document_id': normalizedId},
    );
    final bucket = deleted['storage_bucket']?.toString();
    final path = deleted['storage_path']?.toString();
    if (bucket == null || bucket.isEmpty || path == null || path.isEmpty) {
      throw StateError('The deleted medical document had no storage location.');
    }
    await _client.storage.from(bucket).remove([path]);
  }

  @override
  Future<void> deleteCareRecord({
    required String table,
    required String recordId,
  }) async {
    // Clinical orders and their attachments are retained for auditability.
    // The live schema exposes the cancelled lifecycle state for this action.
    const validTables = {'laboratory_requests'};
    if (!validTables.contains(table)) {
      throw ArgumentError('Invalid table for care record deletion.');
    }
    if (recordId.trim().isEmpty) {
      throw ArgumentError('A care record is required for deletion.');
    }
    final updated = await _client
        .from(table)
        .update({'status': 'cancelled'})
        .eq('id', recordId)
        .inFilter('status', const ['requested', 'scheduled'])
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw StateError(
        'Only a requested or scheduled laboratory order can be cancelled.',
      );
    }
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
        .select(
          'id,hospital_id,user_id,display_name,specialization,license_number',
        )
        .eq('user_id', appUser['id'])
        .single();
  }
}

String _dateOnly(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
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

String _medicalMimeType(String fileName, List<int> bytes) {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw ArgumentError('Medical files must be between 1 byte and 20 MB.');
  }
  final extension = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  final mimeType = const <String, String>{
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  }[extension];
  final matchesSignature = switch (extension) {
    'pdf' =>
      bytes.length >= 5 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46 &&
          bytes[4] == 0x2D,
    'jpg' || 'jpeg' =>
      bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF,
    'png' =>
      bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0D &&
          bytes[5] == 0x0A &&
          bytes[6] == 0x1A &&
          bytes[7] == 0x0A,
    'doc' =>
      bytes.length >= 8 &&
          bytes[0] == 0xD0 &&
          bytes[1] == 0xCF &&
          bytes[2] == 0x11 &&
          bytes[3] == 0xE0 &&
          bytes[4] == 0xA1 &&
          bytes[5] == 0xB1 &&
          bytes[6] == 0x1A &&
          bytes[7] == 0xE1,
    'docx' =>
      bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
          (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08),
    _ => false,
  };
  if (mimeType == null || !matchesSignature) {
    throw ArgumentError(
      'Only valid PDF, JPEG, PNG, DOC, and DOCX files are supported.',
    );
  }
  return mimeType;
}

String _shortId(String value) =>
    value.length <= 8 ? value : value.substring(0, 8).toUpperCase();

String? _nullableText(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
