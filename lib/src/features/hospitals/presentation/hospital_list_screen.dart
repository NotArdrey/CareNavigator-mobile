import 'dart:async';

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

class HospitalListScreen extends ConsumerStatefulWidget {
  const HospitalListScreen({super.key});

  @override
  ConsumerState<HospitalListScreen> createState() => _HospitalListScreenState();
}

class _HospitalListScreenState extends ConsumerState<HospitalListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _emergencyOnly = false;
  int? _level;

  bool get _hasFilters => _query.isNotEmpty || _emergencyOnly || _level != null;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _clearFilters() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _emergencyOnly = false;
      _level = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hospitals = ref.watch(hospitalsProvider(_query));
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.medium;
    return SafeArea(
      child: Column(
        children: [
          AppPageHeader(
            eyebrow: 'Verified network',
            title: 'Find capable care',
            subtitle: 'Compare services, care levels, and current capacity',
            icon: AppIcons.localHospitalRounded,
            actions: [
              if (compact)
                IconButton.filledTonal(
                  tooltip: 'Nearby hospitals',
                  onPressed: () => context.go('/hospitals/map'),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    foregroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  icon: const Icon(AppIcons.location),
                )
              else
                AppButton(
                  label: 'Open geographic view',
                  icon: AppIcons.location,
                  style: AppButtonStyle.secondary,
                  onPressed: () => context.go('/hospitals/map'),
                ),
            ],
          ),
          Expanded(
            child: AsyncValuePanel<List<Hospital>>(
              value: hospitals,
              onRetry: () => ref.invalidate(hospitalsProvider(_query)),
              data: (items) {
                final visible = items
                    .where(
                      (item) =>
                          (!_emergencyOnly || item.isEmergencyAvailable) &&
                          (_level == null || item.capabilityLevel == _level),
                    )
                    .toList(growable: false);
                return _DirectoryWorkspace(
                  hospitals: visible,
                  totalCount: items.length,
                  compact: compact,
                  searchController: _searchController,
                  emergencyOnly: _emergencyOnly,
                  level: _level,
                  hasFilters: _hasFilters,
                  onSearch: _onSearch,
                  onEmergencyChanged: (value) =>
                      setState(() => _emergencyOnly = value),
                  onLevelChanged: (value) => setState(() => _level = value),
                  onClear: _clearFilters,
                  onRefresh: () async =>
                      ref.refresh(hospitalsProvider(_query).future),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryWorkspace extends StatelessWidget {
  const _DirectoryWorkspace({
    required this.hospitals,
    required this.totalCount,
    required this.compact,
    required this.searchController,
    required this.emergencyOnly,
    required this.level,
    required this.hasFilters,
    required this.onSearch,
    required this.onEmergencyChanged,
    required this.onLevelChanged,
    required this.onClear,
    required this.onRefresh,
  });

  final List<Hospital> hospitals;
  final int totalCount;
  final bool compact;
  final TextEditingController searchController;
  final bool emergencyOnly;
  final int? level;
  final bool hasFilters;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool> onEmergencyChanged;
  final ValueChanged<int?> onLevelChanged;
  final VoidCallback onClear;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              children: [
                AppTextField(
                  label: 'Search the network',
                  controller: searchController,
                  hint: 'Hospital, location, service, or specialty',
                  prefixIcon: AppIcons.searchRounded,
                  onChanged: onSearch,
                ),
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        selected: emergencyOnly,
                        label: const Text('Emergency room'),
                        avatar: const Icon(
                          AppIcons.emergencyOutlined,
                          size: 17,
                        ),
                        onSelected: onEmergencyChanged,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      ChoiceChip(
                        selected: level == null,
                        label: const Text('All levels'),
                        onSelected: (_) => onLevelChanged(null),
                      ),
                      for (final item in const [1, 2, 3]) ...[
                        const SizedBox(width: AppSpacing.xs),
                        ChoiceChip(
                          selected: level == item,
                          label: Text('Level $item'),
                          onSelected: (_) => onLevelChanged(item),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _results(context)),
        ],
      );
    }

    return ResponsivePageContainer(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.md,
        AppSpacing.xxl,
        AppSpacing.xxl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 286,
            child: _DirectoryFilters(
              searchController: searchController,
              emergencyOnly: emergencyOnly,
              level: level,
              hasFilters: hasFilters,
              totalCount: totalCount,
              onSearch: onSearch,
              onEmergencyChanged: onEmergencyChanged,
              onLevelChanged: onLevelChanged,
              onClear: onClear,
            ),
          ),
          const SizedBox(width: AppSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppSectionHeader(
                        eyebrow: hasFilters
                            ? 'Filtered network'
                            : 'Care network',
                        title:
                            '${hospitals.length} ${hospitals.length == 1 ? 'facility' : 'facilities'} found',
                        subtitle:
                            'Verified details are grouped for faster comparison.',
                      ),
                    ),
                    if (hasFilters)
                      AppButton(
                        label: 'Reset filters',
                        icon: AppIcons.filterAltOffRounded,
                        style: AppButtonStyle.quiet,
                        onPressed: onClear,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(child: _results(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context) {
    if (hospitals.isEmpty) {
      return AppEmptyState(
        icon: AppIcons.travelExploreRounded,
        title: hasFilters
            ? 'No facility matches this care profile'
            : 'The verified network is being prepared',
        message: hasFilters
            ? 'Broaden the location, service, emergency, or capability filters.'
            : 'Approved hospitals will appear here as soon as they are published.',
        action: hasFilters
            ? AppButton(
                label: 'Clear every filter',
                icon: AppIcons.refreshRounded,
                onPressed: onClear,
              )
            : null,
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.only(
          left: compact ? AppSpacing.lg : 0,
          right: compact ? AppSpacing.lg : 0,
          bottom: AppSpacing.xxl,
        ),
        itemCount: hospitals.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) =>
            _HospitalDirectoryRow(hospital: hospitals[index], compact: compact),
      ),
    );
  }
}

class _DirectoryFilters extends StatelessWidget {
  const _DirectoryFilters({
    required this.searchController,
    required this.emergencyOnly,
    required this.level,
    required this.hasFilters,
    required this.totalCount,
    required this.onSearch,
    required this.onEmergencyChanged,
    required this.onLevelChanged,
    required this.onClear,
  });

  final TextEditingController searchController;
  final bool emergencyOnly;
  final int? level;
  final bool hasFilters;
  final int totalCount;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool> onEmergencyChanged;
  final ValueChanged<int?> onLevelChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => AppCard(
    tone: AppCardTone.dark,
    borderRadius: AppRadius.extraLarge,
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppStatusBadge(
          label: 'DIRECTORY FILTERS',
          color: Color(0xFF9DD8C8),
          icon: AppIcons.tuneRounded,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Build a care profile',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Narrow the verified network by what matters now.',
          style: TextStyle(color: Color(0xFFB7C8C2), height: 1.45),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          label: 'Search',
          labelColor: Colors.white,
          controller: searchController,
          hint: 'Name or service',
          prefixIcon: AppIcons.searchRounded,
          onChanged: onSearch,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'CAPABILITY LEVEL',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xFF9DD8C8),
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _FilterChoice(
          label: 'All verified levels',
          selected: level == null,
          onTap: () => onLevelChanged(null),
        ),
        for (final item in const [1, 2, 3])
          _FilterChoice(
            label: 'Level $item care',
            selected: level == item,
            onTap: () => onLevelChanged(item),
          ),
        const SizedBox(height: AppSpacing.md),
        _FilterChoice(
          label: 'Emergency room available',
          icon: AppIcons.emergencyOutlined,
          selected: emergencyOnly,
          onTap: () => onEmergencyChanged(!emergencyOnly),
        ),
        const Spacer(),
        const Divider(color: Color(0xFF31574E)),
        const SizedBox(height: AppSpacing.md),
        Text(
          '$totalCount verified facilities in the network',
          style: const TextStyle(color: Color(0xFFB7C8C2), fontSize: 12),
        ),
        if (hasFilters) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Clear filters',
            style: AppButtonStyle.quiet,
            foregroundColor: Colors.white,
            onPressed: onClear,
          ),
        ],
      ],
    ),
  );
}

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Material(
      color: selected ? const Color(0xFF28584D) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 11,
          ),
          child: Row(
            children: [
              Icon(
                icon ??
                    (selected
                        ? AppIcons.radioButtonChecked
                        : AppIcons.radioButtonUnchecked),
                size: 18,
                color: selected ? AppColors.sea : const Color(0xFF9FB4AD),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFB7C8C2),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HospitalDirectoryRow extends StatelessWidget {
  const _HospitalDirectoryRow({required this.hospital, required this.compact});

  final Hospital hospital;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final erColor = hospital.isEmergencyAvailable
        ? AppColors.success
        : AppColors.warning;
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => context.go('/hospitals/${hospital.id}'),
      child: SizedBox(
        height: compact ? 146 : 164,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: compact ? 104 : 218,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HospitalImage(hospital: hospital),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Colors.transparent, Color(0x22092B25)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(
                  compact ? AppSpacing.sm : AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            hospital.name,
                            maxLines: compact ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: compact
                                ? Theme.of(context).textTheme.titleMedium
                                : Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (!compact)
                          const Icon(AppIcons.arrowOutwardRounded, size: 21),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      hospital.locationLabel.isEmpty
                          ? hospital.address
                          : hospital.locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        AppStatusBadge(
                          label: hospital.capabilityLabel,
                          color: AppColors.cobalt,
                        ),
                        AppStatusBadge(
                          label: hospital.emergencyRoomStatus == null
                              ? 'ER unreported'
                              : 'ER ${_label(hospital.emergencyRoomStatus!)}',
                          color: erColor,
                          icon: AppIcons.emergencyOutlined,
                        ),
                        if (!compact)
                          AppStatusBadge(
                            label:
                                '${hospital.availableBeds} beds · ${hospital.availableRooms} rooms',
                            color: AppColors.forest,
                            icon: AppIcons.bedOutlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _label(String value) => value
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
