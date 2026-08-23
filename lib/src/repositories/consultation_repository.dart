import 'package:supabase/supabase.dart';

import '../models/consultation_scheduling.dart';
import '../models/consultation_type.dart';
import 'repository_failure.dart';

class GuestConsultationDraft {
  const GuestConsultationDraft({
    required this.firstName,
    required this.lastName,
    required this.birthDate,
    required this.sex,
    required this.mobileNumber,
    required this.email,
    required this.address,
    required this.concern,
    required this.symptomDuration,
    this.hospitalId,
    this.departmentId,
    this.preferredStart,
    this.consultationType = 'guest_online',
  });

  final String firstName;
  final String lastName;
  final DateTime birthDate;
  final String sex;
  final String mobileNumber;
  final String email;
  final String address;
  final String concern;
  final String symptomDuration;
  final String? hospitalId;
  final String? departmentId;
  final DateTime? preferredStart;
  final String consultationType;

  String get fullName => [
    firstName.trim(),
    lastName.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
}

class GuestReviewDoctor {
  const GuestReviewDoctor({
    required this.id,
    required this.displayName,
    required this.specialization,
    this.departmentId,
  });

  final String id;
  final String displayName;
  final String specialization;
  final String? departmentId;
}

class AvailableConsultationSlot {
  const AvailableConsultationSlot({
    required this.startsAt,
    required this.endsAt,
  });

  final DateTime startsAt;
  final DateTime endsAt;

  factory AvailableConsultationSlot.fromJson(Map<String, dynamic> json) {
    final startsAt = DateTime.tryParse(json['starts_at']?.toString() ?? '');
    final endsAt = DateTime.tryParse(json['ends_at']?.toString() ?? '');
    if (startsAt == null || endsAt == null) {
      throw const FormatException(
        'The available consultation slot is invalid.',
      );
    }
    return AvailableConsultationSlot(startsAt: startsAt, endsAt: endsAt);
  }
}

abstract interface class ConsultationRepository {
  Future<void> sendGuestVerificationCode(String email);

  Future<void> verifyGuestEmailCode({
    required String email,
    required String otp,
  });

  Future<String> createGuestRequest(GuestConsultationDraft draft);

  Future<List<GuestReviewDoctor>> listGuestReviewDoctors({
    required String hospitalId,
    String? departmentId,
  });

  Future<List<AvailableConsultationSlot>> listAvailableSlots({
    required String doctorId,
    required String consultationType,
    int horizonDays = 30,
  });

  Future<String> reserveConsultation({
    required String doctorId,
    required String hospitalId,
    required String consultationType,
    required DateTime appointmentDate,
    required String chiefComplaint,
    String symptomDuration = 'Not specified',
    List<String> sharedCategories = const [],
    List<Map<String, Object?>> selectedRecords = const [],
    List<String> supportingDocumentIds = const [],
  });

  Future<void> verifyGuestEmail({
    required String requestId,
    required String otp,
  });

  Future<void> cancelConsultation(String consultationId);

  Future<void> rescheduleConsultation({
    required String consultationId,
    required DateTime scheduledFor,
  });

  Future<void> transitionConsultation({
    required String consultationId,
    required String status,
    String? notes,
    DateTime? scheduledFor,
    Map<String, Object?> clinicalPayload = const {},
  });

  Future<void> ensureVideoRoom(String consultationId);

  Future<void> reviewGuestRequest({
    required String requestId,
    required String decision,
    String? doctorId,
    DateTime? appointmentDate,
    String? notes,
  });

  Future<void> reviewOnlineRequest({
    required String requestId,
    required String decision,
    String? doctorId,
    DateTime? confirmedSchedule,
    String? channel,
    String? notes,
  });

  Future<void> cancelOnlineRequest({
    required String requestId,
    required String reason,
  });

  Future<Uri> getApprovedVideoRoom(String consultationId);
}

final class SupabaseConsultationRepository implements ConsultationRepository {
  SupabaseConsultationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AvailableConsultationSlot>> listAvailableSlots({
    required String doctorId,
    required String consultationType,
    int horizonDays = 30,
  }) async {
    final normalizedDoctorId = doctorId.trim();
    if (normalizedDoctorId.isEmpty) {
      throw ArgumentError('Choose a clinician to view available times.');
    }
    if (horizonDays < 1 || horizonDays > 60) {
      throw ArgumentError('The availability window must be 1 to 60 days.');
    }
    final normalizedType = ConsultationType.normalize(consultationType);
    try {
      final response = await _client.rpc<List<dynamic>>(
        'list_available_consultation_slots',
        params: {
          'target_doctor_id': normalizedDoctorId,
          'target_type': normalizedType,
          'horizon_days': horizonDays,
        },
      );
      return response
          .whereType<Map>()
          .map(
            (row) => AvailableConsultationSlot.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .where((slot) => meetsReservationLeadTime(slot.startsAt))
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw UnexpectedRepositoryFailure(
        'Available appointment times could not be loaded.',
        cause: error,
      );
    }
  }

  @override
  Future<void> sendGuestVerificationCode(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      throw ArgumentError('Enter a valid consultation email address.');
    }
    try {
      await _client.auth.signInWithOtp(
        email: normalizedEmail,
        shouldCreateUser: true,
      );
    } on AuthException catch (error) {
      throw AuthenticationFailure(error.message, cause: error);
    }
  }

