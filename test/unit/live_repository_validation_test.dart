import 'package:care_navigator_ph/src/repositories/admin_repository.dart';
import 'package:care_navigator_ph/src/repositories/care_repository.dart';
import 'package:care_navigator_ph/src/repositories/consultation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'public-test-key');
  });

  test('assignment-only clinical relationship uses assignment provenance', () {
    const relationship = ClinicalRelationship(
      patientId: 'patient',
      patientLabel: 'Patient',
      consultationId: '',
      consultationLabel: 'Assigned care relationship',
      assignmentId: 'assignment',
    );

    expect(relationship.hasConsultation, isFalse);
    expect(relationship.clinicalReferenceId, 'assignment');
    expect(relationship.clinicalReferenceType, 'doctor_patient_assignment');
  });

  test(
    'care mutations reject unsafe input before any network request',
    () async {
      final repository = SupabaseCareRepository(client);

      await expectLater(
        repository.sendMessage(conversationId: 'conversation', body: '   '),
        throwsArgumentError,
      );
      await expectLater(
        repository.sendMessage(
          conversationId: 'conversation',
          body: 'Attachment',
          attachment: (bytes: <int>[1, 2, 3], name: 'report.pdf'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.extractCheckupFromAttachments(attachments: const []),
        throwsArgumentError,
      );
      await expectLater(
        repository.extractCheckupFromAttachments(
          attachments: const [
            (bytes: <int>[1, 2, 3], name: 'scan.docx'),
          ],
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.extractCheckupFromAttachments(
          attachments: List.generate(
            6,
            (index) =>
                (bytes: <int>[0xFF, 0xD8, 0xFF], name: 'scan-$index.jpg'),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.createScheduleSlot(
          dayOfWeek: 7,
          startsAt: '09:00',
          endsAt: '10:00',
          consultationType: 'online',
          slotMinutes: 30,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.createScheduleSlot(
          dayOfWeek: 1,
          startsAt: '09:00',
          endsAt: '10:00',
          consultationType: 'telephone',
          slotMinutes: 30,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.createScheduleSlot(
          dayOfWeek: 1,
          startsAt: '12:00',
          endsAt: '09:00',
          consultationType: 'online',
          slotMinutes: 30,
        ),
        throwsArgumentError,
      );
      const relationship = ClinicalRelationship(
        patientId: 'patient',
        patientLabel: 'Patient',
        consultationId: 'consultation',
        consultationLabel: 'Consultation',
      );
      await expectLater(
        repository.createPrescription(
          relationship: relationship,
          medicationName: ' ',
          dosage: '500 mg',
          frequency: 'Daily',
          duration: '5 days',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.createLaboratoryRequest(
          relationship: relationship,
          testName: 'CBC',
          priority: 'immediate',
        ),
        throwsArgumentError,
      );
    },
  );

  test('admin mutations enforce table and field allowlists', () async {
    final repository = SupabaseAdminRepository(client);

    await expectLater(
      repository.updateAccountStatus(userId: 'user', status: 'deleted'),
      throwsArgumentError,
    );
    await expectLater(
      repository.updateOperationalRecord(
        table: 'users',
        recordId: 'record',
        changes: const {'account_status': 'active'},
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.updateEmergencyCapacity(
        recordId: 'record',
        totalCapacity: 10,
        occupiedCapacity: 8,
        closedOrUnstaffedCapacity: 2,
        reservedCapacity: 1,
        currentPatientCount: 12,
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.updateOperationalRecord(
        table: 'hospital_beds',
        recordId: 'record',
        changes: const {'hospital_id': 'other-hospital'},
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.updateOperationalRecord(
        table: 'emergency_room_status',
        recordId: 'record',
        changes: const {'status': 'unavailable'},
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.deleteManagedRecord(table: 'users', recordId: 'user'),
      throwsArgumentError,
    );
    await expectLater(
      repository.createDoctorAccount(
        hospitalId: 'hospital',
        firstName: 'Ana',
        lastName: 'Santos',
        email: 'not-an-email',
        temporaryPassword: 'long-enough-password',
        specialization: 'Internal medicine',
        licenseNumber: 'LICENSE',
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.createDoctorAccount(
        hospitalId: 'hospital',
        firstName: 'Ana',
        lastName: 'Santos',
        email: 'ana.santos@example.test',
        temporaryPassword: 'long-enough-password',
        specialization: 'Internal medicine',
        licenseNumber: 'LICENSE',
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.updateDoctorDepartment(
        userId: ' ',
        departmentId: 'department',
      ),
      throwsArgumentError,
    );
    final startsAt = DateTime.now().add(const Duration(hours: 2));
    await expectLater(
      repository.createMaintenanceWindow(
        title: 'Maintenance',
        message: 'Planned maintenance window.',
        startsAt: startsAt,
        endsAt: startsAt.subtract(const Duration(minutes: 30)),
      ),
      throwsArgumentError,
    );
  });

  test('care messages expose linked secure attachment metadata', () {
    final message = CareMessage.fromJson(const {
      'id': 'message-id',
      'conversation_id': 'conversation-id',
      'sender_id': 'auth-user-id',
      'message': 'Please review',
      'sent_at': '2026-08-14T01:02:03Z',
      'message_type': 'file',
      'attachment_path': 'consultation/auth/report.pdf',
    });

    expect(message.attachmentPath, 'consultation/auth/report.pdf');
    expect(message.sentAt, DateTime.utc(2026, 8, 14, 1, 2, 3));
  });

  test('guest review accepts only explicit terminal decisions', () async {
    final repository = SupabaseConsultationRepository(client);

    await expectLater(
      repository.reviewGuestRequest(requestId: 'request', decision: 'maybe'),
      throwsArgumentError,
    );
    await expectLater(
      repository.reviewOnlineRequest(
        requestId: 'request',
        decision: 'auto_approve',
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.reviewOnlineRequest(
        requestId: 'request',
        decision: 'confirmed',
        channel: 'sms_assisted',
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.cancelOnlineRequest(requestId: 'request', reason: ' '),
      throwsArgumentError,
    );
    await expectLater(
      repository.reserveConsultation(
        doctorId: 'doctor',
        hospitalId: 'hospital',
        consultationType: 'telephone',
        appointmentDate: DateTime.now().add(const Duration(days: 1)),
        chiefComplaint: 'Persistent cough',
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.listAvailableSlots(doctorId: ' ', consultationType: 'online'),
      throwsArgumentError,
    );
    await expectLater(
      repository.listAvailableSlots(
        doctorId: 'doctor',
        consultationType: 'online',
        horizonDays: 61,
      ),
      throwsArgumentError,
    );
  });

  test('available consultation slots preserve server timestamps', () {
    final slot = AvailableConsultationSlot.fromJson(const {
      'starts_at': '2026-08-24T01:00:00Z',
      'ends_at': '2026-08-24T01:30:00Z',
    });

    expect(slot.startsAt, DateTime.utc(2026, 8, 24, 1));
    expect(slot.endsAt, DateTime.utc(2026, 8, 24, 1, 30));
  });

  test('consultation join window starts 15 minutes before the appointment', () {
    final appointment = DateTime.utc(2026, 8, 12, 10);

    expect(
      isConsultationJoinWindowOpen(
        appointment,
        at: DateTime.utc(2026, 8, 12, 9, 44, 59),
      ),
      isFalse,
    );
    expect(
      isConsultationJoinWindowOpen(
        appointment,
        at: DateTime.utc(2026, 8, 12, 9, 45),
      ),
      isTrue,
    );
    expect(
      isConsultationJoinWindowOpen(
        appointment,
        at: DateTime.utc(2026, 8, 12, 13, 59, 59),
      ),
      isTrue,
    );
    expect(
      isConsultationJoinWindowOpen(
        appointment,
        at: DateTime.utc(2026, 8, 12, 14),
      ),
      isFalse,
    );
  });
}
