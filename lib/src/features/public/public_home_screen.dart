import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/hospitals/hospital_models.dart';
import '../../providers/hospital_directory_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_shell/public_scaffold.dart';
import '../../widgets/data_display/content_panel.dart';
import '../../widgets/data_display/hospital_image.dart';
import '../../widgets/layout/page_header.dart';

const homePublishedFacilityLimit = 5;

class PublicHomeScreen extends StatelessWidget {
  const PublicHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PublicScaffold(
      currentLocation: '/',
      body: PatientCareHomeContent(),
    );
  }
}

/// The care-discovery landing content shared by the public and patient homes.
class PatientCareHomeContent extends ConsumerWidget {
  const PatientCareHomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(hospitalDirectoryProvider);
    final featuredHospitals = [...directory.entries]
      ..sort((left, right) => left.name.compareTo(right.name));
    return SingleChildScrollView(
      child: PageContent(
        maxWidth: 1240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _CareSearchHeader(),
            const SizedBox(height: AppSpacing.x5),
            _NearbyCarePanel(
              hospitals: featuredHospitals
                  .take(homePublishedFacilityLimit)
                  .toList(),
              isLoading: directory.isLoading,
              errorMessage: directory.errorMessage,
              onRetry: ref.read(hospitalDirectoryProvider.notifier).refresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyCarePanel extends StatelessWidget {
  const _NearbyCarePanel({
    required this.hospitals,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final List<HospitalDirectoryEntry> hospitals;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ContentPanel(
      title: 'Published facilities',
      subtitle:
          'Verified facilities from the CareNavigator directory. The assistant can use your saved address for distance-aware recommendations.',
      action: TextButton(
        onPressed: () => context.go('/hospitals'),
        child: const Text('See all'),
      ),
      child: isLoading
          ? const DataState(
              icon: Icons.sync,
              title: 'Loading verified facilities',
              message: 'CareNavigator is checking the public directory.',
            )
          : errorMessage != null
          ? DataState(
              icon: Icons.cloud_off_outlined,
              title: 'Hospital directory unavailable',
              message: errorMessage!,
              action: OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            )
          : hospitals.isEmpty
          ? const DataState(
              icon: Icons.location_searching,
              title: 'No facilities published',
              message: 'Open the directory to adjust filters.',
            )
          : Column(
              children: [
                for (var index = 0; index < hospitals.length; index++) ...[
                  _NearbyCareRow(hospital: hospitals[index]),
                  if (index != hospitals.length - 1) const Divider(height: 25),
                ],
              ],
            ),
    );
  }
}

class _NearbyCareRow extends StatelessWidget {
  const _NearbyCareRow({required this.hospital});

  final HospitalDirectoryEntry hospital;

  @override
  Widget build(BuildContext context) {
    final statusColor = hospital.isAvailable
        ? AppColors.success
        : AppColors.warning;
    return Semantics(
      button: true,
      label: 'Open ${hospital.name} details',
      child: InkWell(
        onTap: () => context.go('/hospitals/${hospital.id}'),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HospitalImage(
                    imageUrl: hospital.imageUrl,
                    width: 76,
                    height: 88,
                    borderRadius: AppRadius.control,
                    semanticLabel: '${hospital.name} exterior',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hospital.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hospital.locationLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 7),
                        StatusTag(
                          label: hospital.isAvailable ? 'Available' : 'Limited',
                          icon: hospital.isAvailable
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_outlined,
                          color: statusColor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.chevron_right,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (hospital.hasCoordinates)
                    const _CareMetric(
                      icon: Icons.location_on_outlined,
                      label: 'Directions available',
                    ),
                  if (hospital.estimatedWaitMinutes != null)
                    _CareMetric(
                      icon: Icons.schedule_outlined,
                      label:
                          '${hospital.estimatedWaitMinutes} min estimated wait',
                    ),
                  if (hospital.availableBeds != null &&
                      hospital.hasCurrentEmergencyCapacity())
                    _CareMetric(
                      icon: Icons.bed_outlined,
                      label: '${hospital.availableBeds} ER beds available',
                    ),
                  _CareMetric(
                    icon: Icons.medical_services_outlined,
                    label:
                        '${hospital.doctors.length} clinician${hospital.doctors.length == 1 ? '' : 's'}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CareMetric extends StatelessWidget {
  const _CareMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.compact),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CareSearchHeader extends StatefulWidget {
  const _CareSearchHeader();

  @override
  State<_CareSearchHeader> createState() => _CareSearchHeaderState();
}

class _CareSearchHeaderState extends State<_CareSearchHeader> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusTag(
                label: 'Clinical navigation',
                icon: Icons.health_and_safety_outlined,
                color: AppColors.primary,
              ),
              const SizedBox(height: 14),
              Semantics(
                header: true,
                child: Text(
                  'Find the right care,\nwith clear next steps.',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Find care facilities or ask the CareNavigator assistant for guidance.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          );
          final tasks = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _openSearch(),
                decoration: InputDecoration(
                  labelText: 'Search hospitals, doctors, or services',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Search care',
                    onPressed: _openSearch,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const _QuickActions(),
            ],
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [intro, const SizedBox(height: 24), tasks],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: intro),
              const SizedBox(width: 48),
              Expanded(child: tasks),
            ],
          );
        },
      ),
    );
  }

  void _openSearch() {
    final query = _searchController.text.trim();
    context.go(
      Uri(
        path: '/hospitals',
        queryParameters: query.isEmpty ? null : {'q': query},
      ).toString(),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.local_hospital_outlined, 'Find a hospital', '/hospitals'),
      (Icons.chat_bubble_outline, 'Ask care assistant', '/hospitals'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final action in actions)
          OutlinedButton.icon(
            onPressed: () => context.go(action.$3),
            icon: Icon(action.$1, size: 19),
            label: Text(action.$2),
          ),
      ],
    );
  }
}
