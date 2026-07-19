class PossibleCondition {
  const PossibleCondition({required this.name, required this.rationale});

  factory PossibleCondition.fromJson(dynamic value) {
    if (value is String) {
      return PossibleCondition(name: value, rationale: '');
    }
    final json = Map<String, dynamic>.from(value as Map);
    return PossibleCondition(
      name: json['name']?.toString() ?? 'Possible condition',
      rationale: json['rationale']?.toString() ?? '',
    );
  }

  final String name;
  final String rationale;
}

class AiAssessment {
  const AiAssessment({
    required this.possibleConditions,
    required this.urgencyLevel,
    required this.warningSigns,
    required this.recommendedDepartment,
    required this.recommendedAction,
    required this.hospitalRequirements,
    required this.disclaimer,
  });

  factory AiAssessment.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => (json[key] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);

    return AiAssessment(
      possibleConditions: (json['possible_conditions'] as List? ?? const [])
          .map(PossibleCondition.fromJson)
          .toList(growable: false),
      urgencyLevel: json['urgency_level']?.toString() ?? 'routine',
      warningSigns: strings('warning_signs'),
      recommendedDepartment:
          json['recommended_department']?.toString() ?? 'General Medicine',
      recommendedAction:
          json['recommended_action']?.toString() ??
          'Contact a licensed healthcare professional.',
      hospitalRequirements: strings('hospital_requirements'),
      disclaimer:
          json['disclaimer']?.toString() ??
          'This preliminary assessment is not a medical diagnosis.',
    );
  }

  final List<PossibleCondition> possibleConditions;
  final String urgencyLevel;
  final List<String> warningSigns;
  final String recommendedDepartment;
  final String recommendedAction;
  final List<String> hospitalRequirements;
  final String disclaimer;

  bool get isEmergency => urgencyLevel == 'emergency';

  /// Minimum hospital capability level that can reasonably support the care
  /// navigation result. This is deterministic safety routing, not a diagnosis.
  int get minimumHospitalLevel {
    if (isEmergency) return 3;

    final needs = [
      recommendedDepartment,
      ...hospitalRequirements,
    ].join(' ').toLowerCase();
    const advancedCare = [
      'intensive care',
      'icu',
      'trauma',
      'cardiac catheter',
      'cardiothoracic',
      'neurosurgery',
      'neurology',
      'oncology',
      'dialysis',
      'mri',
      'ventilator',
      'blood bank',
      'burn unit',
      'high-risk',
    ];
    if (advancedCare.any(needs.contains)) return 3;

    if (urgencyLevel == 'urgent') return 2;
    const specialistCare = [
      'cardiology',
      'orthopedic',
      'surgery',
      'obstetric',
      'gynecology',
      'pediatric',
      'pulmonology',
      'nephrology',
      'gastroenterology',
      'specialist',
    ];
    return specialistCare.any(needs.contains) ? 2 : 1;
  }

  String get hospitalLevelLabel => 'Level $minimumHospitalLevel';

  String get hospitalLevelDescription => switch (minimumHospitalLevel) {
    3 => 'advanced specialty, intensive, and referral care',
    2 => 'specialist and intermediate hospital care',
    _ => 'basic hospital and first-contact care',
  };
}
