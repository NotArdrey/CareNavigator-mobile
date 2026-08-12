import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/guest_consultation_models.dart';
import '../../providers/core_providers.dart';
import '../../providers/guest_consultation_provider.dart';
import '../../routing/root_overlay.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_shell/public_scaffold.dart';
import '../../widgets/data_display/content_panel.dart';
import '../../widgets/feedback/async_action_button.dart';
import '../../widgets/layout/page_header.dart';

class GuestVerificationScreen extends ConsumerStatefulWidget {
  const GuestVerificationScreen({super.key});

  @override
  ConsumerState<GuestVerificationScreen> createState() =>
      _GuestVerificationScreenState();
}

class _GuestVerificationScreenState
    extends ConsumerState<GuestVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  String? _verificationError;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intake = ref.watch(guestConsultationProvider);
    if (ref.watch(consultationRepositoryProvider) == null) {
      return const _VerificationState(
        icon: Icons.cloud_off_outlined,
        title: 'Verification service unavailable',
        message:
            'Email verification is unavailable until the consultation service is configured.',
      );
    }
    if (intake.status == GuestRequestStatus.drafting) {
      return const _MissingVerificationState();
    }
    if (intake.status == GuestRequestStatus.submitted) {
      return _AlreadyVerifiedState(requestId: intake.requestId!);
    }
    return PublicScaffold(
      currentLocation: '/consultation/verify',
      body: SingleChildScrollView(
        child: PageContent(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'Verify consultation email',
                description:
                    'Enter the code sent to your email before the private request is submitted.',
              ),
              const SizedBox(height: 20),
              ContentPanel(
                title: 'Email verification',
                subtitle:
                    'The request is created only after we verify this email address.',
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        initialValue: intake.draft.email,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Email address from intake',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        decoration: InputDecoration(
                          labelText: 'Six-digit email code',
                          prefixIcon: const Icon(Icons.password_outlined),
                          errorText: _verificationError,
                        ),
                        onChanged: (_) {
                          if (_verificationError != null) {
                            setState(() => _verificationError = null);
                          }
                        },
                        validator: (value) =>
                            RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                            ? null
                            : 'Enter a six-digit code.',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AsyncActionButton(
                            label: intake.resendCount == 0
                                ? 'Resend email code'
                                : 'Resend again (${intake.resendCount})',
                            icon: Icons.refresh,
                            busy: intake.busy,
                            onPressed: _resend,
                          ),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton(
                                onPressed: () =>
                                    context.go('/consultation/request'),
                                child: const Text('Back'),
                              ),
                              FilledButton(
                                onPressed: intake.busy ? null : _verify,
                                child: const Text('Verify and continue'),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  Future<void> _resend() async {
    try {
      await ref
          .read(guestConsultationProvider.notifier)
          .resendVerificationCode();
      showRootMessage('A new verification code was sent.');
    } catch (_) {
      showRootMessage('The verification code could not be resent. Try again.');
    }
  }

  Future<void> _verify() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final intake = ref.read(guestConsultationProvider);
    try {
      final requestId = await ref
          .read(guestConsultationProvider.notifier)
          .verifyCode(email: intake.draft.email, code: _otpController.text);
      if (mounted) context.go('/consultation/confirmation/$requestId');
    } on ArgumentError {
      setState(
        () => _verificationError = 'The verification code is incorrect.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _verificationError =
              'Verification or request submission failed. Check the code and try again.',
        );
      }
    }
  }
}

class GuestConfirmationScreen extends ConsumerWidget {
  const GuestConfirmationScreen({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(guestConsultationProvider);
    final resolved =
        intake.requestId == requestId &&
        intake.status == GuestRequestStatus.submitted;
    return PublicScaffold(
      currentLocation: '/consultation/confirmation/$requestId',
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: resolved
                ? _ResolvedConfirmation(intake: intake)
                : _UnresolvedConfirmation(requestId: requestId),
          ),
        ),
      ),
    );
  }
}

class _ResolvedConfirmation extends ConsumerWidget {
  const _ResolvedConfirmation({required this.intake});

  final GuestConsultationState intake;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ContentPanel(
    child: Column(
      children: [
        const Icon(Icons.task_alt_outlined, size: 48, color: AppColors.success),
        const SizedBox(height: 14),
        Text(
          'Consultation request submitted',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your verified request is pending review. This is not yet an approved appointment.',
          textAlign: TextAlign.center,
        ),
        const Divider(height: 28),
        _ConfirmationLine(label: 'Request ID', value: intake.requestId!),
        _ConfirmationLine(
          label: 'Hospital',
          value: intake.draft.hospitalLabel!,
        ),
        _ConfirmationLine(
          label: 'Department',
          value: intake.draft.departmentLabel!,
        ),
        _ConfirmationLine(
          label: 'Preferred schedule',
          value: DateFormat(
            'MMM d, y • h:mm a',
          ).format(intake.draft.preferredStart!),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            FilledButton(
              onPressed: () => context.go('/hospitals'),
              child: const Text('Return to care directory'),
            ),
            OutlinedButton(
              onPressed: () {
                ref.read(guestConsultationProvider.notifier).reset();
                context.go('/consultation/request');
              },
              child: const Text('Start another request'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _UnresolvedConfirmation extends StatelessWidget {
  const _UnresolvedConfirmation({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) => ContentPanel(
    child: DataState(
      icon: Icons.pending_actions_outlined,
      title: 'Consultation confirmation unavailable',
      message:
          'Request $requestId is not available in the current verified request state.',
      action: FilledButton(
        onPressed: () => context.go('/consultation/request'),
        child: const Text('Start consultation request'),
      ),
    ),
  );
}

class _MissingVerificationState extends StatelessWidget {
  const _MissingVerificationState();

  @override
  Widget build(BuildContext context) => _VerificationState(
    icon: Icons.mark_email_unread_outlined,
    title: 'No verification pending',
    message:
        'Complete contact, care selection, and scheduling before email verification.',
    action: FilledButton(
      onPressed: () => context.go('/consultation/request'),
      child: const Text('Start consultation request'),
    ),
  );
}

class _AlreadyVerifiedState extends StatelessWidget {
  const _AlreadyVerifiedState({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) => _VerificationState(
    icon: Icons.task_alt_outlined,
    title: 'Request already submitted',
    message: 'The verified consultation request is ready to review.',
    action: FilledButton(
      onPressed: () => context.go('/consultation/confirmation/$requestId'),
      child: const Text('View confirmation'),
    ),
  );
}

class _VerificationState extends StatelessWidget {
  const _VerificationState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => PublicScaffold(
    currentLocation: '/consultation/verify',
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ContentPanel(
            child: DataState(
              icon: icon,
              title: title,
              message: message,
              action: action,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ConfirmationLine extends StatelessWidget {
  const _ConfirmationLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
