import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/hospitals/hospital_models.dart';
import '../../providers/doctor_directory_provider.dart';
import '../../providers/hospital_directory_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_shell/public_scaffold.dart';
import '../../widgets/data_display/content_panel.dart';
import '../../widgets/data_display/hospital_image.dart';
import '../../widgets/layout/page_header.dart';

class DoctorDirectoryScreen extends ConsumerStatefulWidget {
  const DoctorDirectoryScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<DoctorDirectoryScreen> createState() =>
      _DoctorDirectoryScreenState();
}

class _DoctorDirectoryScreenState extends ConsumerState<DoctorDirectoryScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    final routedQuery = widget.initialQuery?.trim() ?? '';
    _searchController = TextEditingController(text: routedQuery);
    if (routedQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(doctorDirectoryProvider.notifier).setQuery(routedQuery);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(doctorDirectoryProvider);
    final hospitals = ref.watch(hospitalDirectoryProvider);
    final controller = ref.read(doctorDirectoryProvider.notifier);
    final results = directory.filteredEntries;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final sortField = SizedBox(
      width: compact ? double.infinity : 210,
      child: DropdownButtonFormField<DoctorDirectorySort>(
        isExpanded: true,
        initialValue: directory.filters.sort,
        decoration: const InputDecoration(labelText: 'Sort'),
        items: [
          DropdownMenuItem(
            value: DoctorDirectorySort.earliestAvailability,
            child: const Text('Earliest availability'),
          ),
          const DropdownMenuItem(
            value: DoctorDirectorySort.distance,
            child: Text('Distance'),
          ),
          const DropdownMenuItem(
            value: DoctorDirectorySort.name,
            child: Text('Clinician name'),
          ),
        ],
        onChanged: (value) {
          if (value != null) controller.setSort(value);
        },
      ),
    );
    return PublicScaffold(
      currentLocation: '/doctors',
      body: SingleChildScrollView(
        child: PageContent(
          maxWidth: 1240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Find a clinician',
                description:
                    'Compare published clinicians by specialty, location, care setting, and recurring availability.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => context.go('/hospitals'),
                    icon: const Icon(Icons.local_hospital_outlined),
                    label: const Text('Hospital directory'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 16),
              ContentPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: controller.setQuery,
                      decoration: InputDecoration(
                        labelText:
                            'Clinician, specialty, hospital, or location',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: directory.filters.query.trim().isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear clinician search',
                                onPressed: () {
                                  _searchController.clear();
                                  controller.setQuery('');
                                  context.replace('/doctors');
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 260,
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey(
                              'specialty-${directory.filters.specialty}',
                            ),
                            isExpanded: true,
                            initialValue: directory.filters.specialty,
                            decoration: const InputDecoration(
                              labelText: 'Specialty',
                            ),
                            items: [
                              const DropdownMenuItem(
                                child: Text('All specialties'),
                              ),
                              for (final specialty in directory.specialties)
                                DropdownMenuItem(
                                  value: specialty,
                                  child: Text(
                                    specialty,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: controller.setSpecialty,
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey(
                              'doctor-province-${directory.filters.province}',
                            ),
                            isExpanded: true,
                            initialValue: directory.filters.province,
                            decoration: const InputDecoration(
                              labelText: 'Location',
                            ),
                            items: [
                              const DropdownMenuItem(
                                child: Text('All locations'),
                              ),
                              for (final province in directory.provinces)
                                DropdownMenuItem(
                                  value: province,
                                  child: Text(
                                    province,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: controller.setProvince,
                          ),
                        ),
                        FilterChip(
                          selected: directory.filters.onlineOnly,
                          avatar: const Icon(Icons.videocam_outlined, size: 18),
                          label: const Text('Online care'),
                          onSelected: controller.setOnlineOnly,
                        ),
                        FilterChip(
                          selected: directory.filters.availableFacilityOnly,
                          avatar: const Icon(
                            Icons.event_available_outlined,
                            size: 18,
                          ),
                          label: const Text('Available facility'),
                          onSelected: controller.setAvailableFacilityOnly,
                        ),
                        if (_hasActiveFilters(directory.filters))
                          TextButton.icon(
                            onPressed: () {
                              _searchController.clear();
                              controller.clearFilters();
                              context.replace('/doctors');
                            },
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text('Clear filters'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ContentPanel(
                title: 'Published clinician directory',
                subtitle:
                    '${results.length} clinician result${results.length == 1 ? '' : 's'} from verified hospitals.',
                action: compact ? null : sortField,
                child: hospitals.isLoading
                    ? const DataState(
                        icon: Icons.sync,
                        title: 'Loading published clinicians',
                        message: 'Checking verified hospitals and schedules.',
                      )
                    : hospitals.errorMessage != null
                    ? DataState(
                        icon: Icons.cloud_off_outlined,
                        title: 'Clinician directory unavailable',
                        message: hospitals.errorMessage!,
                        action: OutlinedButton(
                          onPressed: () => ref
                              .read(hospitalDirectoryProvider.notifier)
                              .refresh(),
                          child: const Text('Retry'),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (compact) ...[
                            sortField,
                            const SizedBox(height: 16),
                          ],
                          if (results.isEmpty)
                            DataState(
                              icon: Icons.person_search_outlined,
                              title: 'No clinicians match',
                              message:
                                  'Adjust the query or filters and try again.',
                            )
                          else
                            Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < results.length;
                                  index++
                                ) ...[
                                  _DoctorDirectoryRow(entry: results[index]),
                                  if (index != results.length - 1)
                                    const Divider(height: 25),
                                ],
                              ],
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorDirectoryRow extends StatelessWidget {
  const _DoctorDirectoryRow({required this.entry});

  final DoctorDirectoryEntry entry;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final identity = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.selected,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: const Icon(
              Icons.medical_services_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.doctor.displayLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(entry.doctor.specialtyLabel),
                const SizedBox(height: 5),
                Text(
                  '${entry.hospitalName} • ${entry.locationLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 5),
                Text(
                  'Next recurring slot ${DateFormat('MMM d, y • h:mm a').format(entry.doctor.nextAvailableAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      );
      final actions = Column(
        crossAxisAlignment: constraints.maxWidth < 790
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusTag(
                label: entry.doctor.offersOnlineCare
                    ? 'Online care'
                    : 'In-person care',
                icon: entry.doctor.offersOnlineCare
                    ? Icons.videocam_outlined
                    : Icons.location_on_outlined,
                color: entry.doctor.offersOnlineCare
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              StatusTag(
                label: entry.hospitalIsAvailable
                    ? 'Facility available'
                    : 'Facility unavailable',
                icon: entry.hospitalIsAvailable
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
                color: entry.hospitalIsAvailable
                    ? AppColors.success
                    : AppColors.destructive,
              ),
              if (entry.distanceKm != null)
                Text(
                  '${entry.distanceKm!.toStringAsFixed(1)} km',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => context.go('/hospitals/${entry.hospitalId}'),
                child: const Text('Hospital'),
              ),
              FilledButton(
                onPressed: entry.hospitalIsAvailable
                    ? () => context.go(
                        '/consultation/request?hospitalId=${entry.hospitalId}',
                      )
                    : null,
                child: const Text('Request care'),
              ),
            ],
          ),
        ],
      );
      if (constraints.maxWidth < 790) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HospitalImage(
              imageUrl: entry.hospitalImageUrl,
              height: 132,
              semanticLabel: '${entry.hospitalName} exterior',
            ),
            const SizedBox(height: 14),
            identity,
            const SizedBox(height: 14),
            actions,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: HospitalImage(
              imageUrl: entry.hospitalImageUrl,
              height: 104,
              semanticLabel: '${entry.hospitalName} exterior',
            ),
          ),
          const SizedBox(width: 18),
          Expanded(child: identity),
          const SizedBox(width: 18),
          Flexible(child: actions),
        ],
      );
    },
  );
}

bool _hasActiveFilters(DoctorDirectoryFilters filters) =>
    filters.query.trim().isNotEmpty ||
    filters.specialty != null ||
    filters.province != null ||
    filters.onlineOnly ||
    filters.availableFacilityOnly;
