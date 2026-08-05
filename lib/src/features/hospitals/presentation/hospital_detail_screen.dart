import 'package:care_navigator_ph/src/features/hospitals/presentation/hospital_image.dart';
import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
import 'package:care_navigator_ph/src/widgets/async_value_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HospitalDetailScreen extends ConsumerWidget {
  const HospitalDetailScreen({required this.hospitalId, super.key});

  final String hospitalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hospital = ref.watch(hospitalProvider(hospitalId));
    return AsyncValuePanel<Hospital>(
      value: hospital,
      onRetry: () {
        ref.invalidate(hospitalProvider(hospitalId));
        ref.invalidate(hospitalServicesProvider(hospitalId));
      },
      data: (item) => _HospitalDetailBody(hospital: item),
    );
  }
}

class _HospitalDetailBody extends ConsumerWidget {
  const _HospitalDetailBody({required this.hospital});

  final Hospital hospital;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(hospitalServicesProvider(hospital.id));
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.medium;

    return SafeArea(
      child: Column(
        children: [
          AppPageHeader(
            eyebrow: 'Verified facility profile',
            title: 'Hospital details',
            subtitle: 'Capability, access, and service information',
            icon: AppIcons.localHospitalRounded,
            onBack: () => context.go('/hospitals'),
            backTooltip: 'Back to hospital directory',
          ),
          Expanded(
            child: ListView(
              children: [
                ResponsivePageContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HospitalHero(hospital: hospital, compact: compact),
                      const SizedBox(height: AppSpacing.xl),
                      if (compact) ...[
                        _HospitalSummary(hospital: hospital),
                        const SizedBox(height: AppSpacing.xl),
                        _details(details),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 8, child: _details(details)),
                            const SizedBox(width: AppSpacing.xl),
                            SizedBox(
                              width: 340,
                              child: _HospitalSummary(hospital: hospital),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(AsyncValue<Map<String, dynamic>> details) => details.when(
    data: (data) => Column(
      children: [
        _Section(
          title: 'About this facility',
          child: Text(
            (hospital.description?.trim().isNotEmpty ?? false)
                ? hospital.description!
                : 'This hospital has not added a public description yet.',
          ),
        ),
        _HospitalCapabilities(data: data),
      ],
    ),
    loading: () => const AppLoadingState(label: 'Loading clinical services…'),
    error: (error, stack) => AppNotice(
      icon: AppIcons.infoOutline,
      color: AppColors.warning,
      message: 'Service details are unavailable: $error',
    ),
  );
}

class _HospitalHero extends StatelessWidget {
  const _HospitalHero({required this.hospital, required this.compact});

  final Hospital hospital;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.all(compact ? AppSpacing.xl : AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AppStatusBadge(
            label: 'VERIFIED FACILITY',
            color: Color(0xFF9DD8C8),
            icon: AppIcons.verifiedRounded,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            hospital.name,
            style:
                (compact
                        ? Theme.of(context).textTheme.headlineLarge
                        : Theme.of(context).textTheme.displaySmall)
                    ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            hospital.locationLabel.isEmpty
                ? hospital.address
                : hospital.locationLabel,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: const Color(0xFFC7D7D1)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppStatusBadge(
                label: hospital.classificationLabel,
                color: const Color(0xFF9DD8C8),
              ),
              AppStatusBadge(
                label:
                    'ER ${_pretty(hospital.emergencyRoomStatus ?? 'unreported')}',
                color: hospital.isEmergencyAvailable
                    ? const Color(0xFF9DD8C8)
                    : const Color(0xFFFFD27E),
                icon: AppIcons.emergencyOutlined,
              ),
            ],
          ),
        ],
      ),
    );
    return AppCard(
      tone: AppCardTone.dark,
      padding: EdgeInsets.zero,
      borderRadius: AppRadius.feature,
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 190, child: HospitalImage(hospital: hospital)),
                content,
              ],
            )
          : SizedBox(
              height: 360,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 6, child: content),
                  Expanded(
                    flex: 5,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(AppRadius.feature),
                        bottomRight: Radius.circular(AppRadius.feature),
                      ),
                      child: HospitalImage(hospital: hospital),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _HospitalSummary extends StatelessWidget {
  const _HospitalSummary({required this.hospital});

  final Hospital hospital;

  @override
  Widget build(BuildContext context) => AppCard(
    tone: AppCardTone.mint,
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Plan your visit', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _CapacityMetric(
                value: hospital.availableBeds.toString(),
                label: 'beds',
                icon: AppIcons.bedOutlined,
              ),
            ),
            Expanded(
              child: _CapacityMetric(
                value: hospital.availableRooms.toString(),
                label: 'rooms',
                icon: AppIcons.meetingRoomOutlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _ContactRow(icon: AppIcons.locationOnOutlined, value: hospital.address),
        if (hospital.contactNumber != null)
          _ContactRow(
            icon: AppIcons.phoneOutlined,
            value: hospital.contactNumber!,
          ),
        if (hospital.emergencyContactNumber != null)
          _ContactRow(
            icon: AppIcons.emergencyOutlined,
            value: hospital.emergencyContactNumber!,
          ),
        if (hospital.email != null)
          _ContactRow(icon: AppIcons.emailOutlined, value: hospital.email!),
        if (_hoursLabel(hospital.operatingHours) case final hours?) ...[
          const Divider(),
          _ContactRow(icon: AppIcons.scheduleOutlined, value: hours),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Request online consultation',
          icon: AppIcons.videoCallRounded,
          expand: true,
          onPressed: () => context.go('/consult?hospital=${hospital.id}'),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          label: 'Compare on map',
          icon: AppIcons.nearMeOutlined,
          style: AppButtonStyle.quiet,
          expand: true,
          onPressed: () => context.go('/hospitals/map'),
        ),
      ],
    ),
  );
}

class _CapacityMetric extends StatelessWidget {
  const _CapacityMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: AppColors.forest),
      const SizedBox(height: AppSpacing.xs),
      Text(value, style: Theme.of(context).textTheme.headlineMedium),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _HospitalCapabilities extends StatelessWidget {
  const _HospitalCapabilities({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final departments = _list(data['departments']);
    final services = _list(data['services']);
    final doctors = _list(data['doctors']);
    final facilities = _list(data['facilities']);
    final announcements = _list(data['announcements']);
    return Column(
      children: [
        if (announcements.isNotEmpty)
          _Section(
            title: 'Announcements',
            child: Column(
              children: [
                for (final item in announcements)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      item['is_global'] == true
                          ? AppIcons.publicRounded
                          : AppIcons.campaignOutlined,
                      color: AppColors.blue,
                    ),
                    title: Text(item['title']?.toString() ?? 'Announcement'),
                    subtitle: Text(item['message']?.toString() ?? ''),
                  ),
              ],
            ),
          ),
        _ListSection(
          title: 'Departments',
          icon: AppIcons.apartmentRounded,
          items: departments
              .map((item) => item['department_name']?.toString() ?? '')
              .where((value) => value.isNotEmpty)
              .toList(),
        ),
        _ServiceOfferingsSection(services: services),
        _ListSection(
          title: 'Available doctors',
          icon: AppIcons.medicalServicesOutlined,
          items: doctors
              .map(
                (item) => '${item['display_name']} — ${item['specialization']}',
              )
              .toList(),
        ),
        _ListSection(
          title: 'Facilities',
          icon: AppIcons.monitorHeartRounded,
          items: facilities
              .map(
                (item) =>
                    '${_pretty(item['facility_type']?.toString() ?? '')}: ${_pretty(item['status']?.toString() ?? '')}',
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ServiceOfferingsSection extends StatelessWidget {
  const _ServiceOfferingsSection({required this.services});

  final List<Map<String, dynamic>> services;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Services offered',
    child: services.isEmpty
        ? const Text('No public service information has been added yet.')
        : Column(
            children: services
                .map((service) => _ServiceOfferingCard(service: service))
                .toList(growable: false),
          ),
  );
}

class _ServiceOfferingCard extends StatelessWidget {
  const _ServiceOfferingCard({required this.service});

  final Map<String, dynamic> service;

  @override
  Widget build(BuildContext context) {
    final category = _relationValue(
      service['healthcare_service_categories'],
      'category_name',
    );
    final department = _relationValue(
      service['hospital_departments'],
      'department_name',
    );
    final modes = (service['delivery_modes'] as List? ?? const [])
        .map((value) => _pretty(value.toString()))
        .toList(growable: false);
    final tags = (service['tags'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final assignments = _list(service['assigned_doctors']);
    final fee = _feeLabel(service['fee_min'], service['fee_max']);
    final hours = _hoursLabel(service['operating_hours']);
    final availability = service['availability_status']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        tone: AppCardTone.soft,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  AppIcons.healthAndSafetyOutlined,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service['service_name']?.toString() ??
                            'Hospital service',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (category != null || department != null)
                        Text(
                          [
                            category,
                            department,
                          ].whereType<String>().join(' · '),
                        ),
                    ],
                  ),
                ),
                _ServiceStatus(value: availability),
              ],
            ),
            if ((service['description'] ?? '')
                .toString()
                .trim()
                .isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(service['description'].toString()),
            ],
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final mode in modes)
                  Chip(
                    avatar: const Icon(AppIcons.checkCircleOutline, size: 16),
                    label: Text(mode),
                  ),
                if (service['appointment_required'] == true)
                  const Chip(label: Text('Appointment required')),
                if (service['accepts_walk_ins'] == true)
                  const Chip(label: Text('Walk-ins accepted')),
                if (fee != null) Chip(label: Text(fee)),
              ],
            ),
            if (hours != null) ...[
              const SizedBox(height: 9),
              _DetailLine(icon: AppIcons.scheduleOutlined, text: hours),
            ],
            if ((service['preparation_instructions'] ?? '')
                .toString()
                .trim()
                .isNotEmpty) ...[
              const SizedBox(height: 8),
              _DetailLine(
                icon: AppIcons.assignmentOutlined,
                text:
                    'Before your visit: ${service['preparation_instructions']}',
              ),
            ],
            if ((service['contact_number'] ?? '')
                .toString()
                .trim()
                .isNotEmpty) ...[
              const SizedBox(height: 8),
              _DetailLine(
                icon: AppIcons.phoneOutlined,
                text: 'Service contact: ${service['contact_number']}',
              ),
            ],
            if (assignments.isNotEmpty) ...[
              const SizedBox(height: 11),
              Text(
                'Assigned doctors',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: assignments
                    .map((assignment) {
                      final doctor = assignment['doctors'];
                      final doctorMap = doctor is Map ? doctor : const {};
                      final primary = assignment['is_primary'] == true;
                      return Chip(
                        avatar: Icon(
                          primary
                              ? AppIcons.starRounded
                              : AppIcons.personOutline,
                          size: 16,
                        ),
                        label: Text(
                          '${doctorMap['display_name'] ?? 'Doctor'}${primary ? ' · Primary' : ''}',
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                tags.map((tag) => '#$tag').join('  '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.blue),
      const SizedBox(width: 7),
      Expanded(child: Text(text)),
    ],
  );
}

class _ServiceStatus extends StatelessWidget {
  const _ServiceStatus({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final color = value == 'available'
        ? AppColors.teal
        : value == 'limited'
        ? const Color(0xFF9A6700)
        : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _pretty(value),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(title: title),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    ),
  );
}

class _ListSection extends StatelessWidget {
  const _ListSection({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) => _Section(
    title: title,
    child: items.isEmpty
        ? const Text('No public information has been added yet.')
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                Chip(avatar: Icon(icon, size: 16), label: Text(item)),
            ],
          ),
  );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.blue),
        const SizedBox(width: 10),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

List<Map<String, dynamic>> _list(dynamic value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

String _pretty(String value) => value
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');

String? _relationValue(dynamic relation, String key) {
  if (relation is Map) return relation[key]?.toString();
  if (relation is List && relation.isNotEmpty && relation.first is Map) {
    return (relation.first as Map)[key]?.toString();
  }
  return null;
}

String? _feeLabel(dynamic minimum, dynamic maximum) {
  final min = double.tryParse(minimum?.toString() ?? '');
  final max = double.tryParse(maximum?.toString() ?? '');
  if (min == null && max == null) return null;
  if (min != null && max != null && min != max) {
    return '₱${_amount(min)}–₱${_amount(max)}';
  }
  return '₱${_amount(min ?? max!)}';
}

String _amount(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String? _hoursLabel(dynamic value) {
  if (value is! Map) return null;
  final openDays = value.entries
      .where((entry) {
        final day = entry.value;
        return day is Map && day['enabled'] == true;
      })
      .map((entry) {
        final day = entry.value as Map;
        return '${_pretty(entry.key.toString())} ${day['open']}–${day['close']}';
      })
      .toList(growable: false);
  if (openDays.isEmpty) return null;
  if (openDays.length <= 3) return openDays.join(' · ');
  return '${openDays.take(3).join(' · ')} · +${openDays.length - 3} more';
}
