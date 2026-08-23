import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/consultation_scheduling.dart';
import '../../models/guest_consultation_models.dart';
import '../../models/hospitals/hospital_models.dart';
import '../../providers/guest_consultation_provider.dart';
import '../../providers/hospital_directory_provider.dart';
import '../../providers/core_providers.dart';
import '../../repositories/repository_failure.dart';
import '../../routing/root_overlay.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_shell/public_scaffold.dart';
import '../../widgets/data_display/content_panel.dart';
import '../../widgets/forms/patient_details_fields.dart';
import '../../widgets/layout/page_header.dart';
import '../../widgets/overlays/action_dialogs.dart';

class ConsultationRequestScreen extends ConsumerStatefulWidget {
  const ConsultationRequestScreen({super.key, this.initialHospitalId});

  final String? initialHospitalId;

  @override
  ConsumerState<ConsultationRequestScreen> createState() =>
      _ConsultationRequestScreenState();
}

class _ConsultationRequestScreenState
    extends ConsumerState<ConsultationRequestScreen> {
  final _contactFormKey = GlobalKey<FormState>();
  final _careFormKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _concernController = TextEditingController();
  final _durationController = TextEditingController();

  var _step = 0;
  String? _hospitalId;
  String? _departmentLabel;
  String? _sex;
  DateTime? _birthDate;
  DateTime? _preferredStart;
  var _privacyAccepted = false;
  var _careMode = GuestCareMode.inPerson;

  @override
  void initState() {
    super.initState();
    _hospitalId = widget.initialHospitalId;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _concernController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intake = ref.watch(guestConsultationProvider);
    final directory = ref.watch(hospitalDirectoryProvider);
    if (intake.status != GuestRequestStatus.drafting) {
      return _ExistingIntakeScreen(status: intake.status);
    }
    if (ref.watch(consultationRepositoryProvider) == null) {
      return const _ConsultationUnavailableScreen();
    }
    if (directory.isLoading) {
      return const _ConsultationStateScreen(
        icon: Icons.sync,
        title: 'Loading care locations',
        message: 'Checking published hospitals and departments.',
      );
    }
    if (directory.errorMessage != null) {
      return _ConsultationStateScreen(
        icon: Icons.cloud_off_outlined,
        title: 'Care locations unavailable',
        message: directory.errorMessage!,
        onRetry: () => ref.read(hospitalDirectoryProvider.notifier).refresh(),
      );
    }
    if (directory.entries.isEmpty) {
      return const _ConsultationStateScreen(
        icon: Icons.local_hospital_outlined,
        title: 'No care locations published',
        message:
            'A consultation request can be started when a hospital is published.',
      );
    }

    final selectedHospital = directory.findById(_hospitalId ?? '');
    return PublicScaffold(
      currentLocation: '/consultation/request',
      body: SingleChildScrollView(
        child: PageContent(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Request a consultation',
                description:
                    'Step ${_step + 1} of 3 · ${const ['Identity and contact details', 'Care location and mode', 'Review and schedule'][_step]}',
              ),
              const SizedBox(height: 14),
              _IntakeProgress(currentStep: _step),
              const SizedBox(height: 18),
              switch (_step) {
                0 => _contactStep(),
                1 => _careStep(directory.entries, selectedHospital),
                _ => _scheduleStep(selectedHospital, intake),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactStep() => ContentPanel(
    title: 'Contact and identity',
    subtitle:
        'These details are used to verify the request and help the care team review it safely.',
    child: Form(
      key: _contactFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PatientDetailsFields(
            firstNameController: _firstNameController,
            lastNameController: _lastNameController,
            mobileController: _mobileController,
            addressController: _addressController,
            emailController: _emailController,
            birthDate: _birthDate,
            sex: _sex,
            onBirthDateChanged: (value) => setState(() => _birthDate = value),
            onSexChanged: (value) => setState(() => _sex = value),
            fieldSpacing: 14,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _concernController,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Primary care concern',
              hintText: 'Describe the symptoms or reason for consultation.',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_outlined),
            ),
            validator: (value) {
              final length = value?.trim().length ?? 0;
              if (length < 10) {
                return 'Describe the concern in at least 10 characters.';
              }
              return length > 1000 ? 'Use 1000 characters or fewer.' : null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _durationController,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'How long has this been happening?',
              hintText: 'For example, 2 days or since last week.',
              prefixIcon: Icon(Icons.timelapse_outlined),
            ),
            validator: (value) => value?.trim().isEmpty ?? true
                ? 'Describe the symptom duration.'
                : null,
          ),
          const SizedBox(height: 8),
          FormField<bool>(
            initialValue: _privacyAccepted,
            validator: (value) =>
                value == true ? null : 'Consent is required before continuing.',
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _privacyAccepted,
                  onChanged: (value) {
                    final accepted = value ?? false;
                    setState(() => _privacyAccepted = accepted);
                    field.didChange(accepted);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I consent to the use of this information for consultation review.',
                  ),
                ),
                if (field.errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      field.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _StepActions(
            onBack: () => context.go('/hospitals'),
            onNext: _saveContact,
            nextLabel: 'Choose care location',
          ),
        ],
      ),
    ),
  );

  Widget _careStep(
    List<HospitalDirectoryEntry> hospitals,
    HospitalDirectoryEntry? selectedHospital,
  ) => ContentPanel(
    title: 'Care location and department',
    subtitle: 'Choose a verified hospital and one of its linked departments.',
    child: Form(
      key: _careFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selectedHospital?.id,
            decoration: const InputDecoration(
              labelText: 'Hospital',
              prefixIcon: Icon(Icons.local_hospital_outlined),
            ),
            items: [
              for (final hospital in hospitals)
                DropdownMenuItem(
                  value: hospital.id,
                  child: Text(hospital.name),
                ),
            ],
            validator: (value) => value == null ? 'Select a hospital.' : null,
            onChanged: (value) {
              final hospital = ref
                  .read(hospitalDirectoryProvider)
                  .findById(value ?? '');
              setState(() {
                _hospitalId = hospital?.id;
                _departmentLabel = hospital?.departments.firstOrNull;
                if (_careMode == GuestCareMode.online &&
                    !(hospital?.services.any(
                          (service) => service.toLowerCase().contains('online'),
                        ) ??
                        false)) {
                  _careMode = GuestCareMode.inPerson;
                }
              });
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey(_hospitalId),
            isExpanded: true,
            initialValue: _departmentLabel,
            decoration: const InputDecoration(
              labelText: 'Department',
              prefixIcon: Icon(Icons.account_tree_outlined),
            ),
            items: [
              for (final department
                  in selectedHospital?.departments ?? const <String>[])
                DropdownMenuItem(value: department, child: Text(department)),
            ],
            validator: (value) => value == null ? 'Select a department.' : null,
            onChanged: (value) => setState(() => _departmentLabel = value),
          ),
          const SizedBox(height: 16),
          Text('Care mode', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<GuestCareMode>(
            segments: [
              const ButtonSegment(
                value: GuestCareMode.inPerson,
                icon: Icon(Icons.local_hospital_outlined),
                label: Text('In person'),
              ),
              ButtonSegment(
                value: GuestCareMode.online,
                enabled:
                    selectedHospital?.services.any(
                      (service) => service.toLowerCase().contains('online'),
                    ) ??
                    false,
                icon: const Icon(Icons.video_call_outlined),
                label: const Text('Online'),
              ),
            ],
            selected: {_careMode},
            onSelectionChanged: (selection) =>
                setState(() => _careMode = selection.single),
          ),
          if (selectedHospital != null) ...[
            const SizedBox(height: 12),
            Text(
              '${selectedHospital.locationLabel} • ${selectedHospital.isAvailable ? 'Available' : 'Currently unavailable'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 18),
          _StepActions(
            onBack: () => setState(() => _step = 0),
            onNext: _saveCare,
            nextLabel: 'Choose schedule',
          ),
        ],
      ),
    ),
  );

  Widget _scheduleStep(
    HospitalDirectoryEntry? hospital,
    GuestConsultationState intake,
  ) => ContentPanel(
    title: 'Preferred schedule and review',
    subtitle:
        'A preference is not an appointment. An authorized care team member will review the request.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: intake.busy ? null : _chooseSchedule,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            _preferredStart == null
                ? 'Choose preferred date and time'
                : DateFormat('MMM d, y • h:mm a').format(_preferredStart!),
          ),
        ),
        const SizedBox(height: 18),
        _ReviewLine(label: 'Name', value: intake.draft.fullName),
        _ReviewLine(label: 'Email', value: intake.draft.email),
        _ReviewLine(label: 'Hospital', value: hospital?.name ?? 'Not selected'),
        _ReviewLine(
          label: 'Department',
          value: _departmentLabel ?? 'Not selected',
        ),
        _ReviewLine(
          label: 'Mode',
          value: _careMode == GuestCareMode.online ? 'Online' : 'In person',
        ),
        _ReviewLine(label: 'Concern', value: _concernController.text.trim()),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Text(
            'This intake is not medical advice, a diagnosis, or an appointment. For emergency warning signs: ${ref.watch(publicAppSettingsProvider).value?.emergencyHelpText ?? 'Contact your local emergency services or go to the nearest emergency department.'}',
          ),
        ),
        const SizedBox(height: 18),
        _StepActions(
          onBack: intake.busy ? null : () => setState(() => _step = 1),
          onNext: _preferredStart == null || intake.busy
              ? null
              : _submitRequest,
          nextLabel: intake.busy ? 'Sending code...' : 'Verify email',
        ),
      ],
    ),
  );

  void _saveContact() {
    if (!(_contactFormKey.currentState?.validate() ?? false)) return;
    try {
      ref
          .read(guestConsultationProvider.notifier)
          .saveContact(
            email: _emailController.text,
            concern: _concernController.text,
            privacyAccepted: _privacyAccepted,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            birthDate: _birthDate,
            sex: _sex ?? '',
            mobileNumber: _mobileController.text,
            address: _addressController.text,
            symptomDuration: _durationController.text,
          );
      setState(() => _step = 1);
    } catch (error) {
      showRootMessage(userFacingRepositoryError(error));
    }
  }

  void _saveCare() {
    if (!(_careFormKey.currentState?.validate() ?? false)) return;
    try {
      ref
          .read(guestConsultationProvider.notifier)
          .saveCareSelection(
            hospitalId: _hospitalId!,
            departmentLabel: _departmentLabel!,
            careMode: _careMode,
          );
      setState(() => _step = 2);
    } catch (error) {
      showRootMessage(userFacingRepositoryError(error));
    }
  }

  Future<void> _chooseSchedule() async {
    final minimum = DateTime.now().add(reservationMinimumLeadTime);
    final value = await requestRootDateTime(
      initial: _preferredStart ?? minimum.add(const Duration(days: 1)),
      minimum: minimum,
    );
    if (value == null) return;
    try {
      ref.read(guestConsultationProvider.notifier).saveSchedule(value);
      setState(() => _preferredStart = value);
    } catch (error) {
      showRootMessage(userFacingRepositoryError(error));
    }
  }

  Future<void> _submitRequest() async {
    if (_preferredStart == null) return;
    try {
      await ref
          .read(guestConsultationProvider.notifier)
          .beginVerificationFlow();
      if (!mounted) return;
      showRootMessage('A verification code was sent to your email.');
      context.go('/consultation/verify');
    } catch (error) {
      if (mounted) showRootMessage(userFacingRepositoryError(error));
    }
  }
}

