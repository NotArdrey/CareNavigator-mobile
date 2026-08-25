enum UserRole {
  guest,
  patient,
  doctor,
  hospitalAdministrator,
  superAdministrator;

  String get label => switch (this) {
    UserRole.guest => 'Guest',
    UserRole.patient => 'Patient',
    UserRole.doctor => 'Doctor',
    UserRole.hospitalAdministrator => 'Hospital administrator',
    UserRole.superAdministrator => 'Super administrator',
  };

  String get homeLocation => switch (this) {
    UserRole.guest => '/',
    UserRole.patient => '/patient',
    UserRole.doctor => '/doctor',
    UserRole.hospitalAdministrator => '/hospital-admin',
    UserRole.superAdministrator => '/super-admin',
  };

  String get routePrefix => switch (this) {
    UserRole.guest => '/',
    UserRole.patient => '/patient',
    UserRole.doctor => '/doctor',
    UserRole.hospitalAdministrator => '/hospital-admin',
    UserRole.superAdministrator => '/super-admin',
  };
}

enum AccountStatus { active, pending, restricted, inactive }

class AppIdentity {
  const AppIdentity({
    required this.role,
    required this.status,
    this.userId,
    this.displayName,
    this.assignedHospitalName,
  });

  const AppIdentity.guest()
    : role = UserRole.guest,
      status = AccountStatus.active,
      userId = null,
      displayName = null,
      assignedHospitalName = null;

  final UserRole role;
  final AccountStatus status;
  final String? userId;
  final String? displayName;
  final String? assignedHospitalName;

  bool get isAuthenticated => userId != null;
}
