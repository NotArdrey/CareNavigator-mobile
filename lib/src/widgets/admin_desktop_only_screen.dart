import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/routing/role_routes.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
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
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: AppColors.mint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.desktop_windows_outlined,
                      size: 40,
                      color: AppColors.teal,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Desktop web portal required',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    adminMobileAccessMessage,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _returnToLogin,
                    child: const Text('Return to sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
