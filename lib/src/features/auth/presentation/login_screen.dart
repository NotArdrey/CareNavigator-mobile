import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/routing/role_routes.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/auth_page_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _accessMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _rejectExistingMobileAdminSession(),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _adminIsBlockedOnThisDevice(String? role) => shouldBlockAdminAccess(
    role: role,
    isWeb: kIsWeb,
    logicalWidth: MediaQuery.sizeOf(context).width,
  );

  Future<void> _rejectExistingMobileAdminSession() async {
    final repository = ref.read(authRepositoryProvider);
    if (repository.currentSession == null) return;
    try {
      final profile = await repository.getProfile();
      if (!mounted || !_adminIsBlockedOnThisDevice(profile?.role)) return;
      await repository.signOut();
      ref.invalidate(currentProfileProvider);
      if (mounted) {
        setState(() => _accessMessage = adminMobileAccessMessage);
      }
    } catch (_) {
      // A normal sign-in attempt will surface any authentication error.
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _accessMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithPassword(
            email: _emailController.text,
            password: _passwordController.text,
          );
      final profile = await ref.read(authRepositoryProvider).getProfile();
      if (!mounted) return;
      ref.invalidate(currentProfileProvider);
      if (_adminIsBlockedOnThisDevice(profile?.role)) {
        await ref.read(authRepositoryProvider).signOut();
        ref.invalidate(currentProfileProvider);
        if (mounted) {
          setState(() => _accessMessage = adminMobileAccessMessage);
        }
        return;
      }
      final requested = GoRouterState.of(
        context,
      ).uri.queryParameters['redirect'];
      final isAdministrator = {
        'super_admin',
        'hospital_admin',
      }.contains(profile?.role);
      if (requested != null &&
          ((requested.startsWith('/admin') && isAdministrator) ||
              requested == '/dashboard' ||
              requested == '/care')) {
        context.go(requested);
      } else {
        context.go(landingRouteForRole(profile?.role));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email address first.')),
      );
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset instructions were sent.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayAccessMessage =
        _accessMessage ??
        (GoRouterState.of(context).uri.queryParameters['blocked'] ==
                'admin_mobile'
            ? adminMobileAccessMessage
            : null);
    return AuthPageShell(
      maxWidth: 480,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome back',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Pick up your care journey exactly where you left it.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.inkMuted),
            ),
            if (displayAccessMessage != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppNotice(
                title: 'Desktop access required',
                message: displayAccessMessage,
                icon: AppIcons.desktopWindowsOutlined,
                color: AppColors.warning,
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            AppTextField(
              label: 'Email address',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              hint: 'you@example.com',
              prefixIcon: AppIcons.alternateEmailRounded,
              validator: (value) => value == null || !value.contains('@')
                  ? 'Enter a valid email address.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Password',
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              prefixIcon: AppIcons.keyRounded,
              suffix: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? AppIcons.visibilityOutlined
                      : AppIcons.visibilityOffOutlined,
                ),
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
              onSubmitted: (_) {
                if (!_submitting) _signIn();
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _submitting ? null : _resetPassword,
                child: const Text('Forgot password?'),
              ),
            ),
            AppButton(
              label: 'Sign in to my workspace',
              icon: AppIcons.arrowForwardRounded,
              onPressed: _submitting ? null : _signIn,
              loading: _submitting,
              expand: true,
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Text(
                    'NEW TO CARE NAVIGATOR?',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .7,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Create a visitor account',
              icon: AppIcons.personAddAlt1Rounded,
              style: AppButtonStyle.secondary,
              expand: true,
              onPressed: _submitting ? null : () => context.go('/register'),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'Explore without signing in',
              icon: AppIcons.exploreOutlined,
              style: AppButtonStyle.quiet,
              expand: true,
              onPressed: _submitting ? null : () => context.go('/home'),
            ),
          ],
        ),
      ),
    );
  }
}

String _friendlyError(Object error) {
  final message = error
      .toString()
      .replaceFirst('AuthException(message: ', '')
      .split(', statusCode:')
      .first;
  return message.isEmpty ? 'Sign-in failed. Please try again.' : message;
}
