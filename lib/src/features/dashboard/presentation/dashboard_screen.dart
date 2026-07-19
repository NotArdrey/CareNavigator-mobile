import 'package:care_navigator_ph/src/models/user_profile.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/async_value_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session =
        ref.watch(authStateProvider).value?.session ??
        ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) return const SizedBox.shrink();

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
    final horizontal = width < 600 ? 20.0 : 40.0;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 28, horizontal, 18),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor: AppColors.mint,
                  foregroundColor: AppColors.teal,
                  child: Text(
                    profile.displayName.characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, ${profile.displayName}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${profile.roleLabel} • ${_pretty(profile.accountStatus)} account',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => context.go('/notifications'),
                  icon: const Icon(Icons.notifications_outlined),
                ),
                if (profile.role == 'patient')
                  IconButton(
                    tooltip: 'Edit profile',
                    onPressed: () => _editPatientProfile(context, ref, profile),
                    icon: const Icon(Icons.manage_accounts_outlined),
                  ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: () async {
                    final router = GoRouter.of(context);
                    await ref.read(authRepositoryProvider).signOut();
                    router.go('/login');
                  },
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            ),
          ),
        ),
        if (isAdministrator)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 18),
            sliver: SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => context.go('/admin'),
                  icon: const Icon(Icons.admin_panel_settings_rounded),
                  label: const Text('Open administration console'),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 36),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: width >= 1180
                  ? 3
                  : width >= 680
                  ? 2
                  : 1,
              mainAxisExtent: 168,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            itemCount: cards.length,
            itemBuilder: (context, index) => _DashboardCard(item: cards[index]),
          ),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.item});

  final _DashboardItem item;

  @override
  Widget build(BuildContext context) {
    final route = _routeForDashboardTitle(item.title);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.color),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
              const Spacer(),
              Text(item.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              Text(
                item.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignInPrompt extends ConsumerWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: AppColors.mint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_person_outlined,
                size: 40,
                color: AppColors.teal,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sign in to My care',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            const Text(
              'View your appointments, medical records, laboratory results, and prescriptions in one secure place.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final router = GoRouter.of(context);
                  await ref.read(authRepositoryProvider).signOut();
                  router.go('/login');
                },
                child: const Text('Sign in now'),
              ),
            ),
            const SizedBox(height: 8),
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
      ),
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
          Icons.calendar_month_rounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Medical records',
          'Doctor-confirmed care history',
          Icons.folder_shared_rounded,
          AppColors.teal,
        ),
        _DashboardItem(
          'Laboratory results',
          'Authorized files and findings',
          Icons.science_rounded,
          Color(0xFF6A4BBC),
        ),
        _DashboardItem(
          'Prescriptions',
          'Medication and instructions',
          Icons.medication_rounded,
          Color(0xFFD05A29),
        ),
        _DashboardItem(
          'Messages',
          'Chat with assigned doctors',
          Icons.chat_bubble_rounded,
          Color(0xFF2F7B72),
        ),
      ];
    case 'doctor':
      return const [
        _DashboardItem(
          'Assigned patients',
          'Care team and patient history',
          Icons.groups_rounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Consultations',
          'Review, schedule, and complete visits',
          Icons.video_call_rounded,
          AppColors.teal,
        ),
        _DashboardItem(
          'Medical result review',
          'OCR and AI findings awaiting confirmation',
          Icons.document_scanner_rounded,
          Color(0xFF6A4BBC),
        ),
        _DashboardItem(
          'Messages',
          'Patient conversations',
          Icons.forum_rounded,
          Color(0xFFD05A29),
        ),
      ];
    case 'hospital_admin':
      return const [
        _DashboardItem(
          'Hospital profile',
          'Services and public information',
          Icons.local_hospital_rounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Doctors',
          'Accounts, departments, and schedules',
          Icons.badge_rounded,
          AppColors.teal,
        ),
        _DashboardItem(
          'Availability',
          'Rooms, beds, ER, ICU, and facilities',
          Icons.bed_rounded,
          Color(0xFF6A4BBC),
        ),
        _DashboardItem(
          'Reports',
          'Hospital operations and activity',
          Icons.analytics_rounded,
          Color(0xFFD05A29),
        ),
      ];
    case 'super_admin':
      return const [
        _DashboardItem(
          'Hospitals',
          'Approval and platform directory',
          Icons.domain_rounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Administrators',
          'Hospital administrator access',
          Icons.admin_panel_settings_rounded,
          AppColors.teal,
        ),
        _DashboardItem(
          'Platform analytics',
          'Usage and performance',
          Icons.query_stats_rounded,
          Color(0xFF6A4BBC),
        ),
        _DashboardItem(
          'Security & audit',
          'Platform activity logs',
          Icons.security_rounded,
          Color(0xFFD05A29),
        ),
      ];
    default:
      return const [
        _DashboardItem(
          'Consultation request',
          'Track your first-time request',
          Icons.video_call_rounded,
          AppColors.blue,
        ),
        _DashboardItem(
          'Hospital directory',
          'Find nearby verified care',
          Icons.local_hospital_rounded,
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
