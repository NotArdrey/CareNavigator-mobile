import 'shared/patient_identity.dart';

enum GuestCareMode { inPerson, online }

enum GuestRequestStatus { drafting, awaitingVerification, submitted }

class GuestConsultationIntakeDraft {
  const GuestConsultationIntakeDraft({
    this.firstName = '',
    this.lastName = '',
    this.birthDate,
    this.sex = '',
    this.mobileNumber = '',
    this.email = '',
    this.address = '',
    this.concern = '',
    this.symptomDuration = '',
    this.privacyAccepted = false,
    this.hospitalId,
    this.hospitalLabel,
    this.locationLabel,
    this.departmentLabel,
    this.departmentId,
    this.careMode = GuestCareMode.inPerson,
    this.preferredStart,
  });

  final String firstName;
  final String lastName;
  final DateTime? birthDate;
  final String sex;
  final String mobileNumber;
  final String email;
  final String address;
  final String concern;
  final String symptomDuration;
  final bool privacyAccepted;
  final String? hospitalId;
  final String? hospitalLabel;
  final String? locationLabel;
  final String? departmentLabel;
  final String? departmentId;
  final GuestCareMode careMode;
  final DateTime? preferredStart;

  String get fullName => [
    firstName.trim(),
    lastName.trim(),
  ].where((part) => part.isNotEmpty).join(' ');

  bool get hasContact =>
      email.isNotEmpty && concern.isNotEmpty && privacyAccepted;

  bool get hasIdentity =>
      PatientIdentity(
        firstName: firstName,
        lastName: lastName,
        birthDate: birthDate,
        sex: sex,
        mobileNumber: mobileNumber,
        email: email,
        address: address,
      ).isComplete &&
      symptomDuration.isNotEmpty;

  bool get hasCareSelection =>
      hospitalId != null && departmentId != null && locationLabel != null;

  bool get isComplete =>
      hasContact && hasIdentity && hasCareSelection && preferredStart != null;

  GuestConsultationIntakeDraft copyWith({
    String? firstName,
    String? lastName,
    DateTime? birthDate,
    String? sex,
    String? mobileNumber,
    String? email,
    String? address,
    String? concern,
    String? symptomDuration,
    bool? privacyAccepted,
    String? hospitalId,
    String? hospitalLabel,
    String? locationLabel,
    String? departmentLabel,
    String? departmentId,
    GuestCareMode? careMode,
    DateTime? preferredStart,
  }) => GuestConsultationIntakeDraft(
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    birthDate: birthDate ?? this.birthDate,
    sex: sex ?? this.sex,
    mobileNumber: mobileNumber ?? this.mobileNumber,
    email: email ?? this.email,
    address: address ?? this.address,
    concern: concern ?? this.concern,
    symptomDuration: symptomDuration ?? this.symptomDuration,
    privacyAccepted: privacyAccepted ?? this.privacyAccepted,
    hospitalId: hospitalId ?? this.hospitalId,
    hospitalLabel: hospitalLabel ?? this.hospitalLabel,
    locationLabel: locationLabel ?? this.locationLabel,
    departmentLabel: departmentLabel ?? this.departmentLabel,
    departmentId: departmentId ?? this.departmentId,
    careMode: careMode ?? this.careMode,
    preferredStart: preferredStart ?? this.preferredStart,
  );
}

class GuestConsultationState {
  const GuestConsultationState({
    required this.draft,
    required this.status,
    required this.busy,
    required this.resendCount,
    this.requestId,
  });

  final GuestConsultationIntakeDraft draft;
  final GuestRequestStatus status;
  final bool busy;
  final int resendCount;
  final String? requestId;

  GuestConsultationState copyWith({
    GuestConsultationIntakeDraft? draft,
    GuestRequestStatus? status,
    bool? busy,
    int? resendCount,
    String? requestId,
  }) => GuestConsultationState(
    draft: draft ?? this.draft,
    status: status ?? this.status,
    busy: busy ?? this.busy,
    resendCount: resendCount ?? this.resendCount,
    requestId: requestId ?? this.requestId,
  );
}
