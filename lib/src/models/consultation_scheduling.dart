const reservationMinimumLeadTime = Duration(hours: 24);

bool meetsReservationLeadTime(DateTime scheduledFor, {DateTime? now}) {
  final checkedAt = (now ?? DateTime.now()).toUtc();
  return !scheduledFor.toUtc().isBefore(
    checkedAt.add(reservationMinimumLeadTime),
  );
}

const reservationLeadTimeMessage =
    'Choose a reservation time at least 24 hours from now.';

// A Manila wall-clock date for comparing recurring hospital schedules.
DateTime manilaWallTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));
