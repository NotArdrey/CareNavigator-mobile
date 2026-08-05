import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/auth_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final response = await ref
          .read(authRepositoryProvider)
          .signUp(
            email: _emailController.text,
            password: _passwordController.text,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
          );
      if (!mounted) return;
      if (response.session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account created. Check your email to confirm it, then sign in.',
            ),
          ),
        );
        context.go('/login');
      } else {
        ref.invalidate(currentProfileProvider);
        context.go('/home');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyRegistrationError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      maxWidth: 520,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Start your care journey',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a secure visitor account. Your care team can activate clinical access after verification.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'YOUR DETAILS',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.forest,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final firstName = AppTextField(
                  label: 'First name',
                  controller: _firstNameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  hint: 'Juan',
                  validator: _requiredName,
                );
                final lastName = AppTextField(
                  label: 'Last name',
                  controller: _lastNameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  hint: 'Dela Cruz',
                  validator: _requiredName,
                );
                if (constraints.maxWidth < 430) {
                  return Column(
                    children: [
                      firstName,
                      const SizedBox(height: AppSpacing.lg),
                      lastName,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: firstName),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: lastName),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Email address',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              hint: 'you@example.com',
              prefixIcon: AppIcons.alternateEmailRounded,
              validator: (value) => value == null || !value.trim().contains('@')
                  ? 'Enter a valid email address.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'SECURE YOUR ACCOUNT',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.forest,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Password',
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              prefixIcon: AppIcons.keyRounded,
              suffix: IconButton(
                tooltip: _obscurePassword ? 'Show passwords' : 'Hide passwords',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? AppIcons.visibilityOutlined
                      : AppIcons.visibilityOffOutlined,
                ),
              ),
              validator: (value) => value == null || value.length < 8
                  ? 'Use at least 8 characters.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Confirm password',
              controller: _confirmPasswordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              prefixIcon: AppIcons.lockResetRounded,
              validator: (value) => value != _passwordController.text
                  ? 'Passwords do not match.'
                  : null,
              onSubmitted: (_) {
                if (!_submitting) _register();
              },
            ),
            const SizedBox(height: AppSpacing.md),
            const AppCard(
              tone: AppCardTone.soft,
              padding: EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.shieldOutlined,
                    color: AppColors.forest,
                    size: 20,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Use at least 8 characters. Your password is handled by secure authentication and is never visible to care staff.',
                      style: TextStyle(fontSize: 12, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'I already have an account',
              style: AppButtonStyle.secondary,
              expand: true,
              onPressed: _submitting ? null : () => context.go('/login'),
            ),
            AppButton(
              label: 'Explore as a guest',
              style: AppButtonStyle.quiet,
              expand: true,
              onPressed: _submitting ? null : () => context.go('/home'),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'By creating an account, you agree to use Care Navigator for healthcare navigation—not emergency response or diagnosis.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String? _requiredName(String? value) =>
    value == null || value.trim().isEmpty ? 'Required.' : null;

String _friendlyRegistrationError(Object error) {
  final message = error
      .toString()
      .replaceFirst('AuthException(message: ', '')
      .split(', statusCode:')
      .first;
  return message.isEmpty ? 'Registration failed. Please try again.' : message;
}
