import 'package:care_navigator_ph/src/models/care_models.dart';
import 'package:care_navigator_ph/src/models/user_profile.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
import 'package:care_navigator_ph/src/widgets/async_value_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session =
        ref.watch(authStateProvider).value?.session ??
        ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) {
      return SafeArea(
        child: Column(
          children: [
            const AppPageHeader(
              eyebrow: 'MY CARE',
              title: 'Your care, in one secure place',
              subtitle: 'Sign in to access your private care journey',
              icon: AppIcons.dashboardRounded,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: AppPageBody.horizontalPadding(
                    MediaQuery.sizeOf(context).width,
                  ),
                  vertical: AppSpacing.xxl,
                ),
                child: const _SignInPrompt(),
              ),
            ),
          ],
        ),
      );
    }

    final profile = ref.watch(currentProfileProvider);
    return SafeArea(
      child: AsyncValuePanel<UserProfile?>(
        value: profile,
        onRetry: () => ref.invalidate(currentProfileProvider),
        data: (item) => item == null
            ? const _SignInPrompt()
            : _RoleDashboard(profile: item),
      ),
    );
  }
}

class _RoleDashboard extends ConsumerWidget {
  const _RoleDashboard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = _cardsForRole(profile.role);
    final isAdministrator = {
      'super_admin',
      'hospital_admin',
    }.contains(profile.role);
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = AppPageBody.horizontalPadding(width);
    final careSnapshot = {'patient', 'doctor'}.contains(profile.role)
        ? ref.watch(typedCareWorkspaceProvider(profile.role))
        : null;

    final compact = width < 700;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: AppPageHeader(
            eyebrow: 'SECURE ${profile.roleLabel.toUpperCase()} WORKSPACE',
            title: 'Your care command center',
            subtitle:
                'One clear view of the decisions and records that matter now',
            icon: _dashboardIcon(profile.role),
            actions: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () => context.go('/notifications'),
                icon: const Icon(AppIcons.notificationsOutlined),
              ),
              if (profile.role == 'patient')
                IconButton(
                  tooltip: 'Edit profile',
                  onPressed: () => _editPatientProfile(context, ref, profile),
                  icon: const Icon(AppIcons.manageAccountsOutlined),
                ),
            ],
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.xl,
            horizontal,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _DashboardHero(
              profile: profile,
              administrator: isAdministrator,
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.xl,
            horizontal,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: AppSectionHeader(
              eyebrow: careSnapshot == null
                  ? 'WORKSPACE ACCESS'
                  : 'TODAY\'S SIGNAL',
              title: careSnapshot == null
                  ? 'Operate with the right level of access'
                  : 'What needs your attention',
              subtitle: careSnapshot == null
                  ? 'Administrative tools are separated by operational purpose.'
                  : 'A live summary drawn from your secure care workspace.',
            ),
          ),
        ),
        if (careSnapshot != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.md,
              horizontal,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: careSnapshot.when(
                data: (workspace) =>
                    _CareOverview(profile: profile, workspace: workspace),
                loading: () => const _CareOverviewLoading(),
                error: (_, _) => AppNotice(
                  icon: AppIcons.syncProblemOutlined,
                  message:
                      'Your care summary is temporarily unavailable. Open the workspace to retry.',
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.md,
              horizontal,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: AppCard(
                tone: AppCardTone.mint,
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final copy = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppStatusBadge(
                          label: 'Scoped administrator access',
                          color: AppColors.teal,
                          icon: AppIcons.verifiedUserOutlined,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          profile.role == 'super_admin'
                              ? 'Platform-wide operations are ready.'
                              : 'Your hospital workspace is ready.',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'Review the directory, accounts, capacity, reporting, and auditable system activity from the dedicated console.',
                        ),
                      ],
                    );
                    final action = AppButton(
                      label: 'Open administration console',
                      icon: AppIcons.arrowForwardRounded,
                      onPressed: () => context.go('/admin'),
                    );
                    if (constraints.maxWidth < 720) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          copy,
                          const SizedBox(height: AppSpacing.lg),
                          action,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: copy),
                        const SizedBox(width: 40),
                        action,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.xxl,
            horizontal,
            AppSpacing.xxxl + (compact ? 72 : 0),
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  eyebrow: 'WORKSPACE DIRECTORY',
                  title: 'Choose your next move',
                  subtitle: 'Each destination opens a focused task area.',
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < cards.length; index++) ...[
                        _DashboardCard(item: cards[index], index: index + 1),
                        if (index != cards.length - 1)
                          const Divider(height: 1, indent: 84),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.item, required this.index});

  final _DashboardItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final route = _routeForDashboardTitle(item.title);
    return InkWell(
      onTap: () => context.go(route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.softMint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                index.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: AppColors.teal,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppIconTile(icon: item.icon, color: item.color, size: 40),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(AppIcons.arrowOutwardRounded),
          ],
        ),
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({required this.profile, required this.administrator});

  final UserProfile profile;
  final bool administrator;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    decoration: BoxDecoration(
      color: AppColors.deepGreen,
      borderRadius: BorderRadius.circular(AppRadius.xlarge),
      boxShadow: AppShadows.medium,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final identity = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppStatusBadge(
              label: '${_pretty(profile.accountStatus)} account',
              color: AppColors.mint,
              icon: AppIcons.verifiedRounded,
              inverse: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Good day, ${profile.displayName}.',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                height: 1.02,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              administrator
                  ? 'See the operating picture, then move directly into the console that owns the work.'
                  : 'Start with the signal below, then move into the focused care area you need.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.mist,
                height: 1.45,
              ),
            ),
          ],
        );
        final monogram = Container(
          width: 124,
          height: 124,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.forest,
            borderRadius: BorderRadius.circular(38),
          ),
          child: Text(
            profile.displayName.characters.first.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: 72,
                height: 72,
                child: FittedBox(child: monogram),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 48),
            monogram,
          ],
        );
      },
    ),
  );
}

