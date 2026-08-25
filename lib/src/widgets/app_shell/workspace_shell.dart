import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth/user_role.dart';
import '../../routing/root_overlay.dart';
import '../../theme/app_tokens.dart';
import '../branding/brand_mark.dart';
import '../care_assistant/care_navigator_assistant.dart';
import '../navigation/app_navigation.dart';

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    super.key,
    required this.identity,
    required this.location,
    required this.title,
    required this.body,
    required this.onSignOut,
    required this.onNotifications,
    this.immersiveBody = false,
    this.showAssistant = true,
    this.onBack,
    this.unreadMessageCount = 0,
    this.unreadNotificationCount = 0,
  });

  final AppIdentity identity;
  final String location;
  final String title;
  final Widget body;
  final VoidCallback onSignOut;
  final VoidCallback onNotifications;
  final bool immersiveBody;
  final bool showAssistant;
  final VoidCallback? onBack;
  final int unreadMessageCount;
  final int unreadNotificationCount;

  @override
  Widget build(BuildContext context) {
    final destinations = workspaceDestinations(identity.role);
    final desktop = MediaQuery.sizeOf(context).width >= 960;
    final desktopDestinations = destinations
        .where((destination) => destination.label != 'Profile')
        .toList(growable: false);
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final selected = _selectedIndex(
      desktop ? desktopDestinations : destinations,
    );
    final messagesLocation = workspaceMessagesLocation(identity.role);
    final profileLocation = identity.role == UserRole.guest
        ? null
        : '${identity.role.homeLocation}/profile';
    final onMessages = messagesLocation == null
        ? null
        : () => context.go(messagesLocation);
    final onProfile = profileLocation == null
        ? null
        : () => context.go(profileLocation);

    if (desktop) {
      return _WorkspaceKeyboardScope(
        onSearch: () => _openWorkspaceSearch(desktopDestinations, selected),
        child: Scaffold(
          floatingActionButton: showAssistant
              ? const CareNavigatorAssistant()
              : null,
          body: Row(
            children: [
              _Sidebar(
                identity: identity,
                location: location,
                destinations: desktopDestinations,
                selectedIndex: selected,
                onSignOut: onSignOut,
              ),
              Expanded(
                child: Column(
                  children: [
                    _UtilityBar(
                      title: title,
                      identity: identity,
                      onMessages: onMessages,
                      onNotifications: onNotifications,
                      onProfile: onProfile,
                      unreadMessageCount: unreadMessageCount,
                      unreadNotificationCount: unreadNotificationCount,
                    ),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final mobileDestinations = destinations
        .where((d) => d.isPrimary)
        .toList(growable: false);
    final sidebarDestinations = destinations
        .where((d) => !d.isPrimary)
        .toList(growable: false);
    final mobileSelectedRaw = _selectedIndex(mobileDestinations);
    final mobileSelected = mobileSelectedRaw >= 0 ? mobileSelectedRaw : 0;
    final sidebarSelected = _selectedIndex(sidebarDestinations);
    return _WorkspaceKeyboardScope(
      onSearch: () => _openWorkspaceSearch(destinations, selected),
      child: Scaffold(
        appBar: immersiveBody
            ? null
            : AppBar(
                automaticallyImplyLeading: false,
                toolbarHeight: enlargedText ? 88 : 72,
                titleSpacing: 0,
                leadingWidth: onBack == null ? 92 : 52,
                leading: onBack == null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Builder(
                            builder: (context) => IconButton(
                              tooltip: 'Open navigation menu',
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                              icon: const Icon(Icons.menu),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const BrandMark(size: 28),
                        ],
                      )
                    : IconButton(
                        tooltip: 'Back to appointments',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                title: Text(
                  title,
                  maxLines: enlargedText ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                actionsPadding: const EdgeInsets.only(right: 8),
                shape: const Border(
                  bottom: BorderSide(color: AppColors.divider),
                ),
                shadowColor: Colors.transparent,
                actions: [
                  if (onMessages != null)
                    _WorkspaceHeaderAction(
                      tooltip: 'Messages',
                      onPressed: onMessages,
                      icon: Icons.message_outlined,
                      badgeCount: unreadMessageCount,
                    ),
                  _WorkspaceHeaderAction(
                    tooltip: 'Notifications',
                    onPressed: onNotifications,
                    icon: Icons.notifications_outlined,
                    badgeCount: unreadNotificationCount,
                  ),
                ],
              ),
        drawer: immersiveBody
            ? null
            : Drawer(
                backgroundColor: const Color(0xFF063B4C),
                child: _Sidebar(
                  identity: identity,
                  location: location,
                  destinations: sidebarDestinations,
                  selectedIndex: sidebarSelected,
                  onSignOut: onSignOut,
                ),
              ),
        body: body,
        floatingActionButton: immersiveBody || !showAssistant
            ? null
            : const CareNavigatorAssistant(),
        bottomNavigationBar: immersiveBody || mobileDestinations.isEmpty
            ? null
            : DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.divider)),
                ),
                child: NavigationBarTheme(
                  data: appMobileNavigationBarTheme(),
                  child: NavigationBar(
                    selectedIndex: mobileSelected,
                    onDestinationSelected: (index) {
                      context.go(mobileDestinations[index].location);
                    },
                    destinations: [
                      for (final item in mobileDestinations)
                        NavigationDestination(
                          icon: _MobileNavigationIcon(item),
                          selectedIcon: _MobileNavigationIcon(item),
                          label: item.label,
                          // Flutter's destination tooltip uses an
                          // OverlayPortal. On web, a route change while the
                          // pointer remains over a destination can leave that
                          // portal attached to the outgoing layout and trigger
                          // overlay-size and duplicate-GlobalKey assertions.
                          // Labels are always visible here, so the tooltip is
                          // redundant.
                          tooltip: '',
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  int _selectedIndex(List<AppDestination> destinations) {
    var bestIndex = -1;
    var bestLength = -1;
    for (var index = 0; index < destinations.length; index++) {
      final destination = destinations[index];
      final candidates = [destination, ...destination.children];
      for (final candidateDestination in candidates) {
        final candidate = candidateDestination.location;
        if ((location == candidate || location.startsWith('$candidate/')) &&
            candidate.length > bestLength) {
          bestIndex = index;
          bestLength = candidate.length;
        }
      }
    }
    return bestIndex;
  }

  Future<void> _openWorkspaceSearch(
    List<AppDestination> destinations,
    int selected,
  ) async {
    final location = await showRootSheet<String>(
      builder: (context) => _WorkspaceSearchSheet(
        destinations: destinations,
        selectedIndex: selected,
      ),
    );
    final context = rootNavigatorKey.currentContext;
    if (location != null && context != null && context.mounted) {
      context.go(location);
    }
  }
}

class _MobileNavigationIcon extends StatelessWidget {
  const _MobileNavigationIcon(this.item);

  final AppDestination item;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: Center(
        child: Transform.scale(
          scale: item.mobileIconScale,
          child: Icon(item.icon, size: 20),
        ),
      ),
    );
  }
}

class _WorkspaceKeyboardScope extends StatelessWidget {
  const _WorkspaceKeyboardScope({required this.onSearch, required this.child});

  final VoidCallback onSearch;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): onSearch,
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): onSearch,
    },
    child: Focus(autofocus: true, child: child),
  );
}

class _WorkspaceSearchSheet extends StatefulWidget {
  const _WorkspaceSearchSheet({
    required this.destinations,
    required this.selectedIndex,
  });

  final List<AppDestination> destinations;
  final int selectedIndex;

  @override
  State<_WorkspaceSearchSheet> createState() => _WorkspaceSearchSheetState();
}

class _WorkspaceSearchSheetState extends State<_WorkspaceSearchSheet> {
  final _controller = TextEditingController();
  var _query = '';

  List<(int, AppDestination)> get _destinations => [
    for (var index = 0; index < widget.destinations.length; index++) ...[
      (index, widget.destinations[index]),
      for (final child in widget.destinations[index].children) (index, child),
    ],
  ];

  List<(int, AppDestination)> get _results {
    final query = _query.trim().toLowerCase();
    return [
      for (final entry in _destinations)
        if (query.isEmpty ||
            entry.$2.label.toLowerCase().contains(query) ||
            entry.$2.location.toLowerCase().contains(query))
          entry,
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Search workspace sections',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close search',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (results.isNotEmpty) {
                  Navigator.of(context).pop(results.first.$2.location);
                }
              },
              decoration: InputDecoration(
                labelText: 'Section name',
                hintText: 'Appointments, laboratory, security…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear workspace search',
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.backspace_outlined),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${results.length} section${results.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Flexible(
              child: results.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_outlined,
                              size: 34,
                              color: AppColors.textMuted,
                            ),
                            SizedBox(height: 10),
                            Text('No matching workspace sections'),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, resultIndex) {
                        final (index, item) = results[resultIndex];
                        final selected = index == widget.selectedIndex;
                        return ListTile(
                          selected: selected,
                          leading: Icon(item.icon),
                          title: Text(item.label),
                          trailing: selected
                              ? const Icon(
                                  Icons.check,
                                  semanticLabel: 'Current section',
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).pop(item.location),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.identity,
    required this.location,
    required this.destinations,
    required this.selectedIndex,
    required this.onSignOut,
  });

  final AppIdentity identity;
  final String location;
  final List<AppDestination> destinations;
  final int selectedIndex;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final assignedHospitalName = identity.assignedHospitalName?.trim();
    return Container(
      width: 248,
      color: const Color(0xFF063B4C),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: BrandLockup(onDark: true),
            ),
            const SizedBox(height: 28),
            Text(
              identity.role.label,
              style: const TextStyle(
                color: Color(0xFF9FC8D1),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (identity.role == UserRole.hospitalAdministrator &&
                assignedHospitalName != null &&
                assignedHospitalName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Semantics(
                label: 'Assigned hospital: $assignedHospitalName',
                child: Tooltip(
                  message: assignedHospitalName,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.local_hospital_outlined,
                        size: 17,
                        color: Color(0xFFDCECEF),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          assignedHospitalName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = 0;
                      index < destinations.length;
                      index++
                    ) ...[
                      _SidebarItem(
                        item: destinations[index],
                        selected: index == selectedIndex,
                      ),
                      if (destinations[index].children.isNotEmpty)
                        _SidebarSubnav(
                          items: destinations[index].children,
                          location: location,
                        ),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(color: Color(0xFF20596A)),
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                leading: const Icon(Icons.logout, color: Color(0xFFB9D4DA)),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: Color(0xFFDCECEF)),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                onTap: onSignOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.item, required this.selected});

  final AppDestination item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: const Color(0xFF087B83),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(
          item.icon,
          size: 20,
          color: selected ? Colors.white : const Color(0xFFB9D4DA),
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFDCECEF),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        onTap: () {
          if (Scaffold.maybeOf(context)?.isDrawerOpen == true) {
            Navigator.of(context).pop();
          }
          context.go(item.location);
        },
      ),
    );
  }
}

class _SidebarSubnav extends StatelessWidget {
  const _SidebarSubnav({required this.items, required this.location});

  final List<AppDestination> items;
  final String location;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 22, top: 2, bottom: 4),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFF327381))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              _SidebarSubnavItem(
                item: item,
                selected: _matchesLocation(location, item.location),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarSubnavItem extends StatelessWidget {
  const _SidebarSubnavItem({required this.item, required this.selected});

  final AppDestination item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        minVerticalPadding: 0,
        selected: selected,
        selectedTileColor: const Color(0xFF0A6575),
        contentPadding: const EdgeInsets.only(left: 12, right: 10),
        leading: Icon(
          item.icon,
          size: 17,
          color: selected ? Colors.white : const Color(0xFF9FC8D1),
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFC9E0E4),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.compact),
        ),
        onTap: () {
          if (Scaffold.maybeOf(context)?.isDrawerOpen == true) {
            Navigator.of(context).pop();
          }
          context.go(item.location);
        },
      ),
    );
  }
}

bool _matchesLocation(String location, String candidate) =>
    location == candidate || location.startsWith('$candidate/');

class _UtilityBar extends StatelessWidget {
  const _UtilityBar({
    required this.title,
    required this.identity,
    required this.onMessages,
    required this.onNotifications,
    required this.onProfile,
    required this.unreadMessageCount,
    required this.unreadNotificationCount,
  });

  final String title;
  final AppIdentity identity;
  final VoidCallback? onMessages;
  final VoidCallback onNotifications;
  final VoidCallback? onProfile;
  final int unreadMessageCount;
  final int unreadNotificationCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (onMessages != null)
            _WorkspaceHeaderAction(
              tooltip: 'Messages',
              onPressed: onMessages,
              icon: Icons.message_outlined,
              badgeCount: unreadMessageCount,
            ),
          _WorkspaceHeaderAction(
            tooltip: 'Notifications',
            onPressed: onNotifications,
            icon: Icons.notifications_outlined,
            badgeCount: unreadNotificationCount,
          ),
          const SizedBox(width: 10),
          _WorkspaceHeaderProfile(identity: identity, onPressed: onProfile),
        ],
      ),
    );
  }
}

class _WorkspaceHeaderProfile extends StatelessWidget {
  const _WorkspaceHeaderProfile({
    required this.identity,
    required this.onPressed,
  });

  final AppIdentity identity;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Open profile',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('workspace-header-profile'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.selected,
                child: Icon(
                  Icons.person_outline,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identity.displayName ?? identity.role.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      identity.role.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WorkspaceHeaderAction extends StatelessWidget {
  const _WorkspaceHeaderAction({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.badgeCount = 0,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final visibleCount = badgeCount > 99 ? '99+' : '$badgeCount';
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      iconSize: 26,
      icon: SizedBox.square(
        dimension: 30,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon),
            if (badgeCount > 0)
              Positioned(
                top: -5,
                right: -7,
                child: Semantics(
                  label: '$badgeCount unread ${tooltip.toLowerCase()}',
                  child: Container(
                    key: Key('${tooltip.toLowerCase()}-unread-badge'),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.destructive,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      visibleCount,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
