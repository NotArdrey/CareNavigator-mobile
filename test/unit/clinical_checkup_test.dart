import 'package:care_navigator_ph/src/models/clinical_checkup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BMI is calculated from height and weight', () {
    const checkup = ClinicalCheckupDraft(heightCm: 175, weightKg: 70);

    expect(checkup.bmi, closeTo(22.86, 0.01));
    expect(checkup.toPayload()['bmi'], closeTo(22.86, 0.01));
  });

  test('optional checkup data can be represented without identity fields', () {
    const checkup = ClinicalCheckupDraft(
      allergies: ['Penicillin'],
      currentMedications: ['Salbutamol'],
    );

    expect(checkup.hasAnyData, isTrue);
    expect(checkup.toPayload()['known_medical_conditions'], isEmpty);
    expect(checkup.toPayload()['allergies'], ['Penicillin']);
  });

  test('medical list input accepts commas, semicolons, and new lines', () {
    expect(clinicalListValues('Asthma, Hypertension; Diabetes\nMigraine'), [
      'Asthma',
      'Hypertension',
      'Diabetes',
      'Migraine',
    ]);
  });

  test('AI payload values are normalized into an editable checkup draft', () {
    final checkup = ClinicalCheckupDraft.fromPayload({
      'height_cm': '168.5',
      'heart_rate_bpm': 72.0,
      'known_medical_conditions': [' Hypertension ', '', 14],
      'doctor_notes': 'Notes: Follow-up form\n\nObservations: BP was flagged.',
    });

    expect(checkup.heightCm, 168.5);
    expect(checkup.heartRateBpm, 72);
    expect(checkup.knownMedicalConditions, ['Hypertension']);
    expect(checkup.doctorNotes, contains('Observations:'));
  });
}
