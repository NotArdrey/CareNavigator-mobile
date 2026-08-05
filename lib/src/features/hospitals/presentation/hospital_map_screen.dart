import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class HospitalMapScreen extends ConsumerStatefulWidget {
  const HospitalMapScreen({
    this.initialNeed,
    this.initialMinimumLevel = 1,
    this.initialRequiredServices = const [],
    this.initialEmergencyOnly = false,
    super.key,
  });

  final String? initialNeed;
  final int initialMinimumLevel;
  final List<String> initialRequiredServices;
  final bool initialEmergencyOnly;

  @override
  ConsumerState<HospitalMapScreen> createState() => _HospitalMapScreenState();
}

class _HospitalMapScreenState extends ConsumerState<HospitalMapScreen> {
  late final TextEditingController _needController;
  Position? _position;
  bool _locating = false;
  bool _recommending = false;
  late bool _emergencyOnly;
  late int _minimumLevel;
  String? _locationError;
  String? _selectedHospitalId;
  Map<String, Map<String, dynamic>> _recommendations = const {};

  @override
  void initState() {
    super.initState();
    _needController = TextEditingController(text: widget.initialNeed ?? '');
    _emergencyOnly = widget.initialEmergencyOnly;
    _minimumLevel = widget.initialMinimumLevel.clamp(1, 3);
  }

