import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/shared/patient_identity.dart';

class PatientDetailsFields extends StatelessWidget {
  const PatientDetailsFields({
    super.key,
    required this.firstNameController,
    required this.lastNameController,
    required this.mobileController,
    required this.addressController,
    required this.emailController,
    required this.birthDate,
    required this.sex,
    required this.onBirthDateChanged,
    required this.onSexChanged,
    this.requiredFields = true,
    this.requiredNameFields = true,
    this.emailEnabled = true,
    this.fieldSpacing = 16,
    this.consistentDateField = false,
    this.stackNameFields = false,
    this.multilineAddress = true,
  });

  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController mobileController;
  final TextEditingController addressController;
  final TextEditingController emailController;
  final DateTime? birthDate;
  final String? sex;
  final ValueChanged<DateTime> onBirthDateChanged;
  final ValueChanged<String?> onSexChanged;
  final bool requiredFields;
  final bool requiredNameFields;
  final bool emailEnabled;
  final double fieldSpacing;
  final bool consistentDateField;
  final bool stackNameFields;
  final bool multilineAddress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _nameFields(),
        SizedBox(height: fieldSpacing),
        _birthDateField(context),
        SizedBox(height: fieldSpacing),
        DropdownButtonFormField<String>(
          initialValue: sex,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Sex',
            hintText: 'Select your sex',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          items: [
            for (final option in patientSexOptions)
              DropdownMenuItem(value: option.value, child: Text(option.label)),
          ],
          validator: (value) =>
              requiredFields && value == null ? 'Select one option.' : null,
          onChanged: onSexChanged,
        ),
        SizedBox(height: fieldSpacing),
        TextFormField(
          controller: mobileController,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            hintText: '09XX XXX XXXX',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          validator: (value) {
            if (!requiredFields && (value?.trim().isEmpty ?? true)) {
              return null;
            }
            return validateMobileNumber(value);
          },
        ),
        SizedBox(height: fieldSpacing),
        TextFormField(
          controller: addressController,
          minLines: multilineAddress ? 2 : 1,
          maxLines: multilineAddress ? 4 : 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: multilineAddress
              ? const InputDecoration(
                  labelText: 'Home address',
                  hintText: 'House no., Street, Barangay, City, Province',
                  prefixIcon: Align(
                    alignment: Alignment.topCenter,
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Icon(Icons.home_outlined),
                    ),
                  ),
                  alignLabelWithHint: true,
                )
              : const InputDecoration(
                  labelText: 'Home address',
                  hintText: 'House no., Street, Barangay, City, Province',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
          validator: (value) {
            if (!requiredFields && (value?.trim().isEmpty ?? true)) {
              return null;
            }
            return validateHomeAddress(value);
          },
        ),
        SizedBox(height: fieldSpacing),
        TextFormField(
          controller: emailController,
          enabled: emailEnabled,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'Enter your email address',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          validator: (value) {
            if (!requiredFields && (value?.trim().isEmpty ?? true)) {
              return null;
            }
            return validateEmailAddress(value);
          },
        ),
      ],
    );
  }

  Widget _nameFields() => LayoutBuilder(
    builder: (context, constraints) {
      final firstName = TextFormField(
        controller: firstNameController,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.givenName],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'First name',
          hintText: 'Enter your first name',
          prefixIcon: Icon(Icons.person_outline),
        ),
        validator: (value) {
          if (!requiredNameFields && (value?.trim().isEmpty ?? true)) {
            return null;
          }
          return validatePatientName(value, label: 'first name');
        },
      );
      final lastName = TextFormField(
        controller: lastNameController,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.familyName],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Last name',
          hintText: 'Enter your last name',
          prefixIcon: Icon(Icons.person_outline),
        ),
        validator: (value) {
          if (!requiredNameFields && (value?.trim().isEmpty ?? true)) {
            return null;
          }
          return validatePatientName(value, label: 'last name');
        },
      );

      if (stackNameFields || constraints.maxWidth < 400) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            firstName,
            SizedBox(height: fieldSpacing),
            lastName,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: firstName),
          SizedBox(width: fieldSpacing),
          Expanded(child: lastName),
        ],
      );
    },
  );

  Widget _birthDateField(BuildContext context) => consistentDateField
      ? _consistentBirthDateField(context)
      : FormField<DateTime>(
          key: ValueKey(birthDate?.toIso8601String()),
          initialValue: birthDate,
          validator: (value) =>
              requiredFields ? validateBirthDate(value) : null,
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final today = DateTime.now();
                  final selected = await showDatePicker(
                    context: context,
                    useRootNavigator: true,
                    initialDate: birthDate ?? DateTime(today.year - 30, 1, 1),
                    firstDate: DateTime(1900),
                    lastDate: today,
                    helpText: 'Select birth date',
                  );
                  if (selected == null) return;
                  onBirthDateChanged(selected);
                  field.didChange(selected);
                },
                icon: const Icon(Icons.cake_outlined),
                label: Text(
                  birthDate == null
                      ? 'Select date of birth'
                      : DateFormat('MMM d, y').format(birthDate!),
                ),
              ),
              if (field.errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
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
        );

  Widget _consistentBirthDateField(BuildContext context) => TextFormField(
    key: ValueKey(birthDate?.toIso8601String()),
    initialValue: birthDate == null
        ? null
        : DateFormat('MMM d, y').format(birthDate!),
    readOnly: true,
    showCursor: false,
    enableInteractiveSelection: false,
    validator: (_) => requiredFields ? validateBirthDate(birthDate) : null,
    onTap: () async {
      final today = DateTime.now();
      final selected = await showDatePicker(
        context: context,
        useRootNavigator: true,
        initialDate: birthDate ?? DateTime(today.year - 30, 1, 1),
        firstDate: DateTime(1900),
        lastDate: today,
        helpText: 'Select birth date',
      );
      if (selected != null) onBirthDateChanged(selected);
    },
    decoration: const InputDecoration(
      labelText: 'Birth date',
      hintText: 'Select date of birth',
      prefixIcon: Icon(Icons.cake_outlined),
      suffixIcon: Icon(Icons.calendar_today_outlined),
    ),
  );
}
