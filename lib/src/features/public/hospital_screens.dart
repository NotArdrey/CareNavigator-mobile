import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/hospitals/hospital_models.dart';
import '../../providers/care_assistant_provider.dart';
import '../../providers/hospital_directory_provider.dart';
import '../../routing/root_overlay.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_shell/public_scaffold.dart';
import '../../widgets/data_display/content_panel.dart';
import '../../widgets/data_display/hospital_image.dart';
import '../../widgets/layout/page_header.dart';

class HospitalDirectoryScreen extends ConsumerStatefulWidget {
  const HospitalDirectoryScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<HospitalDirectoryScreen> createState() =>
      _HospitalDirectoryScreenState();
}

class _HospitalDirectoryScreenState
    extends ConsumerState<HospitalDirectoryScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    if (_searchController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(hospitalDirectoryProvider.notifier)
              .setQuery(_searchController.text);
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
    final directory = ref.watch(hospitalDirectoryProvider);
    final controller = ref.read(hospitalDirectoryProvider.notifier);
    final compact = MediaQuery.sizeOf(context).width < 700;
    return PublicScaffold(
      currentLocation: '/hospitals',
      body: SingleChildScrollView(
        child: PageContent(
          maxWidth: 1240,
          padding: compact ? const EdgeInsets.fromLTRB(16, 16, 16, 32) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Find a hospital',
                description:
                    'Browse published facilities, services, departments, and clinician availability.',
                actions: compact
                    ? const []
                    : [
                        OutlinedButton.icon(
                          onPressed: () => context.go('/hospitals/map'),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Map view'),
                        ),
                      ],
              ),
              SizedBox(height: compact ? 12 : 16),
              _SearchAndFilters(
                directory: directory,
                controller: controller,
                searchController: _searchController,
                compact: compact,
              ),
              const SizedBox(height: 16),
              if (compact) ...[
                _DirectorySectionHeader(
                  resultCount: directory.filteredEntries.length,
                ),
                const SizedBox(height: 12),
                _DirectoryBody(
                  directory: directory,
                  onRetry: () => controller.refresh(),
                  compact: true,
                ),
              ] else
                ContentPanel(
                  title: 'Published hospitals',
                  subtitle:
                      '${directory.filteredEntries.length} result${directory.filteredEntries.length == 1 ? '' : 's'} from the verified directory.',
                  child: _DirectoryBody(
                    directory: directory,
                    onRetry: () => controller.refresh(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HospitalMapScreen extends ConsumerWidget {
  const HospitalMapScreen({
    super.key,
    this.initialQuery,
    this.selectedHospitalId,
    this.selectionSource,
    this.initialUserLatitude,
    this.initialUserLongitude,
  });

  final String? initialQuery;
  final String? selectedHospitalId;
  final String? selectionSource;
  final double? initialUserLatitude;
  final double? initialUserLongitude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(hospitalDirectoryProvider);
    final normalizedQuery = initialQuery?.trim().toLowerCase() ?? '';
    final points = directory.filteredEntries
        .where(
          (hospital) =>
              normalizedQuery.isEmpty ||
              <String>[
                hospital.name,
                hospital.city,
                hospital.province,
                hospital.careLevel,
                ...hospital.services,
                ...hospital.departments,
              ].join(' ').toLowerCase().contains(normalizedQuery),
        )
        .where((hospital) => hospital.hasCoordinates)
        .where(
          (hospital) => _philippinesMapBounds.contains(
            LatLng(hospital.latitude!, hospital.longitude!),
          ),
        )
        .toList(growable: false);
    return PublicScaffold(
      currentLocation: '/hospitals/map',
      body: SingleChildScrollView(
        child: PageContent(
          maxWidth: 1240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Hospital map',
                description:
                    selectionSource == 'current-location-recommendation'
                    ? 'Focused on the nearest CareNavigator recommendation using your current location.'
                    : selectionSource == 'location-recommendation'
                    ? 'Focused on the nearest CareNavigator recommendation using your saved location.'
                    : 'View published hospitals with coordinates supplied by the directory.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => context.go('/hospitals'),
                    icon: const Icon(Icons.list_alt_outlined),
                    label: const Text('List view'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (directory.isLoading)
                const ContentPanel(
                  child: DataState(
                    icon: Icons.sync,
                    title: 'Loading hospital locations',
                    message: 'Checking published directory coordinates.',
                  ),
                )
              else if (directory.errorMessage != null)
                ContentPanel(
                  child: DataState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Hospital directory unavailable',
                    message: directory.errorMessage!,
                    action: OutlinedButton(
                      onPressed: () => ref
                          .read(hospitalDirectoryProvider.notifier)
                          .refresh(),
                      child: const Text('Retry'),
                    ),
                  ),
                )
              else if (points.isEmpty)
                const ContentPanel(
                  child: DataState(
                    icon: Icons.map_outlined,
                    title: 'No mapped hospitals published',
                    message:
                        'Published facilities without coordinates remain available in the list view.',
                  ),
                )
              else
                _HospitalMap(
                  points: points,
                  selectedHospitalId: selectedHospitalId,
                  selectionSource: selectionSource,
                  initialUserLocation:
                      initialUserLatitude != null &&
                          initialUserLongitude != null
                      ? LatLng(initialUserLatitude!, initialUserLongitude!)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HospitalDetailScreen extends ConsumerWidget {
  const HospitalDetailScreen({super.key, required this.hospitalId});

  final String hospitalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directory = ref.watch(hospitalDirectoryProvider);
    final assistant = ref.watch(careAssistantProvider);
    final hospital = directory.findById(hospitalId);
    final recommendationReasons = [
      for (final recommendation in assistant.recommendations)
        if (recommendation.hospitalId == hospitalId) ...recommendation.reasons,
    ];
    final content = directory.isLoading
        ? const DataState(
            icon: Icons.sync,
            title: 'Loading hospital details',
            message: 'Checking the published hospital record.',
          )
        : directory.errorMessage != null
        ? DataState(
            icon: Icons.cloud_off_outlined,
            title: 'Hospital details unavailable',
            message: directory.errorMessage!,
            action: OutlinedButton(
              onPressed: () =>
                  ref.read(hospitalDirectoryProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          )
        : hospital == null
        ? const DataState(
            icon: Icons.search_off_outlined,
            title: 'Hospital not found',
            message:
                'The hospital may have been removed or is not currently published.',
          )
        : _HospitalDetails(
            hospital: hospital,
            recommendationReasons: recommendationReasons,
          );
    return PublicScaffold(
      currentLocation: '/hospitals/$hospitalId',
      body: SingleChildScrollView(
        child: PageContent(
          maxWidth: 1000,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: hospital?.name ?? 'Hospital details',
                description: hospital == null
                    ? 'Published hospital record'
                    : '${hospital.careLevel} · ${hospital.locationLabel}',
                actions: [
                  OutlinedButton(
                    onPressed: () => context.go('/hospitals'),
                    child: const Text('Back to hospitals'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/hospitals/map'),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Back to map'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ContentPanel(child: content),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.directory,
    required this.controller,
    required this.searchController,
    required this.compact,
  });

  final HospitalDirectoryState directory;
  final HospitalDirectoryController controller;
  final TextEditingController searchController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        directory.filters.query.isNotEmpty ||
        directory.filters.province != null ||
        directory.filters.careLevel != null ||
        directory.filters.onlyAvailable;
    final search = TextField(
      controller: searchController,
      onChanged: controller.setQuery,
      decoration: InputDecoration(
        hintText: compact ? 'Search hospitals or services' : null,
        labelText: compact
            ? null
            : 'Hospital, service, department, or location',
        isDense: compact,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: directory.filters.query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  searchController.clear();
                  controller.setQuery('');
                },
                icon: const Icon(Icons.close),
              ),
      ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FilterDropdown(
                  label: 'Location',
                  value: directory.filters.province,
                  values: directory.provinces,
                  onChanged: controller.setProvince,
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterDropdown(
                  label: 'Care level',
                  value: directory.filters.careLevel,
                  values: directory.careLevels,
                  onChanged: controller.setCareLevel,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                selected: directory.filters.onlyAvailable,
                avatar: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Available now'),
                onSelected: controller.setOnlyAvailable,
                visualDensity: VisualDensity.compact,
              ),
              if (hasFilters)
                TextButton.icon(
                  onPressed: () {
                    searchController.clear();
                    controller.clearFilters();
                  },
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ],
      );
    }
    return ContentPanel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 360, child: search),
          _FilterDropdown(
            label: 'Location',
            value: directory.filters.province,
            values: directory.provinces,
            onChanged: controller.setProvince,
          ),
          _FilterDropdown(
            label: 'Care level',
            value: directory.filters.careLevel,
            values: directory.careLevels,
            onChanged: controller.setCareLevel,
          ),
          FilterChip(
            selected: directory.filters.onlyAvailable,
            avatar: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Available only'),
            onSelected: controller.setOnlyAvailable,
          ),
          if (hasFilters)
            TextButton.icon(
              onPressed: () {
                searchController.clear();
                controller.clearFilters();
              },
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.compact = false,
  });

  final String label;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final field = DropdownButtonFormField<String?>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: compact ? null : label,
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 13)
            : null,
        prefixIcon: compact
            ? Icon(
                label == 'Location'
                    ? Icons.location_on_outlined
                    : Icons.local_hospital_outlined,
                size: 18,
              )
            : null,
        prefixIconConstraints: compact
            ? const BoxConstraints(minWidth: 38, minHeight: 38)
            : null,
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            label == 'Location' ? 'All locations' : 'All care levels',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final item in values)
          DropdownMenuItem<String?>(
            value: item,
            child: Text(item, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
    return compact ? field : SizedBox(width: 190, child: field);
  }
}

class _DirectorySectionHeader extends StatelessWidget {
  const _DirectorySectionHeader({required this.resultCount});

  final int resultCount;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Published hospitals',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '$resultCount hospital${resultCount == 1 ? '' : 's'} found',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('List')),
          ButtonSegment(value: true, label: Text('Map')),
        ],
        selected: const {false},
        onSelectionChanged: (selection) {
          if (selection.first) context.go('/hospitals/map');
        },
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        ),
      ),
    ],
  );
}

class _DirectoryBody extends StatelessWidget {
  const _DirectoryBody({
    required this.directory,
    required this.onRetry,
    this.compact = false,
  });

  final HospitalDirectoryState directory;
  final Future<void> Function() onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (directory.isLoading) {
      return const DataState(
        icon: Icons.sync,
        title: 'Loading published hospitals',
        message: 'Checking verified facility records.',
      );
    }
    if (directory.errorMessage != null) {
      return DataState(
        icon: Icons.cloud_off_outlined,
        title: 'Hospital directory unavailable',
        message: directory.errorMessage!,
        action: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      );
    }
    final hospitals = directory.filteredEntries;
    if (hospitals.isEmpty) {
      return const DataState(
        icon: Icons.local_hospital_outlined,
        title: 'No hospitals match',
        message: 'Adjust the search or filters and try again.',
      );
    }
    return Column(
      children: [
        for (var index = 0; index < hospitals.length; index++) ...[
          _HospitalListTile(hospital: hospitals[index], compact: compact),
          if (index != hospitals.length - 1) Divider(height: compact ? 24 : 26),
        ],
      ],
    );
  }
}

class _HospitalListTile extends StatelessWidget {
  const _HospitalListTile({required this.hospital, this.compact = false});

  final HospitalDirectoryEntry hospital;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hospital.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(hospital.locationLabel),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusTag(
                label: hospital.isAvailable ? 'Available' : 'Unavailable',
                icon: hospital.isAvailable
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
                color: hospital.isAvailable
                    ? AppColors.success
                    : AppColors.warning,
              ),
              StatusTag(
                label: hospital.careLevel,
                icon: Icons.account_balance_outlined,
                color: _careLevelColor(hospital.careLevel),
              ),
              if (hospital.estimatedWaitMinutes != null)
                StatusTag(
                  label: '${hospital.estimatedWaitMinutes} min estimated wait',
                  icon: Icons.schedule_outlined,
                  color: AppColors.information,
                ),
              if (hospital.availableBeds != null)
                StatusTag(
                  label: '${hospital.availableBeds} beds available',
                  icon: Icons.bed_outlined,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ],
      );
      final actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: () => context.go('/hospitals/${hospital.id}'),
            child: const Text('Details'),
          ),
          FilledButton(
            onPressed: hospital.isAvailable
                ? () => context.go(
                    '/consultation/request?hospitalId=${hospital.id}',
                  )
                : null,
            child: const Text('Request care'),
          ),
          if (hospital.hasCoordinates)
            OutlinedButton(
              onPressed: () => context.go(
                Uri(
                  path: '/hospitals/map',
                  queryParameters: {'hospitalId': hospital.id},
                ).toString(),
              ),
              child: const Text('View map'),
            ),
        ],
      );
      if (constraints.maxWidth < 700) {
        final capabilities = <String>{
          ...hospital.departments,
          ...hospital.services,
        }.take(3).toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HospitalImage(
              imageUrl: hospital.imageUrl,
              height: 140,
              semanticLabel: '${hospital.name} exterior',
            ),
            const SizedBox(height: 12),
            Text(hospital.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              hospital.locationLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _CompactStatusTag(
                  label: hospital.isAvailable ? 'Available' : 'Unavailable',
                  icon: hospital.isAvailable
                      ? Icons.check_circle_outline
                      : Icons.block_outlined,
                  color: hospital.isAvailable
                      ? AppColors.success
                      : AppColors.warning,
                ),
                _CompactStatusTag(
                  label: hospital.careLevel,
                  icon: Icons.account_balance_outlined,
                  color: _careLevelColor(hospital.careLevel),
                ),
                if (hospital.availableBeds != null)
                  _CompactStatusTag(
                    label: '${hospital.availableBeds} beds',
                    icon: Icons.bed_outlined,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
            if (capabilities.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                capabilities.join(' \u00B7 '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: hospital.isAvailable
                        ? () => context.go(
                            '/consultation/request?hospitalId=${hospital.id}',
                          )
                        : null,
                    style: _compactFilledActionStyle(),
                    child: const Text('Request care'),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => context.go('/hospitals/${hospital.id}'),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward, size: 17),
                    label: const Text('View details'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                if (hospital.hasCoordinates) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: 'Directions',
                    onPressed: () => context.go(
                      Uri(
                        path: '/hospitals/map',
                        queryParameters: {'hospitalId': hospital.id},
                      ).toString(),
                    ),
                    icon: const Icon(Icons.directions_outlined),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 190,
            child: HospitalImage(
              imageUrl: hospital.imageUrl,
              height: 128,
              semanticLabel: '${hospital.name} exterior',
            ),
          ),
          const SizedBox(width: 18),
          Expanded(child: details),
          const SizedBox(width: 16),
          actions,
        ],
      );
    },
  );
}

class _CompactStatusTag extends StatelessWidget {
  const _CompactStatusTag({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HospitalDetails extends StatelessWidget {
  const _HospitalDetails({
    required this.hospital,
    required this.recommendationReasons,
  });

  final HospitalDirectoryEntry hospital;
  final List<String> recommendationReasons;

  @override
  Widget build(BuildContext context) {
    final emergencyHours = hospital.operatingHours.entries
        .where((entry) => entry.key.toLowerCase().contains('emergency'))
        .map((entry) => entry.value)
        .firstOrNull;
    final isEmergencyAlwaysOpen =
        emergencyHours?.toLowerCase().contains('24/7') ?? false;
    final capabilities = <String>{
      ...hospital.departments,
      ...hospital.services,
    }.take(12).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HospitalImage(
          imageUrl: hospital.imageUrl,
          height: MediaQuery.sizeOf(context).width < 600 ? 190 : 300,
          semanticLabel: '${hospital.name} exterior',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusTag(
              label: hospital.isAvailable ? 'Available' : 'Unavailable',
              icon: hospital.isAvailable
                  ? Icons.check_circle_outline
                  : Icons.block_outlined,
              color: hospital.isAvailable
                  ? AppColors.success
                  : AppColors.warning,
            ),
            StatusTag(
              label: hospital.careLevel,
              icon: Icons.account_balance_outlined,
              color: _careLevelColor(hospital.careLevel),
            ),
            StatusTag(
              label: isEmergencyAlwaysOpen
                  ? 'Emergency 24/7'
                  : _operatingStatusLabel(hospital.operatingStatus),
              icon: Icons.schedule_outlined,
              color: hospital.operatingStatus == 'open'
                  ? AppColors.success
                  : AppColors.warning,
            ),
          ],
        ),
        if (hospital.description != null) ...[
          const SizedBox(height: 14),
          Text(hospital.description!),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (hospital.hasCoordinates)
              OutlinedButton.icon(
                onPressed: () => context.go(
                  Uri(
                    path: '/hospitals/map',
                    queryParameters: {'hospitalId': hospital.id},
                  ).toString(),
                ),
                icon: const Icon(Icons.directions_outlined, size: 18),
                label: const Text('Get directions'),
                style: _compactOutlinedActionStyle(),
              ),
            if (hospital.contactNumber != null)
              OutlinedButton.icon(
                onPressed: () => _callHospital(hospital.contactNumber!),
                icon: const Icon(Icons.phone_outlined, size: 18),
                label: const Text('Call hospital'),
                style: _compactOutlinedActionStyle(),
              ),
            FilledButton.icon(
              onPressed: hospital.isAvailable
                  ? () => context.go(
                      '/consultation/request?hospitalId=${hospital.id}',
                    )
                  : null,
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: const Text('Request care'),
              style: _compactFilledActionStyle(),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionHeader(
          icon: Icons.monitor_heart_outlined,
          title: 'Current status',
          description:
              'Published operational information. Confirm urgent capacity directly with the hospital.',
        ),
        const SizedBox(height: 12),
        _StatusGrid(
          items: [
            _StatusMetric(
              label: 'Emergency room',
              value: hospital.emergencyStatus == null
                  ? 'Not published'
                  : _displayIdentifier(hospital.emergencyStatus!),
              detail: isEmergencyAlwaysOpen
                  ? 'Open 24 hours'
                  : emergencyHours ?? 'Hours not published',
              color: _availabilityColor(hospital.emergencyStatus),
            ),
            _StatusMetric(
              label: 'Estimated ER wait',
              value: hospital.estimatedWaitMinutes == null
                  ? 'Not published'
                  : '${hospital.estimatedWaitMinutes} min',
              detail: 'Call ahead when possible',
              color: AppColors.information,
            ),
            _StatusMetric(
              label: 'Emergency beds',
              value: hospital.availableBeds == null
                  ? 'Not published'
                  : hospital.totalBeds == null
                  ? '${hospital.availableBeds} available'
                  : '${hospital.availableBeds} / ${hospital.totalBeds} available',
              detail: hospital.currentEmergencyPatients == null
                  ? 'ER capacity'
                  : '${hospital.currentEmergencyPatients} current patients',
              color: AppColors.primary,
            ),
            _StatusMetric(
              label: 'Last status update',
              value: _formatFreshness(hospital.statusLastUpdated),
              detail: hospital.statusLastUpdated == null
                  ? 'No timestamp published'
                  : DateFormat(
                      'MMM d, y · h:mm a',
                    ).format(hospital.statusLastUpdated!.toLocal()),
              color: AppColors.textSecondary,
            ),
          ],
        ),
        if (hospital.bedAvailability.isNotEmpty) ...[
          const SizedBox(height: 12),
          _LabelWrap(
            values: [
              for (final bed in hospital.bedAvailability)
                '${_displayIdentifier(bed.type)}: ${bed.availableBeds} / ${bed.totalBeds} available',
            ],
          ),
        ],
        const SizedBox(height: 26),
        _WhyThisHospital(
          reasons: recommendationReasons,
          capabilities: capabilities,
          hospital: hospital,
        ),
        const SizedBox(height: 26),
        const _SectionHeader(
          icon: Icons.place_outlined,
          title: 'Contact and visiting information',
        ),
        const SizedBox(height: 8),
        _DetailRow(
          icon: Icons.location_on_outlined,
          label: 'Full address',
          value: hospital.fullAddress,
        ),
        _DetailRow(
          icon: Icons.phone_outlined,
          label: 'Main phone',
          value: hospital.contactNumber ?? 'Not published',
        ),
        _DetailRow(
          icon: Icons.emergency_outlined,
          label: 'Emergency phone',
          value: hospital.emergencyContactNumber ?? 'Not published',
        ),
        _DetailRow(
          icon: Icons.email_outlined,
          label: 'Email',
          value: hospital.email ?? 'Not published',
        ),
        if (hospital.operatingHours.isEmpty)
          const _DetailRow(
            icon: Icons.schedule_outlined,
            label: 'Operating hours',
            value: 'Not published',
          )
        else
          for (final hours in hospital.operatingHours.entries)
            _DetailRow(
              icon: Icons.schedule_outlined,
              label: '${_displayIdentifier(hours.key)} hours',
              value: hours.value,
            ),
        const SizedBox(height: 26),
        const _SectionHeader(
          icon: Icons.health_and_safety_outlined,
          title: 'Facilities and equipment',
          description:
              'Published facility status and available units, where supplied.',
        ),
        const SizedBox(height: 12),
        if (hospital.facilities.isEmpty)
          const _PublishedDataNotice(
            icon: Icons.domain_disabled_outlined,
            message: 'No facility or equipment status is currently published.',
          )
        else
          _FacilityGrid(facilities: hospital.facilities),
        const SizedBox(height: 26),
        const _SectionHeader(
          icon: Icons.medical_services_outlined,
          title: 'Departments',
        ),
        const SizedBox(height: 10),
        if (hospital.departments.isEmpty)
          const Text('No departments are currently published.')
        else
          _LabelWrap(values: hospital.departments),
        const SizedBox(height: 22),
        const _SectionHeader(
          icon: Icons.design_services_outlined,
          title: 'Services',
        ),
        const SizedBox(height: 10),
        if (hospital.services.isEmpty)
          const Text('No services are currently published.')
        else
          _LabelWrap(values: hospital.services),
        const SizedBox(height: 26),
        const _SectionHeader(
          icon: Icons.badge_outlined,
          title: 'Clinician availability',
          description:
              'Published recurring schedules; contact the hospital to confirm same-day coverage.',
        ),
        const SizedBox(height: 8),
        if (hospital.doctors.isEmpty)
          const _PublishedDataNotice(
            icon: Icons.person_search_outlined,
            message:
                'No clinician schedules are currently published. Department listings do not guarantee a doctor is on duty.',
          )
        else
          for (final doctor in hospital.doctors)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                child: Icon(Icons.medical_services_outlined),
              ),
              title: Text(doctor.displayLabel),
              subtitle: Text(
                '${doctor.specialtyLabel} · next recurring slot ${DateFormat('MMM d, y h:mm a').format(doctor.nextAvailableAt.toLocal())}',
              ),
              trailing: Text(
                doctor.offersOnlineCare ? 'Online / in person' : 'In person',
              ),
            ),
        const SizedBox(height: 26),
        const _SectionHeader(
          icon: Icons.payments_outlined,
          title: 'Payment and insurance',
        ),
        const SizedBox(height: 10),
        const _PublishedDataNotice(
          icon: Icons.info_outline,
          message:
              'Payment and insurance acceptance is not published. Contact the hospital to confirm PhilHealth, HMO, private insurance, and self-pay options.',
        ),
      ],
    );
  }
}

class _WhyThisHospital extends StatelessWidget {
  const _WhyThisHospital({
    required this.reasons,
    required this.capabilities,
    required this.hospital,
  });

  final List<String> reasons;
  final List<String> capabilities;
  final HospitalDirectoryEntry hospital;

  @override
  Widget build(BuildContext context) {
    final hasRecommendation = reasons.isNotEmpty;
    final comparisonReasons = hasRecommendation
        ? reasons
        : <String>[
            '${hospital.careLevel} with ${hospital.departments.length} published department${hospital.departments.length == 1 ? '' : 's'}.',
            hospital.isAvailable
                ? 'The directory currently reports this facility as available.'
                : 'The directory does not currently report this facility as available.',
            if (hospital.availableBeds != null)
              '${hospital.availableBeds} emergency beds are currently reported available.',
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.selected,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.secondary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasRecommendation
                            ? 'Why CareNavigator recommends this hospital'
                            : 'Why this facility may fit your needs',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasRecommendation
                            ? 'Based on the needs discussed with the CareNavigator assistant.'
                            : 'Use these published details to compare facilities. They are not a diagnosis or guarantee of suitability.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final reason in comparisonReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(reason)),
                  ],
                ),
              ),
            if (capabilities.isNotEmpty) ...[
              const SizedBox(height: 6),
              _LabelWrap(values: capabilities),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.description,
  });

  final IconData icon;
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: AppColors.primary),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (description != null) ...[
              const SizedBox(height: 3),
              Text(description!),
            ],
          ],
        ),
      ),
    ],
  );
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({required this.items});

  final List<_StatusMetric> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760
          ? 4
          : constraints.maxWidth >= 400
          ? 2
          : 1;
      final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in items) SizedBox(width: width, child: item),
        ],
      );
    },
  );
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: Border.all(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _FacilityGrid extends StatelessWidget {
  const _FacilityGrid({required this.facilities});

  final List<HospitalFacilityAvailability> facilities;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 620 ? 2 : 1;
      final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final facility in facilities)
            SizedBox(
              width: width,
              child: _FacilityTile(facility: facility),
            ),
        ],
      );
    },
  );
}

