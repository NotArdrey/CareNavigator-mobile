import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth/user_role.dart';
import '../../providers/core_providers.dart';
import '../../repositories/profile_repository.dart';
import '../../routing/root_overlay.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/data_display/content_panel.dart';
import '../../widgets/forms/patient_details_fields.dart';
import '../../widgets/layout/page_header.dart';

class LiveProfileView extends ConsumerStatefulWidget {
  const LiveProfileView({super.key, required this.role});

  final UserRole role;

  @override
  ConsumerState<LiveProfileView> createState() => _LiveProfileViewState();
}

class _LiveProfileViewState extends ConsumerState<LiveProfileView> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _emailAddress = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  final _bloodType = TextEditingController();
  final _emergencyContact = TextEditingController();
  final _allergies = TextEditingController();
  final _conditions = TextEditingController();
  CareProfile? _profile;
  DateTime? _birthDate;
  String? _sex;
  bool _consultations = true;
  bool _appointments = true;
  bool _results = true;
  bool _prescriptions = true;
  bool _messages = true;
  bool _hospitalAlerts = true;
  bool _email = false;
  bool _inApp = true;
  bool _saving = false;
  XFile? _selectedImage;
  List<int>? _selectedImageBytes;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _emailAddress.dispose();
    _mobile.dispose();
    _address.dispose();
    _bloodType.dispose();
    _emergencyContact.dispose();
    _allergies.dispose();
    _conditions.dispose();
    super.dispose();
  }

  void _adopt(CareProfile profile) {
    if (_profile?.userId == profile.userId) return;
    _profile = profile;
    _firstName.text = profile.firstName;
    _lastName.text = profile.lastName;
    _emailAddress.text = profile.email ?? '';
    _mobile.text = profile.mobileNumber ?? '';
    _address.text = profile.address ?? '';
    _bloodType.text = profile.bloodType ?? '';
    _emergencyContact.text = profile.emergencyContact ?? '';
    _allergies.text = profile.allergies ?? '';
    _conditions.text = profile.existingConditions ?? '';
    _birthDate = profile.birthDate;
    _sex = profile.sex;
    final preferences = profile.preferences;
    _consultations = preferences.consultationUpdates;
    _appointments = preferences.appointmentReminders;
    _results = preferences.medicalResults;
    _prescriptions = preferences.prescriptions;
    _messages = preferences.messages;
    _hospitalAlerts = preferences.hospitalAlerts;
    _email = preferences.emailEnabled;
    _inApp = preferences.inAppEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(careProfileProvider);
    return profile.when(
      loading: () => const DataState(
        icon: Icons.person_outline,
        title: 'Loading your profile',
        message: 'Retrieving your private account and preference settings.',
        action: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
      error: (error, _) => DataState(
        icon: Icons.person_off_outlined,
        title: 'Profile unavailable',
        message: _profileErrorMessage(error),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(careProfileProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ),
      data: (value) {
        _adopt(value);
        return _buildForm(context, value);
      },
    );
  }

  Widget _buildForm(BuildContext context, CareProfile profile) {
    final patient = profile.patientId != null;
    final width = MediaQuery.sizeOf(context).width;
    final mobileLayout = width < 960;
    final horizontalPadding = width < 600
        ? 16.0
        : width < 1000
        ? 24.0
        : 32.0;
    return SingleChildScrollView(
      child: PageContent(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          24,
          horizontalPadding,
          mobileLayout ? 96 : 40,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Profile & preferences',
                description:
                    'Maintain your live account details and opt-in notification channels.',
                descriptionSpacing: AppSpacing.x1,
              ),
              const SizedBox(height: AppSpacing.x4),
              _ProfileHeader(
                imageUrl: profile.profileImageUrl,
                selectedImage: _selectedImage,
                selectedBytes: _selectedImageBytes,
                name: _displayName(profile),
                email: profile.email,
                enabled: !_saving,
                onPick: _pickProfileImage,
              ),
              const SizedBox(height: AppSpacing.x4),
              ContentPanel(
                title: 'Account details',
                subtitle:
                    'Keep these patient details current so registration, consultation, and checkup records stay aligned.',
                child: PatientDetailsFields(
                  firstNameController: _firstName,
                  lastNameController: _lastName,
                  mobileController: _mobile,
                  addressController: _address,
                  emailController: _emailAddress,
                  birthDate: _birthDate,
                  sex: _sex,
                  requiredFields: false,
                  emailEnabled: false,
                  fieldSpacing: AppSpacing.x3,
                  consistentDateField: true,
                  onBirthDateChanged: (value) =>
                      setState(() => _birthDate = value),
                  onSexChanged: (value) => setState(() => _sex = value),
                ),
              ),
              if (profile.doctorDisplayName != null) ...[
                const SizedBox(height: AppSpacing.x4),
                ContentPanel(
                  title: 'Clinical credentials',
                  subtitle:
                      'Hospital administrators manage credentialed doctor fields.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ReadOnlyProfileLine(
                        label: 'Display name',
                        value: profile.doctorDisplayName!,
                      ),
                      const Divider(),
                      _ReadOnlyProfileLine(
                        label: 'Specialization',
                        value: profile.specialization ?? 'Not set',
                      ),
                      const Divider(),
                      _ReadOnlyProfileLine(
                        label: 'License number',
                        value: profile.licenseNumber ?? 'Not set',
                      ),
                    ],
                  ),
                ),
              ],
              if (patient) ...[
                const SizedBox(height: AppSpacing.x4),
                ContentPanel(
                  title: 'Health profile',
                  subtitle:
                      'Patient-entered context supports care navigation; clinicians verify official records.',
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _bloodType,
                        decoration: const InputDecoration(
                          labelText: 'Blood type',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x3),
                      TextFormField(
                        controller: _emergencyContact,
                        decoration: const InputDecoration(
                          labelText: 'Emergency contact',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x3),
                      TextFormField(
                        controller: _allergies,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Known allergies',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x3),
                      TextFormField(
                        controller: _conditions,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Existing conditions',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.x4),
              ContentPanel(
                title: 'Notification preferences',
                subtitle:
                    'In-app notifications are private. Email delivery occurs only when explicitly enabled.',
                child: Column(
                  children: [
                    _switch('In-app notifications', _inApp, (v) => _inApp = v),
                    _switch('Email notifications', _email, (v) => _email = v),
                    const Divider(),
                    _switch(
                      'Consultation updates',
                      _consultations,
                      (v) => _consultations = v,
                    ),
                    _switch(
                      'Appointment reminders',
                      _appointments,
                      (v) => _appointments = v,
                    ),
                    _switch('Medical results', _results, (v) => _results = v),
                    _switch(
                      'Prescriptions',
                      _prescriptions,
                      (v) => _prescriptions = v,
                    ),
                    _switch('Messages', _messages, (v) => _messages = v),
                    _switch(
                      'Hospital alerts',
                      _hospitalAlerts,
                      (v) => _hospitalAlerts = v,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              Align(alignment: Alignment.centerRight, child: _saveButton()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> update) =>
      SwitchListTile(
        value: value,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        onChanged: _saving ? null : (next) => setState(() => update(next)),
      );

  Widget _saveButton() => FilledButton.icon(
    onPressed: _saving ? null : _save,
    icon: _saving
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryForeground,
            ),
          )
        : const Icon(Icons.save_outlined),
    label: const Text('Save changes'),
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final profile = _profile;
    final repository = ref.read(profileRepositoryProvider);
    if (profile == null || repository == null) return;
    setState(() => _saving = true);
    try {
      await repository.updateProfile(
        CareProfileUpdate(
          firstName: _firstName.text,
          lastName: _lastName.text,
          mobileNumber: _mobile.text,
          birthDate: _birthDate,
          sex: _sex,
          address: _address.text,
          patientId: profile.patientId,
          bloodType: _bloodType.text,
          emergencyContact: _emergencyContact.text,
          allergies: _allergies.text,
          existingConditions: _conditions.text,
        ),
      );
      if (_selectedImageBytes != null && _selectedImage != null) {
        await repository.updateProfileImage(
          bytes: _selectedImageBytes!,
          fileName: _selectedImage!.name,
        );
      }
      await repository.updateNotificationPreferences(
        NotificationPreferenceUpdate(
          consultationUpdates: _consultations,
          appointmentReminders: _appointments,
          medicalResults: _results,
          prescriptions: _prescriptions,
          messages: _messages,
          hospitalAlerts: _hospitalAlerts,
          emailEnabled: _email,
          inAppEnabled: _inApp,
        ),
      );
      _profile = null;
      ref.invalidate(careProfileProvider);
      showRootMessage('Profile and notification preferences saved.');
    } catch (error) {
      showRootMessage(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickProfileImage() async {
    const imageTypes = XTypeGroup(
      label: 'Profile images',
      extensions: ['jpg', 'jpeg', 'png'],
    );
    final selected = await openFile(acceptedTypeGroups: const [imageTypes]);
    if (selected == null) return;
    final bytes = await selected.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 5 * 1024 * 1024) {
      showRootMessage('Choose an image smaller than 5 MB.');
      return;
    }
    setState(() {
      _selectedImage = selected;
      _selectedImageBytes = bytes;
    });
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.imageUrl,
    required this.selectedImage,
    required this.selectedBytes,
    required this.name,
    required this.email,
    required this.enabled,
    required this.onPick,
  });

  final String? imageUrl;
  final XFile? selectedImage;
  final List<int>? selectedBytes;
  final String name;
  final String? email;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final image = selectedBytes != null
        ? Image.memory(Uint8List.fromList(selectedBytes!), fit: BoxFit.cover)
        : imageUrl == null
        ? null
        : Image.network(imageUrl!, fit: BoxFit.cover);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 42,
          backgroundColor: AppColors.surfaceMuted,
          child: ClipOval(
            child: SizedBox.square(
              dimension: 84,
              child:
                  image ??
                  Center(
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Your profile' : name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                email?.trim().isNotEmpty == true
                    ? email!.trim()
                    : 'Email address not available',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.x2),
              OutlinedButton.icon(
                onPressed: enabled ? onPick : null,
                icon: const Icon(Icons.upload_outlined),
                label: Text(
                  selectedImage != null || imageUrl != null
                      ? 'Change photo'
                      : 'Choose photo',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _displayName(CareProfile profile) {
  final name = '${profile.firstName} ${profile.lastName}'.trim();
  return name.isEmpty ? (profile.doctorDisplayName ?? '') : name;
}

String _profileErrorMessage(Object error) {
  final detail = error.toString().toLowerCase();
  if (detail.contains('jsonmap') || detail.contains('subtype of type')) {
    return 'Some profile details need to be refreshed. Please retry.';
  }
  return 'We could not load your profile right now. Please try again.';
}

class _ReadOnlyProfileLine extends StatelessWidget {
  const _ReadOnlyProfileLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
