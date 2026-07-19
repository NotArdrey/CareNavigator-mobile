import 'package:care_navigator_ph/src/routing/role_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('landingRouteForRole', () {
    test('opens the administration console for platform administrators', () {
      expect(landingRouteForRole('super_admin'), '/admin');
    });

    test('opens the administration console for hospital administrators', () {
      expect(landingRouteForRole('hospital_admin'), '/admin');
    });

    test('opens the clinical workspace for doctors', () {
      expect(landingRouteForRole('doctor'), '/care');
    });

    test('opens My Care for patients', () {
      expect(landingRouteForRole('patient'), '/dashboard');
    });

    test('keeps guests and missing profiles on the public home page', () {
      expect(landingRouteForRole('guest'), '/home');
      expect(landingRouteForRole(null), '/home');
    });
  });

  group('navigationForRole', () {
    test('keeps super administrators out of clinical navigation', () {
      final navigation = navigationForRole('super_admin');

      expect(navigation.map((item) => item.destination), [
        RoleDestination.dashboard,
        RoleDestination.admin,
        RoleDestination.operations,
        RoleDestination.notifications,
      ]);
      expect(
        navigation.map((item) => item.destination),
        isNot(contains(RoleDestination.care)),
      );
    });

    test('gives hospital administrators hospital and care operations', () {
      final navigation = navigationForRole('hospital_admin');

      expect(
        navigation.map((item) => item.destination),
        containsAll([
          RoleDestination.admin,
          RoleDestination.operations,
          RoleDestination.care,
        ]),
      );
      expect(
        navigation.map((item) => item.destination),
        isNot(contains(RoleDestination.consult)),
      );
    });

    test('gives doctors clinical navigation', () {
      expect(
        navigationForRole('doctor').map((item) => item.destination),
        containsAll([
          RoleDestination.dashboard,
          RoleDestination.care,
          RoleDestination.notifications,
        ]),
      );
    });

    test('gives patients personal care navigation', () {
      expect(
        navigationForRole('patient').map((item) => item.label),
        containsAll(['Home', 'My care', 'Records', 'Alerts']),
      );
    });
  });

  group('admin device access', () {
    test('blocks both administrator roles in native mobile apps', () {
      for (final role in ['super_admin', 'hospital_admin']) {
        expect(
          shouldBlockAdminAccess(role: role, isWeb: false, logicalWidth: 1200),
          isTrue,
        );
      }
    });

    test('blocks administrators in compact mobile browsers', () {
      expect(
        shouldBlockAdminAccess(
          role: 'super_admin',
          isWeb: true,
          logicalWidth: 390,
        ),
        isTrue,
      );
    });

    test('allows administrators only on desktop web', () {
      expect(
        shouldBlockAdminAccess(
          role: 'hospital_admin',
          isWeb: true,
          logicalWidth: adminDesktopBreakpoint,
        ),
        isFalse,
      );
    });

    test('does not block doctors or patients on mobile', () {
      for (final role in ['doctor', 'patient']) {
        expect(
          shouldBlockAdminAccess(role: role, isWeb: false, logicalWidth: 390),
          isFalse,
        );
      }
    });
  });
}
