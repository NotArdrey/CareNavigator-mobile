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
}
