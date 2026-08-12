import 'dart:typed_data';

import 'package:supabase/supabase.dart';

abstract interface class ProfileRepository {
  Future<CareProfile> loadProfile();

  Future<void> updateProfile(CareProfileUpdate update);

  Future<void> updateProfileImage({
    required List<int> bytes,
    required String fileName,
  });

  Future<void> updateNotificationPreferences(
    NotificationPreferenceUpdate update,
  );
}

class CareProfile {
  const CareProfile({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.mobileNumber,
    required this.birthDate,
    required this.sex,
    required this.address,
    required this.preferences,
    this.patientId,
    this.bloodType,
    this.emergencyContact,
    this.allergies,
    this.existingConditions,
    this.doctorDisplayName,
    this.specialization,
    this.licenseNumber,
    this.profileImageUrl,
  });

  final String userId;
  final String firstName;
  final String lastName;
  final String? email;
  final String? mobileNumber;
  final DateTime? birthDate;
  final String? sex;
  final String? address;
  final String? patientId;
  final String? bloodType;
  final String? emergencyContact;
  final String? allergies;
  final String? existingConditions;
  final String? doctorDisplayName;
  final String? specialization;
  final String? licenseNumber;
  final String? profileImageUrl;
  final NotificationPreferences preferences;
}

class CareProfileUpdate {
  const CareProfileUpdate({
    required this.firstName,
    required this.lastName,
    required this.mobileNumber,
    required this.birthDate,
    required this.sex,
    required this.address,
    this.patientId,
    this.bloodType,
    this.emergencyContact,
    this.allergies,
    this.existingConditions,
  });

  final String firstName;
  final String lastName;
  final String mobileNumber;
  final DateTime? birthDate;
  final String? sex;
  final String address;
  final String? patientId;
  final String? bloodType;
  final String? emergencyContact;
  final String? allergies;
  final String? existingConditions;
}

class NotificationPreferences {
  const NotificationPreferences({
    this.consultationUpdates = true,
    this.appointmentReminders = true,
    this.medicalResults = true,
    this.prescriptions = true,
    this.messages = true,
    this.hospitalAlerts = true,
    this.emailEnabled = false,
    this.inAppEnabled = true,
  });

  final bool consultationUpdates;
  final bool appointmentReminders;
  final bool medicalResults;
  final bool prescriptions;
  final bool messages;
  final bool hospitalAlerts;
  final bool emailEnabled;
  final bool inAppEnabled;

  factory NotificationPreferences.fromJson(Map<String, dynamic>? json) =>
      NotificationPreferences(
        consultationUpdates: json?['consultation_updates'] as bool? ?? true,
        appointmentReminders: json?['appointment_reminders'] as bool? ?? true,
        medicalResults: json?['medical_results'] as bool? ?? true,
        prescriptions: json?['prescriptions'] as bool? ?? true,
        messages: json?['messages'] as bool? ?? true,
        hospitalAlerts: json?['hospital_alerts'] as bool? ?? true,
        emailEnabled: json?['email_enabled'] as bool? ?? false,
        inAppEnabled: json?['in_app_enabled'] as bool? ?? true,
      );
}

class NotificationPreferenceUpdate {
  const NotificationPreferenceUpdate({
    required this.consultationUpdates,
    required this.appointmentReminders,
    required this.medicalResults,
    required this.prescriptions,
    required this.messages,
    required this.hospitalAlerts,
    required this.emailEnabled,
    required this.inAppEnabled,
  });

  final bool consultationUpdates;
  final bool appointmentReminders;
  final bool medicalResults;
  final bool prescriptions;
  final bool messages;
  final bool hospitalAlerts;
  final bool emailEnabled;
  final bool inAppEnabled;

