import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/core_providers.dart';

enum LegalDocument { terms, privacy }

class LegalPolicyDialog extends ConsumerWidget {
  const LegalPolicyDialog({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = _documents[document]!;
    final emergencyGuidance =
        ref.watch(publicAppSettingsProvider).value?.emergencyHelpText ??
        'contact your local emergency services or go to the nearest emergency department.';
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(620.0, math.max(0.0, viewport.width - 64));

    return AlertDialog(
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            data.icon,
            color: Theme.of(context).colorScheme.primary,
            semanticLabel: data.title,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(data.title)),
        ],
      ),
      content: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(620.0, viewport.height * 0.68),
          ),
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    data.summary,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  for (
                    var index = 0;
                    index < data.sections.length;
                    index++
                  ) ...[
                    if (index > 0) const Divider(height: 28),
                    _PolicySectionView(
                      section: data.sections[index],
                      emergencyGuidance: emergencyGuidance,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PolicySectionView extends StatelessWidget {
  const _PolicySectionView({
    required this.section,
    required this.emergencyGuidance,
  });

  final _PolicySection section;
  final String emergencyGuidance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          section.title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (section.body.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            section.body.replaceAll('{emergency_guidance}', emergencyGuidance),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
        if (section.bullets.isNotEmpty) ...[
          if (section.body.isNotEmpty) const SizedBox(height: 8),
          for (final bullet in section.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 10),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: theme.colorScheme.primary,
                      semanticLabel: 'Bullet',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      bullet,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _PolicyDocument {
  const _PolicyDocument({
    required this.title,
    required this.icon,
    required this.summary,
    required this.sections,
  });

  final String title;
  final IconData icon;
  final String summary;
  final List<_PolicySection> sections;
}

class _PolicySection {
  const _PolicySection({
    required this.title,
    this.body = '',
    this.bullets = const [],
  });

  final String title;
  final String body;
  final List<String> bullets;
}

const _documents = <LegalDocument, _PolicyDocument>{
  LegalDocument.terms: _PolicyDocument(
    title: 'Terms and Conditions',
    icon: Icons.description_outlined,
    summary:
        'Please read these terms before creating a CareNavigator PH account. They explain how the service may be used and what to expect from its care-navigation features.',
    sections: [
      _PolicySection(
        title: 'Service scope',
        body:
            'CareNavigator PH helps people find verified care facilities, request consultations, manage care-related information, and communicate with authorized care teams. Features and availability may vary by account role, facility, and region.',
      ),
      _PolicySection(
        title: 'Not an emergency service',
        body:
            'CareNavigator is not a replacement for emergency services, a doctor, or an official diagnosis. If someone is in immediate danger: {emergency_guidance}',
      ),
      _PolicySection(
        title: 'Your account',
        body:
            'Provide accurate information, keep your credentials private, and tell us if you suspect unauthorized access. You are responsible for activity under your account.',
      ),
      _PolicySection(
        title: 'Consultations and health information',
        body:
            'Submitting a consultation request does not guarantee an appointment or a clinical outcome. Information is reviewed within the authorized care workflow. By submitting information, you authorize its use for the requested care and agree to the Privacy Policy.',
      ),
      _PolicySection(
        title: 'Acceptable use',
        body:
            'Do not misuse the service, impersonate another person, upload malicious content, attempt to access another person’s records, or interfere with security or availability.',
      ),
      _PolicySection(
        title: 'Availability and changes',
        body:
            'We may update, suspend, or retire features to maintain safety, security, or operations. We will present important changes in the app where appropriate.',
      ),
    ],
  ),
  LegalDocument.privacy: _PolicyDocument(
    title: 'Privacy Policy',
    icon: Icons.privacy_tip_outlined,
    summary:
        'This policy explains what information CareNavigator PH may handle when you use the service and how that information supports care navigation and account security.',
    sections: [
      _PolicySection(
        title: 'Information we collect',
        bullets: [
          'Account and profile information, such as your name, email address, role, authentication details, and preferences.',
          'Care information, such as consultation details, symptoms, appointments, messages, files, prescriptions, and laboratory requests when those features are enabled for authorized users.',
          'Technical and usage information needed to protect the service, diagnose problems, and keep the app reliable.',
        ],
      ),
      _PolicySection(
        title: 'How we use information',
        bullets: [
          'Create and manage your account and provide the features you request.',
          'Route consultation requests, support reservations, and deliver authorized care-workspace functions.',
          'Protect security, prevent abuse, audit important changes, and resolve service problems.',
          'Send verification, service, and operational notifications when needed.',
          'Maintain and improve the service.',
        ],
      ),
      _PolicySection(
        title: 'When information is shared',
        body:
            'We share information only as needed for the requested care workflow, such as with authorized clinicians, staff, and facilities connected to a consultation or care relationship. We may use infrastructure and service providers to operate the platform under appropriate safeguards, and may disclose information when required by law or to protect safety and rights. We do not sell personal health information.',
      ),
      _PolicySection(
        title: 'Storage and security',
        body:
            'Data is transmitted using secure connections and access is restricted by account role, care relationship, and server-side authorization. No online system is completely risk-free, so keep your credentials private and report suspected unauthorized access promptly.',
      ),
      _PolicySection(
        title: 'Your choices and rights',
        body:
            'You may review or correct available profile information and may ask for help with access, correction, or deletion of information. Some records may need to be retained for legal, safety, audit, or care reasons.',
      ),
      _PolicySection(
        title: 'Policy updates',
        body:
            'We may update this policy when the service or legal requirements change. The current version is available from the registration flow, and important changes will be presented in the app where appropriate.',
      ),
    ],
  ),
};
