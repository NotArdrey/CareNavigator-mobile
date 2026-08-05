import 'dart:async';

import 'package:care_navigator_ph/src/features/hospitals/presentation/hospital_image.dart';
import 'package:care_navigator_ph/src/models/ai_assessment.dart';
import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
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
    final horizontal = AppPageBody.horizontalPadding(width);

    return SafeArea(
      child: Column(
        children: [
          AppPageHeader(
            eyebrow: 'Care direction tool',
            title: 'Find the right level of care',
            subtitle:
                'Describe symptoms and receive preliminary navigation guidance',
            icon: AppIcons.symptomCheck,
            onBack: () => context.go('/home'),
            backTooltip: 'Back to home',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontal, 28, horizontal, 42),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _AssessmentIntro(),
                      const SizedBox(height: AppSpacing.lg),
                      const _EmergencyNotice(),
                      const SizedBox(height: AppSpacing.xl),
                      if (width >= 900)
                        AppCard(
                          padding: EdgeInsets.zero,
                          borderRadius: AppRadius.extraLarge,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildForm()),
                              const SizedBox(
                                height: 760,
                                child: VerticalDivider(),
                              ),
                              Expanded(child: _buildResult()),
                            ],
                          ),
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
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Build your symptom profile',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Specific details help identify urgency and suitable care capability.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
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
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: _submitting
                  ? 'Preparing guidance…'
                  : 'Generate care guidance',
              icon: AppIcons.arrowForwardRounded,
              loading: _submitting,
              expand: true,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final result = _result;
    if (result == null) {
      return SizedBox(
        height: MediaQuery.sizeOf(context).width >= 900 ? 700 : 320,
        child: const AppEmptyState(
          icon: AppIcons.routeOutlined,
          title: 'Your care direction will appear here',
          message:
              'Complete the symptom profile to see urgency, suggested department, and matching facility requirements.',
        ),
      );
    }
    final emergency = result.isEmergency;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        tone: emergency ? AppCardTone.coral : AppCardTone.mint,
        padding: const EdgeInsets.all(AppSpacing.xl),
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
                    emergency ? 'EMERGENCY' : result.urgencyLevel.toUpperCase(),
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
                          leading: const Icon(AppIcons.circle, size: 8),
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
                icon: const Icon(AppIcons.nearMeOutlined),
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
                  AppIcons.localHospitalOutlined,
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
                    icon: const Icon(AppIcons.myLocationRounded),
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
              child: Icon(AppIcons.chevronRightRounded),
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

class _AssessmentIntro extends StatelessWidget {
  const _AssessmentIntro();

  @override
  Widget build(BuildContext context) => AppCard(
    tone: AppCardTone.dark,
    borderRadius: AppRadius.extraLarge,
    padding: const EdgeInsets.all(AppSpacing.xxl),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final introduction = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppStatusBadge(
              label: 'PRELIMINARY GUIDANCE',
              color: Color(0xFF9DD8C8),
              icon: AppIcons.healthAndSafetyOutlined,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'From symptoms to a safer next step.',
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Care Navigator suggests urgency and facility capability. It does not diagnose, prescribe, or replace a clinician.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: const Color(0xFFC7D7D1)),
            ),
          ],
        );
        final steps = const Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _AssessmentStep(number: '01', label: 'Describe'),
            _AssessmentStep(number: '02', label: 'Review'),
            _AssessmentStep(number: '03', label: 'Find care'),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              introduction,
              const SizedBox(height: AppSpacing.xl),
              steps,
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: introduction),
            const SizedBox(width: AppSpacing.xxxl),
            Expanded(flex: 2, child: steps),
          ],
        );
      },
    ),
  );
}

class _AssessmentStep extends StatelessWidget {
  const _AssessmentStep({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(AppRadius.medium),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: const TextStyle(
            color: AppColors.sea,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    ),
  );
}

class _EmergencyNotice extends StatelessWidget {
  const _EmergencyNotice();

  @override
  Widget build(BuildContext context) => const AppNotice(
    title: 'Emergency guidance',
    icon: AppIcons.emergencyRounded,
    color: AppColors.danger,
    message:
        'Do not wait for this tool during an emergency. Call 911 or go to the nearest emergency room now.',
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
