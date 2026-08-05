import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/routing/role_routes.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminDesktopOnlyScreen extends ConsumerStatefulWidget {
  const AdminDesktopOnlyScreen({this.signOut = false, super.key});

  final bool signOut;

  @override
  ConsumerState<AdminDesktopOnlyScreen> createState() =>
      _AdminDesktopOnlyScreenState();
}

class _AdminDesktopOnlyScreenState
    extends ConsumerState<AdminDesktopOnlyScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.signOut) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _signOut());
    }
  }

  Future<void> _signOut() async {
    final router = GoRouter.of(context);
    if (ref.read(authRepositoryProvider).currentSession == null) return;
    await ref.read(authRepositoryProvider).signOut();
    ref.invalidate(currentProfileProvider);
    router.go('/login?blocked=admin_mobile');
  }

  Future<void> _returnToLogin() async {
    final router = GoRouter.of(context);
    if (ref.read(authRepositoryProvider).currentSession != null) {
      await ref.read(authRepositoryProvider).signOut();
      ref.invalidate(currentProfileProvider);
    }
    router.go('/login');
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        const AppPageHeader(
          eyebrow: 'SECURE ADMINISTRATOR PORTAL',
          title: 'A wider control surface is required',
          subtitle: 'Operational tables and audit tools are desktop-only',
          icon: AppIcons.adminPanelSettingsRounded,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                decoration: BoxDecoration(
                  color: AppColors.evergreenDark,
                  borderRadius: BorderRadius.circular(AppRadius.extraLarge),
                  boxShadow: AppShadows.medium,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppStatusBadge(
                      label: 'DESKTOP SECURITY POLICY',
                      color: AppColors.mint,
                      icon: AppIcons.lockRounded,
                      inverse: true,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.forest,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: const Icon(
                        AppIcons.desktopWindowsRounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Open the administrator portal on desktop web.',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      adminMobileAccessMessage,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: AppColors.mist),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                tone: AppCardTone.mint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommended workspace',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Use a display at least 1024 logical pixels wide so tables, filters, and audit context remain visible together.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: 'Return to sign in',
                      icon: AppIcons.arrowBackRounded,
                      onPressed: _returnToLogin,
                      expand: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
