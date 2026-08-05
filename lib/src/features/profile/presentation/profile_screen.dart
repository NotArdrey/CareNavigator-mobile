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

typedef JsonMap = Map<String, dynamic>;

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

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
              eyebrow: 'PROFILE',
              title: 'Your account',
              subtitle: 'Sign in to manage your CareNavigator account',
              icon: AppIcons.profile,
              showProfileAction: false,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: AppPageBody.horizontalPadding(
                    MediaQuery.sizeOf(context).width,
                  ),
                  vertical: AppSpacing.xxl,
                ),
                child: AppStatePanel(
                  kind: AppStateKind.restricted,
                  accentColor: AppColors.forest,
                  icon: AppIcons.profile,
                  title: 'Sign in to your profile',
                  message:
                      'Manage your account, care preferences, and private records in one secure place.',
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Sign in'),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        onPressed: () => context.go('/register'),
                        child: const Text('Create an account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return AsyncValuePanel<UserProfile?>(
      value: ref.watch(currentProfileProvider),
      onRetry: () => ref.invalidate(currentProfileProvider),
      data: (profile) => profile == null
          ? const AppStatePanel(
              kind: AppStateKind.error,
              icon: AppIcons.personOffOutlined,
              title: 'Profile unavailable',
              message: 'No CareNavigator profile was found for this account.',
            )
          : _ProfileBody(profile: profile),
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  bool _loading = true;
  Object? _error;
  JsonMap _account = const {};
  JsonMap? _doctor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final client = ref.read(supabaseClientProvider);
      final results = await Future.wait<dynamic>([
        client
            .from('users')
            .select(
              'first_name, last_name, email, mobile_number, birth_date, sex, '
              'address, account_status, hospitals(hospital_name)',
            )
            .eq('id', widget.profile.id)
            .single(),
        if (widget.profile.role == 'doctor')
          client
              .from('doctors')
              .select(
                'display_name, specialization, license_number, '
                'availability_status, consultation_fee, biography, '
                'hospitals(hospital_name), hospital_departments(department_name)',
              )
              .eq('user_id', widget.profile.id)
              .maybeSingle()
        else
          Future<JsonMap?>.value(null),
      ]);
      if (!mounted) return;
      setState(() {
        _account = JsonMap.from(results[0] as Map);
        final doctor = results[1];
        _doctor = doctor is Map ? JsonMap.from(doctor) : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    final router = GoRouter.of(context);
    await ref.read(authRepositoryProvider).signOut();
    router.go('/login');
  }

  Future<void> _editProfile() async {
    final firstName = TextEditingController(
      text: _account['first_name']?.toString() ?? '',
    );
    final lastName = TextEditingController(
      text: _account['last_name']?.toString() ?? '',
    );
    final mobile = TextEditingController(
      text: _account['mobile_number']?.toString() ?? '',
    );
    final address = TextEditingController(
      text: _account['address']?.toString() ?? '',
    );
    final values = await showDialog<JsonMap>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit personal information'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: lastName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: mobile,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile number'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: address,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: AppSpacing.sm),
                const AppNotice(
                  icon: AppIcons.infoOutlineRounded,
                  message:
                      'Your role, hospital assignment, verification, and account status are managed by authorized administrators.',
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
              if (firstName.text.trim().isEmpty ||
                  lastName.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('First and last name are required.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'first_name': firstName.text.trim(),
                'last_name': lastName.text.trim(),
                'mobile_number': mobile.text.trim(),
                'address': address.text.trim(),
              });
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
    firstName.dispose();
    lastName.dispose();
    mobile.dispose();
    address.dispose();
    if (values == null) return;
    try {
      await ref
          .read(supabaseClientProvider)
          .from('users')
          .update(values)
          .eq('id', widget.profile.id);
      ref.invalidate(currentProfileProvider);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Personal information updated.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _account['email']?.toString().trim() ?? '';
    if (email.isEmpty) return;
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset instructions were sent by email.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        AppPageHeader(
          eyebrow: 'IDENTITY, PRIVACY & ACCESS',
          title: 'Account settings',
          subtitle: 'Keep your verified identity and care permissions current',
          icon: AppIcons.accountCircleRounded,
          actions: [
            IconButton(
              tooltip: 'Edit personal information',
              onPressed: _loading ? null : _editProfile,
              icon: const Icon(AppIcons.editOutlined),
            ),
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => context.go('/notifications'),
              icon: const Icon(AppIcons.notificationsOutlined),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(AppIcons.refreshRounded),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: _signOut,
              icon: const Icon(AppIcons.logoutRounded),
            ),
          ],
        ),
        Expanded(child: _redesignedContent(context)),
      ],
    ),
  );

  Widget _redesignedContent(BuildContext context) {
    if (_loading) return const AppLoadingState(label: 'Loading profile');
    if (_error != null) {
      return AppStatePanel(
        kind: AppStateKind.error,
        icon: AppIcons.cloudOffRounded,
        title: 'Unable to load your profile',
        message: _error.toString(),
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(AppIcons.refreshRounded),
          label: const Text('Try again'),
        ),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = AppPageBody.horizontalPadding(width);
    final identity = _ProfileHero(
      name: _doctor?['display_name']?.toString() ?? widget.profile.displayName,
      role: widget.profile.roleLabel,
      initial: widget.profile.displayName.characters.first.toUpperCase(),
      hospital: _doctor == null
          ? _relation(_account['hospitals'], 'hospital_name')
          : _relation(_doctor!['hospitals'], 'hospital_name'),
      onEdit: _editProfile,
    );
    final account = _ProfileSection(
      title: 'Verified account details',
      icon: AppIcons.badgeOutlined,
      children: [
        _ProfileDetail('Email', _account['email']),
        _ProfileDetail('Mobile number', _account['mobile_number']),
        _ProfileDetail('Address', _account['address']),
        _ProfileDetail('Account status', _account['account_status']),
      ],
    );
    final professional = _doctor == null
        ? null
        : _ProfileSection(
            title: 'Clinical credentials',
            icon: AppIcons.medicalServicesOutlined,
            children: [
              _ProfileDetail('Specialization', _doctor!['specialization']),
              _ProfileDetail(
                'Department',
                _relation(_doctor!['hospital_departments'], 'department_name'),
              ),
              _ProfileDetail(
                'Hospital',
                _relation(_doctor!['hospitals'], 'hospital_name'),
              ),
              _ProfileDetail('License number', _doctor!['license_number']),
              _ProfileDetail('Availability', _doctor!['availability_status']),
            ],
          );
    final controls = AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _ProfileControlRow(
            icon: AppIcons.securityOutlined,
            title: 'Security & access',
            description:
                'Send a verified recovery link to update your password.',
            actionLabel: 'Password reset',
            onPressed: _sendPasswordReset,
          ),
          const Divider(height: 1, indent: 76),
          _ProfileControlRow(
            icon: AppIcons.notificationsActiveOutlined,
            title: 'Notification preferences',
            description: 'Choose which care events and messages reach you.',
            actionLabel: 'Manage',
            onPressed: () => context.go('/notifications'),
          ),
          const Divider(height: 1, indent: 76),
          _ProfileControlRow(
            icon: AppIcons.privacyTipOutlined,
            title: 'Privacy & consent',
            description: widget.profile.role == 'patient'
                ? 'Review permissions shared with your assigned care team.'
                : 'Review your role-scoped clinical workspace access.',
            actionLabel: widget.profile.role == 'patient'
                ? 'Review'
                : 'Open care',
            onPressed: () => context.go('/care'),
          ),
          const Divider(height: 1, indent: 76),
          _ProfileControlRow(
            icon: AppIcons.logoutRounded,
            title: 'End this session',
            description: 'Sign out before leaving a shared or public device.',
            actionLabel: 'Sign out',
            destructive: true,
            onPressed: _signOut,
          ),
        ],
      ),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        AppSpacing.xl,
        horizontal,
        width < 700 ? 108 : AppSpacing.xxxl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppSectionHeader(
                      eyebrow: 'VERIFIED RECORD',
                      title: 'Identity details',
                      subtitle:
                          'Information used across your secure care experience.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    account,
                    if (professional != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      professional,
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    const AppSectionHeader(
                      eyebrow: 'ACCOUNT CONTROLS',
                      title: 'Privacy and access',
                      subtitle: 'Focused controls grouped by purpose.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    controls,
                  ],
                );
                if (constraints.maxWidth < 820) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      identity,
                      const SizedBox(height: AppSpacing.xl),
                      details,
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 334, child: identity),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(child: details),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // Kept temporarily during the route-wide visual migration for diff review.
  // ignore: unused_element
  Widget _content(BuildContext context) {
    if (_loading) return const AppLoadingState(label: 'Loading profile');
    if (_error != null) {
      return AppStatePanel(
        kind: AppStateKind.error,
        icon: AppIcons.cloudOffRounded,
        title: 'Unable to load your profile',
        message: _error.toString(),
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(AppIcons.refreshRounded),
          label: const Text('Try again'),
        ),
      );
    }
    final horizontal = AppPageBody.horizontalPadding(
      MediaQuery.sizeOf(context).width,
    );
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontal,
        vertical: AppSpacing.xl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileHero(
                  name:
                      _doctor?['display_name']?.toString() ??
                      widget.profile.displayName,
                  role: widget.profile.roleLabel,
                  initial: widget.profile.displayName.characters.first
                      .toUpperCase(),
                  hospital: _doctor == null
                      ? _relation(_account['hospitals'], 'hospital_name')
                      : _relation(_doctor!['hospitals'], 'hospital_name'),
                  onEdit: _editProfile,
                ),
                const SizedBox(height: AppSpacing.md),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = constraints.maxWidth >= 780
                        ? (constraints.maxWidth - AppSpacing.md) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _ProfileSection(
                            title: 'Account information',
                            icon: AppIcons.badgeOutlined,
                            children: [
                              _ProfileDetail('Email', _account['email']),
                              _ProfileDetail(
                                'Mobile number',
                                _account['mobile_number'],
                              ),
                              _ProfileDetail('Address', _account['address']),
                              _ProfileDetail(
                                'Account status',
                                _account['account_status'],
                              ),
                            ],
                          ),
                        ),
                        if (_doctor != null)
                          SizedBox(
                            width: cardWidth,
                            child: _ProfileSection(
                              title: 'Professional profile',
                              icon: AppIcons.medicalServicesOutlined,
                              children: [
                                _ProfileDetail(
                                  'Specialization',
                                  _doctor!['specialization'],
                                ),
                                _ProfileDetail(
                                  'Department',
                                  _relation(
                                    _doctor!['hospital_departments'],
                                    'department_name',
                                  ),
                                ),
                                _ProfileDetail(
                                  'Hospital',
                                  _relation(
                                    _doctor!['hospitals'],
                                    'hospital_name',
                                  ),
                                ),
                                _ProfileDetail(
                                  'License number',
                                  _doctor!['license_number'],
                                ),
                                _ProfileDetail(
                                  'Availability',
                                  _doctor!['availability_status'],
                                ),
                              ],
                            ),
                          ),
                        SizedBox(
                          width: cardWidth,
                          child: _ProfileActionSection(
                            icon: AppIcons.securityOutlined,
                            title: 'Security & access',
                            description:
                                'Use email-based recovery to update your password. Signed-in sessions remain protected by Supabase authentication.',
                            actionLabel: 'Send password reset',
                            onPressed: _sendPasswordReset,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _ProfileActionSection(
                            icon: AppIcons.notificationsActiveOutlined,
                            title: 'Notification preferences',
                            description:
                                'Choose which consultation, record, prescription, message, and hospital updates reach you.',
                            actionLabel: 'Manage notifications',
                            onPressed: () => context.go('/notifications'),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _ProfileActionSection(
                            icon: AppIcons.privacyTipOutlined,
                            title: 'Privacy & consent',
                            description: widget.profile.role == 'patient'
                                ? 'Review the permissions that allow your assigned care team to coordinate treatment and access required records.'
                                : 'Clinical access is limited by role, assignment, and hospital scope. Sensitive actions remain auditable.',
                            actionLabel: widget.profile.role == 'patient'
                                ? 'Review care consents'
                                : 'Open care workspace',
                            onPressed: () => context.go('/care'),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _ProfileActionSection(
                            icon: AppIcons.logoutRounded,
                            title: 'Session controls',
                            description:
                                'Sign out when you are using a shared or public device. You can return with the same verified email.',
                            actionLabel: 'Sign out securely',
                            destructive: true,
                            onPressed: _signOut,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.role,
    required this.initial,
    required this.hospital,
    required this.onEdit,
  });

  final String name;
  final String role;
  final String initial;
  final String hospital;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    decoration: BoxDecoration(
      color: AppColors.evergreenDark,
      borderRadius: BorderRadius.circular(AppRadius.extraLarge),
      boxShadow: AppShadows.medium,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth > 500;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 84 : 72,
              height: compact ? 84 : 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.forest,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppStatusBadge(
              label: role,
              color: AppColors.mint,
              icon: AppIcons.verifiedUserOutlined,
              inverse: true,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              name,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontSize: compact ? 34 : 30,
                height: 1.05,
              ),
            ),
            if (hospital.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                hospital,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.mist),
              ),
            ],
            const SizedBox(height: AppSpacing.massive),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x55FFFFFF)),
                ),
                icon: const Icon(AppIcons.editOutlined),
                label: const Text('Edit verified information'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Icon(
                  AppIcons.lockOutlineRounded,
                  color: AppColors.mint,
                  size: 17,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Protected identity record',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.mist),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _ProfileControlRow extends StatelessWidget {
  const _ProfileControlRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          AppIconTile(
            icon: icon,
            color: destructive ? AppColors.danger : AppColors.forest,
            size: 40,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            actionLabel,
            style: TextStyle(
              color: destructive ? AppColors.danger : AppColors.forest,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            AppIcons.arrowOutwardRounded,
            color: destructive ? AppColors.danger : AppColors.forest,
          ),
        ],
      ),
    ),
  );
}

class _ProfileActionSection extends StatelessWidget {
  const _ProfileActionSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: icon,
            color: destructive ? AppColors.danger : AppColors.blue,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(description),
          const SizedBox(height: AppSpacing.md),
          if (destructive)
            OutlinedButton.icon(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: Color(0xFFE5A5A0)),
              ),
              icon: const Icon(AppIcons.logoutRounded),
              label: Text(actionLabel),
            )
          else
            TextButton.icon(
              onPressed: onPressed,
              icon: const Icon(AppIcons.arrowForwardRounded),
              label: Text(actionLabel),
            ),
        ],
      ),
    ),
  );
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.blue),
              const SizedBox(width: 9),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    ),
  );
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail(this.label, this.value);

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              text.isEmpty ? 'Not provided' : _label(text),
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _relation(dynamic value, String key) {
  final relation = value is List ? (value.isEmpty ? null : value.first) : value;
  if (relation is Map<String, dynamic>) {
    return relation[key]?.toString() ?? '';
  }
  if (relation is Map) return relation[key]?.toString() ?? '';
  return '';
}

String _label(String value) => value
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
