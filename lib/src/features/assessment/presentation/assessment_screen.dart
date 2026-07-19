import 'dart:async';

import 'package:care_navigator_ph/src/features/hospitals/presentation/hospital_image.dart';
import 'package:care_navigator_ph/src/models/ai_assessment.dart';
import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({super.key});

  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _symptoms = TextEditingController();
  final _duration = TextEditingController();
  final _age = TextEditingController();
  final _conditions = TextEditingController();
  final _allergies = TextEditingController();
  final _medications = TextEditingController();

  AiAssessment? _result;
  bool _submitting = false;
  bool _findingHospitals = false;
  String? _hospitalMessage;
  List<_HospitalMatch> _hospitalMatches = const [];
  int _recommendationRun = 0;

  @override
  void dispose() {
    for (final controller in [
      _symptoms,
      _duration,
      _age,
      _conditions,
      _allergies,
      _medications,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 600 ? 20.0 : 40.0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(horizontal, 28, horizontal, 42),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI symptom navigator',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Describe what you are experiencing. CareNavigator will suggest urgency and the type of care to seek—it will not diagnose or prescribe.',
                ),
                const SizedBox(height: 18),
                const _EmergencyNotice(),
                const SizedBox(height: 20),
                if (width >= 900)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildForm()),
                      const SizedBox(width: 18),
                      Expanded(child: _buildResult()),
                    ],
                  )
                else ...[
                  _buildForm(),
                  const SizedBox(height: 18),
                  _buildResult(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tell us what you feel',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _symptoms,
                minLines: 4,
                maxLines: 7,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Symptoms *',
                  hintText:
                      'Example: fever, dry cough, and headache since yesterday',
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Describe at least one symptom.'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _duration,
                      decoration: const InputDecoration(
                        labelText: 'How long?',
                        hintText: '2 days',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Age'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final age = int.tryParse(value.trim());
                        return age == null || age < 0 || age > 120
                            ? 'Use 0–120.'
                            : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _conditions,
                minLines: 2,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Existing conditions',
                  hintText: 'Example: Asthma\nDiabetes',
                  helperText: 'Enter one per line or separate with commas.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _allergies,
                minLines: 2,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Allergies',
                  hintText: 'Example: Penicillin\nPeanuts',
                  helperText: 'Enter one per line or separate with commas.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _medications,
                minLines: 2,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Current medications',
                  hintText: 'Example: Metformin\nLosartan',
                  helperText: 'Enter one per line or separate with commas.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    _submitting ? 'Assessing safely…' : 'Check symptoms',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    final result = _result;
    if (result == null) {
      return const SizedBox(
        width: double.infinity,
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(26),
            child: Column(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  size: 46,
                  color: AppColors.blue,
                ),
                SizedBox(height: 14),
                Text(
                  'Your navigation result will appear here.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    final emergency = result.isEmergency;
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: emergency ? const Color(0xFFFFE8E6) : AppColors.mint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emergency
                          ? 'EMERGENCY'
                          : result.urgencyLevel.toUpperCase(),
                      style: TextStyle(
                        color: emergency ? AppColors.danger : AppColors.teal,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      result.recommendedAction,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _ResultSection(
                title: 'Recommended department',
                child: Text(result.recommendedDepartment),
              ),
              if (result.warningSigns.isNotEmpty)
                _ResultSection(
                  title: 'Warning signs',
                  child: _BulletList(items: result.warningSigns),
                ),
              if (result.possibleConditions.isNotEmpty)
                _ResultSection(
                  title: 'Possibilities to discuss with a clinician',
                  child: Column(
                    children: result.possibleConditions
                        .map(
                          (item) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.circle, size: 8),
                            title: Text(item.name),
                            subtitle: item.rationale.isEmpty
                                ? null
                                : Text(item.rationale),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              if (result.hospitalRequirements.isNotEmpty)
                _ResultSection(
                  title: 'Look for a hospital with',
                  child: _BulletList(items: result.hospitalRequirements),
                ),
              _buildHospitalRecommendations(result),
              Text(
                result.disclaimer,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final parameters = <String, String>{
                      'need': result.recommendedDepartment,
                      if (result.isEmergency) 'emergency': '1',
                      'level': result.minimumHospitalLevel.toString(),
                      if (result.hospitalRequirements.isNotEmpty)
                        'services': result.hospitalRequirements.join('~'),
                    };
                    context.go(
                      Uri(
                        path: '/hospitals/map',
                        queryParameters: parameters,
                      ).toString(),
                    );
                  },
                  icon: const Icon(Icons.near_me_outlined),
                  label: Text(
                    emergency
                        ? 'Find nearby emergency rooms'
                        : 'Find matching hospitals',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => context.go('/hospitals'),
                  child: const Text('Browse the full hospital directory'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHospitalRecommendations(AiAssessment result) {
    return _ResultSection(
      title: 'Nearby hospitals for your needs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.local_hospital_outlined,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${result.hospitalLevelLabel} or higher recommended: '
                    '${result.hospitalLevelDescription}.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (_findingHospitals) ...[
            const SizedBox(height: 13),
            const LinearProgressIndicator(),
            const SizedBox(height: 9),
            const Text('Using your location to find capable hospitals…'),
          ] else if (_hospitalMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD98A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_hospitalMessage!),
                  const SizedBox(height: 7),
                  TextButton.icon(
                    onPressed: () => _findHospitals(result),
                    icon: const Icon(Icons.my_location_rounded),
                    label: const Text('Try location again'),
                  ),
                ],
              ),
            ),
          ] else if (_hospitalMatches.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._hospitalMatches.map(
              (match) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RecommendedHospitalCard(match: match),
              ),
            ),
            Text(
              'Distance is straight-line only. Confirm current services and open directions before leaving.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(assessmentRepositoryProvider)
          .analyze(
            symptoms: _symptoms.text,
            duration: _duration.text,
            age: int.tryParse(_age.text.trim()),
            existingConditions: _csv(_conditions.text),
            allergies: _csv(_allergies.text),
            currentMedications: _csv(_medications.text),
          );
      if (mounted) {
        setState(() {
          _result = result;
          _hospitalMatches = const [];
          _hospitalMessage = null;
        });
        unawaited(_findHospitals(result));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _findHospitals(AiAssessment result) async {
    final run = ++_recommendationRun;
    setState(() {
      _findingHospitals = true;
      _hospitalMessage = null;
      _hospitalMatches = const [];
    });
    try {
      final position = await _currentPosition();
      final requiredServices = <String>{
        result.recommendedDepartment,
        ...result.hospitalRequirements,
      }.where((value) => value.trim().isNotEmpty).toList(growable: false);
      final values = await ref
          .read(careRepositoryProvider)
          .recommendHospitals(
            department: result.recommendedDepartment,
            requiredServices: requiredServices,
            urgencyLevel: result.urgencyLevel,
            latitude: position.latitude,
            longitude: position.longitude,
            radiusKm: 100,
            limit: 25,
          );
      final hospitals = await ref.read(hospitalsProvider('').future);
      if (!mounted || run != _recommendationRun) return;

      final byId = {for (final hospital in hospitals) hospital.id: hospital};
      final matches = values
          .map((item) {
            final hospital = byId[item['hospital_id']?.toString()];
            if (hospital == null) return null;
            final reasons = (item['match_reasons'] as List? ?? const [])
                .map((value) => value.toString())
                .toList(growable: false);
            final hasClinicalMatch =
                result.isEmergency ||
                reasons.any(
                  (reason) =>
                      reason.contains('department') ||
                      reason.contains('service') ||
                      reason.contains('specialist'),
                );
            if (!hospital.meetsCapabilityLevel(result.minimumHospitalLevel) ||
                !hasClinicalMatch ||
                (result.isEmergency && !hospital.isEmergencyAvailable)) {
              return null;
            }
            return _HospitalMatch(
              hospital: hospital,
              distanceKm: _number(item['distance_km']),
              matchScore: _number(item['match_score']),
              reasons: reasons,
            );
          })
          .whereType<_HospitalMatch>()
          .take(3)
          .toList(growable: false);

      setState(() {
        _hospitalMatches = matches;
        _hospitalMessage = matches.isEmpty
            ? 'No nearby ${result.hospitalLevelLabel} hospitals currently report the required capability. Browse the map to widen your search.'
            : null;
      });
    } catch (error) {
      if (mounted && run == _recommendationRun) {
        setState(() => _hospitalMessage = _locationError(error));
      }
    } finally {
      if (mounted && run == _recommendationRun) {
        setState(() => _findingHospitals = false);
      }
    }
  }

  Future<Position> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Turn on location services to see nearby hospitals.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is blocked. Enable it in device settings to see nearby hospitals.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw Exception(
        'Allow location access to automatically see nearby capable hospitals.',
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }
}

class _RecommendedHospitalCard extends StatelessWidget {
  const _RecommendedHospitalCard({required this.match});

  final _HospitalMatch match;

  @override
  Widget build(BuildContext context) {
    final hospital = match.hospital;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFD8E4F2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/hospitals/${hospital.id}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HospitalImage(hospital: hospital, width: 104, height: 126),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hospital.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hospital.classificationLabel,
                      style: const TextStyle(
                        color: AppColors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      children: [
                        if (match.distanceKm != null)
                          Text(
                            '${match.distanceKm!.toStringAsFixed(1)} km away',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (match.matchScore != null)
                          Text(
                            '${match.matchScore!.round()}% match',
                            style: const TextStyle(
                              color: AppColors.teal,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                    if (match.reasons.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        match.reasons.take(2).join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 12, right: 10),
              child: Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _HospitalMatch {
  const _HospitalMatch({
    required this.hospital,
    required this.distanceKm,
    required this.matchScore,
    required this.reasons,
  });

  final Hospital hospital;
  final double? distanceKm;
  final double? matchScore;
  final List<String> reasons;
}

class _EmergencyNotice extends StatelessWidget {
  const _EmergencyNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F0),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFFD0CC)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.emergency_rounded, color: AppColors.danger),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Do not wait for this tool during an emergency. Call 911 or go to the nearest emergency room now.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 7),
        child,
      ],
    ),
  );
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: items
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text('•  $item'),
          ),
        )
        .toList(growable: false),
  );
}

List<String> _csv(String value) => value
    .split(RegExp(r'[,;\n\r]+'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);

String _friendlyError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.contains('401')
      ? 'Your session expired. Please sign in again.'
      : text;
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _locationError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.contains('TimeoutException')
      ? 'Location took too long. Check your signal and try again.'
      : text;
}
