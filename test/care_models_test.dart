import 'package:care_navigator_ph/src/models/care_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'role workspace parses nested care records without exposing other rows',
    () {
      final workspace = RoleWorkspace.fromJson('patient', {
        'consultations': [
          {
            'id': 'consultation-1',
            'status': 'scheduled',
            'consultation_type': 'online',
            'appointment_date': '2026-07-20T02:00:00Z',
            'chief_complaint': 'Follow-up consultation',
            'patient_id': 'patient-1',
            'doctor_id': 'doctor-1',
            'hospital_id': 'hospital-1',
            'patients': {
              'patient_number': 'CNPH-P-000001',
              'users': {'first_name': 'Ana', 'last_name': 'Reyes'},
            },
            'doctors': {'display_name': 'Dr. Santos'},
            'hospitals': {'hospital_name': 'Care Hospital'},
          },
        ],
        'patients': [
          {
            'id': 'patient-1',
            'patient_number': 'CNPH-P-000001',
            'account_activation_status': 'active',
            'users': {'first_name': 'Ana', 'last_name': 'Reyes'},
            'allergies': ['Penicillin'],
            'existing_conditions': ['Asthma'],
          },
        ],
        'laboratory_results': [
          {
            'id': 'result-1',
            'patient_id': 'patient-1',
            'test_name': 'Complete blood count',
            'verification_status': 'doctor_confirmed',
            'file_path': 'patient-1/result.pdf',
            'uploaded_at': '2026-07-19T02:00:00Z',
            'doctor_confirmed_findings': 'Reviewed by a doctor',
          },
        ],
        'diagnoses': [
          {
            'id': 'diagnosis-1',
            'patient_id': 'patient-1',
            'consultation_id': 'consultation-1',
            'diagnosis': 'Doctor-confirmed asthma',
            'is_primary': true,
            'confirmed_at': '2026-07-20T03:00:00Z',
            'doctors': {'display_name': 'Dr. Santos'},
          },
        ],
        'treatment_plans': [
          {
            'id': 'plan-1',
            'patient_id': 'patient-1',
            'consultation_id': 'consultation-1',
            'plan': 'Continue prescribed controller medication.',
            'status': 'active',
            'created_at': '2026-07-20T03:05:00Z',
          },
        ],
        'medical_documents': [
          {
            'id': 'document-1',
            'patient_id': 'patient-1',
            'document_type': 'clinical_note',
            'title': 'Follow-up note',
            'storage_bucket': 'medical-documents',
            'storage_path': 'patient-1/medical-documents/note.pdf',
            'mime_type': 'application/pdf',
            'size_bytes': 2048,
            'created_at': '2026-07-20T03:10:00Z',
          },
        ],
        'consultation_attachments': [
          {
            'id': 'attachment-1',
            'consultation_id': 'consultation-1',
            'patient_id': 'patient-1',
            'file_name': 'care-plan.pdf',
            'storage_path': 'consultation-1/clinical/care-plan.pdf',
            'size_bytes': 4096,
            'created_at': '2026-07-20T03:15:00Z',
          },
        ],
        'patient_consents': [
          {
            'id': 'consent-1',
            'patient_id': 'patient-1',
            'consent_type': 'telemedicine',
            'consent_version': '1.0',
            'is_granted': true,
            'granted_at': '2026-07-20T03:20:00Z',
            'metadata': {'capture_channel': 'patient_care_workspace'},
            'updated_at': '2026-07-20T03:20:00Z',
          },
        ],
      });

      expect(workspace.role, 'patient');
      expect(workspace.consultations.single.doctorName, 'Dr. Santos');
      expect(workspace.consultations.single.patientName, 'Ana Reyes');
      expect(workspace.consultations.single.status, 'scheduled');
      expect(workspace.patients.single.displayName, 'Ana Reyes');
      expect(workspace.patients.single.allergies, ['Penicillin']);
      expect(workspace.laboratoryResults.single.status, 'doctor_confirmed');
      expect(
        workspace.laboratoryResults.single.doctorConfirmedFindings,
        'Reviewed by a doctor',
      );
      expect(workspace.prescriptions, isEmpty);
      expect(workspace.conversations, isEmpty);
      expect(workspace.diagnoses.single.isPrimary, isTrue);
      expect(workspace.diagnoses.single.doctorName, 'Dr. Santos');
      expect(workspace.treatmentPlans.single.status, 'active');
      expect(workspace.medicalDocuments.single.sizeBytes, 2048);
      expect(
        workspace.consultationAttachments.single.fileName,
        'care-plan.pdf',
      );
      expect(workspace.patientConsents.single.isGranted, isTrue);
      expect(workspace.patientConsents.single.consentVersion, '1.0');
    },
  );

  test('consultation model safely applies workflow defaults', () {
    final consultation = CareConsultation.fromJson({
      'id': 'consultation-2',
      'appointment_date': '2026-07-20T02:00:00Z',
      'chief_complaint': 'General checkup',
    });

    expect(consultation.status, 'pending');
    expect(consultation.consultationType, 'online');
    expect(consultation.meetingLink, isNull);
  });
}
