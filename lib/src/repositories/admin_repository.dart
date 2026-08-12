import 'dart:typed_data';

import 'package:supabase/supabase.dart';

abstract interface class AdminRepository {
  Future<void> approveHospital(String hospitalId);

  Future<void> rejectHospital({
    required String hospitalId,
    required String reason,
  });

  Future<void> updateAccountStatus({
    required String userId,
    required String status,
  });

  Future<HospitalAdminContext> loadHospitalAdminContext();

  Future<void> createDoctorAccount({
    required String hospitalId,
    required String firstName,
    required String lastName,
    required String email,
    required String temporaryPassword,
    required String specialization,
    required String licenseNumber,
    String? departmentId,
    double? consultationFee,
    String? biography,
    List<int>? profileImageBytes,
    String? profileImageFileName,
  });

  Future<void> createHospitalDepartment({
    required String name,
    required String description,
  });

  Future<void> createHospitalService({
    required String name,
    required String description,
    String? departmentId,
  });

  Future<void> createMaintenanceWindow({
    required String title,
    required String message,
    required DateTime startsAt,
    required DateTime endsAt,
  });

  Future<void> deleteManagedRecord({
    required String table,
    required String recordId,
  });

  Future<void> updateHospitalAvailability({
    required String hospitalId,
    required Map<String, Object?> changes,
  });

  Future<void> updateOperationalRecord({
    required String table,
    required String recordId,
    required Map<String, Object?> changes,
  });

  Future<void> updatePermission({
    required String permissionId,
    required bool allowed,
  });

  Future<void> updateSystemSetting({
    required String key,
    required Object value,
  });

  Future<void> setMaintenanceActive({
    required String maintenanceId,
    required bool active,
  });
}

class HospitalDepartmentOption {
  const HospitalDepartmentOption({required this.id, required this.name});

  final String id;
  final String name;
}

class HospitalAdminContext {
  const HospitalAdminContext({
    required this.hospitalId,
    required this.departments,
  });

