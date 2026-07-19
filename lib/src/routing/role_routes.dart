/// Returns the first workspace a signed-in user should see for their role.
String landingRouteForRole(String? role) => switch (role) {
  'super_admin' || 'hospital_admin' => '/admin',
  'doctor' => '/care',
  'patient' => '/dashboard',
  _ => '/home',
};

const adminMobileAccessMessage =
    'Admin accounts cannot access the mobile application. Please sign in through the desktop web portal.';

const adminDesktopBreakpoint = 920.0;

bool isAdministratorRole(String? role) =>
    role == 'super_admin' || role == 'hospital_admin';

bool isDesktopAdminPortalAvailable({
  required bool isWeb,
  required double logicalWidth,
}) => isWeb && logicalWidth >= adminDesktopBreakpoint;

bool shouldBlockAdminAccess({
  required String? role,
  required bool isWeb,
  required double logicalWidth,
}) =>
    isAdministratorRole(role) &&
    !isDesktopAdminPortalAvailable(isWeb: isWeb, logicalWidth: logicalWidth);

enum RoleDestination {
  home('/home'),
  hospitals('/hospitals'),
  consult('/consult'),
  dashboard('/dashboard'),
  care('/care'),
  admin('/admin'),
  operations('/admin/operations'),
  notifications('/notifications');

  const RoleDestination(this.path);

  final String path;
}

class RoleNavigationItem {
  const RoleNavigationItem(this.destination, this.label);

  final RoleDestination destination;
  final String label;

  String get path => destination.path;
}

/// Navigation shared by the mobile bottom bar and the desktop/web rail.
List<RoleNavigationItem> navigationForRole(String? role) => switch (role) {
  'super_admin' => const [
    RoleNavigationItem(RoleDestination.dashboard, 'Overview'),
    RoleNavigationItem(RoleDestination.admin, 'Platform'),
    RoleNavigationItem(RoleDestination.operations, 'Operations'),
    RoleNavigationItem(RoleDestination.notifications, 'Alerts'),
  ],
  'hospital_admin' => const [
    RoleNavigationItem(RoleDestination.dashboard, 'Overview'),
    RoleNavigationItem(RoleDestination.admin, 'Hospital'),
    RoleNavigationItem(RoleDestination.operations, 'Operations'),
    RoleNavigationItem(RoleDestination.care, 'Care'),
    RoleNavigationItem(RoleDestination.notifications, 'Alerts'),
  ],
  'doctor' => const [
    RoleNavigationItem(RoleDestination.dashboard, 'Overview'),
    RoleNavigationItem(RoleDestination.care, 'Clinical'),
    RoleNavigationItem(RoleDestination.hospitals, 'Hospitals'),
    RoleNavigationItem(RoleDestination.notifications, 'Alerts'),
  ],
  'patient' => const [
    RoleNavigationItem(RoleDestination.home, 'Home'),
    RoleNavigationItem(RoleDestination.hospitals, 'Hospitals'),
    RoleNavigationItem(RoleDestination.dashboard, 'My care'),
    RoleNavigationItem(RoleDestination.care, 'Records'),
    RoleNavigationItem(RoleDestination.notifications, 'Alerts'),
  ],
  _ => const [
    RoleNavigationItem(RoleDestination.home, 'Home'),
    RoleNavigationItem(RoleDestination.hospitals, 'Hospitals'),
    RoleNavigationItem(RoleDestination.consult, 'Consult'),
    RoleNavigationItem(RoleDestination.dashboard, 'My care'),
  ],
};
