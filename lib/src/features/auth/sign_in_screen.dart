import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/auth/user_role.dart';
import '../../providers/core_providers.dart';
import '../../repositories/repository_failure.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_shell/public_scaffold.dart';
import '../../widgets/auth/auth_card.dart';
import 'auth_validation.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.redirectTo});

  final String? redirectTo;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _obscurePassword = true;
  var _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PublicScaffold(
      currentLocation: '/sign-in',
      minimalNavigation: true,
      hideHeader: true,
      body: AuthCard(
        showHospitalBackground: true,
        title: 'Welcome back',
        description: 'Sign in to access your CareNavigator account.',
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: TextButton(
                onPressed: () => context.go('/forgot-password'),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 8),
            const AuthDivider(),
            const SizedBox(height: 12),
            AuthSecondaryButton(
              onPressed: _busy ? null : _continueAsGuest,
              child: Text(
                _busy ? 'Starting guest access...' : 'Continue as guest',
              ),
            ),
            const SizedBox(height: 12),
            AuthSecondaryButton(
              onPressed: _busy ? null : () => context.go('/register'),
              child: const Text('Create an account'),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                AuthStatusMessage(message: _errorMessage!, isError: true),
                const SizedBox(height: 20),
              ],
              _emailField(),
              const SizedBox(height: 16),
              _passwordField(),
              const SizedBox(height: 20),
              AuthPrimaryButton(
                onPressed: _busy ? null : _signIn,
                child: Text(_busy ? 'Signing in...' : 'Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emailField() => TextFormField(
    controller: _emailController,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    decoration: const InputDecoration(
      labelText: 'Email address',
      hintText: 'Enter your email',
      prefixIcon: Icon(Icons.email_outlined),
    ),
    validator: (value) => isValidEmailAddress(value?.trim() ?? '')
        ? null
        : 'Enter a valid email address.',
  );

  Widget _passwordField() => TextFormField(
    controller: _passwordController,
    obscureText: _obscurePassword,
    autofillHints: const [AutofillHints.password],
    decoration: InputDecoration(
      labelText: 'Password',
      hintText: 'Enter your password',
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: signInPasswordValidationError,
  );

  Future<void> _signIn() async {
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final repository = ref.read(authRepositoryProvider);
    if (repository == null) {
      setState(
        () => _errorMessage =
            'We could not sign you in right now. Please try again later.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(appIdentityProvider.notifier)
          .signInWithPassword(
            email: _emailController.text,
            password: _passwordController.text,
          );
      if (!mounted) return;
      final identity = ref.read(appIdentityProvider);
      final requestedLocation = widget.redirectTo;
      context.go(
        identity.role == UserRole.patient &&
                requestedLocation != null &&
                requestedLocation.startsWith('/consultation/request')
            ? requestedLocation
            : identity.role.homeLocation,
      );
    } on RepositoryFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'We could not sign you in right now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() => _errorMessage = null);

    final repository = ref.read(authRepositoryProvider);
    if (repository == null) {
      setState(
        () => _errorMessage =
            'Guest access is temporarily unavailable. Please try again later.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(appIdentityProvider.notifier).signInAnonymously();
      if (!mounted) return;
      context.go('/');
    } on RepositoryFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Guest access is temporarily unavailable. Please try again later.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class AccessStateScreen extends StatelessWidget {
  const AccessStateScreen({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel = 'Go to sign in',
    this.actionLocation = '/sign-in',
  });

  final String title;
  final String message;
  final String actionLabel;
  final String actionLocation;

  @override
  Widget build(BuildContext context) {
    return PublicScaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 42,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => context.go(actionLocation),
                      child: Text(actionLabel),
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
}
