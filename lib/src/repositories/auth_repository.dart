import '../models/auth/user_role.dart';
import 'package:supabase/supabase.dart';

import 'repository_failure.dart';

abstract interface class AuthRepository {
  Stream<AppIdentity> watchIdentity();

  Future<AppIdentity> signInAnonymously();

  Future<AppIdentity> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> register({
    required String email,
    required String password,
    required Map<String, Object?> profileInput,
  });

  Future<void> sendEmailOtp(String email);

  Future<AppIdentity> verifyEmailOtp({
    required String email,
    required String token,
  });

  Future<void> requestPasswordReset(String email);

  Future<void> updatePassword(String password);

  Future<void> signOut();
}

final class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AppIdentity> signInAnonymously() async {
    try {
      final response = await _client.auth.signInAnonymously();
      return _identityForSession(response.session);
    } on AuthException catch (error) {
      throw AuthenticationFailure(
        'Guest access is temporarily unavailable. Please try again later.',
        cause: error,
      );
    } on PostgrestException catch (error) {
      throw UnexpectedRepositoryFailure(
        'Guest access could not be started.',
        cause: error,
      );
    }
  }

  @override
  Stream<AppIdentity> watchIdentity() async* {
    yield await _identityForSession(_client.auth.currentSession);
    await for (final state in _client.auth.onAuthStateChange) {
      yield await _identityForSession(state.session);
    }
  }

  @override
  Future<AppIdentity> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      return _identityForSession(response.session);
    } on AuthException catch (error) {
      throw AuthenticationFailure(error.message, cause: error);
    } on PostgrestException catch (error) {
      throw UnexpectedRepositoryFailure(
        'The account profile could not be loaded.',
        cause: error,
      );
    }
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required Map<String, Object?> profileInput,
  }) async {
    final firstName = _requiredProfileValue(profileInput, 'first_name');
    final lastName = _requiredProfileValue(profileInput, 'last_name');
    final mobileNumber = _requiredProfileValue(profileInput, 'mobile_number');
    final birthDate = _requiredProfileValue(profileInput, 'birth_date');
    final sex = _requiredProfileValue(profileInput, 'sex');
    final address = _requiredProfileValue(profileInput, 'address');
    try {
      await _client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: {
          'registration_source': 'patient_self_service',
          'first_name': firstName,
          'last_name': lastName,
          'mobile_number': mobileNumber,
          'birth_date': birthDate,
          'sex': sex,
          'address': address,
        },
      );
    } on AuthException catch (error) {
      throw AuthenticationFailure(error.message, cause: error);
    }
  }

  @override
  Future<void> sendEmailOtp(String email) async {
    try {
      await _client.auth.signInWithOtp(
        email: email.trim().toLowerCase(),
        shouldCreateUser: false,
      );
    } on AuthException catch (error) {
      throw AuthenticationFailure(error.message, cause: error);
    }
  }

  @override
  Future<AppIdentity> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    try {
      final response = await _client.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: token.trim(),
        type: OtpType.email,
      );
      return _identityForSession(response.session);
    } on AuthException catch (error) {
      throw AuthenticationFailure(error.message, cause: error);
    }
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim().toLowerCase());
    } on AuthException catch (error) {
      throw AuthenticationFailure(error.message, cause: error);
    }
  }

  @override
  Future<void> updatePassword(String password) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      throw AuthenticationFailure(error.message, cause: error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw AuthenticationFailure(error.message, cause: error);
    }
  }

  Future<AppIdentity> _identityForSession(Session? session) async {
    final authUser = session?.user;
    if (authUser == null || authUser.isAnonymous) {
      return const AppIdentity.guest();
    }

    final data = await _client
        .from('users')
        .select(
          'id, first_name, last_name, account_status, roles!inner(role_name), hospital:hospitals!users_hospital_id_fkey(hospital_name)',
        )
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    if (data == null) {
      throw const ContractUnavailableFailure(
        'The signed-in account does not have an application profile.',
      );
    }

    final roleData = data['roles'];
    final roleRecord = roleData is List
        ? (roleData.isEmpty ? null : roleData.first)
        : roleData;
    final roleName = roleRecord is Map
        ? roleRecord['role_name']?.toString()
        : null;
    final hospitalData = data['hospital'];
    final hospitalRecord = hospitalData is List
        ? (hospitalData.isEmpty ? null : hospitalData.first)
        : hospitalData;
    final assignedHospitalName = hospitalRecord is Map
        ? hospitalRecord['hospital_name']?.toString().trim()
        : null;
    final firstName = data['first_name']?.toString().trim() ?? '';
    final lastName = data['last_name']?.toString().trim() ?? '';
    final displayName = [
      firstName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ');

    return AppIdentity(
      role: _roleFromDatabase(roleName),
      status: _statusFromDatabase(data['account_status']?.toString()),
      userId: data['id']?.toString() ?? authUser.id,
      displayName: displayName.isEmpty ? authUser.email : displayName,
      assignedHospitalName:
          assignedHospitalName == null || assignedHospitalName.isEmpty
          ? null
          : assignedHospitalName,
    );
  }

  static String _requiredProfileValue(Map<String, Object?> input, String key) {
    final value = input[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw ValidationFailure('$key is required.');
    }
    return value;
  }

  static UserRole _roleFromDatabase(String? value) => switch (value) {
    'patient' => UserRole.patient,
    'doctor' => UserRole.doctor,
    'hospital_admin' => UserRole.hospitalAdministrator,
    'super_admin' => UserRole.superAdministrator,
    _ => UserRole.guest,
  };

  static AccountStatus _statusFromDatabase(String? value) => switch (value) {
    'pending' => AccountStatus.pending,
    'inactive' => AccountStatus.inactive,
    'suspended' => AccountStatus.restricted,
    _ => AccountStatus.active,
  };
}
