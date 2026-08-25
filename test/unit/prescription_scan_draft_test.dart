import 'package:care_navigator_ph/src/repositories/care_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prescription scan payload remains structured and editable', () {
    final draft = PrescriptionScanDraft.fromPayload({
      'diagnosis_reason': 'Bacterial infection',
      'medication_name': 'Amoxicillin',
      'medication_form_strength': '500 mg capsule',
      'route': 'Oral',
      'exact_dose': '1 capsule',
      'frequency': 'Every 8 hours',
      'duration': '7 days',
      'quantity_to_dispense': '21 capsules',
      'refills': 0,
      'start_date': '2026-08-23',
      'end_date': '2026-08-29',
      'is_prn': false,
      'instructions': 'Take after food.',
    });

    expect(draft.medicationName, 'Amoxicillin');
    expect(draft.medicationFormStrength, '500 mg capsule');
    expect(draft.exactDose, '1 capsule');
    expect(draft.refills, 0);
    expect(draft.startDate, DateTime(2026, 8, 23));
    expect(draft.endDate, DateTime(2026, 8, 29));
    expect(draft.isPrn, isFalse);
  });

  test('unknown scan values stay null instead of being invented', () {
    final draft = PrescriptionScanDraft.fromPayload({
      'medication_name': '  ',
      'refills': 'not stated',
      'start_date': null,
      'is_prn': false,
    });

    expect(draft.medicationName, isNull);
    expect(draft.refills, isNull);
    expect(draft.startDate, isNull);
  });

  test('multi-medication scan payload creates one editable draft per item', () {
    final drafts = PrescriptionScanDraft.listFromPayload({
      'prescription': {
        'diagnosis_reason': 'Hypertension',
        'medications': [
          {
            'medication_name': 'Amlodipine',
            'medication_form_strength': '5 mg tablet',
            'route': 'Oral',
          },
          {
            'medication_name': 'Losartan',
            'medication_form_strength': '50 mg tablet',
            'route': 'Oral',
          },
        ],
      },
    });

    expect(drafts, hasLength(2));
    expect(drafts.map((draft) => draft.medicationName), [
      'Amlodipine',
      'Losartan',
    ]);
    expect(
      drafts.map((draft) => draft.diagnosisReason),
      everyElement('Hypertension'),
    );
  });

  test('top-level medications array extracts all distinct medications', () {
    final drafts = PrescriptionScanDraft.listFromPayload({
      'diagnosis_reason': 'Post-operative care',
      'medications': [
        {
          'medication_name': 'HMBB',
          'medication_form_strength': '10mg tab',
          'exact_dose': '1 tab',
          'frequency': '3x a day',
          'quantity_to_dispense': '10',
          'refills': 0,
          'start_date': '2023-03-02',
          'instructions': '1 tab 3x a day',
        },
        {
          'medication_name': 'Ciprofloxacin',
          'medication_form_strength': '500mg tab',
          'exact_dose': '1 tab',
          'frequency': '2x a day for 1 week',
          'quantity_to_dispense': '14',
          'refills': 0,
          'start_date': '2023-03-02',
          'instructions': '1 tab 2x a day for 1 week',
        },
        {
          'medication_name': 'Sambong',
          'medication_form_strength': '500mg capsule',
          'exact_dose': '1 capsule',
          'frequency': '4x a day for 2 weeks',
          'quantity_to_dispense': '56',
          'refills': 0,
          'start_date': '2023-03-02',
          'instructions': '1 capsule 4x a day for 2 weeks',
        },
        {
          'medication_name': 'Tamsulosine',
          'medication_form_strength': '400mcg capsule',
          'exact_dose': '1 capsule',
          'frequency': 'once a day for 1 month',
          'quantity_to_dispense': '30',
          'refills': 0,
          'start_date': '2023-03-02',
          'instructions': '1 capsule once a day for 1 month',
        },
      ],
    });

    expect(drafts, hasLength(4));
    expect(drafts.map((d) => d.medicationName), [
      'HMBB',
      'Ciprofloxacin',
      'Sambong',
      'Tamsulosine',
    ]);
    expect(drafts.map((d) => d.quantityToDispense), [
      '10',
      '14',
      '56',
      '30',
    ]);
    expect(drafts.map((d) => d.startDate), [
      DateTime(2023, 3, 2),
      DateTime(2023, 3, 2),
      DateTime(2023, 3, 2),
      DateTime(2023, 3, 2),
    ]);
    expect(
      drafts.map((d) => d.diagnosisReason),
      everyElement('Post-operative care'),
    );
  });

  test('top-level prescriptions array preserves all drafts', () {
    final drafts = PrescriptionScanDraft.listFromPayload({
      'prescriptions': [
        {
          'medication_name': 'HMBB',
          'medication_form_strength': '10mg tab',
          'quantity_to_dispense': '10',
        },
        {
          'medication_name': 'Ciprofloxacin',
          'medication_form_strength': '500mg tab',
          'quantity_to_dispense': '14',
        },
      ],
    });

    expect(drafts, hasLength(2));
    expect(drafts.map((d) => d.medicationName), ['HMBB', 'Ciprofloxacin']);
  });
}
