import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Nearby care',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                FilledButton.icon(
                  onPressed: _locating ? null : _locate,
                  icon: _locating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(
                    _position == null ? 'Use my location' : 'Refresh location',
                  ),
                ),
                FilterChip(
                  selected: _emergencyOnly,
                  onSelected: (value) => setState(() => _emergencyOnly = value),
                  avatar: const Icon(Icons.emergency_rounded, size: 18),
                  label: const Text('ER available'),
                ),
                DropdownButton<int>(
                  value: _minimumLevel,
                  onChanged: (value) {
                    if (value != null) setState(() => _minimumLevel = value);
                  },
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Level 1+ care')),
                    DropdownMenuItem(value: 2, child: Text('Level 2+ care')),
                    DropdownMenuItem(value: 3, child: Text('Level 3 care')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Verified hospitals are ranked by straight-line distance. Travel time can vary; open directions before leaving.',
            ),
            if (_emergencyOnly) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD0CC)),
                ),
                child: const Text(
                  'Emergency filter active. Call 911 for life-threatening symptoms and use Directions before leaving.',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (_locationError != null) ...[
              const SizedBox(height: 10),
              Text(
                _locationError!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _needController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _recommend(),
                    decoration: const InputDecoration(
                      labelText: 'Needed department, service, or specialty',
                      hintText: 'Example: Cardiology or dialysis',
                      prefixIcon: Icon(Icons.medical_information_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _recommending ? null : _recommend,
                  icon: _recommending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.recommend_outlined),
                  label: const Text('Rank matches'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: hospitals.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Could not load hospitals: $error'),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(hospitalsProvider('')),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (items) {
                  final ranked =
                      items
                          .where(
                            (hospital) =>
                                hospital.meetsCapabilityLevel(_minimumLevel) &&
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
                    return const Center(
                      child: Text('No verified hospitals match this filter.'),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.refresh(hospitalsProvider('').future),
                    child: ListView.separated(
                      itemCount: ranked.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = ranked[index];
                        final hospital = item.hospital;
                        final recommendation = _recommendations[hospital.id];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor: hospital.isEmergencyAvailable
                                      ? AppColors.mint
                                      : const Color(0xFFE8F1FD),
                                  foregroundColor: hospital.isEmergencyAvailable
                                      ? AppColors.teal
                                      : AppColors.blue,
                                  child: const Icon(
                                    Icons.local_hospital_rounded,
                                  ),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              visualDensity:
                                                  VisualDensity.compact,
                                              label: Text(
                                                '${item.distance!.toStringAsFixed(1)} km away',
                                              ),
                                            ),
                                          Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              '${hospital.availableBeds} beds',
                                            ),
                                          ),
                                          Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              hospital.isEmergencyAvailable
                                                  ? 'ER ${hospital.emergencyRoomStatus}'
                                                  : 'ER not reported available',
                                            ),
                                          ),
                                          if (recommendation != null)
                                            Chip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              avatar: const Icon(
                                                Icons.auto_awesome_rounded,
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
                                          (recommendation['match_reasons']
                                                  as List)
                                              .map((value) => value.toString())
                                              .join(' · '),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  children: [
                                    SizedBox(
                                      width: 138,
                                      height: 44,
                                      child: OutlinedButton.icon(
                                        onPressed: () => context.go(
                                          '/hospitals/${hospital.id}',
                                        ),
                                        icon: const Icon(
                                          Icons.info_outline_rounded,
                                        ),
                                        label: const Text('Details'),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: 138,
                                      height: 44,
                                      child: FilledButton.icon(
                                        onPressed: () => _directions(hospital),
                                        icon: const Icon(
                                          Icons.directions_rounded,
                                        ),
                                        label: const Text('Directions'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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