  @override
  Future<String> reserveConsultation({
    required String doctorId,
    required String hospitalId,
    required String consultationType,
    required DateTime appointmentDate,
    required String chiefComplaint,
    String symptomDuration = 'Not specified',
    List<String> sharedCategories = const [],
    List<Map<String, Object?>> selectedRecords = const [],
    List<String> supportingDocumentIds = const [],
  }) async {
    final complaint = chiefComplaint.trim();
    final normalizedDoctorId = doctorId.trim();
    final normalizedHospitalId = hospitalId.trim();
    if (normalizedDoctorId.isEmpty || normalizedHospitalId.isEmpty) {
      throw ArgumentError('A published clinician and hospital are required.');
    }
    final normalizedConsultationType = ConsultationType.normalize(
      consultationType,
    );
    if (!meetsReservationLeadTime(appointmentDate)) {
      throw ArgumentError(reservationLeadTimeMessage);
    }
    if (complaint.length < 5) {
      throw ArgumentError(
        'Describe the care concern in at least 5 characters.',
      );
    }
    try {
      return await _client.rpc<String>(
        'book_consultation',
        params: {
          'booking_payload': {
            'doctor_id': normalizedDoctorId,
            'hospital_id': normalizedHospitalId,
            'consultation_type': normalizedConsultationType,
            'appointment_date': appointmentDate.toUtc().toIso8601String(),
            'chief_complaint': complaint,
            'symptom_duration': symptomDuration.trim().isEmpty
                ? 'Not specified'
                : symptomDuration.trim(),
            'shared_categories': sharedCategories,
            'selected_records': selectedRecords,
            'supporting_document_ids': supportingDocumentIds,
          },
        },
      );
    } on PostgrestException catch (error) {
      throw PermissionFailure(
        'The appointment could not be reserved. Confirm that the slot is still published and available at least 24 hours in advance.',
        cause: error,
      );
    }
  }

  @override
  Future<void> verifyGuestEmailCode({
    required String email,
    required String otp,
  }) async {
    if (email.trim().isEmpty || otp.trim().isEmpty) {
      throw ArgumentError(
        'An email address and verification code are required.',
      );
    }
    try {
      await _client.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: otp.trim(),
        type: OtpType.email,
      );
    } on AuthException catch (error) {
      throw AuthenticationFailure(error.message, cause: error);
    }
  }

