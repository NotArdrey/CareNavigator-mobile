import 'package:care_navigator_ph/src/models/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  bool get hasVerifiedEmail =>
      _client.auth.currentSession != null &&
      (_client.auth.currentUser?.email?.isNotEmpty ?? false);

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) {
    return _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {'first_name': firstName.trim(), 'last_name': lastName.trim()},
    );
  }

  Future<void> sendEmailOtp(String email) async {
    await _client.auth.signInWithOtp(
      email: email.trim().toLowerCase(),
      shouldCreateUser: true,
      data: const {'access_purpose': 'guest_consultation'},
    );
  }

  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: token.trim(),
      type: OtpType.email,
    );
  }

  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<UserProfile?> getProfile() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;
    final response = await _client
        .from('users')
        .select(
          'id, first_name, last_name, email, hospital_id, account_status, roles(role_name)',
        )
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    return response == null ? null : UserProfile.fromJson(response);
  }
}
