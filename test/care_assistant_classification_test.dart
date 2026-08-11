import 'package:care_navigator_ph/src/repositories/care_assistant_repository.dart';
import 'package:care_navigator_ph/src/services/care_assistant_input_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CareAssistantNeedProfile classification', () {
    test(
      'classifies unrelated programming help as non-medical routine input',
      () {
        final profile = classifyCareAssistantInput('help me with javascript');

        expect(profile.intent, CareAssistantIntent.nonMedical);
        expect(profile.isEmergency, isFalse);
      },
    );

    test('classifies a headache as medical but not emergency', () {
      final profile = classifyCareAssistantInput('I have a headache');

      expect(profile.intent, CareAssistantIntent.medical);
      expect(profile.isEmergency, isFalse);
    });

    test('classifies clear breathing danger as emergency', () {
      final profile = classifyCareAssistantInput(
        "I have severe chest pain and can't breathe",
      );

      expect(profile.intent, CareAssistantIntent.emergency);
      expect(profile.isEmergency, isTrue);
    });

    test('classifies ambiguous breathing difficulty as urgent follow-up', () {
      final profile = classifyCareAssistantInput(
        'I have a hard time breathing and my tonsil has many stones',
      );

      expect(profile.intent, CareAssistantIntent.medical);
      expect(profile.urgency, CareAssistantUrgency.urgent);
      expect(profile.isEmergency, isFalse);
      expect(profile.followUpQuestion, contains('speak normally'));
    });

    test('classifies swallowing difficulty as urgent medical input', () {
      final profile = classifyCareAssistantInput(
        'I have a hard time swallowing food',
      );

      expect(profile.intent, CareAssistantIntent.medical);
      expect(profile.urgency, CareAssistantUrgency.urgent);
      expect(profile.isEmergency, isFalse);
      expect(profile.followUpQuestion, contains('swallow liquids'));
    });

    test('classifies tonsil stones as medical without emergency actions', () {
      final profile = classifyCareAssistantInput('I have tonsil stones');

      expect(profile.intent, CareAssistantIntent.medical);
      expect(profile.urgency, CareAssistantUrgency.soon);
      expect(profile.isEmergency, isFalse);
    });

    test('classifies difficulty eating as medical conversational input', () {
      final profile = classifyCareAssistantInput(
        'I have a hard time eating food',
      );

      expect(profile.intent, CareAssistantIntent.medical);
      expect(profile.urgency, CareAssistantUrgency.soon);
      expect(profile.isEmergency, isFalse);
      expect(profile.followUpQuestion, contains('chewing or swallowing'));
    });

    test('asks for clarification for vague health wording', () {
      final profile = classifyCareAssistantInput('I feel bad');

      expect(profile.intent, CareAssistantIntent.unclear);
      expect(profile.isEmergency, isFalse);
    });

    test('keeps short answers inside an active medical conversation', () {
      final profile = classifyCareAssistantInput(
        'two days',
      ).continueMedicalConversation();

      expect(profile.intent, CareAssistantIntent.medical);
      expect(profile.urgency, CareAssistantUrgency.routine);
    });

    test('allows an explicit topic change during a medical conversation', () {
      final profile = classifyCareAssistantInput(
        'help me with javascript',
      ).continueMedicalConversation();

      expect(profile.intent, CareAssistantIntent.nonMedical);
      expect(profile.isExplicitlyNonMedical, isTrue);
    });
  });

  test('structured reply parses intent and urgency independently', () {
    final reply = CareAssistantReply.fromMap(const {
      'message': 'Tell me what health concern you are experiencing.',
      'intent': 'non_medical',
      'urgency': 'routine',
      'showEmergencyActions': false,
    });

    expect(reply.intent, CareAssistantIntent.nonMedical);
    expect(reply.urgency, CareAssistantUrgency.routine);
  });
}
