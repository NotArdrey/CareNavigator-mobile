import 'package:care_navigator_ph/src/features/auth/presentation/login_screen.dart';
import 'package:care_navigator_ph/src/features/auth/presentation/register_screen.dart';
import 'package:care_navigator_ph/src/features/assessment/presentation/assessment_screen.dart';
import 'package:care_navigator_ph/src/features/admin/presentation/admin_console_screen.dart';
import 'package:care_navigator_ph/src/features/admin/presentation/admin_operations_screen.dart';
import 'package:care_navigator_ph/src/features/consultation/presentation/guest_consultation_screen.dart';
import 'package:care_navigator_ph/src/features/care/presentation/care_workspace_screen.dart';
import 'package:care_navigator_ph/src/features/chat/presentation/chat_screen.dart';
import 'package:care_navigator_ph/src/features/dashboard/presentation/dashboard_screen.dart';
import 'package:care_navigator_ph/src/features/home/presentation/home_screen.dart';
import 'package:care_navigator_ph/src/features/hospitals/presentation/hospital_detail_screen.dart';
import 'package:care_navigator_ph/src/features/hospitals/presentation/hospital_list_screen.dart';
import 'package:care_navigator_ph/src/features/hospitals/presentation/hospital_map_screen.dart';
import 'package:care_navigator_ph/src/features/notifications/presentation/notification_center_screen.dart';
import 'package:care_navigator_ph/src/features/profile/presentation/profile_screen.dart';
import 'package:care_navigator_ph/src/features/shell/presentation/app_shell.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    errorBuilder: (context, state) => _NotFoundScreen(path: state.uri.path),
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            redirect: (context, state) =>
                ref.read(authRepositoryProvider).currentSession == null
                ? '/login'
                : '/home',
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/hospitals',
            builder: (context, state) => const HospitalListScreen(),
            routes: [
              GoRoute(
                path: 'map',
                builder: (context, state) => HospitalMapScreen(
                  initialNeed: state.uri.queryParameters['need'],
                  initialMinimumLevel:
                      int.tryParse(state.uri.queryParameters['level'] ?? '') ??
                      1,
                  initialEmergencyOnly:
                      state.uri.queryParameters['emergency'] == '1',
                  initialRequiredServices:
                      state.uri.queryParameters['services']
                          ?.split('~')
                          .where((value) => value.trim().isNotEmpty)
                          .toList(growable: false) ??
                      const [],
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
            path: '/admin',
            redirect: (context, state) =>
                ref.read(authRepositoryProvider).currentSession == null
                ? '/login?redirect=${Uri.encodeComponent(state.uri.toString())}'
                : null,
            builder: (context, state) => const AdminConsoleScreen(),
          ),
          GoRoute(
            path: '/admin/operations',
            redirect: (context, state) =>
                ref.read(authRepositoryProvider).currentSession == null
                ? '/login?redirect=${Uri.encodeComponent(state.uri.toString())}'
                : null,
            builder: (context, state) => const AdminOperationsScreen(),
          ),
          GoRoute(
            path: '/assessment',
            builder: (context, state) => const AssessmentScreen(),
          ),
          GoRoute(
            path: '/consult',
            builder: (context, state) => GuestConsultationScreen(
              initialHospitalId: state.uri.queryParameters['hospital'],
            ),
          ),
          GoRoute(
            path: '/dashboard',
            redirect: (context, state) =>
                ref.read(authRepositoryProvider).currentSession == null
                ? '/login?redirect=${Uri.encodeComponent(state.uri.toString())}'
                : null,
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/care',
            redirect: (context, state) =>
                ref.read(authRepositoryProvider).currentSession == null
                ? '/login?redirect=${Uri.encodeComponent(state.uri.toString())}'
                : null,
            builder: (context, state) => const CareWorkspaceScreen(),
          ),
          GoRoute(
            path: '/profile',
            redirect: (context, state) =>
                ref.read(authRepositoryProvider).currentSession == null
                ? '/login?redirect=${Uri.encodeComponent(state.uri.toString())}'
                : null,
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/messages/:conversationId',
            builder: (context, state) => ChatScreen(
              conversationId: state.pathParameters['conversationId']!,
            ),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationCenterScreen(),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: '/register',
            builder: (context, state) => const RegisterScreen(),
          ),
        ],
      ),
    ],
  );
});

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_outlined, size: 54),
              const SizedBox(height: 14),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              Text('There is no CareNavigator page at $path.'),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('Return home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
