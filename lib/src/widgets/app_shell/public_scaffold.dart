import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth/user_role.dart';
import '../../providers/core_providers.dart';
import '../../theme/app_tokens.dart';
import '../branding/brand_mark.dart';
import '../care_assistant/care_navigator_assistant.dart';
import '../navigation/app_navigation.dart';
import 'workspace_shell.dart';

class PublicScaffold extends ConsumerWidget {
  const PublicScaffold({
    super.key,
    required this.body,
    this.currentLocation,
    this.minimalNavigation = false,
    this.hideHeader = false,
  });

  final Widget body;
  final String? currentLocation;
  final bool minimalNavigation;
  final bool hideHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hideHeader) {
      return Scaffold(body: body);
    }

    final identity = ref.watch(appIdentityProvider);
    final isPatientCareDirectory =
        identity.isAuthenticated &&
        identity.role == UserRole.patient &&
        (currentLocation?.startsWith('/hospitals') ?? false);
    if (isPatientCareDirectory) {
      final unreadMessageCount =
          ref.watch(unreadMessageCountProvider).asData?.value ?? 0;
      final unreadNotificationCount = ref.watch(
        unreadNotificationCountProvider,
      );
      return WorkspaceShell(
        identity: identity,
        location: currentLocation!,
        title: 'Find care',
        body: body,
        onNotifications: () => context.go('/patient/notifications'),
        unreadMessageCount: unreadMessageCount,
        unreadNotificationCount: unreadNotificationCount,
        onSignOut: () async {
          await ref.read(appIdentityProvider.notifier).signOut();
          if (context.mounted) context.go('/');
        },
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 1080;
    if (!wide) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          leading: minimalNavigation
              ? null
              : Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Open navigation menu',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu),
                  ),
                ),
          title: const BrandLockup(compact: true),
          actions: [
            if (minimalNavigation)
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to home'),
              )
            else
              IconButton(
                tooltip: 'Sign in',
                onPressed: () => context.go('/sign-in'),
                icon: const Icon(Icons.login),
              ),
            const SizedBox(width: 6),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(),
          ),
        ),
        drawer: minimalNavigation
            ? null
            : _PublicNavigationDrawer(currentLocation: currentLocation),
        body: body,
        floatingActionButton: minimalNavigation
            ? null
            : const CareNavigatorAssistant(),
        bottomNavigationBar: minimalNavigation
            ? null
            : SafeArea(
                top: false,
                child: NavigationBarTheme(
                  data: appMobileNavigationBarTheme(),
                  child: NavigationBar(
                    selectedIndex: _selectedMobileIndex(currentLocation),
                    onDestinationSelected: (index) {
                      context.go(_publicMobileDestinations[index].location!);
                    },
                    destinations: [
                      for (final destination in _publicMobileDestinations)
                        NavigationDestination(
                          icon: Icon(destination.icon, size: 20),
                          label: destination.label,
                          // Avoid stale Tooltip OverlayPortals during Flutter
                          // web route transitions. Labels remain visible.
                          tooltip: '',
                        ),
                    ],
                  ),
                ),
              ),
      );
    }

    return Scaffold(
      floatingActionButton: minimalNavigation
          ? null
          : const CareNavigatorAssistant(),
      body: Column(
        children: [
          Material(
            color: AppColors.surface,
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => context.go('/'),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: BrandLockup(),
                    ),
                  ),
                  const Spacer(),
                  if (minimalNavigation)
                    TextButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Back to home'),
                    )
                  else ...[
                    _HeaderLink(
                      label: 'Find care',
                      selected:
                          currentLocation?.startsWith('/hospitals') ?? false,
                      onTap: () => context.go('/hospitals'),
                    ),
                    _HeaderLink(
                      label: 'Clinicians',
                      selected:
                          currentLocation?.startsWith('/doctors') ?? false,
                      onTap: () => context.go('/doctors'),
                    ),
                    _HeaderLink(
                      label: 'Reserve consultation',
                      selected:
                          currentLocation?.startsWith('/consultation') ?? false,
                      onTap: () => context.go('/consultation/request'),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton(
                      onPressed: () => context.go('/sign-in'),
                      child: const Text('Sign in'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

const _publicMobileDestinations = [
  _PublicMobileDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    location: '/',
  ),
  _PublicMobileDestination(
    label: 'Find care',
    icon: Icons.local_hospital_outlined,
    location: '/hospitals',
  ),
  _PublicMobileDestination(
    label: 'Consult',
    icon: Icons.video_call_outlined,
    location: '/consultation/request',
  ),
];

class _PublicMobileDestination {
  const _PublicMobileDestination({
    required this.label,
    required this.icon,
    this.location,
  });

  final String label;
  final IconData icon;
  final String? location;
}

int _selectedMobileIndex(String? location) {
  final path = location ?? '/';
  if (path.startsWith('/hospitals')) return 1;
  if (path.startsWith('/consultation')) return 2;
  return 0;
}

class _PublicNavigationDrawer extends StatelessWidget {
  const _PublicNavigationDrawer({required this.currentLocation});

  final String? currentLocation;

  @override
  Widget build(BuildContext context) => Drawer(
    backgroundColor: const Color(0xFF063B4C),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 24),
            child: Row(
              children: [
                BrandMark(size: 30),
                SizedBox(width: 12),
                Text(
                  'CareNavigator',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _PublicDrawerDestination(
            label: 'Clinicians',
            icon: Icons.medical_services_outlined,
            location: '/doctors',
            selected: currentLocation?.startsWith('/doctors') ?? false,
          ),
          const Divider(color: Color(0x4DFFFFFF), height: 32),
          const _PublicDrawerDestination(
            label: 'Sign in',
            icon: Icons.login,
            location: '/sign-in',
            selected: false,
          ),
        ],
      ),
    ),
  );
}

class _PublicDrawerDestination extends StatelessWidget {
  const _PublicDrawerDestination({
    required this.label,
    required this.icon,
    required this.location,
    required this.selected,
  });

  final String label;
  final IconData icon;
  final String location;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: ListTile(
      selected: selected,
      selectedTileColor: const Color(0x2EFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.of(context).pop();
        context.go(location);
      },
    ),
  );
}

class _HeaderLink extends StatelessWidget {
  const _HeaderLink({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: selected
              ? AppColors.primary
              : AppColors.textSecondary,
        ),
        child: Text(label),
      ),
    );
  }
}
