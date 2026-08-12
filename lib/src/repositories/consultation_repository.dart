import 'package:supabase/supabase.dart';

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

  String get fullName => [
    firstName.trim(),
    lastName.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
}

abstract interface class ConsultationRepository {
  Future<void> sendGuestVerificationCode(String email);

  Future<void> verifyGuestEmailCode({
    required String email,
    required String otp,
  });

  Future<String> createGuestRequest(GuestConsultationDraft draft);

  Future<String> bookConsultation({
    required String doctorId,
    required String hospitalId,
    required String consultationType,
    required DateTime appointmentDate,
    required String chiefComplaint,
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

  Future<Uri> getApprovedVideoRoom(String consultationId);
}

final class SupabaseConsultationRepository implements ConsultationRepository {
  SupabaseConsultationRepository(this._client);

  final SupabaseClient _client;

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
  Future<String> bookConsultation({
    required String doctorId,
    required String hospitalId,
    required String consultationType,
    required DateTime appointmentDate,
    required String chiefComplaint,
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
    if (!appointmentDate.toUtc().isAfter(DateTime.now().toUtc())) {
      throw ArgumentError('Choose a future appointment time.');
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
          },
        },
      );
    } on PostgrestException catch (error) {
      throw PermissionFailure(
        'The appointment could not be booked. Confirm that the slot is still published and available.',
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
        draft.preferredStart == null ||
        !draft.preferredStart!.toUtc().isAfter(DateTime.now().toUtc())) {
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
    if (!scheduledFor.toUtc().isAfter(DateTime.now().toUtc())) {
      throw ArgumentError('Choose a future appointment time.');
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
