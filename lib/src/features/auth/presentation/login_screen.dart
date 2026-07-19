import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/routing/role_routes.dart';
import 'package:care_navigator_ph/src/widgets/brand_mark.dart';
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
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: BrandMark(),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Welcome back',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Sign in to access your CareNavigator workspace.',
                      ),
                      if (displayAccessMessage != null) ...[
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4D8),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF0D28A)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.desktop_windows_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  displayAccessMessage,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) =>
                            value == null || !value.contains('@')
                            ? 'Enter a valid email address.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your password.'
                            : null,
                        onFieldSubmitted: (_) => _submitting ? null : _signIn(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _submitting ? null : _resetPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      FilledButton(
                        onPressed: _submitting ? null : _signIn,
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => context.go('/register'),
                        child: const Text('Create an account'),
                      ),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => context.go('/home'),
                        child: const Text('Continue as guest'),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Patient accounts are created or approved by authorized doctors. Hospital administrators create doctor accounts.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7C91),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