  @override
  Future<String> createGuestRequest(GuestConsultationDraft draft) async {
    final normalizedEmail = draft.email.trim().toLowerCase();
    if (draft.fullName.trim().isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail) ||
        draft.concern.trim().length < 10 ||
        draft.symptomDuration.trim().isEmpty ||
        draft.hospitalId == null ||
        draft.departmentId == null ||
        !{'face_to_face', 'guest_online'}.contains(draft.consultationType) ||
        draft.preferredStart == null ||
        !meetsReservationLeadTime(draft.preferredStart!)) {
      throw ArgumentError(
        'Complete the consultation request before submitting.',
      );
    }
    final authUser = _client.auth.currentUser;
    if (authUser == null || authUser.email?.toLowerCase() != normalizedEmail) {
      throw const AuthenticationFailure(
        'Verify the consultation email before submitting the request.',
      );
    }
    try {
      final data = await _client
          .from('guest_consultation_requests')
          .insert({
            'submitted_by': authUser.id,
            'first_name': draft.firstName.trim(),
            'last_name': draft.lastName.trim(),
            'full_name': draft.fullName.trim(),
            'birth_date': _date(draft.birthDate),
            'sex': draft.sex,
            'mobile_number': draft.mobileNumber.trim(),
            'email': normalizedEmail,
            'address': draft.address.trim(),
            'symptoms': draft.concern.trim(),
            'symptom_duration': draft.symptomDuration.trim(),
            'consultation_reason': draft.concern.trim(),
            'preferred_hospital_id': draft.hospitalId,
            'preferred_department_id': draft.departmentId,
            'preferred_consultation_type': draft.consultationType,
            'preferred_schedule': draft.preferredStart
                ?.toUtc()
                .toIso8601String(),
            'otp_verified_at': DateTime.now().toUtc().toIso8601String(),
            'consent_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();
      return data['id'].toString();
    } on PostgrestException catch (error) {
      throw UnexpectedRepositoryFailure(
        'The consultation request could not be submitted.',
        cause: error,
      );
    }
  }

  @override
  Future<List<GuestReviewDoctor>> listGuestReviewDoctors({
    required String hospitalId,
    String? departmentId,
  }) async {
    final normalizedHospitalId = hospitalId.trim();
    if (normalizedHospitalId.isEmpty) {
      throw ArgumentError('A hospital is required to assign a doctor.');
    }
    dynamic query = _client
        .from('doctors')
        .select('id,display_name,specialization,department_id')
        .eq('hospital_id', normalizedHospitalId)
        .neq('availability_status', 'unavailable')
        .order('display_name');
    final normalizedDepartmentId = departmentId?.trim();
    if (normalizedDepartmentId != null && normalizedDepartmentId.isNotEmpty) {
      query = query.eq('department_id', normalizedDepartmentId);
    }
    final rows = await query;
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(
          (row) => GuestReviewDoctor(
            id: row['id'].toString(),
            displayName: row['display_name']?.toString() ?? 'Doctor',
            specialization: row['specialization']?.toString() ?? 'General care',
            departmentId: row['department_id']?.toString(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> verifyGuestEmail({
    required String requestId,
    required String otp,
  }) async {
    throw const ContractUnavailableFailure(
      'Guest email verification occurs before request creation.',
    );
  }

  @override
  Future<void> cancelConsultation(String consultationId) async {
    if (consultationId.trim().isEmpty) {
      throw ArgumentError(
        'A consultation is required to cancel an appointment.',
      );
    }
    try {
      await _client.rpc<Map<String, dynamic>>(
        'cancel_consultation',
        params: {'target_consultation_id': consultationId},
      );
    } on PostgrestException catch (error) {
      throw PermissionFailure(
        'This consultation can no longer be cancelled.',
        cause: error,
      );
    }
  }

  @override
  Future<void> rescheduleConsultation({
    required String consultationId,
    required DateTime scheduledFor,
  }) async {
    if (consultationId.trim().isEmpty) {
      throw ArgumentError(
        'A consultation is required to reschedule an appointment.',
      );
    }
    if (!meetsReservationLeadTime(scheduledFor)) {
      throw ArgumentError(reservationLeadTimeMessage);
    }
    try {
      await _client.rpc<Map<String, dynamic>>(
        'reschedule_consultation',
        params: {
          'target_consultation_id': consultationId,
          'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        },
      );
    } on PostgrestException catch (error) {
      throw PermissionFailure(
        'The consultation could not be rescheduled to that time.',
        cause: error,
      );
    }
  }

  @override
  Future<void> transitionConsultation({
    required String consultationId,
    required String status,
    String? notes,
    DateTime? scheduledFor,
    Map<String, Object?> clinicalPayload = const {},
  }) async {
    if (consultationId.trim().isEmpty) {
      throw ArgumentError('A consultation is required for this update.');
    }
    try {
      await _client.rpc<Map<String, dynamic>>(
        'transition_consultation',
        params: {
          'target_consultation_id': consultationId,
          'target_status': status,
          'transition_notes': notes?.trim(),
          'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
          'clinical_payload': clinicalPayload,
        },
      );
    } on PostgrestException catch (error) {
      throw PermissionFailure(
        'This consultation transition is not permitted.',
        cause: error,
      );
    }
  }

  @override
  Future<void> ensureVideoRoom(String consultationId) async {
    if (consultationId.trim().isEmpty) {
      throw ArgumentError('A consultation is required to open a video room.');
    }
    try {
      await _client.rpc<String>(
        'ensure_video_session',
        params: {'target_consultation_id': consultationId},
      );
    } on PostgrestException catch (error) {
      throw PermissionFailure(
        'The secure video room could not be prepared.',
        cause: error,
      );
    }
  }

  @override
  Future<void> reviewGuestRequest({
    required String requestId,
    required String decision,
    String? doctorId,
    DateTime? appointmentDate,
    String? notes,
  }) async {
    if (requestId.trim().isEmpty) {
      throw ArgumentError('A guest request is required for this review.');
    }
    if (!{'approved', 'rejected'}.contains(decision)) {
      throw ArgumentError.value(
        decision,
        'decision',
        'Unsupported review decision.',
      );
    }
    if (decision == 'approved' &&
        appointmentDate != null &&
        !meetsReservationLeadTime(appointmentDate)) {
      throw ArgumentError(reservationLeadTimeMessage);
    }
    try {
      await _client.rpc<Map<String, dynamic>>(
        'review_guest_consultation',
        params: {
          'target_request_id': requestId,
          'decision': decision,
          'target_doctor_id': doctorId,
          'target_appointment_date': appointmentDate?.toUtc().toIso8601String(),
          'review_notes': notes?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw PermissionFailure(
        'The guest consultation review could not be completed.',
        cause: error,
      );
    }
  }

  @override
  Future<void> reviewOnlineRequest({
    required String requestId,
    required String decision,
    String? doctorId,
    DateTime? confirmedSchedule,
    String? channel,
    String? notes,
  }) async {
    final normalizedRequestId = requestId.trim();
    final normalizedDecision = decision.trim().toLowerCase();
    final normalizedChannel = channel?.trim().toLowerCase();
    if (normalizedRequestId.isEmpty) {
      throw ArgumentError('An online request is required for this review.');
    }
    if (!{
      'under_review',
      'more_information_required',
      'schedule_proposed',
      'confirmed',
      'rejected',
      'cancelled',
      'patient_unreachable',
      'face_to_face_recommended',
    }.contains(normalizedDecision)) {
      throw ArgumentError.value(
        decision,
        'decision',
        'Unsupported online request decision.',
      );
    }
    if (normalizedChannel != null &&
        normalizedChannel.isNotEmpty &&
        !{'call', 'email', 'video'}.contains(normalizedChannel)) {
      throw ArgumentError.value(
        channel,
        'channel',
        'Choose call, email, or video consultation.',
      );
    }
    if (normalizedDecision == 'confirmed' &&
        (normalizedChannel == null || normalizedChannel.isEmpty)) {
      throw ArgumentError('A confirmed request requires a contact channel.');
    }
    if ({'schedule_proposed', 'confirmed'}.contains(normalizedDecision) &&
        confirmedSchedule != null &&
        !meetsReservationLeadTime(confirmedSchedule)) {
      throw ArgumentError(reservationLeadTimeMessage);
    }
    try {
      await _client.rpc<Map<String, dynamic>>(
        'review_online_consultation_request',
        params: {
          'target_request_id': normalizedRequestId,
          'decision': normalizedDecision,
          'target_doctor_id': doctorId,
          'target_confirmed_schedule': confirmedSchedule
              ?.toUtc()
              .toIso8601String(),
          'target_channel': normalizedChannel,
          'review_notes': notes?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw PermissionFailure(
        'The online consultation review could not be completed.',
        cause: error,
      );
    }
  }

  @override
  Future<void> cancelOnlineRequest({
    required String requestId,
    required String reason,
  }) async {
    if (requestId.trim().isEmpty || reason.trim().isEmpty) {
      throw ArgumentError('A request and cancellation reason are required.');
    }
    try {
      await _client.rpc<Map<String, dynamic>>(
        'cancel_online_consultation_request',
        params: {
          'target_request_id': requestId.trim(),
          'cancellation_reason': reason.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw PermissionFailure(
        'This online consultation request can no longer be cancelled.',
        cause: error,
      );
    }
  }

  @override
  Future<Uri> getApprovedVideoRoom(String consultationId) async {
    if (consultationId.trim().isEmpty) {
      throw ArgumentError('A consultation is required to open a video room.');
    }
    try {
      final rawUrl = await _client.rpc<String>(
        'get_approved_video_room',
        params: {'target_consultation_id': consultationId},
      );
      final uri = Uri.tryParse(rawUrl);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'meet.jit.si' ||
          !uri.path.startsWith('/cnph-')) {
        throw const ContractUnavailableFailure(
          'The approved video room returned an invalid address.',
        );
      }
      return uri;
    } on PostgrestException catch (error) {
      throw ContractUnavailableFailure(
        'The video room is not ready or is outside its scheduled join window.',
        cause: error,
      );
    }
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

const consultationJoinLeadTime = Duration(minutes: 15);
const consultationJoinDuration = Duration(hours: 4);

bool isConsultationJoinWindowOpen(DateTime appointmentDate, {DateTime? at}) {
  final scheduledAt = appointmentDate.toUtc();
  final checkedAt = (at ?? DateTime.now()).toUtc();
  return !checkedAt.isBefore(scheduledAt.subtract(consultationJoinLeadTime)) &&
      checkedAt.isBefore(scheduledAt.add(consultationJoinDuration));
}
