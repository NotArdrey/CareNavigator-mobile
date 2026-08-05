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
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
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
      body: SafeArea(
        child: Column(
          children: [
            const AppPageHeader(
              eyebrow: 'ROUTE RECOVERY',
              title: 'This path is outside the care map',
              subtitle: 'Return to a verified CareNavigator destination',
              icon: AppIcons.healthAndSafetyRounded,
            ),
            Expanded(
              child: ResponsivePageContainer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final marker = Container(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      decoration: BoxDecoration(
                        color: AppColors.evergreenDark,
                        borderRadius: BorderRadius.circular(
                          AppRadius.extraLarge,
                        ),
                        boxShadow: AppShadows.medium,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppStatusBadge(
                            label: 'UNMAPPED DESTINATION',
                            color: AppColors.mint,
                            icon: AppIcons.exploreOffOutlined,
                            inverse: true,
                          ),
                          const Spacer(),
                          Text(
                            '404',
                            style: Theme.of(context).textTheme.displayLarge
                                ?.copyWith(
                                  color: AppColors.coral,
                                  fontSize: 92,
                                  height: .9,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            path,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                    final recovery = AppCard(
                      tone: AppCardTone.mint,
                      child: AppEmptyState(
                        kind: AppStateKind.error,
                        icon: AppIcons.signpostOutlined,
                        title: 'Choose a verified route',
                        message:
                            'This address does not match an existing CareNavigator screen. Your account and records are unchanged.',
                        compact: constraints.maxWidth < 720,
                        action: AppButton(
                          label: 'Return to care home',
                          icon: AppIcons.homeOutlined,
                          onPressed: () => context.go('/home'),
                        ),
                      ),
                    );
                    if (constraints.maxWidth < 720) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 220, child: marker),
                          const SizedBox(height: AppSpacing.md),
                          Expanded(child: recovery),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 4, child: marker),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(flex: 6, child: recovery),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
