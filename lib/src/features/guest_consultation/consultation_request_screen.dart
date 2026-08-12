import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/hospitals/hospital_models.dart';
import '../../models/guest_consultation_models.dart';
import '../../providers/guest_consultation_provider.dart';
import '../../providers/hospital_directory_provider.dart';
import '../../providers/core_providers.dart';
import '../../routing/root_overlay.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_shell/public_scaffold.dart';
import '../../widgets/data_display/content_panel.dart';
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
  final _careFormKey = GlobalKey<FormState>();
  var _step = 0;
  String? _hospitalId;
  String? _departmentLabel;
  var _careMode = GuestCareMode.inPerson;
  DateTime? _preferredStart;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _hospitalId = widget.initialHospitalId;
  }

  @override
  Widget build(BuildContext context) {
    final intake = ref.watch(guestConsultationProvider);
    final directory = ref.watch(hospitalDirectoryProvider);
    if (intake.status != GuestRequestStatus.drafting) {
      return _ExistingIntakeScreen(status: intake.status);
    }
    if (ref.watch(careRepositoryProvider) == null) {
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
    if (_hospitalId != null && selectedHospital == null) {
      _hospitalId = null;
      _departmentLabel = null;
    }
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
                    'Step ${_step + 1} of 2. Complete a consultation request.',
              ),
              const SizedBox(height: 14),
              _IntakeProgress(currentStep: _step),
              const SizedBox(height: 18),
              switch (_step) {
                0 => _careStep(directory.entries, selectedHospital),
                _ => _scheduleStep(selectedHospital),
              },
            ],
          ),
        ),
      ),
    );
  }

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
            decoration: InputDecoration(
              labelText: 'Hospital',
              prefixIcon: const Icon(Icons.local_hospital_outlined),
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
                    !(hospital?.services.contains('Online consultation') ??
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
            decoration: InputDecoration(
              labelText: 'Department',
              prefixIcon: const Icon(Icons.account_tree_outlined),
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
            onBack: () => context.go('/hospitals'),
            onNext: _saveCare,
            nextLabel: 'Choose schedule',
          ),
        ],
      ),
    ),
  );

  Widget _scheduleStep(HospitalDirectoryEntry? hospital) => ContentPanel(
    title: 'Preferred schedule and review',
    subtitle:
        'A preference is not a booking. Production scheduling requires an available published doctor slot.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _chooseSchedule,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            _preferredStart == null
                ? 'Choose preferred date and time'
                : DateFormat('MMM d, y • h:mm a').format(_preferredStart!),
          ),
        ),
        const SizedBox(height: 18),
        Consumer(
          builder: (context, ref, child) {
            final profile = ref.watch(careProfileProvider).value;
            final name = profile != null
                ? '${profile.firstName} ${profile.lastName}'.trim()
                : 'Not available';
            return _ReviewLine(label: 'Patient name', value: name);
          },
        ),
        _ReviewLine(label: 'Hospital', value: hospital?.name ?? 'Not selected'),
        _ReviewLine(
          label: 'Department',
          value: _departmentLabel ?? 'Not selected',
        ),
        _ReviewLine(
          label: 'Mode',
          value: _careMode == GuestCareMode.online
              ? 'Online preference'
              : 'In-person preference',
        ),
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
          onBack: _submitting ? null : () => setState(() => _step = 0),
          onNext: _preferredStart == null || _submitting
              ? null
              : _submitRequest,
          nextLabel: _submitting ? 'Submitting...' : 'Submit request',
        ),
      ],
    ),
  );

  void _saveCare() {
    if (!(_careFormKey.currentState?.validate() ?? false)) return;
    setState(() => _step = 1);
  }

  Future<void> _chooseSchedule() async {
    final value = await requestRootDateTime(
      initial: _preferredStart ?? DateTime.now().add(const Duration(days: 1)),
    );
    if (value != null) setState(() => _preferredStart = value);
  }

  Future<void> _submitRequest() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');

      await repository.requestConsultationAsPatient(
        hospitalId: _hospitalId!,
        departmentLabel: _departmentLabel!,
        careMode: _careMode.name,
        preferredStart: _preferredStart!,
      );

      if (!mounted) return;
      showRootMessage('Consultation requested successfully.');
      context.go('/patient/appointments');
    } catch (e) {
      if (mounted) {
        showRootMessage('Could not request consultation: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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
  Widget build(BuildContext context) => Semantics(
    label: 'Consultation intake step ${currentStep + 1} of 2',
    value: '${currentStep + 1} of 2',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: (currentStep + 1) / 2),
        const SizedBox(height: 9),
        Row(
          children: [
            for (var index = 0; index < 2; index++) ...[
              Expanded(
                child: Text(
                  const ['Care', 'Schedule'][index],
                  textAlign: index == 0 ? TextAlign.left : TextAlign.right,
                  style: TextStyle(
                    fontWeight: index == currentStep
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: index <= currentStep
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
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
        Expanded(child: Text(value)),
      ],
    ),
  );
}
