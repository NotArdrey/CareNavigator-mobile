import 'package:care_navigator_ph/src/models/guest_consultation_models.dart';
import 'package:care_navigator_ph/src/models/prescription_grouping.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/providers/guest_consultation_provider.dart';
import 'package:care_navigator_ph/src/repositories/consultation_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'verified guest retries an insertion failure without consuming OTP again',
    () async {
      final repository = _RetryRepository();
      final container = ProviderContainer(
        overrides: [
          consultationRepositoryProvider.overrideWithValue(repository),
          guestConsultationProvider.overrideWith(_ReadyController.new),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(guestConsultationProvider.notifier);
      await expectLater(
        controller.verifyCode(email: 'fixture@example.test', code: '123456'),
        throwsStateError,
      );
      final failed = container.read(guestConsultationProvider);
      expect(failed.emailVerified, isTrue);
      expect(failed.busy, isFalse);
      expect(failed.draft.concern, 'A synthetic test care concern');
      expect(
        await controller.verifyCode(email: 'fixture@example.test', code: ''),
        'request-id',
      );
      expect(repository.verifications, 1);
      expect(repository.keys, hasLength(2));
      expect(repository.keys.first, isNotEmpty);
      expect(repository.keys.last, repository.keys.first);
      expect(
        container.read(guestConsultationProvider).status,
        GuestRequestStatus.submitted,
      );
    },
  );

  test('separate orders in the same consultation remain separate', () {
    final rows = <Map<String, Object?>>[
      {'id': 'a', 'order_id': 'order-a', 'consultation_id': 'same'},
      {'id': 'b', 'order_id': 'order-b', 'consultation_id': 'same'},
      {'id': 'c', 'order_id': 'order-a', 'consultation_id': 'same'},
      {'id': 'legacy-a', 'consultation_id': 'same'},
      {'id': 'legacy-b', 'consultation_id': 'same'},
    ];
    final groups = groupPrescriptionOrders(rows, (r) => r);
    expect(groups.map((g) => g.map((r) => r['id']).toList()), [
      ['a', 'c'],
      ['b'],
      ['legacy-a'],
      ['legacy-b'],
    ]);
    expect(
      isPrescriptionOrderAttachment({
        'reference_type': 'prescription_order',
        'reference_id': 'order-b',
      }, groups.first),
      isFalse,
    );
    expect(
      isPrescriptionOrderAttachment({
        'reference_type': 'prescription_order',
        'reference_id': 'order-a',
      }, groups.first),
      isTrue,
    );
    expect(
      isPrescriptionOrderAttachment({'created_at': 'same'}, groups.first),
      isFalse,
    );
  });
}

class _ReadyController extends GuestConsultationController {
  @override
  GuestConsultationState build() => GuestConsultationState(
    draft: GuestConsultationIntakeDraft(
      firstName: 'Test',
      lastName: 'Fixture',
      birthDate: DateTime(1990),
      sex: 'male',
      mobileNumber: '+639171234567',
      email: 'fixture@example.test',
      address: 'Test address',
      concern: 'A synthetic test care concern',
      symptomDuration: 'Three days',
      privacyAccepted: true,
      hospitalId: 'hospital',
      departmentId: 'department',
      preferredStart: DateTime.now().add(const Duration(days: 3)),
    ),
    status: GuestRequestStatus.awaitingVerification,
    busy: false,
    resendCount: 0,
  );
}

class _RetryRepository implements ConsultationRepository {
  int verifications = 0;
  final keys = <String?>[];
  @override
  Future<void> verifyGuestEmailCode({
    required String email,
    required String otp,
  }) async {
    verifications++;
  }

  @override
  Future<String> createGuestRequest(GuestConsultationDraft draft) async {
    keys.add(draft.idempotencyKey);
    if (keys.length == 1) throw StateError('Synthetic insertion failure');
    return 'request-id';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
