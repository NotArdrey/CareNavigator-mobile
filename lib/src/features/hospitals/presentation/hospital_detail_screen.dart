import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
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
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 600 ? 20.0 : 40.0;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          expandedHeight: 260,
          leading: IconButton(
            tooltip: 'Back to hospitals',
            onPressed: () => context.go('/hospitals'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            title: Text(
              hospital.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.navy, AppColors.blue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.local_hospital_rounded,
                  color: Colors.white24,
                  size: 120,
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 40),
          sliver: SliverList.list(
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoChip(
                    icon: Icons.verified_rounded,
                    label: hospital.classification ?? 'Verified hospital',
                    color: AppColors.blue,
                  ),
                  _InfoChip(
                    icon: Icons.emergency_rounded,
                    label:
                        'ER ${_pretty(hospital.emergencyRoomStatus ?? 'unreported')}',
                    color: hospital.isEmergencyAvailable
                        ? AppColors.teal
                        : const Color(0xFF8B5B00),
                  ),
                  _InfoChip(
                    icon: Icons.bed_rounded,
                    label: '${hospital.availableBeds} available beds',
                    color: const Color(0xFF6A4BBC),
                  ),
                  _InfoChip(
                    icon: Icons.meeting_room_outlined,
                    label: '${hospital.availableRooms} available rooms',
                    color: const Color(0xFF9A6700),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'About',
                child: Text(
                  (hospital.description?.trim().isNotEmpty ?? false)
                      ? hospital.description!
                      : 'This hospital has not added a public description yet.',
                ),
              ),
              _Section(
                title: 'Location & contact',
                child: Column(
                  children: [
                    _ContactRow(
                      icon: Icons.location_on_outlined,
                      value: hospital.address,
                    ),
                    if (hospital.contactNumber != null)
                      _ContactRow(
                        icon: Icons.phone_outlined,
                        value: hospital.contactNumber!,
                      ),
                    if (hospital.emergencyContactNumber != null)
                      _ContactRow(
                        icon: Icons.emergency_outlined,
                        value: hospital.emergencyContactNumber!,
                      ),
                    if (hospital.email != null)
                      _ContactRow(
                        icon: Icons.email_outlined,
                        value: hospital.email!,
                      ),
                  ],
                ),
              ),
              if (_hoursLabel(hospital.operatingHours) case final hours?)
                _Section(title: 'Operating hours', child: Text(hours)),
              details.when(
                data: (data) => _HospitalCapabilities(data: data),
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Service details are unavailable: $error',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => context.go('/consult?hospital=${hospital.id}'),
                icon: const Icon(Icons.video_call_rounded),
                label: const Text('Request an online consultation'),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
                          ? Icons.public_rounded
                          : Icons.campaign_outlined,
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
          icon: Icons.apartment_rounded,
          items: departments
              .map((item) => item['department_name']?.toString() ?? '')
              .where((value) => value.isNotEmpty)
              .toList(),
        ),
        _ServiceOfferingsSection(services: services),
        _ListSection(
          title: 'Available doctors',
          icon: Icons.medical_services_outlined,
          items: doctors
              .map(
                (item) => '${item['display_name']} — ${item['specialization']}',
              )
              .toList(),
        ),
        _ListSection(
          title: 'Facilities',
          icon: Icons.monitor_heart_rounded,
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

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                color: AppColors.blue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['service_name']?.toString() ?? 'Hospital service',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (category != null || department != null)
                      Text(
                        [category, department].whereType<String>().join(' · '),
                      ),
                  ],
                ),
              ),
              _ServiceStatus(value: availability),
            ],
          ),
          if ((service['description'] ?? '').toString().trim().isNotEmpty) ...[
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
                  avatar: const Icon(Icons.check_circle_outline, size: 16),
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
            _DetailLine(icon: Icons.schedule_outlined, text: hours),
          ],
          if ((service['preparation_instructions'] ?? '')
              .toString()
              .trim()
              .isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailLine(
              icon: Icons.assignment_outlined,
              text: 'Before your visit: ${service['preparation_instructions']}',
            ),
          ],
          if ((service['contact_number'] ?? '')
              .toString()
              .trim()
              .isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailLine(
              icon: Icons.phone_outlined,
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
                        primary ? Icons.star_rounded : Icons.person_outline,
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
    child: SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
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