class _ConsultationUnavailableScreen extends StatelessWidget {
  const _ConsultationUnavailableScreen();

  @override
  Widget build(BuildContext context) => const _ConsultationStateScreen(
    icon: Icons.cloud_off_outlined,
    title: 'Consultation service unavailable',
    message:
        'The consultation service is not configured. No request data will be submitted until it is available.',
  );
}

class _ConsultationStateScreen extends StatelessWidget {
  const _ConsultationStateScreen({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => PublicScaffold(
    currentLocation: '/consultation/request',
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
              action: onRetry == null
                  ? null
                  : OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ExistingIntakeScreen extends ConsumerWidget {
  const _ExistingIntakeScreen({required this.status});

  final GuestRequestStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PublicScaffold(
    currentLocation: '/consultation/request',
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ContentPanel(
            child: DataState(
              icon: status == GuestRequestStatus.submitted
                  ? Icons.task_alt_outlined
                  : Icons.mark_email_unread_outlined,
              title: status == GuestRequestStatus.submitted
                  ? 'Consultation request submitted'
                  : 'Email verification pending',
              message: 'Continue the current request or start a new one.',
              action: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => context.go(
                      status == GuestRequestStatus.submitted
                          ? '/consultation/confirmation/${ref.read(guestConsultationProvider).requestId}'
                          : '/consultation/verify',
                    ),
                    child: const Text('Continue current request'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      ref.read(guestConsultationProvider.notifier).reset();
                    },
                    child: const Text('Start over'),
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

class _IntakeProgress extends StatelessWidget {
  const _IntakeProgress({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const labels = ['Identity', 'Care', 'Schedule'];
    return Semantics(
      label: 'Consultation intake step ${currentStep + 1} of 3',
      value: '${labels[currentStep]}, ${currentStep + 1} of 3',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (var index = 0; index < labels.length; index++) ...[
                  Expanded(
                    child: AnimatedContainer(
                      key: ValueKey('intake-progress-segment-$index'),
                      duration: const Duration(milliseconds: 200),
                      height: 4,
                      decoration: BoxDecoration(
                        color: index <= currentStep
                            ? AppColors.primary
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(AppRadius.compact),
                      ),
                    ),
                  ),
                  if (index < labels.length - 1)
                    const SizedBox(width: AppSpacing.x1),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < labels.length; index++)
                Expanded(
                  child: _IntakeStepLabel(
                    number: index + 1,
                    label: labels[index],
                    completed: index < currentStep,
                    active: index == currentStep,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntakeStepLabel extends StatelessWidget {
  const _IntakeStepLabel({
    required this.number,
    required this.label,
    required this.completed,
    required this.active,
  });

  final int number;
  final String label;
  final bool completed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final highlighted = completed || active;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: highlighted ? AppColors.primary : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: highlighted ? AppColors.primary : AppColors.border,
            ),
          ),
          child: completed
              ? const Icon(
                  Icons.check,
                  size: 14,
                  color: AppColors.primaryForeground,
                )
              : Text(
                  '$number',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: highlighted
                        ? AppColors.primaryForeground
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.x2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: highlighted ? AppColors.primary : AppColors.textMuted,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepActions extends StatelessWidget {
  const _StepActions({
    this.onBack,
    required this.onNext,
    required this.nextLabel,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: 10,
    runSpacing: 10,
    children: [
      if (onBack != null)
        OutlinedButton(onPressed: onBack, child: const Text('Back')),
      FilledButton(onPressed: onNext, child: Text(nextLabel)),
    ],
  );
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Text(value.isEmpty ? 'Not provided' : value)),
      ],
    ),
  );
}
