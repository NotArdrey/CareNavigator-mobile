import 'dart:typed_data';

import 'package:care_navigator_ph/src/models/guest_consultation_draft.dart';
import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/repositories/consultation_repository.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class GuestConsultationScreen extends ConsumerStatefulWidget {
  const GuestConsultationScreen({this.initialHospitalId, super.key});

  final String? initialHospitalId;

  @override
  ConsumerState<GuestConsultationScreen> createState() =>
      _GuestConsultationScreenState();
}

class _GuestConsultationScreenState
    extends ConsumerState<GuestConsultationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(text: '+63');
  final _otpController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _durationController = TextEditingController();
  final _reasonController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _medicationsController = TextEditingController();

  bool _otpSent = false;
  bool _working = false;
  bool _locating = false;
  String _sex = 'prefer_not_to_say';
  DateTime? _birthDate;
  DateTime? _preferredSchedule;
  String? _hospitalId;
  String? _departmentId;
  List<Map<String, dynamic>> _departments = const [];
  Position? _position;
  PlatformFile? _identification;
  GuestConsultationSubmission? _submission;

  @override
  void initState() {
    super.initState();
    _emailController.text =
        ref.read(authRepositoryProvider).currentSession?.user.email ?? '';
    _hospitalId = widget.initialHospitalId;
    if (_hospitalId != null) {
      Future<void>.microtask(() => _loadDepartments(_hospitalId));
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _phoneController,
      _otpController,
      _fullNameController,
      _emailController,
      _addressController,
      _symptomsController,
      _durationController,
      _reasonController,
      _conditionsController,
      _allergiesController,
      _medicationsController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_validEmail(_emailController.text)) {
      _showError('Enter a valid email address.');
      return;
    }
    setState(() => _working = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .sendEmailOtp(_emailController.text);
      if (mounted) {
        setState(() => _otpSent = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification code sent.')),
        );
      }
    } catch (error) {
      _showError(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verifyOtp() async {
    final codeLength = _otpController.text.trim().length;
    if (codeLength < 6 || codeLength > 8) {
      _showError('Enter the 6–8 digit verification code.');
      return;
    }
    setState(() => _working = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyEmailOtp(
            email: _emailController.text,
            token: _otpController.text,
          );
      ref.invalidate(currentProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified. Complete your request.'),
          ),
        );
      }
    } catch (error) {
      _showError(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select birth date',
    );
    if (selected != null && mounted) setState(() => _birthDate = selected);
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 120)),
      helpText: 'Preferred consultation date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Preferred consultation time',
    );
    if (time != null && mounted) {
      setState(
        () => _preferredSchedule = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _pickIdentification() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result?.files.singleOrNull case final file?) {
      if (file.size > 10 * 1024 * 1024) {
        _showError('Identification must be 10 MB or smaller.');
        return;
      }
      if (file.bytes == null) {
        _showError('The selected file could not be read.');
        return;
      }
      setState(() => _identification = file);
    }
  }

  Future<void> _loadDepartments(String? hospitalId) async {
    if (hospitalId == null) {
      if (mounted) {
        setState(() {
          _departments = const [];
          _departmentId = null;
        });
      }
      return;
    }
    try {
      final rows = await ref
          .read(supabaseClientProvider)
          .from('hospital_departments')
          .select('id, department_name, availability_status')
          .eq('hospital_id', hospitalId)
          .neq('availability_status', 'unavailable')
          .order('department_name');
      if (!mounted || _hospitalId != hospitalId) return;
      setState(() {
        _departments = (rows as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        if (!_departments.any((item) => item['id'] == _departmentId)) {
          _departmentId = null;
        }
      });
    } catch (error) {
      if (mounted) _showError('Could not load hospital departments: $error');
    }
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are turned off.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) setState(() => _position = position);
    } catch (error) {
      _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool get _hasEmergencyWarning => RegExp(
    r'severe (difficulty|trouble) breathing|chest pain|loss of consciousness|unconscious|severe bleeding|heavy bleeding|face droop|slurred speech|stroke|seizure|anaphylaxis|severe allergic reaction',
    caseSensitive: false,
  ).hasMatch(_symptomsController.text);

  Future<bool> _acknowledgeEmergency() async {
    if (!_hasEmergencyWarning) return true;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.emergency_rounded,
          color: AppColors.danger,
          size: 44,
        ),
        title: const Text('Seek emergency care now'),
        content: const Text(
          'Your symptoms include a potentially life-threatening warning sign. Call 911 or go to the nearest emergency room now. Do not wait for online consultation approval.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await launchUrl(Uri(scheme: 'tel', path: '911'));
            },
            child: const Text('Call 911'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context, false);
              context.go('/hospitals/map?emergency=1');
            },
            child: const Text('Find an ER'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Also submit request'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      _showError('Select your birth date.');
      return;
    }
    if (_identification?.bytes == null) {
      _showError('Attach a valid identification document.');
      return;
    }
    if (_hospitalId == null) {
      _showError('Select the hospital that should review this request.');
      return;
    }
    if (!await _acknowledgeEmergency()) return;
    setState(() => _working = true);
    String? uploadedPath;
    try {
      final repository = ref.read(consultationRepositoryProvider);
      uploadedPath = await repository.uploadGuestIdentification(
        bytes: _identification!.bytes as Uint8List,
        fileName: _identification!.name,
        mimeType: _mimeType(_identification!.extension),
      );
      final draft = GuestConsultationDraft(
        fullName: _fullNameController.text,
        birthDate: _birthDate!,
        sex: _sex,
        mobileNumber: _phoneController.text,
        email: _emailController.text,
        address: _addressController.text,
        symptoms: _symptomsController.text,
        symptomDuration: _durationController.text,
        consultationReason: _reasonController.text,
        existingConditions: _csv(_conditionsController.text),
        allergies: _csv(_allergiesController.text),
        currentMedications: _csv(_medicationsController.text),
        preferredHospitalId: _hospitalId,
        preferredDepartmentId: _departmentId,
        preferredSchedule: _preferredSchedule,
        latitude: _position?.latitude,
        longitude: _position?.longitude,
        identificationFilePath: uploadedPath,
      );
      final submission = await repository.submitGuestRequest(draft);
      if (mounted) setState(() => _submission = submission);
    } catch (error) {
      if (uploadedPath != null) {
        try {
          await ref
              .read(consultationRepositoryProvider)
              .deleteGuestIdentification(uploadedPath);
        } catch (_) {
          // Storage lifecycle cleanup also removes abandoned guest uploads.
        }
      }
      _showError(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_submission != null) {
      return _Success(submission: _submission!);
    }

    ref.watch(authStateProvider);
    final isVerified = ref.read(authRepositoryProvider).hasVerifiedEmail;
    if (isVerified && _emailController.text.trim().isEmpty) {
      _emailController.text =
          ref.read(authRepositoryProvider).currentSession?.user.email ?? '';
    }
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 600 ? 20.0 : 40.0;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 26, horizontal, 14),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'First-time online consultation',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Verify your email, tell us what you need, and receive a tracking reference.',
                  ),
                  const SizedBox(height: 18),
                  const _MedicalSafetyNotice(),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 40),
            sliver: SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: isVerified ? _requestForm() : _verificationCard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verificationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _StepNumber(number: 1),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Verify your email address',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _emailController,
              enabled: !_otpSent && !_working,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _otpController,
                enabled: !_working,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: '6–8 digit verification code',
                  prefixIcon: Icon(Icons.password_rounded),
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _working ? null : (_otpSent ? _verifyOtp : _sendOtp),
              icon: _working
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _otpSent ? Icons.verified_rounded : Icons.email_rounded,
                    ),
              label: Text(_otpSent ? 'Verify code' : 'Send verification code'),
            ),
            if (_otpSent)
              TextButton(
                onPressed: _working
                    ? null
                    : () => setState(() {
                        _otpSent = false;
                        _otpController.clear();
                      }),
                child: const Text('Use a different email'),
              ),
            const SizedBox(height: 10),
            const Text(
              'The one-time code is sent to this email address.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7C91)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestForm() {
    final hospitals = ref.watch(hospitalsProvider(''));
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _FormSection(
            step: 2,
            title: 'Personal information',
            children: [
              TextFormField(
                controller: _fullNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name *'),
                validator: _required,
              ),
              OutlinedButton.icon(
                onPressed: _locating ? null : _locate,
                icon: _locating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
                label: Text(
                  _position == null
                      ? 'Attach current location (recommended)'
                      : 'Location attached · refresh',
                ),
              ),
              _FieldRow(
                children: [
                  InkWell(
                    onTap: _working ? null : _pickBirthDate,
                    borderRadius: BorderRadius.circular(14),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Birth date *',
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      child: Text(
                        _birthDate == null
                            ? 'Select date'
                            : DateFormat.yMMMd().format(_birthDate!),
                      ),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _sex,
                    decoration: const InputDecoration(labelText: 'Sex *'),
                    items: const [
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(
                        value: 'intersex',
                        child: Text('Intersex'),
                      ),
                      DropdownMenuItem(
                        value: 'prefer_not_to_say',
                        child: Text('Prefer not to say'),
                      ),
                    ],
                    onChanged: _working
                        ? null
                        : (value) => setState(() => _sex = value!),
                  ),
                ],
              ),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Mobile number *',
                  helperText: 'Used only as a contact number.',
                ),
                validator: (value) => value == null || !_validPhone(value)
                    ? 'Use an international number such as +639171234567.'
                    : null,
              ),
              TextFormField(
                controller: _emailController,
                enabled: false,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Verified email address',
                ),
              ),
              TextFormField(
                controller: _addressController,
                textCapitalization: TextCapitalization.words,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Current address *',
                ),
                validator: _required,
              ),
            ],
          ),
          _FormSection(
            step: 3,
            title: 'Health concern',
            children: [
              TextFormField(
                controller: _symptomsController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Symptoms *',
                  hintText:
                      'Describe what you are experiencing and any warning signs.',
                ),
                validator: _required,
              ),
              TextFormField(
                controller: _durationController,
                decoration: const InputDecoration(
                  labelText: 'Symptom duration *',
                  hintText: 'Example: 2 days',
                ),
                validator: _required,
              ),
              TextFormField(
                controller: _reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Consultation reason *',
                ),
                validator: _required,
              ),
              TextFormField(
                controller: _conditionsController,
                decoration: const InputDecoration(
                  labelText: 'Existing conditions',
                  hintText: 'Separate multiple entries with commas',
                ),
              ),
              TextFormField(
                controller: _allergiesController,
                decoration: const InputDecoration(
                  labelText: 'Known allergies',
                  hintText: 'Separate multiple entries with commas',
                ),
              ),
              TextFormField(
                controller: _medicationsController,
                decoration: const InputDecoration(
                  labelText: 'Current medications',
                  hintText: 'Separate multiple entries with commas',
                ),
              ),
            ],
          ),
          _FormSection(
            step: 4,
            title: 'Hospital, schedule & identity',
            children: [
              hospitals.when(
                data: (items) => DropdownButtonFormField<String?>(
                  initialValue: items.any((item) => item.id == _hospitalId)
                      ? _hospitalId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Preferred hospital *',
                  ),
                  items: [
                    for (final Hospital item in items)
                      DropdownMenuItem<String?>(
                        value: item.id,
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _working
                      ? null
                      : (value) {
                          setState(() {
                            _hospitalId = value;
                            _departmentId = null;
                          });
                          _loadDepartments(value);
                        },
                  validator: (value) => value == null
                      ? 'Select a hospital to review the request.'
                      : null,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text(
                  'Hospitals could not be loaded. Retry before submitting so the request has a reviewing hospital.',
                ),
              ),
              DropdownButtonFormField<String?>(
                initialValue:
                    _departments.any((item) => item['id'] == _departmentId)
                    ? _departmentId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Preferred department (optional)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Let the hospital assign a department'),
                  ),
                  for (final item in _departments)
                    DropdownMenuItem<String?>(
                      value: item['id']?.toString(),
                      child: Text(
                        item['department_name']?.toString() ?? 'Department',
                      ),
                    ),
                ],
                onChanged: _working || _hospitalId == null
                    ? null
                    : (value) => setState(() => _departmentId = value),
              ),
              InkWell(
                onTap: _working ? null : _pickSchedule,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Preferred schedule (optional)',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Text(
                    _preferredSchedule == null
                        ? 'Choose date and time'
                        : DateFormat.yMMMd().add_jm().format(
                            _preferredSchedule!,
                          ),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _working ? null : _pickIdentification,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(
                  _identification == null
                      ? 'Attach valid ID *'
                      : 'Selected: ${_identification!.name}',
                ),
              ),
              const Text(
                'Accepted: JPG, PNG, or PDF up to 10 MB. The file is stored in a private bucket.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7C91)),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: _working ? null : _submit,
            icon: _working
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Submit consultation request'),
          ),
        ],
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.step,
    required this.title,
    required this.children,
  });

  final int step;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StepNumber(number: step),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    ),
  );
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              children.first,
              const SizedBox(height: 14),
              children.last,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: children.first),
            const SizedBox(width: 14),
            Expanded(child: children.last),
          ],
        );
      },
    );
  }
}