IconData _dashboardIcon(String role) => switch (role) {
  'doctor' => AppIcons.medicalServicesRounded,
  'hospital_admin' => AppIcons.localHospitalRounded,
  'super_admin' => AppIcons.adminPanelSettingsRounded,
  _ => AppIcons.healthAndSafetyRounded,
};

class _CareOverview extends StatelessWidget {
  const _CareOverview({required this.profile, required this.workspace});

  final UserProfile profile;
  final RoleWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final isPatient = profile.role == 'patient';
    final nextConsultation = _nextConsultation(workspace.consultations);
    final unread = workspace.notifications
        .where((notification) => !notification.isRead)
        .length;
    final scheduled = workspace.consultations
        .where(
          (consultation) => !{
            'completed',
            'cancelled',
            'rejected',
          }.contains(consultation.status),
        )
        .length;
    final reviewCount = workspace.laboratoryResults
        .where(
          (result) =>
              !{'confirmed', 'verified', 'rejected'}.contains(result.status),
        )
        .length;

    final feature = _OverviewFeature(
      eyebrow: isPatient ? 'YOUR NEXT STEP' : 'CLINICAL WORKSPACE',
      title: isPatient
          ? nextConsultation == null
                ? 'Your care is up to date'
                : 'Upcoming consultation'
          : scheduled == 0
          ? 'No consultations waiting'
          : '$scheduled consultation${scheduled == 1 ? '' : 's'} need attention',
      description: isPatient
          ? nextConsultation == null
                ? 'Review your records or request a consultation whenever you need support.'
                : _consultationSummary(nextConsultation)
          : '${workspace.patients.length} assigned patient${workspace.patients.length == 1 ? '' : 's'} · ${workspace.guestRequests.length} guest request${workspace.guestRequests.length == 1 ? '' : 's'}',
      icon: isPatient
          ? nextConsultation == null
                ? AppIcons.healthAndSafetyOutlined
                : AppIcons.eventAvailableRounded
          : AppIcons.assignmentIndOutlined,
      actionLabel: isPatient
          ? nextConsultation == null
                ? 'Open medical records'
                : 'View appointment'
          : 'Open clinical workspace',
      route: '/care',
    );

