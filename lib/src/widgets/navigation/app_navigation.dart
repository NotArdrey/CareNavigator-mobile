import 'package:flutter/material.dart';

import '../../models/auth/user_role.dart';
import '../../theme/app_tokens.dart';

NavigationBarThemeData appMobileNavigationBarTheme() => NavigationBarThemeData(
  height: 78,
  backgroundColor: AppColors.surface,
  surfaceTintColor: Colors.transparent,
  shadowColor: Colors.transparent,
  elevation: 0,
  indicatorColor: AppColors.selected,
  indicatorShape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
  ),
  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
  iconTheme: WidgetStateProperty.resolveWith((states) {
    final selected = states.contains(WidgetState.selected);
    return IconThemeData(
      color: selected ? AppColors.primary : AppColors.textMuted,
      size: 20,
    );
  }),
  labelTextStyle: WidgetStateProperty.resolveWith((states) {
    final selected = states.contains(WidgetState.selected);
    return TextStyle(
      color: selected ? AppColors.primary : AppColors.textMuted,
      fontSize: 12,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
  }),
);

class AppDestination {
  const AppDestination({
    required this.label,
    required this.icon,
    required this.location,
    this.isPrimary = false,
    this.children = const [],
    this.mobileIconScale = 1,
  });

  final String label;
  final IconData icon;
  final String location;
  final bool isPrimary;
  final List<AppDestination> children;
  final double mobileIconScale;
}

List<AppDestination> workspaceDestinations(UserRole role) => switch (role) {
  UserRole.patient => const [
    AppDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      location: '/patient',
      isPrimary: true,
      mobileIconScale: 1.08,
    ),
    AppDestination(
      label: 'Find care',
      icon: Icons.local_hospital_outlined,
      location: '/hospitals',
      isPrimary: true,
    ),
    AppDestination(
      label: 'Appointments',
      icon: Icons.calendar_today_outlined,
      location: '/patient/appointments',
      isPrimary: true,
      mobileIconScale: 0.93,
    ),
    AppDestination(
      label: 'Consultations',
      icon: Icons.medical_information_outlined,
      location: '/patient/consultations',
    ),
    AppDestination(
      label: 'Medical Overview',
      icon: Icons.dashboard_outlined,
      location: '/patient/medical-records',
    ),
    AppDestination(
      label: 'Lab Results',
      icon: Icons.science_outlined,
      location: '/patient/labs',
    ),
    AppDestination(
      label: 'Prescriptions',
      icon: Icons.medication_outlined,
      location: '/patient/prescriptions',
    ),
    AppDestination(
      label: 'Profile',
      icon: Icons.person_outline,
      location: '/patient/profile',
      isPrimary: true,
      mobileIconScale: 1.1,
    ),
  ],
  UserRole.doctor => const [
    AppDestination(
      label: 'Workspace',
      icon: Icons.dashboard_outlined,
      location: '/doctor',
      isPrimary: true,
    ),
    AppDestination(
      label: 'Scheduling',
      icon: Icons.calendar_month_outlined,
      location: '/doctor/scheduling',
      isPrimary: true,
    ),
    AppDestination(
      label: 'Patients',
      icon: Icons.people_outline,
      location: '/doctor/patients',
      isPrimary: true,
    ),
    AppDestination(
      label: 'Consultations',
      icon: Icons.medical_services_outlined,
      location: '/doctor/consultations',
    ),
    AppDestination(
      label: 'Laboratory',
      icon: Icons.science_outlined,
      location: '/doctor/laboratory',
    ),
    AppDestination(
      label: 'Profile',
      icon: Icons.person_outline,
      location: '/doctor/profile',
      isPrimary: true,
    ),
  ],
  UserRole.hospitalAdministrator => const [
    AppDestination(
      label: 'Overview',
      icon: Icons.dashboard_outlined,
      location: '/hospital-admin',
      isPrimary: true,
    ),
    AppDestination(
      label: 'Appointments',
      icon: Icons.calendar_today_outlined,
      location: '/hospital-admin/appointments',
      isPrimary: true,
    ),
    AppDestination(
      label: 'Facility',
      icon: Icons.domain_outlined,
      location: '/hospital-admin/facility',
    ),
    AppDestination(
      label: 'Emergency room',
      icon: Icons.emergency_outlined,
      location: '/hospital-admin/emergency-room',
      isPrimary: true,
    ),
    AppDestination(
      label: 'Services & Depts',
      icon: Icons.account_tree_outlined,
      location: '/hospital-admin/services-departments',
    ),
    AppDestination(
      label: 'Staff',
      icon: Icons.badge_outlined,
      location: '/hospital-admin/staff',
    ),
    AppDestination(
      label: 'Audit & Reports',
      icon: Icons.assessment_outlined,
      location: '/hospital-admin/audit-reports',
    ),
    AppDestination(
      label: 'Profile',
      icon: Icons.person_outline,
      location: '/hospital-admin/profile',
      isPrimary: true,
    ),
  ],
  UserRole.superAdministrator => const [
    AppDestination(
      label: 'Governance',
      icon: Icons.dashboard_outlined,
      location: '/super-admin',
      isPrimary: true,
    ),
    AppDestination(
      label: 'Approvals',
      icon: Icons.approval_outlined,
      location: '/super-admin/approvals',
      isPrimary: true,
    ),
    AppDestination(
      label: 'Accounts',
      icon: Icons.manage_accounts_outlined,
      location: '/super-admin/accounts',
      isPrimary: true,
    ),
    AppDestination(
      label: 'System',
      icon: Icons.settings_outlined,
      location: '/super-admin/system',
    ),
    AppDestination(
      label: 'Analytics',
      icon: Icons.analytics_outlined,
      location: '/super-admin/analytics',
    ),
    AppDestination(
      label: 'Profile',
      icon: Icons.person_outline,
      location: '/super-admin/profile',
      isPrimary: true,
    ),
  ],
  UserRole.guest => const [],
};

String? workspaceMessagesLocation(UserRole role) => switch (role) {
  UserRole.patient => '/patient/messages',
  UserRole.doctor => '/doctor/messages',
  UserRole.hospitalAdministrator ||
  UserRole.superAdministrator ||
  UserRole.guest => null,
};
