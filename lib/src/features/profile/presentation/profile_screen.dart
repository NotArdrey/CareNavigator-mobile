import 'package:care_navigator_ph/src/models/user_profile.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/async_value_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

typedef JsonMap = Map<String, dynamic>;

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateProvider);
    if (ref.read(supabaseClientProvider).auth.currentSession == null) {
      return Center(
        child: FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Sign in to view your profile'),
        ),
      );
    }
    return AsyncValuePanel<UserProfile?>(
      value: ref.watch(currentProfileProvider),
      onRetry: () => ref.invalidate(currentProfileProvider),
      data: (profile) => profile == null
          ? const Center(child: Text('No CareNavigator profile was found.'))
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

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        AppPageHeader(
          title: 'My profile',
          subtitle:
              '${widget.profile.displayName} · ${widget.profile.roleLabel}',
          icon: Icons.account_circle_rounded,
          actions: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => context.go('/notifications'),
              icon: const Icon(Icons.notifications_outlined),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        Expanded(child: _content(context)),
      ],
    ),
  );

  Widget _content(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load your profile: $_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: const Color(0xFFE8F1FD),
            foregroundColor: AppColors.blue,
            child: Text(
              widget.profile.displayName.characters.first.toUpperCase(),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _doctor?['display_name']?.toString() ?? widget.profile.displayName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          widget.profile.roleLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.blue),
        ),
        const SizedBox(height: 22),
        _ProfileSection(
          title: 'Account information',
          icon: Icons.badge_outlined,
          children: [
            _ProfileDetail('Email', _account['email']),
            _ProfileDetail('Mobile number', _account['mobile_number']),
            _ProfileDetail('Address', _account['address']),
            _ProfileDetail('Account status', _account['account_status']),
          ],
        ),
        if (_doctor != null) ...[
          const SizedBox(height: 14),
          _ProfileSection(
            title: 'Professional profile',
            icon: Icons.medical_services_outlined,
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
              _ProfileDetail(
                'Consultation fee',
                _doctor!['consultation_fee'] == null
                    ? null
                    : '₱${_doctor!['consultation_fee']}',
              ),
              _ProfileDetail('Biography', _doctor!['biography']),
            ],
          ),
        ],
      ],
    );
  }
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
  Widget build(BuildContext context) => Card(
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
  if (value is Map<String, dynamic>) return value[key]?.toString() ?? '';
  if (value is Map) return value[key]?.toString() ?? '';
  return '';
}

String _label(String value) => value
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