    final metrics = isPatient
        ? [
            _OverviewMetric(
              label: 'Medical records',
              value: workspace.medicalRecords.length.toString(),
              icon: AppIcons.folderSharedOutlined,
              color: AppColors.teal,
              route: '/care',
            ),
            _OverviewMetric(
              label: 'Active prescriptions',
              value: workspace.prescriptions.length.toString(),
              icon: AppIcons.medicationOutlined,
              color: const Color(0xFFD05A29),
              route: '/care',
            ),
            _OverviewMetric(
              label: 'Unread updates',
              value: unread.toString(),
              icon: AppIcons.notificationsOutlined,
              color: const Color(0xFF6A4BBC),
              route: '/notifications',
            ),
          ]
        : [
            _OverviewMetric(
              label: 'Assigned patients',
              value: workspace.patients.length.toString(),
              icon: AppIcons.groupsOutlined,
              color: AppColors.blue,
              route: '/care',
            ),
            _OverviewMetric(
              label: 'Guest reviews',
              value: workspace.guestRequests.length.toString(),
              icon: AppIcons.inboxOutlined,
              color: AppColors.teal,
              route: '/care',
            ),
            _OverviewMetric(
              label: 'Results to review',
              value: reviewCount.toString(),
              icon: AppIcons.scienceOutlined,
              color: const Color(0xFF6A4BBC),
              route: '/care',
            ),
          ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final featureCard = _OverviewFeatureCard(feature: feature);
        final metricGrid = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: constraints.maxWidth >= 980
                    ? (constraints.maxWidth * .45 - AppSpacing.sm) / 2
                    : constraints.maxWidth >= 620
                    ? (constraints.maxWidth - AppSpacing.sm * 2) / 3
                    : constraints.maxWidth,
                child: _OverviewMetricCard(metric: metric),
              ),
          ],
        );
        return AppCard(
          padding: EdgeInsets.zero,
          child: constraints.maxWidth < 980
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    featureCard,
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: metricGrid,
                    ),
                  ],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 11, child: featureCard),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 9,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: metricGrid,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  CareConsultation? _nextConsultation(List<CareConsultation> consultations) {
    final candidates =
        consultations
            .where(
              (consultation) => !{
                'completed',
                'cancelled',
                'rejected',
              }.contains(consultation.status),
            )
            .toList()
          ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
    return candidates.isEmpty ? null : candidates.first;
  }

  String _consultationSummary(CareConsultation consultation) {
    final appointment = DateFormat.yMMMd().add_jm().format(
      consultation.appointmentDate.toLocal(),
    );
    final provider = consultation.doctorName ?? 'Your assigned care team';
    final hospital = consultation.hospitalName;
    return hospital == null
        ? '$provider · $appointment'
        : '$provider at $hospital · $appointment';
  }
}

class _OverviewFeatureCard extends StatelessWidget {
  const _OverviewFeatureCard({required this.feature});

  final _OverviewFeature feature;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.seaGlass,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(icon: feature.icon, color: AppColors.blue, size: 48),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.eyebrow,
                  style: const TextStyle(
                    color: AppColors.blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  feature.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(feature.description),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: () => context.go(feature.route),
                  icon: const Icon(AppIcons.arrowForwardRounded),
                  label: Text(feature.actionLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({required this.metric});

  final _OverviewMetric metric;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.go(metric.route),
    borderRadius: BorderRadius.circular(AppRadius.large),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          AppIconTile(icon: metric.icon, color: metric.color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.value,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: AppColors.navy),
                ),
                Text(
                  metric.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CareOverviewLoading extends StatelessWidget {
  const _CareOverviewLoading();

  @override
  Widget build(BuildContext context) => const AppCard(
    tone: AppCardTone.mint,
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.md),
          Text('Preparing your care summary…'),
        ],
      ),
    ),
  );
}

class _OverviewFeature {
  const _OverviewFeature({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.actionLabel,
    required this.route,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final String actionLabel;
  final String route;
}

class _OverviewMetric {
  const _OverviewMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String route;
}

class _SignInPrompt extends ConsumerWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppStatePanel(
    kind: AppStateKind.restricted,
    accentColor: AppColors.forest,
    icon: AppIcons.lockPersonOutlined,
    title: 'Sign in to My care',
    message:
        'View appointments, medical records, laboratory results, and prescriptions in one secure place.',
    action: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: () async {
            final router = GoRouter.of(context);
            await ref.read(authRepositoryProvider).signOut();
            router.go('/login');
          },
          child: const Text('Sign in now'),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: () async {
            final router = GoRouter.of(context);
            await ref.read(authRepositoryProvider).signOut();
            router.go('/register');
          },
          child: const Text('Create an account'),
        ),
      ],
    ),
  );
}

