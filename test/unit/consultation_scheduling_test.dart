import 'package:care_navigator_ph/src/models/consultation_scheduling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reservation requires a full 24 hours of lead time', () {
    final now = DateTime.utc(2026, 8, 23, 9);

    expect(
      meetsReservationLeadTime(
        now.add(const Duration(hours: 23, minutes: 59)),
        now: now,
      ),
      isFalse,
    );
    expect(
      meetsReservationLeadTime(now.add(reservationMinimumLeadTime), now: now),
      isTrue,
    );
  });
}
