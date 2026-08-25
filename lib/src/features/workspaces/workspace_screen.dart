import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth/user_role.dart';
import '../../providers/core_providers.dart';
import '../../widgets/app_shell/workspace_shell.dart';
import 'live_workspace_view.dart';

class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({
    super.key,
    required this.role,
    required this.location,
    this.section,
    this.itemId,
    this.action,
    this.requestReservation = false,
    this.initialReservationHospitalId,
    this.initialReservationDoctorId,
  });

  final UserRole role;
  final String location;
  final String? section;
  final String? itemId;
  final String? action;
  final bool requestReservation;
  final String? initialReservationHospitalId;
  final String? initialReservationDoctorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(appIdentityProvider);
    final unreadMessageCount =
        ref.watch(unreadMessageCountProvider).asData?.value ?? 0;
    final unreadNotificationCount = ref.watch(unreadNotificationCountProvider);
    return WorkspaceShell(
      identity: identity,
      location: location,
      title: _pageTitle(role, section, itemId),
      onSignOut: () async {
        await ref.read(appIdentityProvider.notifier).signOut();
        if (context.mounted) context.go('/');
      },
      onNotifications: () => context.go('${role.homeLocation}/notifications'),
      unreadMessageCount: unreadMessageCount,
      unreadNotificationCount: unreadNotificationCount,
      immersiveBody: section == 'messages' && itemId != null,
      showAssistant:
          !(role == UserRole.patient &&
              itemId != null &&
              {'appointments', 'consultations'}.contains(section)),
      onBack:
          role == UserRole.patient &&
              itemId != null &&
              {'appointments', 'consultations'}.contains(section)
          ? () => context.go('${role.homeLocation}/$section')
          : null,
      body: LiveWorkspaceView(
        role: role,
        section: section,
        itemId: itemId,
        requestReservation: requestReservation,
        initialReservationHospitalId: initialReservationHospitalId,
        initialReservationDoctorId: initialReservationDoctorId,
        showDetailHeader:
            !(role == UserRole.patient &&
                itemId != null &&
                {'appointments', 'consultations'}.contains(section)),
      ),
    );
  }
}

String _pageTitle(UserRole role, String? section, String? itemId) {
  if (section == null) {
    return switch (role) {
      UserRole.patient => 'Your care',
      UserRole.doctor => 'Doctor workspace',
      UserRole.hospitalAdministrator => 'Hospital operations',
      UserRole.superAdministrator => 'Platform governance',
      UserRole.guest => 'CareNavigator PH',
    };
  }
  if (itemId != null && {'appointments', 'consultations'}.contains(section)) {
    return 'Appointment Details';
  }
  if (role == UserRole.patient) {
    return switch (section) {
      'medical-records' || 'records' => 'Medical Overview',
      'labs' => 'Diagnostics',
      _ => _humanizeSection(section),
    };
  }
  return _humanizeSection(section);
}

String _humanizeSection(String section) {
  return section
      .split('-')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}
