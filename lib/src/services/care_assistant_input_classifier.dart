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
  final seizureDanger = _hasAny(text, const [
    'ongoing seizure',
    'first seizure',
    'seizure lasting',
    'multiple seizures',
    'seizures back to back',
    'seizure in water',
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
      seizureDanger ||
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
      _hasAny(text, const ['seizure']) ||
      _hasAny(text, const ['heart racing', 'bleeding', 'very dizzy']);
  if (urgentConcern) {
    final question = breathingConcern
        ? 'How severe is the breathing difficulty right now? Can you speak normally and breathe comfortably while sitting, or are you struggling, gasping, or unable to catch your breath?'
        : swallowingConcern
        ? 'Can you swallow liquids and your saliva? Are you drooling, having trouble breathing, or noticing rapidly worsening throat or neck swelling?'
        : chestPain
        ? 'How severe is the chest pain, and are you having trouble breathing, fainting, sweating heavily, or pain spreading to your arm, jaw, or back?'
        : _hasAny(text, const ['seizure'])
        ? 'Is the seizure happening now, is this the first one, has it lasted 5 minutes or longer, or have seizures repeated without full recovery?'
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
    'cut',
    'wound',
    'burn',
    'scald',
    'sprain',
    'poison',
    'overdose',
    'bite',
    'sting',
    'nosebleed',
    'faint',
    'seizure',
    'choking',
    'allergic',
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

// Keep these offline emergency fallbacks aligned with current public guidance:
// https://www.redcross.org/take-a-class/first-aid/performing-first-aid/first-aid-steps
// https://www.redcross.org/take-a-class/resources/learn-first-aid/infant-choking
// https://www.redcross.org/take-a-class/resources/learn-first-aid/seizures
// https://international.heart.org/resuscitation/hands-only-cpr
CareAssistantFirstAidGuidance emergencyFirstAidFor(String rawText) {
  final text = rawText.trim().toLowerCase();
  const emergencySigns = [
    'The symptoms described are already warning signs requiring emergency medical care.',
    'Any loss of responsiveness, absent or abnormal breathing, blue or gray lips, or rapid worsening is immediately life-threatening.',
  ];

  if (_hasAny(text, const [
    'suicidal',
    'suicide',
    'kill myself',
    'hurt myself',
    'self harm',
    'self-harm',
  ])) {
    return const CareAssistantFirstAidGuidance(
      immediateActions: [
        'Contact local emergency services or a crisis service now and say there is an immediate self-harm risk.',
        'Move away from weapons, medicines, heights, traffic, or other immediate dangers if this can be done safely.',
        'Stay with the person, or ask a trusted adult to stay, until professional help takes over.',
      ],
      avoid: [
        'Do not stay alone or promise to keep the danger secret.',
        'Do not argue, shame, threaten, or leave to search for help without first contacting emergency support.',
      ],
      warningSigns: emergencySigns,
    );
  }

  if (_hasAny(text, const ['choking'])) {
    return const CareAssistantFirstAidGuidance(
      immediateActions: [
        'Contact local emergency services now and put the phone on speaker.',
        'If the person can cough or speak, encourage forceful coughing and watch closely.',
        'If they cannot cough, speak, or breathe: for an adult or child over 1 year, alternate 5 back blows with 5 abdominal thrusts; use chest thrusts instead during pregnancy.',
        'For an infant under 1 year, alternate 5 back blows with 5 chest thrusts. Follow the dispatcher’s instructions.',
        'If the person becomes unresponsive, lower them to a firm surface and begin age-appropriate CPR; use an AED if available.',
      ],
      avoid: [
        'Do not perform a blind finger sweep or try to pull out an object you cannot clearly see.',
        'Do not give food or drink, and do not use abdominal thrusts on an infant or a pregnant person.',
      ],
      warningSigns: emergencySigns,
    );
  }

  if (_hasAny(text, const [
    'uncontrolled bleeding',
    'severe bleeding',
    'heavy bleeding',
  ])) {
    return const CareAssistantFirstAidGuidance(
      immediateActions: [
        'Contact local emergency services now and put the phone on speaker.',
        'Expose the wound and press firmly and continuously with gauze or a clean cloth.',
        'If blood soaks through, keep pressing and add more cloth on top without removing the first layer.',
        'For life-threatening bleeding from an arm or leg, use a commercial tourniquet only if you are trained or the emergency dispatcher directs you.',
        'Keep the person warm and still while watching their breathing and responsiveness.',
      ],
      avoid: [
        'Do not remove an embedded object; press around it instead.',
        'Do not repeatedly lift the cloth to check the wound or give food or drink.',
      ],
      warningSigns: emergencySigns,
    );
  }

  if (_hasAny(text, const ['ongoing seizure', 'seizure'])) {
    return const CareAssistantFirstAidGuidance(
      immediateActions: [
        'Contact local emergency services now and note the time the seizure started.',
        'Clear hard or sharp objects away, cushion the head, loosen tight clothing around the neck, and protect the person from injury.',
        'When the shaking stops, place the person on their side if you can do so safely and monitor breathing.',
        'Stay with the person until they are fully alert or professional help arrives.',
      ],
      avoid: [
        'Do not restrain the person or put anything in their mouth.',
        'Do not give food, drink, or medicine until they are fully alert and can swallow safely.',
      ],
      warningSigns: emergencySigns,
    );
  }

  if (_hasAny(text, const ['anaphylaxis', 'severe allergic reaction'])) {
    return const CareAssistantFirstAidGuidance(
      immediateActions: [
        'Contact local emergency services now and put the phone on speaker.',
        'Use the person’s prescribed epinephrine auto-injector immediately, exactly as directed, if it is available.',
        'Have the person lie down with legs raised; if breathing is difficult, let them sit up slowly. Keep them still.',
        'If they become unresponsive and are not breathing normally, begin age-appropriate CPR and use an AED if available.',
      ],
      avoid: [
        'Do not let the person stand or walk, and do not delay emergency care to see whether symptoms improve.',
        'Do not give food, drink, or an unprescribed medicine.',
      ],
      warningSigns: emergencySigns,
    );
  }

  if (_hasAny(text, const ['stroke', 'face droop', 'slurred speech'])) {
    return const CareAssistantFirstAidGuidance(
      immediateActions: [
        'Contact local emergency services now and note the exact time symptoms began or the person was last known well.',
        'Keep the person safe and comfortable, support a weak limb, and monitor breathing and responsiveness.',
        'If they become unresponsive and are not breathing normally, begin age-appropriate CPR and use an AED if available.',
      ],
      avoid: [
        'Do not drive the person yourself if emergency transport is available.',
        'Do not give food, drink, aspirin, or other medicine unless an emergency professional instructs you.',
      ],
      warningSigns: emergencySigns,
    );
  }

  if (_hasAny(text, const ['unconscious', 'unresponsive', 'gasping'])) {
    return const CareAssistantFirstAidGuidance(
      immediateActions: [
        'Make sure the area is safe, contact local emergency services now, and put the phone on speaker.',
        'Check for a response and normal breathing. Gasping is not normal breathing.',
        'If the person is not breathing normally, start age-appropriate CPR immediately and follow the dispatcher’s coaching.',
        'Send someone for an AED, turn it on, and follow its prompts as soon as it arrives.',
      ],
      avoid: [
        'Do not leave the person alone or delay CPR to check for a pulse if you are not a healthcare professional.',
        'Do not give anything by mouth.',
      ],
      warningSigns: emergencySigns,
    );
  }

  if (_hasAny(text, const ['major trauma', 'crush', 'ejected'])) {
    return const CareAssistantFirstAidGuidance(
      immediateActions: [
        'Contact local emergency services now, make the scene safe, and put the phone on speaker.',
        'Keep the person still and support the head and neck in the position found unless there is immediate danger.',
        'Control severe external bleeding with firm, continuous direct pressure and monitor breathing.',
        'Keep the person warm until professional help arrives.',
      ],
      avoid: [
        'Do not move, straighten, or sit the person up unless the scene is dangerous or breathing requires it.',
        'Do not remove an embedded object or give food, drink, or medicine.',
      ],
      warningSigns: emergencySigns,
    );
  }

  return const CareAssistantFirstAidGuidance(
    immediateActions: [
      'Contact local emergency services now and put the phone on speaker.',
      'Keep the person at rest in the position that makes breathing easiest and loosen tight clothing.',
      'Help with their own prescribed rescue medicine only if it is intended for this situation, and follow the label or emergency dispatcher’s instructions.',
      'Monitor breathing and responsiveness; if they become unresponsive and are not breathing normally, begin age-appropriate CPR and use an AED if available.',
    ],
    avoid: [
      'Do not leave the person alone, let them drive, or delay emergency care to continue chatting.',
      'Do not give food, drink, or someone else’s medicine.',
    ],
    warningSigns: emergencySigns,
  );
}

bool _hasAny(String value, List<String> terms) => terms.any(value.contains);