List<_DashboardItem> _cardsForRole(String role) {
  switch (role) {
    case 'patient':
      return const [
        _DashboardItem(
          'Appointments',
          'Upcoming and previous consultations',
          AppIcons.calendarMonthRounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Medical records',
          'Doctor-confirmed care history',
          AppIcons.folderSharedRounded,
          AppColors.teal,
        ),
        _DashboardItem(
          'Laboratory results',
          'Authorized files and findings',
          AppIcons.scienceRounded,
          Color(0xFF6A4BBC),
        ),
        _DashboardItem(
          'Prescriptions',
          'Medication and instructions',
          AppIcons.medicationRounded,
          Color(0xFFD05A29),
        ),
        _DashboardItem(
          'Messages',
          'Chat with assigned doctors',
          AppIcons.chatBubbleRounded,
          Color(0xFF2F7B72),
        ),
      ];
    case 'doctor':
      return const [
        _DashboardItem(
          'Assigned patients',
          'Care team and patient history',
          AppIcons.groupsRounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Consultations',
          'Review, schedule, and complete visits',
          AppIcons.videoCallRounded,
          AppColors.teal,
        ),
        _DashboardItem(
          'Medical result review',
          'OCR and AI findings awaiting confirmation',
          AppIcons.documentScannerRounded,
          Color(0xFF6A4BBC),
        ),
        _DashboardItem(
          'Messages',
          'Patient conversations',
          AppIcons.forumRounded,
          Color(0xFFD05A29),
        ),
      ];
    case 'hospital_admin':
      return const [
        _DashboardItem(
          'Hospital profile',
          'Services and public information',
          AppIcons.localHospitalRounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Doctors',
          'Accounts, departments, and schedules',
          AppIcons.badgeRounded,
          AppColors.teal,
        ),
        _DashboardItem(
          'Availability',
          'Rooms, beds, ER, ICU, and facilities',
          AppIcons.bedRounded,
          Color(0xFF6A4BBC),
        ),
        _DashboardItem(
          'Reports',
          'Hospital operations and activity',
          AppIcons.analyticsRounded,
          Color(0xFFD05A29),
        ),
      ];
    case 'super_admin':
      return const [
        _DashboardItem(
          'Hospitals',
          'Approval and platform directory',
          AppIcons.domainRounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Administrators',
          'Hospital administrator access',
          AppIcons.adminPanelSettingsRounded,
          AppColors.teal,
        ),
        _DashboardItem(
          'Platform analytics',
          'Usage and performance',
          AppIcons.queryStatsRounded,
          Color(0xFF6A4BBC),
        ),
        _DashboardItem(
          'Security & audit',
          'Platform activity logs',
          AppIcons.securityRounded,
          Color(0xFFD05A29),
        ),
      ];
    default:
      return const [
        _DashboardItem(
          'Consultation request',
          'Track your first-time request',
          AppIcons.videoCallRounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Hospital directory',
          'Find nearby verified care',
          AppIcons.localHospitalRounded,
          AppColors.teal,
        ),
      ];
  }
}

class _DashboardItem {
  const _DashboardItem(this.title, this.description, this.icon, this.color);
  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

String _pretty(String value) => value
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');

String _routeForDashboardTitle(String title) => switch (title) {
  'Hospital directory' => '/hospitals',
  'Consultation request' => '/consult',
  'Hospital profile' ||
  'Doctors' ||
  'Availability' ||
  'Hospitals' ||
  'Administrators' => '/admin',
  'Reports' ||
  'Platform analytics' ||
  'Security & audit' => '/admin/operations',
  _ => '/care',
};

Future<void> _editPatientProfile(
  BuildContext context,
  WidgetRef ref,
  UserProfile profile,
) async {
  try {
    final client = ref.read(supabaseClientProvider);
    final current = await client
        .from('users')
        .select('first_name, middle_name, last_name, mobile_number, address')
        .eq('id', profile.id)
        .single();
    if (!context.mounted) return;
    final first = TextEditingController(
      text: current['first_name']?.toString() ?? '',
    );
    final middle = TextEditingController(
      text: current['middle_name']?.toString() ?? '',
    );
    final last = TextEditingController(
      text: current['last_name']?.toString() ?? '',
    );
    final mobile = TextEditingController(
      text: current['mobile_number']?.toString() ?? '',
    );
    final address = TextEditingController(
      text: current['address']?.toString() ?? '',
    );
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update personal profile'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: first,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'First name *'),
                ),
                TextField(
                  controller: middle,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Middle name'),
                ),
                TextField(
                  controller: last,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Last name *'),
                ),
                TextField(
                  controller: mobile,
                  keyboardType: TextInputType.phone,
                  maxLength: 30,
                  decoration: const InputDecoration(labelText: 'Mobile number'),
                ),
                TextField(
                  controller: address,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Role, hospital assignment, identity verification, and account status cannot be changed here.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (first.text.trim().isEmpty || last.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('First and last name are required.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'first_name': first.text.trim(),
                'middle_name': middle.text.trim(),
                'last_name': last.text.trim(),
                'mobile_number': mobile.text.trim(),
                'address': address.text.trim(),
              });
            },
            child: const Text('Save profile'),
          ),
        ],
      ),
    );
    first.dispose();
    middle.dispose();
    last.dispose();
    mobile.dispose();
    address.dispose();
    if (values == null) return;
    await client.from('users').update(values).eq('id', profile.id);
    ref.invalidate(currentProfileProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