class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 17,
    backgroundColor: AppColors.blue,
    foregroundColor: Colors.white,
    child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _MedicalSafetyNotice extends StatelessWidget {
  const _MedicalSafetyNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F0),
      border: Border.all(color: const Color(0xFFFFD0CC)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.emergency_rounded, color: AppColors.danger),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Do not wait for an online consultation for severe breathing difficulty, chest pain, stroke signs, heavy bleeding, seizures, or loss of consciousness. Call 911 or go to the nearest ER.',
            style: TextStyle(
              color: Color(0xFF7A211B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Success extends StatelessWidget {
  const _Success({required this.submission});

  final GuestConsultationSubmission submission;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.mint,
                  child: Icon(
                    Icons.check_rounded,
                    size: 38,
                    color: AppColors.teal,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Request received',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Keep this temporary reference number. A hospital or doctor can use it to review and track your request.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                SelectableText(
                  submission.referenceNumber,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.blue,
                    letterSpacing: 0.5,
                  ),
                ),
                if (submission.assessment case final assessment?) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: submission.isEmergency
                          ? const Color(0xFFFFE8E6)
                          : AppColors.mint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preliminary ${assessment['urgency_level'] ?? 'care'} guidance',
                          style: TextStyle(
                            color: submission.isEmergency
                                ? AppColors.danger
                                : AppColors.teal,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          assessment['recommended_action']?.toString() ??
                              'Wait for review by the selected hospital.',
                        ),
                        if (assessment['recommended_department'] != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Suggested department: ${assessment['recommended_department']}',
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          assessment['disclaimer']?.toString() ??
                              'This preliminary guidance is not a diagnosis.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                if (submission.assessmentWarning != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    submission.assessmentWarning!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF6B7C91)),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => context.go('/dashboard'),
                  child: const Text('Go to my care'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required.' : null;
bool _validPhone(String value) =>
    RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim());
bool _validEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
List<String> _csv(String value) => value
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();
String _mimeType(String? extension) => switch (extension?.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'pdf' => 'application/pdf',
  _ => 'application/octet-stream',
};
String _friendlyError(Object error) {
  final raw = error.toString();
  if (raw.contains('Error sending magic link') ||
      raw.contains('Email rate limit exceeded')) {
    return 'Email verification is temporarily unavailable. Wait a moment and try again.';
  }
  if (raw.contains('rate limit')) {
    return 'Too many attempts. Wait a moment before trying again.';
  }
  return raw
      .replaceFirst('AuthException(message: ', '')
      .split(', statusCode:')
      .first;
}
