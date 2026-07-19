import 'package:care_navigator_ph/src/models/ai_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a structured navigation assessment', () {
    final assessment = AiAssessment.fromJson({
      'possible_conditions': [
        {'name': 'Viral infection', 'rationale': 'Symptoms can overlap.'},
      ],
      'urgency_level': 'urgent',
      'warning_signs': ['Breathing becomes difficult'],
      'recommended_department': 'Internal Medicine',
      'recommended_action': 'Arrange an in-person evaluation today.',
      'hospital_requirements': ['Laboratory'],
      'disclaimer': 'Not a diagnosis.',
    });

    expect(assessment.urgencyLevel, 'urgent');
    expect(assessment.isEmergency, isFalse);
    expect(assessment.possibleConditions.single.name, 'Viral infection');
    expect(assessment.warningSigns, contains('Breathing becomes difficult'));
    expect(assessment.minimumHospitalLevel, 2);
  });

  test('identifies emergency results', () {
    final assessment = AiAssessment.fromJson({
      'urgency_level': 'emergency',
      'recommended_action': 'Call 911 now.',
      'disclaimer': 'Safety guidance only.',
    });

    expect(assessment.isEmergency, isTrue);
    expect(assessment.recommendedDepartment, 'General Medicine');
    expect(assessment.minimumHospitalLevel, 3);
  });

  test('routes advanced requirements to Level 3 care', () {
    final assessment = AiAssessment.fromJson({
      'urgency_level': 'routine',
      'recommended_department': 'Nephrology',
      'recommended_action': 'Arrange an evaluation.',
      'hospital_requirements': ['Dialysis unit'],
      'disclaimer': 'Not a diagnosis.',
    });

    expect(assessment.minimumHospitalLevel, 3);
    expect(assessment.hospitalLevelLabel, 'Level 3');
  });
}
