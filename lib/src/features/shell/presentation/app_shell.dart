import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/routing/role_routes.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/admin_desktop_only_screen.dart';
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
    final selectedIndex = _selectedIndex(destinations);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 920;
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
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                    child: Container(
                      width: 240,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE0E8F2)),
                      ),
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 22, 20, 28),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: BrandMark(),
                            ),
                          ),
                          for (
                            var index = 0;
                            index < destinations.length;
                            index++
                          )
                            _RailItem(
                              destination: destinations[index],
                              selected: index == selectedIndex,
                              onTap: () =>
                                  _navigate(context, destinations, index),
                            ),
                          const Spacer(),
                          Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: AppColors.mint,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.emergency_rounded,
                                  size: 20,
                                  color: AppColors.danger,
                                ),
                                SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    'Emergency? Call 911 or go to the nearest ER.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) =>
                _navigate(context, destinations, index),
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  icon: Icon(_iconFor(destination.destination)),
                  selectedIcon: Icon(
                    _iconFor(destination.destination, selected: true),
                  ),
                  label: destination.label,
                ),
            ],
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
                  const Icon(Icons.engineering_rounded, size: 20),
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.engineering_rounded, size: 52),
                const SizedBox(height: 14),
                Text(
                  state['title']?.toString() ?? 'Scheduled maintenance',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  state['message']?.toString() ??
                      'Care workflows are temporarily unavailable.',
                  textAlign: TextAlign.center,
                ),
                if (end != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Expected end: ${DateFormat.yMMMd().add_jm().format(end.toLocal())}',
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => context.go('/hospitals'),
                  icon: const Icon(Icons.local_hospital_outlined),
                  label: const Text('Open hospital directory'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'For an emergency, call 911 or go to the nearest emergency room.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
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

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final RoleNavigationItem destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? const Color(0xFFE8F1FD) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(
                  _iconFor(destination.destination, selected: selected),
                  color: selected ? AppColors.blue : const Color(0xFF60758C),
                ),
                const SizedBox(width: 13),
                Text(
                  destination.label,
                  style: TextStyle(
                    color: selected ? AppColors.blue : AppColors.ink,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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

IconData _iconFor(
  RoleDestination destination, {
  bool selected = false,
}) => switch (destination) {
  RoleDestination.home => selected ? Icons.home_rounded : Icons.home_outlined,
  RoleDestination.hospitals =>
    selected ? Icons.local_hospital_rounded : Icons.local_hospital_outlined,
  RoleDestination.consult =>
    selected ? Icons.video_call_rounded : Icons.video_call_outlined,
  RoleDestination.dashboard =>
    selected ? Icons.dashboard_rounded : Icons.dashboard_outlined,
  RoleDestination.care =>
    selected ? Icons.medical_services_rounded : Icons.medical_services_outlined,
  RoleDestination.admin =>
    selected
        ? Icons.admin_panel_settings_rounded
        : Icons.admin_panel_settings_outlined,
  RoleDestination.operations =>
    selected ? Icons.settings_rounded : Icons.settings_outlined,
  RoleDestination.profile =>
    selected ? Icons.account_circle_rounded : Icons.account_circle_outlined,
  RoleDestination.notifications =>
    selected ? Icons.notifications_rounded : Icons.notifications_outlined,
};
