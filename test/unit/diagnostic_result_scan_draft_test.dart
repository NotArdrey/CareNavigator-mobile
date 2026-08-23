import 'package:care_navigator_ph/src/repositories/care_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses supported diagnostic result fields', () {
    final draft = DiagnosticResultScanDraft.fromPayload({
      'result_category': 'ct_scan',
      'test_procedure_name': 'CT scan of chest without contrast',
      'performed_or_collected_date': '2026-08-20',
      'result_date': '2026-08-21',
      'facility': 'Care Navigator Medical Center',
      'requesting_doctor': 'Dr. Juan Dela Cruz',
      'findings_impression': 'No acute findings.',
      'notes': 'Final report.',
    });

    expect(draft.category, 'ct_scan');
    expect(draft.testProcedureName, 'CT scan of chest without contrast');
    expect(draft.performedOrCollectedDate, DateTime(2026, 8, 20));
    expect(draft.resultDate, DateTime(2026, 8, 21));
    expect(draft.facility, 'Care Navigator Medical Center');
    expect(draft.requestingDoctor, 'Dr. Juan Dela Cruz');
    expect(draft.findingsImpression, 'No acute findings.');
    expect(draft.notes, 'Final report.');
  });

  test('rejects unsupported categories and invalid dates', () {
    final draft = DiagnosticResultScanDraft.fromPayload({
      'result_category': 'medical_image',
      'performed_or_collected_date': 'not-a-date',
      'result_date': '',
    });

    expect(draft.category, isNull);
    expect(draft.performedOrCollectedDate, isNull);
    expect(draft.resultDate, isNull);
  });
}
