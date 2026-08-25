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

  test('adds a finding summary to a laboratory result table', () {
    const extracted = '''EXAMINATION | RESULT | UNIT | NORMAL VALUES
WBC | 6.2 | 10^9/L | 4-11
RBC | 5.1 | 10^12/L | 3.9-6.5
Hb | 14 | g/dL | 12-18
HDL | 45 | mg/dL | >50
LDL | 81 | mg/dL | <100''';
    final draft = DiagnosticResultScanDraft.fromPayload({
      'result_category': 'laboratory',
      'findings_impression': extracted,
    });

    expect(
      draft.findingsImpression,
      startsWith(
        'Key findings: Low HDL (45 mg/dL; stated reference >50). '
        'WBC, RBC, Hb, and LDL are within their stated reference ranges.',
      ),
    );
    expect(
      draft.findingsImpression,
      contains('Supporting results:\n$extracted'),
    );
  });

  test('summarizes colon-formatted laboratory values', () {
    final draft = DiagnosticResultScanDraft.fromPayload({
      'result_category': 'laboratory',
      'findings_impression': '''WBC: 12.4 10^9/L (Normal: 4-11)
Hemoglobin: 14 g/dL (Reference range: 12-18)''',
    });

    expect(
      draft.findingsImpression,
      startsWith(
        'Key findings: High WBC (12.4 10^9/L; stated reference 4-11). '
        'Hemoglobin is within its stated reference range.',
      ),
    );
  });

  test('does not duplicate an existing laboratory summary', () {
    const findings = '''Key findings: HDL is low.

Supporting results:
HDL | 45 | mg/dL | >50''';
    final draft = DiagnosticResultScanDraft.fromPayload({
      'result_category': 'laboratory',
      'findings_impression': findings,
    });

    expect(draft.findingsImpression, findings);
  });

  test(
    'does not classify laboratory rows without a numeric matching range',
    () {
      const findings = 'SARS-CoV-2 | Detected | | Not detected';
      final draft = DiagnosticResultScanDraft.fromPayload({
        'result_category': 'laboratory',
        'findings_impression': findings,
      });

      expect(draft.findingsImpression, findings);
    },
  );

  test('preserves complete structured extraction and ambiguous dates', () {
    final draft = DiagnosticResultScanDraft.fromPayload({
      'source_file_name': 'cbc.pdf',
      'patient_name': 'Maria Santos',
      'result_category': 'laboratory',
      'test_procedure_name': 'Complete Blood Count',
      'test_procedure_name_ai_generated': false,
      'performed_or_collected_date': null,
      'performed_or_collected_date_text': '01/02/25',
      'result_date': '2025-02-03',
      'result_date_text': '03 Feb 2025',
      'facility': 'Example Laboratory',
      'requesting_doctor': 'Dr. Ana Reyes',
      'procedure_details': 'Specimen: Serum',
      'results': [
        {
          'test_or_measurement': 'HDL',
          'value': '45',
          'unit': 'mg/dL',
          'reference_range': '>50',
          'status': 'low',
        },
        {
          'test_or_measurement': 'Comment',
          'value': 'Needs verification',
          'unit': null,
          'reference_range': null,
          'status': null,
        },
      ],
      'official_findings_impression': 'Final laboratory report.',
      'recommendations': 'Repeat only if clinically indicated.',
      'technical_summary':
          'HDL is 45 mg/dL, below the report-stated reference value of >50 mg/dL.',
      'patient_friendly_summary':
          'Your HDL is below this laboratory\'s stated target range.',
      'needs_verification': [
        'Confirm whether 01/02/25 means January 2 or February 1, 2025.',
      ],
    });

    expect(draft.sourceFileName, 'cbc.pdf');
    expect(draft.patientName, 'Maria Santos');
    expect(draft.performedOrCollectedDate, isNull);
    expect(draft.performedOrCollectedDateText, '01/02/25');
    expect(draft.resultDate, DateTime(2025, 2, 3));
    expect(draft.procedureDetails, 'Specimen: Serum');
    expect(draft.resultDetails, contains('HDL | 45 | mg/dL | >50 | low'));
    expect(
      draft.resultDetails,
      contains('Comment | Needs verification |  |  | '),
    );
    expect(draft.officialFindingsImpression, 'Final laboratory report.');
    expect(draft.verificationNotes, contains('Confirm whether 01/02/25'));
  });
}
