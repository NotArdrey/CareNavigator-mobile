import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/routing/role_routes.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/admin_desktop_only_screen.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
import 'package:care_navigator_ph/src/widgets/brand_mark.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  int _selectedIndex(List<RoleNavigationItem> destinations) {
    var selected = 0;
    var bestMatchLength = -1;
    for (var index = 0; index < destinations.length; index++) {
      final destination = destinations[index];
      final matchesPath =
          location == destination.path ||
          location.startsWith('${destination.path}/');
      final matchesCareChild =
          destination.destination == RoleDestination.care &&
          location.startsWith('/messages/');
      if ((matchesPath || matchesCareChild) &&
          destination.path.length > bestMatchLength) {
        selected = index;
        bestMatchLength = destination.path.length;
      }
    }
    return selected;
  }

  void _navigate(
    BuildContext context,
    List<RoleNavigationItem> destinations,
    int index,
  ) {
    context.go(destinations[index].path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (location.startsWith('/login') || location.startsWith('/register')) {
      return Scaffold(body: child);
    }

    final role = ref.watch(currentProfileProvider).value?.role;
    final destinations = navigationForRole(role);
    final mobileDestinations = _mobileDestinations(role);
    final selectedIndex = _selectedIndex(destinations);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppBreakpoints.medium;
        if (shouldBlockAdminAccess(
          role: role,
          isWeb: kIsWeb,
          logicalWidth: constraints.maxWidth,
        )) {
          return Scaffold(
            body: AdminDesktopOnlyScreen(
              signOut: shouldSignOutBlockedAdministrator(isWeb: kIsWeb),
            ),
          );
        }
        final adminRouteUnavailable =
            location.startsWith('/admin') &&
            !isDesktopAdminPortalAvailable(
              isWeb: kIsWeb,
              logicalWidth: constraints.maxWidth,
            );
        if (adminRouteUnavailable) {
          return Scaffold(body: child);
        }
        final maintenance = ref.watch(maintenanceStateProvider);
        final effectiveChild = maintenance.maybeWhen(
          data: (state) => _maintenanceChild(context, state),
          orElse: () => child,
        );
        if (isWide) {
          final railWidth = constraints.maxWidth >= AppBreakpoints.expanded
              ? 240.0
              : 216.0;
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: Container(
                    width: railWidth,
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
                    color: AppColors.evergreenDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(8, 0, 8, 0),
                          child: BrandMark(inverse: true),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          'YOUR CARE MAP',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.mist,
                                letterSpacing: 1.25,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (
                          var index = 0;
                          index < destinations.length;
                          index++
                        )
                          _RailItem(
                            destination: destinations[index],
                            selected: index == selectedIndex,
                            expanded: true,
                            onTap: () =>
                                _navigate(context, destinations, index),
                          ),
                        const Spacer(),
                        Tooltip(
                          message:
                              'Emergency? Call 911 or go to the nearest ER.',
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(
                                AppRadius.extraLarge,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .1),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  AppIcons.emergencyRounded,
                                  size: 21,
                                  color: AppColors.coral,
                                ),
                                SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    'Need urgent help?\nCall 911 or go to the nearest ER.',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      height: 1.35,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: effectiveChild),
              ],
            ),
          );
        }

        return Scaffold(
          body: effectiveChild,
          bottomNavigationBar: _MobileNavigationBar(
            destinations: mobileDestinations,
            selectedIndex: _selectedIndex(mobileDestinations),
            onDestinationSelected: (index) =>
                _navigate(context, mobileDestinations, index),
          ),
        );
      },
    );
  }

  Widget _maintenanceChild(BuildContext context, Map<String, dynamic> state) {
    if (state['active'] != true || state['administrator_bypass'] == true) {
      return child;
    }
    final safeRoute =
        location == '/' ||
        location == '/home' ||
        location == '/login' ||
        location.startsWith('/hospitals') ||
        location.startsWith('/admin');
    if (safeRoute) {
      return Column(
        children: [
          Material(
            color: const Color(0xFFFFF4D8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              child: Row(
                children: [
                  const Icon(AppIcons.engineeringRounded, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '${state['title']}: ${state['message']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      );
    }
    final end = DateTime.tryParse(state['ends_at']?.toString() ?? '');
    final expectedEnd = end == null
        ? ''
        : '\nExpected end: ${DateFormat.yMMMd().add_jm().format(end.toLocal())}';
    return Column(
      children: [
        AppPageHeader(
          title: state['title']?.toString() ?? 'Scheduled maintenance',
          subtitle: 'CareNavigator service notice',
          icon: AppIcons.engineeringRounded,
        ),
        Expanded(
          child: AppStatePanel(
            kind: AppStateKind.restricted,
            icon: AppIcons.engineeringRounded,
            title: state['title']?.toString() ?? 'Scheduled maintenance',
            message:
                '${state['message']?.toString() ?? 'Care workflows are temporarily unavailable.'}$expectedEnd\n\nFor an emergency, call 911 or go to the nearest emergency room.',
            action: FilledButton.icon(
              onPressed: () => context.go('/hospitals'),
              icon: const Icon(AppIcons.localHospitalOutlined),
              label: const Text('Open hospital directory'),
            ),
          ),
        ),
      ],
    );
  }
}

List<RoleNavigationItem> _mobileDestinations(String? role) => switch (role) {
  'doctor' => const [
    RoleNavigationItem(RoleDestination.dashboard, 'Overview'),
    RoleNavigationItem(RoleDestination.care, 'Clinical'),
    RoleNavigationItem(RoleDestination.notifications, 'Updates'),
  ],
  'patient' => const [
    RoleNavigationItem(RoleDestination.home, 'Home'),
    RoleNavigationItem(RoleDestination.hospitals, 'Hospitals'),
    RoleNavigationItem(RoleDestination.dashboard, 'My care'),
    RoleNavigationItem(RoleDestination.care, 'Records'),
  ],
  'guest' => const [
    RoleNavigationItem(RoleDestination.home, 'Home'),
    RoleNavigationItem(RoleDestination.hospitals, 'Hospitals'),
    RoleNavigationItem(RoleDestination.consult, 'Consult'),
    RoleNavigationItem(RoleDestination.dashboard, 'My care'),
  ],
  _ => const [
    RoleNavigationItem(RoleDestination.home, 'Home'),
    RoleNavigationItem(RoleDestination.hospitals, 'Hospitals'),
    RoleNavigationItem(RoleDestination.consult, 'Consult'),
    RoleNavigationItem(RoleDestination.dashboard, 'My care'),
  ],
};

class _MobileNavigationBar extends StatelessWidget {
  const _MobileNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<RoleNavigationItem> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      color: AppColors.paper,
      elevation: 8,
      shadowColor: AppColors.evergreenDark.withValues(alpha: .16),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 72,
          backgroundColor: AppColors.paper,
          surfaceTintColor: Colors.transparent,
          indicatorColor: AppColors.seaGlass,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 21,
              color: states.contains(WidgetState.selected)
                  ? AppColors.forest
                  : AppColors.inkMuted,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 10,
              color: states.contains(WidgetState.selected)
                  ? AppColors.forest
                  : AppColors.inkMuted,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex.clamp(0, destinations.length - 1),
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final destination in destinations)
              NavigationDestination(
                icon: Icon(_iconFor(destination.destination)),
                selectedIcon: Icon(_iconFor(destination.destination)),
                label: destination.label,
              ),
          ],
        ),
      ),
    ),
  );
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    this.expanded = false,
    required this.onTap,
  });

  final RoleNavigationItem destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? AppColors.forest : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.extraLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.extraLarge),
          child: Padding(
            padding: expanded
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 14)
                : const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: expanded
                ? Row(
                    children: [
                      Icon(
                        _iconFor(destination.destination),
                        size: 21,
                        color: selected ? Colors.white : AppColors.mist,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          destination.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.white : AppColors.mist,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconFor(destination.destination),
                        size: 23,
                        color: selected ? Colors.white : AppColors.mist,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : AppColors.mist,
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

IconData _iconFor(RoleDestination destination) => switch (destination) {
  RoleDestination.home => AppIcons.home,
  RoleDestination.hospitals => AppIcons.hospitals,
  RoleDestination.consult => AppIcons.videoConsultation,
  RoleDestination.dashboard => AppIcons.medicalRecords,
  RoleDestination.care => AppIcons.consultation,
  RoleDestination.admin => AppIcons.admin,
  RoleDestination.operations => AppIcons.settings,
  RoleDestination.profile => AppIcons.profile,
  RoleDestination.notifications => AppIcons.notifications,
};
