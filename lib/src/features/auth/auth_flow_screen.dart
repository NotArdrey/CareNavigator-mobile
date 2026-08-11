import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/shared/patient_identity.dart';
import '../../providers/core_providers.dart';
import '../../repositories/repository_failure.dart';
import '../../routing/root_overlay.dart';
import '../../widgets/app_shell/public_scaffold.dart';
import '../../widgets/auth/auth_card.dart';
import '../../widgets/forms/patient_details_fields.dart';
import '../legal/legal_policy_dialog.dart';
import 'auth_validation.dart';

enum AuthFlowKind { register, verifyOtp, forgotPassword, resetPassword }

class AuthFlowScreen extends ConsumerStatefulWidget {
  const AuthFlowScreen({super.key, required this.kind});

  final AuthFlowKind kind;

  @override
  ConsumerState<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends ConsumerState<AuthFlowScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _otpController = TextEditingController();
  DateTime? _birthDate;
  String? _sex;
  var _privacyAccepted = false;
  var _obscurePassword = true;
  var _obscureConfirmation = true;
  var _submitted = false;
  var _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PublicScaffold(
      currentLocation: _location,
      minimalNavigation: true,
      hideHeader: true,
      body: AuthCard(
        showHospitalBackground: widget.kind == AuthFlowKind.register,
        compactSpacing: widget.kind == AuthFlowKind.register,
        title: _title,
        description: _description,
        footer: _footer(context),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                AuthStatusMessage(message: _errorMessage!, isError: true),
                const SizedBox(height: 20),
              ],
              if (_submitted) ...[
                AuthStatusMessage(message: _successMessage),
                const SizedBox(height: 20),
              ],
              ..._fields,
              if (widget.kind == AuthFlowKind.register) ...[
                const SizedBox(height: 8),
                _consentRow(context),
              ],
              const SizedBox(height: 20),
              AuthPrimaryButton(
                onPressed:
                    _busy ||
                        widget.kind == AuthFlowKind.register &&
                            !_privacyAccepted
                    ? null
                    : _submit,
                child: Text(_busy ? 'Please wait...' : _actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> get _fields => switch (widget.kind) {
    AuthFlowKind.register => [
      _patientDetailsFields(),
      const SizedBox(height: 24),
      _passwordField(),
      const SizedBox(height: 16),
      TextFormField(
        controller: _confirmationController,
        obscureText: _obscureConfirmation,
        autofillHints: const [AutofillHints.newPassword],
        decoration: InputDecoration(
          labelText: 'Confirm password',
          prefixIcon: Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: _obscureConfirmation
                ? 'Show confirmation password'
                : 'Hide confirmation password',
            onPressed: () =>
                setState(() => _obscureConfirmation = !_obscureConfirmation),
            icon: Icon(
              _obscureConfirmation
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
        validator: (value) => value != _passwordController.text
            ? 'Passwords do not match.'
            : null,
      ),
    ],
    AuthFlowKind.verifyOtp => [
      _emailField(),
      const SizedBox(height: 16),
      TextFormField(
        controller: _otpController,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofillHints: const [AutofillHints.oneTimeCode],
        decoration: const InputDecoration(
          labelText: 'Verification code',
          prefixIcon: Icon(Icons.password_outlined),
        ),
        validator: (value) => RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
            ? null
            : 'Enter a six-digit code.',
      ),
    ],
    AuthFlowKind.forgotPassword => [_emailField()],
    AuthFlowKind.resetPassword => [
      _passwordField(),
      const SizedBox(height: 16),
      TextFormField(
        controller: _confirmationController,
        obscureText: _obscureConfirmation,
        autofillHints: const [AutofillHints.newPassword],
        decoration: InputDecoration(
          labelText: 'Confirm new password',
          prefixIcon: Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: _obscureConfirmation
                ? 'Show confirmation password'
                : 'Hide confirmation password',
            onPressed: () =>
                setState(() => _obscureConfirmation = !_obscureConfirmation),
            icon: Icon(
              _obscureConfirmation
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
        validator: (value) => value != _passwordController.text
            ? 'Passwords do not match.'
            : null,
      ),
    ],
  };

  Widget _patientDetailsFields() => PatientDetailsFields(
    firstNameController: _firstNameController,
    lastNameController: _lastNameController,
    mobileController: _mobileController,
    addressController: _addressController,
    emailController: _emailController,
    birthDate: _birthDate,
    sex: _sex,
    onBirthDateChanged: (value) => setState(() => _birthDate = value),
    onSexChanged: (value) => setState(() => _sex = value),
    fieldSpacing: 12,
    consistentDateField: MediaQuery.sizeOf(context).width < 600,
    stackNameFields: MediaQuery.sizeOf(context).width < 420,
    multilineAddress: false,
  );

  Widget _emailField() => TextFormField(
    controller: _emailController,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email],
    decoration: const InputDecoration(
      labelText: 'Email address',
      prefixIcon: Icon(Icons.email_outlined),
    ),
    validator: (value) {
      final email = value?.trim() ?? '';
      return isValidEmailAddress(email) ? null : 'Enter a valid email address.';
    },
  );

  Widget _passwordField() => TextFormField(
    controller: _passwordController,
    obscureText: _obscurePassword,
    autofillHints: const [AutofillHints.newPassword],
    decoration: InputDecoration(
      labelText: widget.kind == AuthFlowKind.resetPassword
          ? 'New password'
          : 'Password',
      hintText: 'Create a password',
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
    validator: passwordValidationError,
  );

  Widget _consentRow(BuildContext context) {
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).textTheme.bodyMedium?.color,
    );
    final linkStyle = secondaryStyle?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
    );

    return Semantics(
      checked: _privacyAccepted,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _privacyAccepted = !_privacyAccepted),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _privacyAccepted,
                visualDensity: VisualDensity.compact,
                onChanged: (value) =>
                    setState(() => _privacyAccepted = value ?? false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 11),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('I agree to the ', style: secondaryStyle),
                      _PolicyLink(
                        label: 'Terms and Conditions',
                        style: linkStyle,
                        onTap: () => _showPolicyDocument(LegalDocument.terms),
                      ),
                      Text(' and ', style: secondaryStyle),
                      _PolicyLink(
                        label: 'Privacy Policy',
                        style: linkStyle,
                        onTap: () => _showPolicyDocument(LegalDocument.privacy),
                      ),
                      Text('.', style: secondaryStyle),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    if (widget.kind == AuthFlowKind.register) {
      return Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Already have an account?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            TextButton(
              onPressed: () => context.go('/sign-in'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: TextButton(
        onPressed: () => context.go('/sign-in'),
        child: const Text('Back to sign in'),
      ),
    );
  }

  void _showPolicyDocument(LegalDocument document) {
    showRootDialog<void>(
      builder: (context) => LegalPolicyDialog(document: document),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _submitted = false;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final repository = ref.read(authRepositoryProvider);
    if (repository == null) {
      setState(
        () => _errorMessage =
            'This service is temporarily unavailable. Please try again later.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      switch (widget.kind) {
        case AuthFlowKind.register:
          final identity = PatientIdentity(
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            birthDate: _birthDate,
            sex: _sex,
            mobileNumber: _mobileController.text,
            email: _emailController.text,
            address: _addressController.text,
          );
          await repository.register(
            email: _emailController.text,
            password: _passwordController.text,
            profileInput: {...identity.toAuthMetadata()},
          );
        case AuthFlowKind.verifyOtp:
          await repository.verifyEmailOtp(
            email: _emailController.text,
            token: _otpController.text,
          );
        case AuthFlowKind.forgotPassword:
          await repository.requestPasswordReset(_emailController.text);
        case AuthFlowKind.resetPassword:
          await repository.updatePassword(_passwordController.text);
      }
      if (mounted) setState(() => _submitted = true);
    } on RepositoryFailure catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'The account action could not be completed. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _location => switch (widget.kind) {
    AuthFlowKind.register => '/register',
    AuthFlowKind.verifyOtp => '/verify-otp',
    AuthFlowKind.forgotPassword => '/forgot-password',
    AuthFlowKind.resetPassword => '/reset-password',
  };

  String get _title => switch (widget.kind) {
    AuthFlowKind.register => 'Create your account',
    AuthFlowKind.verifyOtp => 'Verify your email',
    AuthFlowKind.forgotPassword => 'Recover your account',
    AuthFlowKind.resetPassword => 'Set a new password',
  };

  String get _description => switch (widget.kind) {
    AuthFlowKind.register =>
      'Create your CareNavigator account to access consultations, records, and healthcare services.',
    AuthFlowKind.verifyOtp =>
      'Enter the verification code sent to your email address.',
    AuthFlowKind.forgotPassword =>
      "Enter your email address and we'll send a secure recovery link.",
    AuthFlowKind.resetPassword =>
      'Choose a new password for your CareNavigator account.',
  };

  String get _actionLabel => switch (widget.kind) {
    AuthFlowKind.register => 'Create account',
    AuthFlowKind.verifyOtp => 'Verify code',
    AuthFlowKind.forgotPassword => 'Send recovery link',
    AuthFlowKind.resetPassword => 'Update password',
  };

  String get _successMessage => switch (widget.kind) {
    AuthFlowKind.register =>
      'Account created. Check your email if confirmation is required, then sign in.',
    AuthFlowKind.verifyOtp => 'Email verified successfully.',
    AuthFlowKind.forgotPassword =>
      'If the account exists, a recovery email has been sent.',
    AuthFlowKind.resetPassword => 'Password updated successfully.',
  };
}

class _PolicyLink extends StatelessWidget {
  const _PolicyLink({
    required this.label,
    required this.style,
    required this.onTap,
  });

  final String label;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        label: label,
        link: true,
        hint: 'Opens $label',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text(label, style: style),
          ),
        ),
      ),
    );
  }
}
