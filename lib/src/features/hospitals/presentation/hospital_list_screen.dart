import 'dart:async';

import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:care_navigator_ph/src/features/hospitals/presentation/hospital_image.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
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

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final hospitals = ref.watch(hospitalsProvider(_query));
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 600 ? 20.0 : 40.0;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hospital directory',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/hospitals/map'),
                      icon: const Icon(Icons.near_me_rounded),
                      label: const Text('Nearby & directions'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Verified facilities, services, specialists, and availability in one view.',
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearch,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText:
                              'Search hospital, location, service, or tag',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    if (width >= 560) ...[
                      const SizedBox(width: 12),
                      FilterChip(
                        selected: _emergencyOnly,
                        avatar: const Icon(Icons.emergency_outlined, size: 18),
                        label: const Text('ER available'),
                        onSelected: (value) =>
                            setState(() => _emergencyOnly = value),
                      ),
                    ],
                  ],
                ),
                if (width < 560) ...[
                  const SizedBox(height: 10),
                  FilterChip(
                    selected: _emergencyOnly,
                    avatar: const Icon(Icons.emergency_outlined, size: 18),
                    label: const Text('Show hospitals with available ER'),
                    onSelected: (value) =>
                        setState(() => _emergencyOnly = value),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Hospital level:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    ChoiceChip(
                      selected: _level == null,
                      label: const Text('All'),
                      onSelected: (_) => setState(() => _level = null),
                    ),
                    for (final level in const [1, 2, 3])
                      ChoiceChip(
                        selected: _level == level,
                        label: Text('Level $level'),
                        onSelected: (_) => setState(() => _level = level),
                      ),
                  ],
                ),
              ],
            ),
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
                if (visible.isEmpty) {
                  return _EmptyHospitals(
                    hasQuery:
                        _query.isNotEmpty || _emergencyOnly || _level != null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.refresh(hospitalsProvider(_query).future),
                  child: GridView.builder(
                    padding: EdgeInsets.fromLTRB(horizontal, 4, horizontal, 36),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: width >= 1260
                          ? 3
                          : width >= 720
                          ? 2
                          : 1,
                      mainAxisExtent: 350,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        _HospitalCard(hospital: visible[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HospitalCard extends StatelessWidget {
  const _HospitalCard({required this.hospital});

  final Hospital hospital;

  @override
  Widget build(BuildContext context) {
    final erColor = hospital.isEmergencyAvailable
        ? AppColors.teal
        : const Color(0xFF8B5B00);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/hospitals/${hospital.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 126,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HospitalImage(hospital: hospital),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x990B1F3A)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        hospital.classificationLabel,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hospital.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 17,
                          color: Color(0xFF6B7C91),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            hospital.locationLabel.isEmpty
                                ? hospital.address
                                : hospital.locationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _StatusPill(
                          icon: Icons.emergency_outlined,
                          label: hospital.emergencyRoomStatus == null
                              ? 'ER unreported'
                              : 'ER ${_label(hospital.emergencyRoomStatus!)}',
                          color: erColor,
                        ),
                        _StatusPill(
                          icon: Icons.bed_outlined,
                          label: '${hospital.availableBeds} beds',
                          color: AppColors.blue,
                        ),
                        _StatusPill(
                          icon: Icons.meeting_room_outlined,
                          label: '${hospital.availableRooms} rooms',
                          color: const Color(0xFF6A4BBC),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          'View hospital',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_rounded, size: 19),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHospitals extends StatelessWidget {
  const _EmptyHospitals({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_hospital_outlined,
              size: 54,
              color: Color(0xFF7890A8),
            ),
            const SizedBox(height: 14),
            Text(
              hasQuery
                  ? 'No hospitals match these filters'
                  : 'No verified hospitals yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 7),
            Text(
              hasQuery
                  ? 'Try another hospital, location, service, or tag.'
                  : 'Approved hospitals will appear here as soon as the platform administrator publishes them.',
              textAlign: TextAlign.center,
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
