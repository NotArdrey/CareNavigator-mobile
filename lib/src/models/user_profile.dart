class UserProfile {
  const UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.accountStatus,
    this.email,
    this.hospitalId,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final roleData = json['roles'];
    return UserProfile(
      id: json['id'] as String,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String?,
      hospitalId: json['hospital_id'] as String?,
      role: roleData is Map<String, dynamic>
          ? roleData['role_name'] as String? ?? 'guest'
          : 'guest',
      accountStatus: json['account_status'] as String? ?? 'pending',
    );
  }

  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? hospitalId;
  final String role;
  final String accountStatus;

  String get displayName {
    final fullName = '$firstName $lastName'.trim();
    return fullName.isEmpty ? (email ?? 'CareNavigator user') : fullName;
  }

  String get roleLabel => role
      .split('_')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}
