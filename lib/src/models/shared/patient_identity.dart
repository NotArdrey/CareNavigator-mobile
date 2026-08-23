class PatientSexOption {
  const PatientSexOption({required this.value, required this.label});

  final String value;
  final String label;
}

const patientSexOptions = <PatientSexOption>[
  PatientSexOption(value: 'female', label: 'Female'),
  PatientSexOption(value: 'male', label: 'Male'),
];

class PatientIdentity {
  const PatientIdentity({
    required this.firstName,
    required this.lastName,
    required this.birthDate,
    required this.sex,
    required this.mobileNumber,
    required this.email,
    required this.address,
  });

  final String firstName;
  final String lastName;
  final DateTime? birthDate;
  final String? sex;
  final String mobileNumber;
  final String email;
  final String address;

  String get fullName => [
    firstName.trim(),
    lastName.trim(),
  ].where((part) => part.isNotEmpty).join(' ');

  bool get isComplete =>
      validatePatientName(firstName, label: 'first name') == null &&
      validatePatientName(lastName, label: 'last name') == null &&
      validateBirthDate(birthDate) == null &&
      patientSexOptions.any((option) => option.value == sex?.trim()) &&
      validateMobileNumber(mobileNumber) == null &&
      validateEmailAddress(email) == null &&
      validateHomeAddress(address) == null;

  Map<String, Object?> toAuthMetadata() => {
    'first_name': firstName.trim(),
    'last_name': lastName.trim(),
    'birth_date': birthDate == null ? null : patientDateValue(birthDate!),
    'sex': sex?.trim(),
    'mobile_number': mobileNumber.trim(),
    'address': address.trim(),
  };
}

String? validatePatientName(String? value, {required String label}) {
  final length = value?.trim().length ?? 0;
  return length >= 2 && length <= 60 ? null : 'Enter a valid $label.';
}

String? validateBirthDate(DateTime? value) {
  if (value == null) return 'Select your date of birth.';
  final today = _dateOnly(DateTime.now());
  return _dateOnly(value).isAfter(today)
      ? 'Date of birth cannot be in the future.'
      : null;
}

String? validateMobileNumber(String? value) {
  final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
  return digits.length < 7 || digits.length > 15
      ? 'Enter a valid mobile number.'
      : null;
}

String? validateEmailAddress(String? value) {
  final email = value?.trim() ?? '';
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
      ? null
      : 'Enter a valid email address.';
}

String? validateHomeAddress(String? value) {
  return (value?.trim().length ?? 0) >= 5
      ? null
      : 'Enter your current address.';
}

String patientDateValue(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
