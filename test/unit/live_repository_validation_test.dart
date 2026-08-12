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

  test(
    'care mutations reject unsafe input before any network request',
    () async {
      final repository = SupabaseCareRepository(client);

      await expectLater(
        repository.sendMessage(conversationId: 'conversation', body: '   '),
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

  test('guest review accepts only explicit terminal decisions', () async {
    final repository = SupabaseConsultationRepository(client);

    await expectLater(
      repository.reviewGuestRequest(requestId: 'request', decision: 'maybe'),
      throwsArgumentError,
    );
    await expectLater(
      repository.bookConsultation(
        doctorId: 'doctor',
        hospitalId: 'hospital',
        consultationType: 'telephone',
        appointmentDate: DateTime.now().add(const Duration(days: 1)),
        chiefComplaint: 'Persistent cough',
      ),
      throwsArgumentError,
    );
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