  Map<String, Object?> toJson(String authUserId) => {
    'user_id': authUserId,
    'consultation_updates': consultationUpdates,
    'appointment_reminders': appointmentReminders,
    'medical_results': medicalResults,
    'prescriptions': prescriptions,
    'messages': messages,
    'hospital_alerts': hospitalAlerts,
    'email_enabled': emailEnabled,
    'in_app_enabled': inAppEnabled,
  };
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<CareProfile> loadProfile() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null || authUser.isAnonymous) {
      throw StateError('An authenticated account is required.');
    }
    final user = await _client
        .from('users')
        .select(
          'id,first_name,last_name,email,mobile_number,birth_date,sex,address,profile_image_url',
        )
        .eq('auth_user_id', authUser.id)
        .single();
    final patient = await _client
        .from('patients')
        .select('id,blood_type,emergency_contact,allergies,existing_conditions')
        .eq('user_id', user['id'])
        .maybeSingle();
    final doctor = await _client
        .from('doctors')
        .select('display_name,specialization,license_number')
        .eq('user_id', user['id'])
        .maybeSingle();
    final preference = await _client
        .from('notification_preferences')
        .select()
        .eq('user_id', authUser.id)
        .maybeSingle();
    return CareProfile(
      userId: _displayText(user['id']) ?? '',
      firstName: _displayText(user['first_name']) ?? '',
      lastName: _displayText(user['last_name']) ?? '',
      email: _displayText(user['email']),
      mobileNumber: _displayText(user['mobile_number']),
      birthDate: _date(user['birth_date']),
      sex: _displayText(user['sex']),
      address: _displayText(user['address']),
      patientId: _displayText(patient?['id']),
      bloodType: _displayText(patient?['blood_type']),
      emergencyContact: _displayText(patient?['emergency_contact']),
      allergies: _displayText(patient?['allergies']),
      existingConditions: _displayText(patient?['existing_conditions']),
      doctorDisplayName: _displayText(doctor?['display_name']),
      specialization: _displayText(doctor?['specialization']),
      licenseNumber: _displayText(doctor?['license_number']),
      profileImageUrl: _displayText(user['profile_image_url']),
      preferences: NotificationPreferences.fromJson(preference),
    );
  }

  @override
  Future<void> updateProfile(CareProfileUpdate update) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null || authUser.isAnonymous) {
      throw StateError('An authenticated account is required.');
    }
    final firstName = update.firstName.trim();
    final lastName = update.lastName.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      throw ArgumentError('First and last names are required.');
    }
    await _client
        .from('users')
        .update({
          'first_name': firstName,
          'last_name': lastName,
          'mobile_number': _nullable(update.mobileNumber),
          'birth_date': update.birthDate == null
              ? null
              : _dateValue(update.birthDate!),
          'sex': _nullable(update.sex),
          'address': _nullable(update.address),
          'address_geocode_hash': null,
          'address_latitude': null,
          'address_longitude': null,
        })
        .eq('auth_user_id', authUser.id)
        .select('id')
        .single();
    if (update.patientId != null) {
      await _client
          .from('patients')
          .update({
            'blood_type': _nullable(update.bloodType),
            'emergency_contact': _textObject(update.emergencyContact),
            'allergies': _textArray(update.allergies),
            'existing_conditions': _textArray(update.existingConditions),
          })
          .eq('id', update.patientId!)
          .select('id')
          .single();
    }
  }

  @override
  Future<void> updateProfileImage({
    required List<int> bytes,
    required String fileName,
  }) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null || authUser.isAnonymous) {
      throw StateError('An authenticated account is required.');
    }
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }
    final extension = fileName.split('.').last.toLowerCase() == 'png'
        ? 'png'
        : 'jpg';
    final path = '${authUser.id}/profile.$extension';
    await _client.storage
        .from('profile-images')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
            upsert: true,
          ),
        );
    final url = _client.storage.from('profile-images').getPublicUrl(path);
    await _client
        .from('users')
        .update({'profile_image_url': url})
        .eq('auth_user_id', authUser.id)
        .select('id')
        .single();
  }

  @override
  Future<void> updateNotificationPreferences(
    NotificationPreferenceUpdate update,
  ) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null || authUser.isAnonymous) {
      throw StateError('An authenticated account is required.');
    }
    await _client
        .from('notification_preferences')
        .upsert(update.toJson(authUser.id), onConflict: 'user_id')
        .select('user_id')
        .single();
  }
}

DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  return value is String ? DateTime.tryParse(value) : null;
}

String _dateValue(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String? _nullable(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

List<String> _textArray(String? value) {
  final normalized = _nullable(value);
  if (normalized == null) return const <String>[];
  return normalized
      .split(RegExp(r'[,;\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _displayText(Object? value) {
  if (value == null) return null;
  if (value is String) return _nullable(value);
  if (value is Map) {
    if (value.length == 1 && value.containsKey('details')) {
      return _displayText(value['details']);
    }
    final parts = <String>[];
    for (final entry in value.entries) {
      final text = _displayText(entry.value);
      if (text != null) {
        parts.add('${_humanizeKey(entry.key.toString())}: $text');
      }
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
  if (value is Iterable) {
    final parts = value.map(_displayText).whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
  return _nullable(value);
}

Map<String, String> _textObject(String? value) => {
  'details': _nullable(value) ?? '',
};

String _humanizeKey(String key) {
  final words = key
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map(
        (word) => word.length == 1
            ? word.toUpperCase()
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .toList();
  return words.join(' ');
}