  final String hospitalId;
  final List<HospitalDepartmentOption> departments;
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);

  static const _accountStatuses = {'active', 'inactive', 'suspended'};
  static const _hospitalOperatingStatuses = {
    'open',
    'limited',
    'temporarily_closed',
    'closed',
  };
  static const _availabilityColumns = {
    'operating_status',
    'operating_hours',
    'contact_number',
    'emergency_contact_number',
    'description',
    'image_url',
  };
  static const _operationalColumns = <String, Set<String>>{
    'hospital_beds': {'total_beds', 'available_beds', 'occupied_beds'},
    'hospital_rooms': {
      'total_rooms',
      'available_rooms',
      'occupied_rooms',
      'status',
    },
    'emergency_room_status': {
      'status',
      'available_beds',
      'current_patient_count',
      'maximum_capacity',
    },
    'hospital_facility_status': {'status', 'available_units', 'notes'},
    'hospital_services': {'availability_status'},
    'hospital_departments': {'availability_status'},
  };
  static const _operationalStatuses = <String, Set<String>>{
    'hospital_rooms': {'available', 'limited', 'unavailable'},
    'emergency_room_status': {
      'available',
      'limited',
      'full',
      'temporarily_closed',
    },
    'hospital_facility_status': {'available', 'limited', 'unavailable'},
    'hospital_services': {'available', 'limited', 'unavailable'},
    'hospital_departments': {'available', 'limited', 'unavailable'},
  };
  static const _deletableTables = {
    'hospital_services',
    'hospital_departments',
    'maintenance_windows',
  };

  final SupabaseClient _client;

  @override
  Future<void> approveHospital(String hospitalId) async {
    if (hospitalId.trim().isEmpty) {
      throw ArgumentError('A hospital is required for approval.');
    }
    await _client.rpc<void>(
      'review_hospital_application',
      params: {
        'target_hospital_id': hospitalId,
        'decision': 'verified',
        'decision_note': 'Verified against the submitted hospital information.',
      },
    );
  }

  @override
  Future<void> rejectHospital({
    required String hospitalId,
    required String reason,
  }) async {
    if (hospitalId.trim().isEmpty) {
      throw ArgumentError('A hospital is required for rejection.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'A rejection reason is required.',
      );
    }
    await _client.rpc<void>(
      'review_hospital_application',
      params: {
        'target_hospital_id': hospitalId,
        'decision': 'rejected',
        'decision_note': reason.trim(),
      },
    );
  }

  @override
  Future<void> updateAccountStatus({
    required String userId,
    required String status,
  }) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError('An account is required for this status update.');
    }
    if (!_accountStatuses.contains(status)) {
      throw ArgumentError.value(
        status,
        'status',
        'Unsupported account status.',
      );
    }
    final response = await _client.functions.invoke(
      'admin-users',
      body: {
        'action': 'update_user_status',
        'user_id': userId,
        'account_status': status,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError(
        message?.toString() ?? 'Could not update account status.',
      );
    }
  }

  @override
  Future<HospitalAdminContext> loadHospitalAdminContext() async {
    final appUser = await _currentAppUser();
    final hospitalId = appUser['hospital_id']?.toString();
    if (hospitalId == null || hospitalId.isEmpty) {
      throw StateError('An assigned hospital is required.');
    }
    final rows = await _client
        .from('hospital_departments')
        .select('id,department_name')
        .eq('hospital_id', hospitalId)
        .order('department_name');
    return HospitalAdminContext(
      hospitalId: hospitalId,
      departments: rows
          .map(
            (row) => HospitalDepartmentOption(
              id: row['id'].toString(),
              name: row['department_name'].toString(),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> createDoctorAccount({
    required String hospitalId,
    required String firstName,
    required String lastName,
    required String email,
    required String temporaryPassword,
    required String specialization,
    required String licenseNumber,
    String? departmentId,
    double? consultationFee,
    String? biography,
    List<int>? profileImageBytes,
    String? profileImageFileName,
  }) async {
    final requiredValues = [
      hospitalId,
      firstName,
      lastName,
      email,
      specialization,
      licenseNumber,
    ];
    if (requiredValues.any((value) => value.trim().isEmpty)) {
      throw ArgumentError('All required doctor fields must be completed.');
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      throw ArgumentError('Enter a valid doctor email address.');
    }
    if (temporaryPassword.length < 12) {
      throw ArgumentError(
        'The temporary password needs at least 12 characters.',
      );
    }
    if (consultationFee != null && consultationFee < 0) {
      throw ArgumentError('The consultation fee cannot be negative.');
    }
    final response = await _client.functions.invoke(
      'admin-users',
      body: {
        'action': 'create_doctor',
        'hospital_id': hospitalId,
        'department_id': _nullableText(departmentId),
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'email': email.trim().toLowerCase(),
        'password': temporaryPassword,
        'specialization': specialization.trim(),
        'license_number': licenseNumber.trim(),
        'consultation_fee': consultationFee,
        'biography': _nullableText(biography),
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error'] : null;
      throw StateError(
        message?.toString() ?? 'Could not create doctor account.',
      );
    }
    if (profileImageBytes != null && profileImageBytes.isNotEmpty) {
      final data = response.data;
      var createdUserId = data is Map ? data['user_id']?.toString() : null;
      if (createdUserId == null || createdUserId.isEmpty) {
        final createdUser = await _client
            .from('users')
            .select('id')
            .eq('email', email.trim().toLowerCase())
            .maybeSingle();
        createdUserId = createdUser?['id']?.toString();
      }
      if (createdUserId == null || createdUserId.isEmpty) {
        throw StateError(
          'Doctor created, but the profile image could not be linked.',
        );
      }
      final extension =
          (profileImageFileName ?? 'profile.jpg')
                  .split('.')
                  .last
                  .toLowerCase() ==
              'png'
          ? 'png'
          : 'jpg';
      final path = '$createdUserId/profile.$extension';
      await _client.storage
          .from('profile-images')
          .uploadBinary(
            path,
            Uint8List.fromList(profileImageBytes),
            fileOptions: FileOptions(
              contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
              upsert: true,
            ),
          );
      await _client
          .from('users')
          .update({
            'profile_image_url': _client.storage
                .from('profile-images')
                .getPublicUrl(path),
          })
          .eq('id', createdUserId)
          .select('id')
          .single();
    }
  }

  @override
  Future<void> createHospitalDepartment({
    required String name,
    required String description,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.length < 2) {
      throw ArgumentError('A department name is required.');
    }
    final appUser = await _currentAppUser();
    final hospitalId = appUser['hospital_id']?.toString();
    if (hospitalId == null || hospitalId.isEmpty) {
      throw StateError('An assigned hospital is required.');
    }
    await _client
        .from('hospital_departments')
        .insert({
          'hospital_id': hospitalId,
          'department_name': normalizedName,
          'description': description.trim(),
        })
        .select('id')
        .single();
  }

  @override
  Future<void> createHospitalService({
    required String name,
    required String description,
    String? departmentId,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.length < 2) {
      throw ArgumentError('A service name is required.');
    }
    final appUser = await _currentAppUser();
    final hospitalId = appUser['hospital_id']?.toString();
    if (hospitalId == null || hospitalId.isEmpty) {
      throw StateError('An assigned hospital is required.');
    }
    await _client
        .from('hospital_services')
        .insert({
          'hospital_id': hospitalId,
          'department_id': _nullableText(departmentId),
          'service_name': normalizedName,
          'description': description.trim(),
        })
        .select('id')
        .single();
  }

  @override
  Future<void> createMaintenanceWindow({
    required String title,
    required String message,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    if (title.trim().length < 3 || message.trim().length < 5) {
      throw ArgumentError(
        'A maintenance title and clear message are required.',
      );
    }
    if (!endsAt.isAfter(startsAt)) {
      throw ArgumentError('Maintenance must end after it starts.');
    }
    final appUser = await _currentAppUser();
    await _client
        .from('maintenance_windows')
        .insert({
          'title': title.trim(),
          'message': message.trim(),
          'starts_at': startsAt.toUtc().toIso8601String(),
          'ends_at': endsAt.toUtc().toIso8601String(),
          'created_by': appUser['id'],
          'is_active': true,
        })
        .select('id')
        .single();
  }

  @override
  Future<void> deleteManagedRecord({
    required String table,
    required String recordId,
  }) async {
    if (!_deletableTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unsupported deletion target.');
    }
    if (recordId.trim().isEmpty) {
      throw ArgumentError('A managed record is required for deletion.');
    }
    await _client.from(table).delete().eq('id', recordId).select('id').single();
  }

  @override
  Future<void> updateHospitalAvailability({
    required String hospitalId,
    required Map<String, Object?> changes,
  }) async {
    if (hospitalId.trim().isEmpty) {
      throw ArgumentError('A hospital is required for this update.');
    }
    if (changes.isEmpty) {
      throw ArgumentError.value(
        changes,
        'changes',
        'At least one change is required.',
      );
    }
    final unsupported = changes.keys.toSet().difference(_availabilityColumns);
    if (unsupported.isNotEmpty) {
      throw ArgumentError(
        'Unsupported hospital fields: ${unsupported.join(', ')}.',
      );
    }
    final operatingStatus = changes['operating_status'];
    if (operatingStatus != null &&
        !_hospitalOperatingStatuses.contains(operatingStatus)) {
      throw ArgumentError.value(
        operatingStatus,
        'operating_status',
        'Unsupported hospital operating status.',
      );
    }
    await _client
        .from('hospitals')
        .update(changes)
        .eq('id', hospitalId)
        .select('id')
        .single();
  }

  @override
  Future<void> updateOperationalRecord({
    required String table,
    required String recordId,
    required Map<String, Object?> changes,
  }) async {
    final allowed = _operationalColumns[table];
    if (allowed == null) {
      throw ArgumentError.value(
        table,
        'table',
        'Unsupported operational table.',
      );
    }
    if (changes.isEmpty || !allowed.containsAll(changes.keys)) {
      throw ArgumentError(
        'The operational update contains unsupported fields.',
      );
    }
    if (recordId.trim().isEmpty) {
      throw ArgumentError('An operational record is required for this update.');
    }
    final statusKey =
        table == 'hospital_services' || table == 'hospital_departments'
        ? 'availability_status'
        : 'status';
    final status = changes[statusKey];
    final supportedStatuses = _operationalStatuses[table];
    if (status != null &&
        supportedStatuses != null &&
        !supportedStatuses.contains(status)) {
      throw ArgumentError.value(
        status,
        statusKey,
        'Unsupported operational status.',
      );
    }
    await _client
        .from(table)
        .update(changes)
        .eq('id', recordId)
        .select('id')
        .single();
  }

  @override
  Future<void> updatePermission({
    required String permissionId,
    required bool allowed,
  }) async {
    if (permissionId.trim().isEmpty) {
      throw ArgumentError('A permission is required for this update.');
    }
    await _client
        .from('role_permissions')
        .update({'is_allowed': allowed})
        .eq('id', permissionId)
        .select('id')
        .single();
  }

  @override
  Future<void> updateSystemSetting({
    required String key,
    required Object value,
  }) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError('A setting key is required.');
    }
    await _client
        .from('system_settings')
        .update({'value': value})
        .eq('key', normalizedKey)
        .select('key')
        .single();
  }

  @override
  Future<void> setMaintenanceActive({
    required String maintenanceId,
    required bool active,
  }) async {
    if (maintenanceId.trim().isEmpty) {
      throw ArgumentError('A maintenance window is required for this update.');
    }
    await _client
        .from('maintenance_windows')
        .update({'is_active': active})
        .eq('id', maintenanceId)
        .select('id')
        .single();
  }

  Future<Map<String, dynamic>> _currentAppUser() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('An authenticated admin is required.');
    return _client
        .from('users')
        .select('id,hospital_id')
        .eq('auth_user_id', user.id)
        .single();
  }
}

String? _nullableText(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
