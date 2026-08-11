import '../repositories/care_assistant_repository.dart';

class CareAssistantInputClassification {
  const CareAssistantInputClassification({
    required this.intent,
    required this.urgency,
    this.followUpQuestion,
    this.isExplicitlyNonMedical = false,
  });

  final CareAssistantIntent intent;
  final CareAssistantUrgency urgency;
  final String? followUpQuestion;
  final bool isExplicitlyNonMedical;

  bool get isEmergency => urgency == CareAssistantUrgency.emergency;

  CareAssistantInputClassification continueMedicalConversation() {
    if (isEmergency ||
        intent == CareAssistantIntent.medical ||
        isExplicitlyNonMedical) {
      return this;
    }
    return const CareAssistantInputClassification(
      intent: CareAssistantIntent.medical,
      urgency: CareAssistantUrgency.routine,
    );
  }
}

CareAssistantInputClassification classifyCareAssistantInput(String rawText) {
  final text = rawText.trim().toLowerCase();
  final hasSeverity = _hasAny(text, const ['severe', 'heavy', 'serious']);
  final chestPain = _hasAny(text, const ['chest pain', 'heart pain']);
  final trauma = _hasAny(text, const [
    'accident',
    'injury',
    'injured',
    'fracture',
    'broken',
    'fall',
    'crash',
  ]);
  final emergency =
      _hasAny(text, const [
        "can't breathe",
        'cannot breathe',
        'unable to breathe',
        'gasping for air',
        "can't catch my breath",
        'cannot catch my breath',
        'struggling to breathe',
        'severe difficulty breathing',
        'severe breathing difficulty',
        'severe trouble breathing',
        'unconscious',
        'unresponsive',
        'ongoing seizure',
        'seizure',
        'stroke',
        'face droop',
        'slurred speech',
        'severe bleeding',
        'heavy bleeding',
        'uncontrolled bleeding',
        'blue lips',
        'anaphylaxis',
        'severe allergic reaction',
        'choking',
        'major trauma',
        'suicidal',
        'suicide',
        'kill myself',
        'hurt myself',
        'self harm',
      ]) ||
      (chestPain && hasSeverity) ||
      (trauma &&
          _hasAny(text, const [
            'major',
            'severe',
            'unconscious',
            'heavy bleeding',
            'uncontrolled bleeding',
            'crush',
            'ejected',
          ]));
  if (emergency) {
    return const CareAssistantInputClassification(
      intent: CareAssistantIntent.emergency,
      urgency: CareAssistantUrgency.emergency,
    );
  }

  final breathingConcern = _hasAny(text, const [
    'trouble breathing',
    'difficulty breathing',
    'hard time breathing',
    'shortness of breath',
    'short of breath',
  ]);
  final swallowingConcern = _hasAny(text, const [
    'difficulty swallowing',
    'difficult to swallow',
    'hard time swallowing',
    'trouble swallowing',
    "can't swallow",
    'cannot swallow',
  ]);
  final eatingConcern = _hasAny(text, const [
    'hard time eating',
    'difficulty eating',
    'difficult to eat',
    'trouble eating',
    "can't eat",
    'cannot eat',
  ]);
  final urgentConcern =
      breathingConcern ||
      swallowingConcern ||
      chestPain ||
      _hasAny(text, const ['heart racing', 'bleeding', 'very dizzy']);
  if (urgentConcern) {
    final question = breathingConcern
        ? 'How severe is the breathing difficulty right now? Can you speak normally and breathe comfortably while sitting, or are you struggling, gasping, or unable to catch your breath?'
        : swallowingConcern
        ? 'Can you swallow liquids and your saliva? Are you drooling, having trouble breathing, or noticing rapidly worsening throat or neck swelling?'
        : chestPain
        ? 'How severe is the chest pain, and are you having trouble breathing, fainting, sweating heavily, or pain spreading to your arm, jaw, or back?'
        : 'How severe is it right now, and is it worsening or accompanied by fainting, breathing difficulty, or weakness?';
    return CareAssistantInputClassification(
      intent: CareAssistantIntent.medical,
      urgency: CareAssistantUrgency.urgent,
      followUpQuestion: question,
    );
  }

  if (eatingConcern) {
    return const CareAssistantInputClassification(
      intent: CareAssistantIntent.medical,
      urgency: CareAssistantUrgency.soon,
      followUpQuestion:
          'When you say eating is difficult, is the problem chewing or swallowing, pain, nausea, or a lack of appetite?',
    );
  }

  final medical = _hasAny(text, const [
    'pain',
    'headache',
    'fever',
    'vomit',
    'rash',
    'infection',
    'dizzy',
    'breath',
    'asthma',
    'chest',
    'stomach',
    'abdominal',
    'belly',
    'injury',
    'fracture',
    'pregnan',
    'doctor',
    'hospital',
    'clinic',
    'healthcare',
    'medical',
    'medicine',
    'checkup',
    'consultation',
    'swallow',
    'throat',
    'tonsil',
    'eat',
    'eating',
    'appetite',
    'chew',
    'mouth',
    'jaw',
  ]);
  if (medical) {
    return CareAssistantInputClassification(
      intent: CareAssistantIntent.medical,
      urgency: _hasAny(text, const ['tonsil', 'throat', 'swallow'])
          ? CareAssistantUrgency.soon
          : CareAssistantUrgency.routine,
    );
  }

  final vagueHealthLanguage = _hasAny(text, const [
    'feel bad',
    'feel strange',
    'feel wrong',
    'unwell',
    'sick',
    'not okay',
  ]);
  final explicitlyNonMedical = _hasAny(text, const [
    'javascript',
    'python code',
    'programming',
    'coding',
    'cook ',
    'cooking',
    'recipe',
    'homework',
    'math problem',
    'weather forecast',
    'sports score',
    'movie recommendation',
    'video game',
    'tell me a joke',
  ]);
  return CareAssistantInputClassification(
    intent: vagueHealthLanguage || text.split(RegExp(r'\s+')).length < 3
        ? CareAssistantIntent.unclear
        : CareAssistantIntent.nonMedical,
    urgency: CareAssistantUrgency.routine,
    isExplicitlyNonMedical: explicitlyNonMedical,
  );
}

bool _hasAny(String value, List<String> terms) => terms.any(value.contains);
