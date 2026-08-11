import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/guest_consultation_models.dart';
import '../models/shared/patient_identity.dart';
import '../repositories/consultation_repository.dart' as consultation;
import 'core_providers.dart';
import 'hospital_directory_provider.dart';

final guestConsultationProvider =
    NotifierProvider<GuestConsultationController, GuestConsultationState>(
      GuestConsultationController.new,
    );

class GuestConsultationController extends Notifier<GuestConsultationState> {
  @override
  GuestConsultationState build() => const GuestConsultationState(
    draft: GuestConsultationIntakeDraft(),
    status: GuestRequestStatus.drafting,
    busy: false,
    resendCount: 0,
  );

  void saveContact({
    required String email,
    required String concern,
    required bool privacyAccepted,
    required String firstName,
    required String lastName,
    required DateTime? birthDate,
    required String sex,
    required String mobileNumber,
    required String address,
    required String symptomDuration,
  }) {
    _ensureDrafting();
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      throw ArgumentError.value(email, 'email', 'A valid email is required.');
    }
    final normalizedConcern = concern.trim();
    if (normalizedConcern.length < 10 || normalizedConcern.length > 1000) {
      throw ArgumentError.value(
        concern,
        'concern',
        'Concern must contain 10 to 1000 characters.',
      );
    }
    if (!privacyAccepted) {
      throw StateError('Consent is required before submitting a request.');
    }
    final identity = PatientIdentity(
      firstName: firstName,
      lastName: lastName,
      birthDate: birthDate,
      sex: sex,
      mobileNumber: mobileNumber,
      email: normalizedEmail,
      address: address,
    );
    if (!identity.isComplete || symptomDuration.trim().isEmpty) {
      throw StateError('Complete every identity and symptom field.');
    }
    state = state.copyWith(
      draft: state.draft.copyWith(
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        birthDate: birthDate,
        sex: sex.trim(),
        mobileNumber: mobileNumber.trim(),
        email: normalizedEmail,
        address: address.trim(),
        concern: normalizedConcern,
        symptomDuration: symptomDuration.trim(),
        privacyAccepted: true,
      ),
    );
  }

  void saveCareSelection({
    required String hospitalId,
    required String departmentLabel,
    required GuestCareMode careMode,
  }) {
    _ensureDrafting();
    final hospital = ref.read(hospitalDirectoryProvider).findById(hospitalId);
    if (hospital == null) throw StateError('Unknown hospital ID: $hospitalId');
    final departmentId = hospital.departmentIds[departmentLabel];
    if (!hospital.departments.contains(departmentLabel) ||
        departmentId == null) {
      throw StateError('Department is not linked to the selected hospital.');
    }
    final offersOnline = hospital.services.any(
      (service) => service.toLowerCase().contains('online'),
    );
    if (careMode == GuestCareMode.online && !offersOnline) {
      throw StateError(
        'The selected hospital does not offer online consultation.',
      );
    }
    state = state.copyWith(
      draft: state.draft.copyWith(
        hospitalId: hospital.id,
        hospitalLabel: hospital.name,
        locationLabel: hospital.locationLabel,
        departmentLabel: departmentLabel,
        departmentId: departmentId,
        careMode: careMode,
      ),
    );
  }

  void saveSchedule(DateTime preferredStart) {
    _ensureDrafting();
    final now = DateTime.now();
    if (!preferredStart.isAfter(now)) {
      throw ArgumentError.value(
        preferredStart,
        'preferredStart',
        'Preferred schedule must be in the future.',
      );
    }
    if (preferredStart.isAfter(now.add(const Duration(days: 180)))) {
      throw ArgumentError.value(
        preferredStart,
        'preferredStart',
        'Preferred schedule must be within 180 days.',
      );
    }
    state = state.copyWith(
      draft: state.draft.copyWith(preferredStart: preferredStart),
    );
  }

  Future<void> beginVerificationFlow() async {
    _ensureDrafting();
    final repository = ref.read(consultationRepositoryProvider);
    if (repository == null) {
      throw StateError('Consultation service is unavailable.');
    }
    if (!state.draft.isComplete) {
      throw StateError('Complete every consultation intake field first.');
    }
    state = state.copyWith(busy: true);
    try {
      await repository.sendGuestVerificationCode(state.draft.email);
      state = state.copyWith(
        busy: false,
        status: GuestRequestStatus.awaitingVerification,
      );
    } catch (_) {
      state = state.copyWith(busy: false);
      rethrow;
    }
  }

  Future<void> resendVerificationCode() async {
    if (state.status != GuestRequestStatus.awaitingVerification) {
      throw StateError('No email verification is awaiting a code.');
    }
    if (state.busy) return;
    final repository = ref.read(consultationRepositoryProvider);
    if (repository == null) {
      throw StateError('Consultation service is unavailable.');
    }
    state = state.copyWith(busy: true);
    try {
      await repository.sendGuestVerificationCode(state.draft.email);
      state = state.copyWith(busy: false, resendCount: state.resendCount + 1);
    } catch (_) {
      state = state.copyWith(busy: false);
      rethrow;
    }
  }

  Future<String> verifyCode({
    required String email,
    required String code,
  }) async {
    if (state.status != GuestRequestStatus.awaitingVerification) {
      throw StateError('No consultation request is awaiting verification.');
    }
    if (email.trim().toLowerCase() != state.draft.email) {
      throw ArgumentError.value(
        email,
        'email',
        'Email must match the consultation request.',
      );
    }
    final repository = ref.read(consultationRepositoryProvider);
    if (repository == null) {
      throw StateError('Consultation service is unavailable.');
    }
    if (state.busy) throw StateError('Verification is already in progress.');
    state = state.copyWith(busy: true);
    try {
      await repository.verifyGuestEmailCode(
        email: state.draft.email,
        otp: code,
      );
      final draft = state.draft;
      final requestId = await repository.createGuestRequest(
        consultation.GuestConsultationDraft(
          firstName: draft.firstName,
          lastName: draft.lastName,
          birthDate: draft.birthDate!,
          sex: draft.sex,
          mobileNumber: draft.mobileNumber,
          email: draft.email,
          address: draft.address,
          concern: draft.concern,
          symptomDuration: draft.symptomDuration,
          hospitalId: draft.hospitalId,
          departmentId: draft.departmentId,
          preferredStart: draft.preferredStart,
        ),
      );
      state = state.copyWith(
        busy: false,
        status: GuestRequestStatus.submitted,
        requestId: requestId,
      );
      return requestId;
    } catch (_) {
      state = state.copyWith(busy: false);
      rethrow;
    }
  }

  void reset() {
    state = const GuestConsultationState(
      draft: GuestConsultationIntakeDraft(),
      status: GuestRequestStatus.drafting,
      busy: false,
      resendCount: 0,
    );
  }

  void _ensureDrafting() {
    if (state.status != GuestRequestStatus.drafting) {
      throw StateError('The consultation request is no longer editable.');
    }
  }
}