  @override
  void dispose() {
    _needController.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are turned off on this device.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(
          permission == LocationPermission.deniedForever
              ? 'Location permission is permanently denied. Enable it in device settings.'
              : 'Location permission was not granted.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) setState(() => _position = position);
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _locationError = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _directions(Hospital hospital) async {
    final destination = hospital.latitude != null && hospital.longitude != null
        ? '${hospital.latitude},${hospital.longitude}'
        : hospital.address;
    final parameters = <String, String>{
      'api': '1',
      'destination': destination,
      'travelmode': 'driving',
      if (_position != null)
        'origin': '${_position!.latitude},${_position!.longitude}',
    };
    final uri = Uri.https('www.google.com', '/maps/dir/', parameters);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the directions application.'),
        ),
      );
    }
  }

  Future<void> _recommend() async {
    if (_position == null) {
      setState(
        () => _locationError =
            'Use your location before requesting ranked recommendations.',
      );
      return;
    }
    setState(() {
      _recommending = true;
      _locationError = null;
    });
    try {
      final need = _needController.text.trim();
      final requiredServices = <String>{
        ...widget.initialRequiredServices
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
        if (need.isNotEmpty) need,
      }.toList(growable: false);
      final values = await ref
          .read(careRepositoryProvider)
          .recommendHospitals(
            department: need.isEmpty ? null : need,
            requiredServices: requiredServices,
            urgencyLevel: _emergencyOnly ? 'emergency' : null,
            latitude: _position!.latitude,
            longitude: _position!.longitude,
          );
      if (mounted) {
        setState(() {
          _recommendations = {
            for (final item in values)
              if (item['hospital_id'] != null)
                item['hospital_id'].toString(): item,
          };
        });
      }
    } catch (error) {
      if (mounted) setState(() => _locationError = error.toString());
    } finally {
      if (mounted) setState(() => _recommending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hospitals = ref.watch(hospitalsProvider(''));
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      child: Column(
        children: [
          AppPageHeader(
            eyebrow: 'Geographic care explorer',
            title: 'Explore nearby care',
            subtitle: 'Plot verified facilities and rank the right capability',
            icon: AppIcons.nearMeRounded,
            onBack: () => context.go('/hospitals'),
            backTooltip: 'Back to hospital directory',
            actions: [
              if (width < 560)
                IconButton(
                  tooltip: _position == null
                      ? 'Use my location'
                      : 'Refresh location',
                  onPressed: _locating ? null : _locate,
                  icon: _locating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppIcons.myLocationRounded),
                )
              else
                FilledButton.icon(
                  onPressed: _locating ? null : _locate,
                  icon: _locating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppIcons.myLocationRounded),
                  label: Text(
                    _position == null ? 'Use my location' : 'Refresh location',
                  ),
                ),
            ],
          ),
          Expanded(
            child: AppPageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppCard(
                    tone: AppCardTone.dark,
                    borderRadius: AppRadius.extraLarge,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AppStatusBadge(
                              label: 'CARE MATCH CONTROLS',
                              color: Color(0xFF9DD8C8),
                              icon: AppIcons.tuneRounded,
                            ),
                            const Spacer(),
                            if (width >= 720)
                              const Text(
                                'Verified coordinates · external directions',
                                style: TextStyle(
                                  color: Color(0xFFB7C8C2),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilterChip(
                              selected: _emergencyOnly,
                              onSelected: (value) =>
                                  setState(() => _emergencyOnly = value),
                              avatar: const Icon(
                                AppIcons.emergencyRounded,
                                size: 18,
                              ),
                              label: const Text('ER available'),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.medium,
                                ),
                              ),
                              child: DropdownButton<int>(
                                value: _minimumLevel,
                                dropdownColor: AppColors.evergreen,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                iconEnabledColor: Colors.white,
                                underline: const SizedBox.shrink(),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.medium,
                                ),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _minimumLevel = value);
                                  }
                                },
                                items: const [
                                  DropdownMenuItem(
                                    value: 1,
                                    child: Text('Level 1+ care'),
                                  ),
                                  DropdownMenuItem(
                                    value: 2,
                                    child: Text('Level 2+ care'),
                                  ),
                                  DropdownMenuItem(
                                    value: 3,
                                    child: Text('Level 3 care'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_emergencyOnly) ...[
                          const SizedBox(height: AppSpacing.sm),
                          const AppNotice(
                            icon: AppIcons.emergencyRounded,
                            color: Color(0xFFFF9C8B),
                            message:
                                'Emergency filter active. Call 911 for life-threatening symptoms and open directions before leaving.',
                          ),
                        ],
                        if (_locationError != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _locationError!,
                            style: const TextStyle(color: Color(0xFFFF9C8B)),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        if (width < 600) ...[
                          TextField(
                            controller: _needController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _recommend(),
                            decoration: const InputDecoration(
                              hintText: 'Care needed · cardiology or dialysis',
                              prefixIcon: Icon(
                                AppIcons.medicalInformationOutlined,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: _recommendButton(),
                          ),
                        ] else
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _needController,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _recommend(),
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Needed department, service, or specialty',
                                    prefixIcon: Icon(
                                      AppIcons.medicalInformationOutlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              _recommendButton(),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: hospitals.when(
                      loading: () => const AppLoadingState(),
                      error: (error, _) => AppStatePanel(
                        kind: AppStateKind.error,
                        icon: AppIcons.cloudOffRounded,
                        title: 'Unable to load hospitals',
                        message: error.toString(),
                        action: OutlinedButton.icon(
                          onPressed: () =>
                              ref.invalidate(hospitalsProvider('')),
                          icon: const Icon(AppIcons.refreshRounded),
                          label: const Text('Try again'),
                        ),
                      ),
                      data: (items) {
                        final ranked =
                            items
                                .where(
                                  (hospital) =>
                                      hospital.meetsCapabilityLevel(
                                        _minimumLevel,
                                      ) &&
                                      (!_emergencyOnly ||
                                          hospital.isEmergencyAvailable),
                                )
                                .map(
                                  (hospital) => (
                                    hospital: hospital,
                                    distance: _distance(hospital),
                                  ),
                                )
                                .toList()
                              ..sort((left, right) {
                                final leftScore = _score(left.hospital.id);
                                final rightScore = _score(right.hospital.id);
                                if (leftScore != rightScore) {
                                  return rightScore.compareTo(leftScore);
                                }
                                final a = left.distance ?? double.infinity;
                                final b = right.distance ?? double.infinity;
                                return a.compareTo(b);
                              });
                        if (ranked.isEmpty) {
                          return const AppStatePanel(
                            icon: AppIcons.localHospitalOutlined,
                            title: 'No matching hospitals',
                            message:
                                'Try a lower capability level or turn off the ER filter.',
                          );
                        }
                        final mapHospitals = ranked
                            .map((item) => item.hospital)
                            .toList(growable: false);
                        final selectedId =
                            _selectedHospitalId ?? mapHospitals.first.id;
                        final compactResults = width < 900;
                        final results = RefreshIndicator(
                          onRefresh: () async =>
                              ref.refresh(hospitalsProvider('').future),
                          child: ListView.separated(
                            shrinkWrap: compactResults,
                            physics: compactResults
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            itemCount: ranked.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = ranked[index];
                              final hospital = item.hospital;
                              final recommendation =
                                  _recommendations[hospital.id];
                              final details = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    hospital.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(hospital.address),
                                  const SizedBox(height: 4),
                                  Text(
                                    hospital.classificationLabel,
                                    style: const TextStyle(
                                      color: AppColors.blue,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if (item.distance != null)
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(
                                            '${item.distance!.toStringAsFixed(1)} km away',
                                          ),
                                        ),
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(
                                          '${hospital.availableBeds} beds',
                                        ),
                                      ),
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(
                                          hospital.isEmergencyAvailable
                                              ? 'ER ${hospital.emergencyRoomStatus}'
                                              : 'ER not reported available',
                                        ),
                                      ),
                                      if (recommendation != null)
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          avatar: const Icon(
                                            AppIcons.symptomCheck,
                                            size: 16,
                                          ),
                                          label: Text(
                                            '${_score(hospital.id).toStringAsFixed(0)}% clinical match',
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (recommendation != null &&
                                      recommendation['match_reasons']
                                          is List) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      (recommendation['match_reasons'] as List)
                                          .map((value) => value.toString())
                                          .join(' · '),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ],
                              );
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compactCard =
                                        constraints.maxWidth < 620;
                                    final info = Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor:
                                              hospital.isEmergencyAvailable
                                              ? AppColors.mint
                                              : const Color(0xFFE8F1FD),
                                          foregroundColor:
                                              hospital.isEmergencyAvailable
                                              ? AppColors.teal
                                              : AppColors.blue,
                                          child: const Icon(
                                            AppIcons.localHospitalRounded,
                                          ),
                                        ),
                                        const SizedBox(width: 13),
                                        Expanded(child: details),
                                      ],
                                    );
                                    final detailsButton = OutlinedButton.icon(
                                      onPressed: () => context.go(
                                        '/hospitals/${hospital.id}',
                                      ),
                                      style: compactCard
                                          ? OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 44),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: AppSpacing.xs,
                                                  ),
                                            )
                                          : null,
                                      icon: const Icon(
                                        AppIcons.infoOutlineRounded,
                                      ),
                                      label: const Text('Details'),
                                    );
                                    final directionsButton = FilledButton.icon(
                                      onPressed: () => _directions(hospital),
                                      style: compactCard
                                          ? FilledButton.styleFrom(
                                              minimumSize: const Size(0, 44),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: AppSpacing.xs,
                                                  ),
                                            )
                                          : null,
                                      icon: const Icon(
                                        AppIcons.directionsRounded,
                                      ),
                                      label: const Text('Directions'),
                                    );
                                    if (compactCard) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          info,
                                          const SizedBox(height: AppSpacing.sm),
                                          Row(
                                            children: [
                                              Expanded(child: detailsButton),
                                              const SizedBox(
                                                width: AppSpacing.xs,
                                              ),
                                              Expanded(child: directionsButton),
                                            ],
                                          ),
                                        ],
                                      );
                                    }
                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: info),
                                        const SizedBox(width: 8),
                                        Column(
                                          children: [
                                            SizedBox(
                                              width: 138,
                                              height: 44,
                                              child: detailsButton,
                                            ),
                                            const SizedBox(height: 8),
                                            SizedBox(
                                              width: 138,
                                              height: 44,
                                              child: directionsButton,
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        );
                        final preview = _HospitalMapPreview(
                          hospitals: mapHospitals,
                          selectedHospitalId: selectedId,
                          userPosition: _position,
                          onSelected: (hospital) =>
                              setState(() => _selectedHospitalId = hospital.id),
                          onDetails: (hospital) =>
                              context.go('/hospitals/${hospital.id}'),
                          onDirections: _directions,
                        );
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth >= 900) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 8, child: preview),
                                  const SizedBox(width: AppSpacing.lg),
                                  Expanded(
                                    flex: 5,
                                    child: _RankedResultsFrame(
                                      count: ranked.length,
                                      child: results,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return ListView(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.lg,
                              ),
                              children: [
                                SizedBox(height: 390, child: preview),
                                const SizedBox(height: AppSpacing.md),
                                _RankedResultsFrameCompact(
                                  count: ranked.length,
                                  child: results,
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendButton() => FilledButton.icon(
    onPressed: _recommending ? null : _recommend,
    icon: _recommending
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(AppIcons.recommendOutlined),
    label: const Text('Rank care matches'),
  );

  double? _distance(Hospital hospital) {
    if (_position == null ||
        hospital.latitude == null ||
        hospital.longitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(
          _position!.latitude,
          _position!.longitude,
          hospital.latitude!,
          hospital.longitude!,
        ) /
        1000;
  }

  double _score(String hospitalId) {
    final value = _recommendations[hospitalId]?['match_score'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _RankedResultsFrame extends StatelessWidget {
  const _RankedResultsFrame({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'CARE MATCHES',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.forest,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        '$count ranked ${count == 1 ? 'facility' : 'facilities'}',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Select a marker or compare the ranked directory.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.md),
      Expanded(child: child),
    ],
  );
}

class _RankedResultsFrameCompact extends StatelessWidget {
  const _RankedResultsFrameCompact({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'CARE MATCHES',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.forest,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        '$count ranked ${count == 1 ? 'facility' : 'facilities'}',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Select a marker or compare the ranked directory.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.md),
      child,
    ],
  );
}

class _HospitalMapPreview extends StatelessWidget {
  const _HospitalMapPreview({
    required this.hospitals,
    required this.selectedHospitalId,
    required this.userPosition,
    required this.onSelected,
    required this.onDetails,
    required this.onDirections,
  });

  final List<Hospital> hospitals;
  final String selectedHospitalId;
  final Position? userPosition;
  final ValueChanged<Hospital> onSelected;
  final ValueChanged<Hospital> onDetails;
  final ValueChanged<Hospital> onDirections;

  @override
  Widget build(BuildContext context) {
    final mapped = hospitals
        .where(
          (hospital) => hospital.latitude != null && hospital.longitude != null,
        )
        .toList(growable: false);
    final selected = hospitals.firstWhere(
      (hospital) => hospital.id == selectedHospitalId,
      orElse: () => hospitals.first,
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: mapped.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIconTile(
                      icon: AppIcons.mapOutlined,
                      color: AppColors.blue,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Map preview unavailable',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'These facilities do not have verified coordinates yet. The ranked directory remains available.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final theme = Theme.of(context);
                final mapPoints = <LatLng>[
                  for (final hospital in mapped)
                    LatLng(hospital.latitude!, hospital.longitude!),
                  if (userPosition case final position?)
                    LatLng(position.latitude, position.longitude),
                ];
                final mapLayer = FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.coordinates(
                      coordinates: mapPoints,
                      padding: const EdgeInsets.fromLTRB(48, 88, 48, 140),
                      minZoom: 11,
                      maxZoom: 16,
                    ),
                    minZoom: 4,
                    maxZoom: 19,
                    backgroundColor: AppColors.alabaster,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'ph.carenavigator.app',
                      maxNativeZoom: 19,
                    ),
                    MarkerLayer(
                      markers: [
                        for (final hospital in mapped)
                          Marker(
                            key: ValueKey('hospital-${hospital.id}'),
                            point: LatLng(
                              hospital.latitude!,
                              hospital.longitude!,
                            ),
                            width: 48,
                            height: 48,
                            child: _HospitalMapMarker(
                              hospital: hospital,
                              selected: hospital.id == selected.id,
                              onTap: () => onSelected(hospital),
                            ),
                          ),
                        if (userPosition case final position?)
                          Marker(
                            key: const ValueKey('user-location'),
                            point: LatLng(
                              position.latitude,
                              position.longitude,
                            ),
                            width: 24,
                            height: 24,
                            child: const _UserLocationMarker(),
                          ),
                      ],
                    ),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(
                          'OpenStreetMap contributors',
                          onTap: () => launchUrl(
                            Uri.parse('https://openstreetmap.org/copyright'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(child: mapLayer),
                    Positioned(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      top: AppSpacing.md,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .94),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppColors.outline),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  AppIcons.locationOnOutlined,
                                  size: 16,
                                  color: AppColors.blue,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Verified locations',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (!compact)
                            Text(
                              'Drag to explore - pinch to zoom',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      bottom: AppSpacing.md,
                      child: _SelectedHospitalCard(
                        hospital: selected,
                        compact: compact,
                        onDetails: () => onDetails(selected),
                        onDirections: () => onDirections(selected),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _HospitalMapMarker extends StatelessWidget {
  const _HospitalMapMarker({
    required this.hospital,
    required this.selected,
    required this.onTap,
  });

  final Hospital hospital;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: hospital.name,
    child: Semantics(
      button: true,
      selected: selected,
      label: 'Select ${hospital.name}',
      child: Material(
        color: selected ? AppColors.blue : Colors.white,
        elevation: selected ? 8 : 3,
        shadowColor: AppColors.navy.withValues(alpha: .24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              AppIcons.localHospitalRounded,
              size: 22,
              color: selected ? Colors.white : AppColors.blue,
            ),
          ),
        ),
      ),
    ),
  );
}

class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Your location',
    child: Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: AppColors.teal,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x33007F73), blurRadius: 8)],
      ),
    ),
  );
}

class _SelectedHospitalCard extends StatelessWidget {
  const _SelectedHospitalCard({
    required this.hospital,
    required this.compact,
    required this.onDetails,
    required this.onDirections,
  });

  final Hospital hospital;
  final bool compact;
  final VoidCallback onDetails;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .97),
      elevation: 8,
      shadowColor: AppColors.navy.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Row(
          children: [
            const AppIconTile(
              icon: AppIcons.localHospitalRounded,
              color: AppColors.blue,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hospital.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hospital.locationLabel.isNotEmpty
                        ? hospital.locationLabel
                        : hospital.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (!compact)
              TextButton(onPressed: onDetails, child: const Text('Details')),
            IconButton.filled(
              tooltip: 'Open directions',
              onPressed: onDirections,
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              icon: const Icon(AppIcons.directionsRounded),
            ),
          ],
        ),
      ),
    );
  }
}
