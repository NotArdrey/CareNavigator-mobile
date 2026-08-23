import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_flow_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/guest_consultation/consultation_request_screen.dart';
import '../features/guest_consultation/guest_verification_screen.dart';
import '../features/public/doctor_directory_screen.dart';
import '../features/public/hospital_screens.dart';
import '../features/public/public_home_screen.dart';
import '../features/workspaces/workspace_screen.dart';
import '../models/auth/user_role.dart';
import '../providers/core_providers.dart';
import 'root_overlay.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  late final GoRouter router;
  router = GoRouter(
    navigatorKey: rootNavigatorKey,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const PublicHomeScreen()),
      GoRoute(
        path: '/doctors',
        builder: (context, state) =>
            DoctorDirectoryScreen(initialQuery: state.uri.queryParameters['q']),
      ),
      GoRoute(
        path: '/hospitals',
        builder: (context, state) => HospitalDirectoryScreen(
          initialQuery: state.uri.queryParameters['q'],
        ),
        routes: [
          GoRoute(
            path: 'map',
            builder: (context, state) => HospitalMapScreen(
              initialQuery: state.uri.queryParameters['q'],
              selectedHospitalId: state.uri.queryParameters['hospitalId'],
              selectionSource: state.uri.queryParameters['source'],
              initialUserLatitude: double.tryParse(
                state.uri.queryParameters['userLat'] ?? '',
              ),
              initialUserLongitude: double.tryParse(
                state.uri.queryParameters['userLng'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: ':hospitalId',
            builder: (context, state) => HospitalDetailScreen(
              hospitalId: state.pathParameters['hospitalId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/consultation/request',
        builder: (context, state) => ConsultationRequestScreen(
          initialHospitalId: state.uri.queryParameters['hospitalId'],
        ),
      ),
      GoRoute(
        path: '/consultation/verify',
        builder: (context, state) => const GuestVerificationScreen(),
      ),
      GoRoute(
        path: '/consultation/confirmation/:requestId',
        builder: (context, state) => GuestConfirmationScreen(
          requestId: state.pathParameters['requestId']!,
        ),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => SignInScreen(
          redirectTo: state.uri.queryParameters['from'],
          showAccountCreatedMessage:
              state.uri.queryParameters['status'] == 'account-created',
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) =>
            const AuthFlowScreen(kind: AuthFlowKind.register),
      ),
      GoRoute(
        path: '/verify-otp',
        builder: (context, state) =>
            const AuthFlowScreen(kind: AuthFlowKind.verifyOtp),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) =>
            const AuthFlowScreen(kind: AuthFlowKind.forgotPassword),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) =>
            const AuthFlowScreen(kind: AuthFlowKind.resetPassword),
      ),
      GoRoute(
        path: '/access/restricted',
        builder: (context, state) => const AccessStateScreen(
          title: 'Access restricted',
          message:
              'This account is not currently permitted to use the requested workspace. Contact an authorized administrator if you believe this is incorrect.',
          actionLabel: 'Return to public care',
          actionLocation: '/',
        ),
      ),
      GoRoute(
        path: '/access/pending',
        builder: (context, state) => const AccessStateScreen(
          title: 'Approval pending',
          message:
              'This account is waiting for an authorized approval workflow before protected features become available.',
          actionLabel: 'Return to public care',
          actionLocation: '/',
        ),
      ),
      GoRoute(
        path: '/access/signed-out',
        builder: (context, state) => const AccessStateScreen(
          title: 'Signed out',
          message: 'Sign in again to continue to a protected workspace.',
        ),
      ),
      GoRoute(
        path: '/access/session-expired',
        builder: (context, state) => const AccessStateScreen(
          title: 'Session expired',
          message:
              'Your session is no longer valid. Sign in again before continuing.',
        ),
      ),
      ..._workspaceRoutes(UserRole.patient, '/patient'),
      ..._workspaceRoutes(UserRole.doctor, '/doctor'),
      ..._workspaceRoutes(UserRole.hospitalAdministrator, '/hospital-admin'),
      ..._workspaceRoutes(UserRole.superAdministrator, '/super-admin'),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route_outlined, size: 44),
              const SizedBox(height: 14),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(state.uri.path, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  ref.listen(appIdentityProvider, (previous, next) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

List<GoRoute> _workspaceRoutes(UserRole role, String path) => [
  GoRoute(
    path: path,
    builder: (context, state) =>
        WorkspaceScreen(role: role, location: state.uri.path),
    routes: [
      GoRoute(
        path: ':section',
        builder: (context, state) => WorkspaceScreen(
          role: role,
          location: state.uri.path,
          section: state.pathParameters['section'],
          requestReservation:
              role == UserRole.patient &&
              (state.uri.queryParameters['reserve'] == 'true' ||
                  state.uri.queryParameters['book'] == 'true'),
          initialReservationHospitalId: state.uri.queryParameters['hospitalId'],
          initialReservationDoctorId: state.uri.queryParameters['doctorId'],
        ),
        routes: [
          GoRoute(
            path: ':itemId',
            builder: (context, state) => WorkspaceScreen(
              role: role,
              location: state.uri.path,
              section: state.pathParameters['section'],
              itemId: state.pathParameters['itemId'],
            ),
            routes: [
              GoRoute(
                path: ':action',
                builder: (context, state) => WorkspaceScreen(
                  role: role,
                  location: state.uri.path,
                  section: state.pathParameters['section'],
                  itemId: state.pathParameters['itemId'],
                  action: state.pathParameters['action'],
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];

String? _redirect(Ref ref, GoRouterState state) {
  final identity = ref.read(appIdentityProvider);
  final path = state.uri.path;

  if (path == '/patient/files' || path.startsWith('/patient/files/')) {
    return '/patient';
  }

  // Keep old assessment links usable while sending people to the assistant-
  // enabled directory. The standalone assessment flow is no longer exposed.
  if (path == '/assessment' || path.startsWith('/assessment/')) {
    return '/hospitals';
  }

  if (path.startsWith('/consultation/request')) {
    // This is the public, email-verified guest intake. Authenticated patients
    // use the server-authoritative reservation flow in their workspace instead.
    if (identity.isAuthenticated && identity.role != UserRole.guest) {
      if (identity.role == UserRole.patient) {
        return Uri(
          path: '/patient/appointments',
          queryParameters: {
            'reserve': 'true',
            'hospitalId': ?state.uri.queryParameters['hospitalId'],
            'doctorId': ?state.uri.queryParameters['doctorId'],
          },
        ).toString();
      }
      return identity.role.homeLocation;
    }
  }

  final protectedRole = _roleForProtectedPath(path);

  if (protectedRole == null) {
    if ({
          '/sign-in',
          '/register',
          '/verify-otp',
          '/forgot-password',
        }.contains(path) &&
        identity.isAuthenticated) {
      final requestedLocation = state.uri.queryParameters['from'];
      if (identity.role == UserRole.patient &&
          requestedLocation != null &&
          requestedLocation.startsWith('/consultation/request')) {
        return requestedLocation;
      }
      return identity.role.homeLocation;
    }
    return null;
  }

  if (!identity.isAuthenticated) {
    return Uri(path: '/sign-in', queryParameters: {'from': path}).toString();
  }
  if (identity.status == AccountStatus.pending) return '/access/pending';
  if (identity.status != AccountStatus.active) return '/access/restricted';
  if (identity.role != protectedRole) return identity.role.homeLocation;
  return null;
}

UserRole? _roleForProtectedPath(String path) {
  if (path == '/patient' || path.startsWith('/patient/')) {
    return UserRole.patient;
  }
  if (path == '/doctor' || path.startsWith('/doctor/')) return UserRole.doctor;
  if (path == '/hospital-admin' || path.startsWith('/hospital-admin/')) {
    return UserRole.hospitalAdministrator;
  }
  if (path == '/super-admin' || path.startsWith('/super-admin/')) {
    return UserRole.superAdministrator;
  }
  return null;
}