class _FacilityTile extends StatelessWidget {
  const _FacilityTile({required this.facility});

  final HospitalFacilityAvailability facility;

  @override
  Widget build(BuildContext context) {
    final color = _availabilityColor(facility.status);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_facilityIcon(facility.type), color: color, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayIdentifier(facility.type),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      _displayIdentifier(facility.status),
                      if (facility.availableUnits != null)
                        '${facility.availableUnits} unit${facility.availableUnits == 1 ? '' : 's'} reported',
                    ].join(' · '),
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  if (facility.notes != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      facility.notes!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelWrap extends StatelessWidget {
  const _LabelWrap({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.compact),
            border: Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Text(value),
          ),
        ),
    ],
  );
}

class _PublishedDataNotice extends StatelessWidget {
  const _PublishedDataNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: Border.all(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 9),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AppColors.textMuted),
        const SizedBox(width: 10),
        SizedBox(
          width: 135,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

ButtonStyle _compactOutlinedActionStyle() => OutlinedButton.styleFrom(
  minimumSize: const Size(0, 40),
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

ButtonStyle _compactFilledActionStyle() => FilledButton.styleFrom(
  minimumSize: const Size(0, 40),
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

Color _careLevelColor(String careLevel) {
  final normalized = careLevel.toLowerCase();
  if (normalized.contains('tertiary')) return const Color(0xFF6E3FA0);
  if (normalized.contains('secondary')) return AppColors.information;
  if (normalized.contains('primary')) return AppColors.success;
  return AppColors.textSecondary;
}

Color _availabilityColor(String? status) => switch (status?.toLowerCase()) {
  'available' || 'open' => AppColors.success,
  'limited' || 'busy' => AppColors.warning,
  'full' || 'unavailable' || 'temporarily_closed' => AppColors.emergency,
  _ => AppColors.textSecondary,
};

String _operatingStatusLabel(String status) => switch (status.toLowerCase()) {
  'open' => 'Open',
  'limited' => 'Limited operations',
  'temporarily_closed' => 'Temporarily closed',
  'closed' => 'Closed',
  _ => 'Hours not published',
};

String _displayIdentifier(String value) {
  final words = value
      .trim()
      .split(RegExp(r'[_\s]+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return 'Not published';
  return words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

String _formatFreshness(DateTime? value) {
  if (value == null) return 'Not published';
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} hr ago';
  if (difference.inDays < 30) return '${difference.inDays} days ago';
  return DateFormat('MMM d, y').format(value.toLocal());
}

IconData _facilityIcon(String type) => switch (type.toLowerCase()) {
  'ambulance' => Icons.emergency_outlined,
  'icu' => Icons.monitor_heart_outlined,
  'laboratory' => Icons.biotech_outlined,
  'operating_room' => Icons.medical_services_outlined,
  'pharmacy' => Icons.local_pharmacy_outlined,
  'dialysis' => Icons.water_drop_outlined,
  _ => Icons.domain_outlined,
};

final _philippinesMapBounds = LatLngBounds(
  const LatLng(4.4, 116.5),
  const LatLng(21.7, 127.0),
);

class _HospitalMap extends StatefulWidget {
  const _HospitalMap({
    required this.points,
    this.selectedHospitalId,
    this.selectionSource,
    this.initialUserLocation,
  });

  final List<HospitalDirectoryEntry> points;
  final String? selectedHospitalId;
  final String? selectionSource;
  final LatLng? initialUserLocation;

  @override
  State<_HospitalMap> createState() => _HospitalMapState();
}

class _HospitalMapState extends State<_HospitalMap> {
  late final MapController _mapController;
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _liveLocation;
  bool _isLocating = false;
  bool _followLiveLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    final initialLocation = widget.initialUserLocation;
    if (initialLocation != null &&
        _philippinesMapBounds.contains(initialLocation)) {
      _liveLocation = initialLocation;
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _showLiveLocation() async {
    if (_isLocating) return;
    if (_liveLocation != null && _positionSubscription != null) {
      setState(() => _followLiveLocation = true);
      _centerOnLiveLocation();
      return;
    }

    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        showRootMessage('Enable device location services and try again.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        showRootMessage(
          'Location permission is needed to show your live position.',
        );
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        showRootMessage(
          'Location permission is blocked. Enable it in your device or browser settings.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: _currentLocationSettings(),
      );
      final point = LatLng(position.latitude, position.longitude);
      if (!_philippinesMapBounds.contains(point)) {
        showRootMessage(
          'Your current location is outside the Philippines map coverage.',
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _liveLocation = point;
        _followLiveLocation = true;
      });
      _centerOnLiveLocation();

      await _positionSubscription?.cancel();
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            (position) {
              final updatedPoint = LatLng(
                position.latitude,
                position.longitude,
              );
              if (!mounted || !_philippinesMapBounds.contains(updatedPoint)) {
                return;
              }
              setState(() => _liveLocation = updatedPoint);
              if (_followLiveLocation) {
                _centerOnLiveLocation();
              }
            },
            onError: (Object _) {
              if (!mounted) return;
              setState(() => _followLiveLocation = false);
              showRootMessage('Live location updates were interrupted.');
            },
          );
    } on PermissionDeniedException {
      showRootMessage(
        'Location access is blocked. Allow location for this site in your browser settings, then try again.',
      );
    } on LocationServiceDisabledException {
      showRootMessage(
        'Device location services are turned off. Enable them in system settings, then try again.',
      );
    } on PositionUpdateException {
      showRootMessage(
        'Your browser could not determine a location. Enable Windows Location services and allow location for localhost, then try again.',
      );
    } on TimeoutException {
      showRootMessage('Your location could not be found in time. Try again.');
    } catch (_) {
      showRootMessage('Your live location is currently unavailable.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _centerOnLiveLocation() {
    final location = _liveLocation;
    if (location == null) return;
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(location, currentZoom < 14 ? 14 : currentZoom);
  }

  @override
  Widget build(BuildContext context) {
    HospitalDirectoryEntry? selectedHospital;
    for (final hospital in widget.points) {
      if (hospital.id == widget.selectedHospitalId) {
        selectedHospital = hospital;
        break;
      }
    }
    final selectedPoint = selectedHospital == null
        ? null
        : LatLng(selectedHospital.latitude!, selectedHospital.longitude!);
    final focusBounds = _publishedLocationsBounds(widget.points);
    final routeBounds = selectedPoint != null && _liveLocation != null
        ? LatLngBounds.fromPoints([selectedPoint, _liveLocation!])
        : null;

    return ContentPanel(
      title: 'Published locations',
      subtitle: selectedHospital == null
          ? 'Markers are color-coded by hospital level. Select one to open its published details.'
          : widget.selectionSource == 'current-location-recommendation'
          ? 'Nearest recommendation from your current location: ${selectedHospital.name} · ${selectedHospital.careLevel}.'
          : widget.selectionSource == 'location-recommendation'
          ? 'Nearest recommendation from your saved location: ${selectedHospital.name} · ${selectedHospital.careLevel}.'
          : widget.selectionSource == 'recommendation'
          ? 'Showing recommended hospital ${selectedHospital.name} · ${selectedHospital.careLevel}.'
          : 'Showing ${selectedHospital.name} · ${selectedHospital.careLevel}. Select its marker to open details.',
      child: Column(
        children: [
          _HospitalLevelLegend(points: widget.points),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final mapHeight = constraints.maxWidth >= 720 ? 360.0 : 280.0;
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: SizedBox(
                  height: mapHeight,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter:
                              selectedPoint ?? const LatLng(12.8797, 121.7740),
                          initialZoom: selectedPoint == null ? 5.0 : 15.0,
                          initialCameraFit: routeBounds != null
                              ? CameraFit.bounds(
                                  bounds: routeBounds,
                                  padding: const EdgeInsets.all(54),
                                  minZoom: 7.25,
                                  maxZoom: 15,
                                )
                              : selectedPoint == null
                              ? CameraFit.bounds(
                                  bounds: focusBounds,
                                  padding: const EdgeInsets.all(42),
                                  minZoom: 7.25,
                                  maxZoom: 10,
                                )
                              : null,
                          minZoom: 7.25,
                          maxZoom: 18.0,
                          backgroundColor: AppColors.selected,
                          cameraConstraint: CameraConstraint.contain(
                            bounds: _philippinesMapBounds,
                          ),
                          onPositionChanged: (_, hasGesture) {
                            if (hasGesture && _followLiveLocation) {
                              setState(() => _followLiveLocation = false);
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            tileBounds: _philippinesMapBounds,
                            userAgentPackageName: 'care_navigator_ph',
                          ),
                          MarkerLayer(
                            markers: [
                              for (final hospital in widget.points)
                                Marker(
                                  key: ValueKey(hospital.id),
                                  point: LatLng(
                                    hospital.latitude!,
                                    hospital.longitude!,
                                  ),
                                  width: 38,
                                  height: 46,
                                  alignment: Alignment.topCenter,
                                  child: Tooltip(
                                    message:
                                        '${hospital.name}\n${hospital.careLevel}\n${hospital.locationLabel}',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(24),
                                      onTap: () => context.go(
                                        '/hospitals/${hospital.id}',
                                      ),
                                      child: _HospitalLevelMarker(
                                        careLevel: hospital.careLevel,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (_liveLocation != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _liveLocation!,
                                  width: 46,
                                  height: 46,
                                  child: const _LiveLocationMarker(),
                                ),
                              ],
                            ),
                        ],
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.public,
                                  color: AppColors.primary,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Philippine facilities',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _MapControlButton(
                                icon: Icons.my_location,
                                tooltip: _liveLocation == null
                                    ? 'Show my live location'
                                    : 'Recenter on my live location',
                                isLoading: _isLocating,
                                isActive: _followLiveLocation,
                                onPressed: _isLocating
                                    ? null
                                    : _showLiveLocation,
                              ),
                              const Divider(height: 1),
                              _MapControlButton(
                                icon: Icons.add,
                                tooltip: 'Zoom in',
                                onPressed: () => _mapController.move(
                                  _mapController.camera.center,
                                  _mapController.camera.zoom + 1,
                                ),
                              ),
                              const Divider(height: 1),
                              _MapControlButton(
                                icon: Icons.remove,
                                tooltip: 'Zoom out',
                                onPressed: () => _mapController.move(
                                  _mapController.camera.center,
                                  _mapController.camera.zoom - 1,
                                ),
                              ),
                              const Divider(height: 1),
                              _MapControlButton(
                                icon: Icons.crop_free,
                                tooltip: 'Show all published hospitals',
                                onPressed: () => _mapController.fitCamera(
                                  CameraFit.bounds(
                                    bounds: focusBounds,
                                    padding: const EdgeInsets.all(42),
                                    minZoom: 7.25,
                                    maxZoom: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            child: Text(
                              '${widget.points.length} published location${widget.points.length == 1 ? '' : 's'}',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          for (final hospital in widget.points)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.location_on,
                color: _careLevelColor(hospital.careLevel),
              ),
              title: Text(hospital.name),
              subtitle: Text(
                '${hospital.careLevel} · ${hospital.locationLabel}',
              ),
              onTap: () => context.go('/hospitals/${hospital.id}'),
            ),
        ],
      ),
    );
  }
}

class _HospitalLevelLegend extends StatelessWidget {
  const _HospitalLevelLegend({required this.points});

  final List<HospitalDirectoryEntry> points;

  @override
  Widget build(BuildContext context) {
    final levels = points.map((hospital) => hospital.careLevel).toSet().toList()
      ..sort(
        (first, second) =>
            _careLevelRank(first).compareTo(_careLevelRank(second)),
      );
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Hospital level', style: Theme.of(context).textTheme.labelLarge),
          for (final level in levels)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: _careLevelColor(level),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(level),
              ],
            ),
        ],
      ),
    );
  }
}

class _HospitalLevelMarker extends StatelessWidget {
  const _HospitalLevelMarker({required this.careLevel});

  final String careLevel;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.topCenter,
    children: [
      Icon(
        Icons.location_on,
        color: _careLevelColor(careLevel),
        size: 40,
        shadows: const [
          Shadow(color: Color(0x55000000), blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      Positioned(
        top: 7,
        child: Container(
          width: 17,
          height: 17,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Text(
            _careLevelCode(careLevel),
            style: TextStyle(
              color: _careLevelColor(careLevel),
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ],
  );
}

LocationSettings _currentLocationSettings() => kIsWeb
    ? WebSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
        maximumAge: const Duration(minutes: 5),
      )
    : const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      );

class _LiveLocationMarker extends StatelessWidget {
  const _LiveLocationMarker();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Your live location',
    child: Center(
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.information,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8)],
        ),
        child: const Icon(Icons.navigation, color: Colors.white, size: 15),
      ),
    ),
  );
}

LatLngBounds _publishedLocationsBounds(List<HospitalDirectoryEntry> hospitals) {
  final points = [
    for (final hospital in hospitals)
      LatLng(hospital.latitude!, hospital.longitude!),
  ];
  if (points.isEmpty) return _philippinesMapBounds;
  if (points.length == 1) {
    final point = points.single;
    return LatLngBounds(
      LatLng(point.latitude - 0.25, point.longitude - 0.25),
      LatLng(point.latitude + 0.25, point.longitude + 0.25),
    );
  }
  return LatLngBounds.fromPoints(points);
}

int _careLevelRank(String careLevel) {
  final normalized = careLevel.toLowerCase();
  if (normalized.contains('primary')) return 1;
  if (normalized.contains('secondary')) return 2;
  if (normalized.contains('tertiary')) return 3;
  return 4;
}

String _careLevelCode(String careLevel) {
  final normalized = careLevel.toLowerCase();
  if (normalized.contains('primary')) return 'P';
  if (normalized.contains('secondary')) return 'S';
  if (normalized.contains('tertiary')) return 'T';
  return 'H';
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isLoading = false,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isActive;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: isLoading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 18),
    tooltip: tooltip,
    splashRadius: 18,
    constraints: const BoxConstraints.tightFor(width: 38, height: 36),
    padding: EdgeInsets.zero,
    color: isActive ? AppColors.information : AppColors.primary,
    onPressed: onPressed,
  );
}

Future<void> _callHospital(String phoneNumber) async {
  final launched = await launchUrl(
    Uri(scheme: 'tel', path: phoneNumber),
    mode: LaunchMode.externalApplication,
  );
  if (!launched) {
    showRootMessage('The hospital phone number could not be opened.');
  }
}
