const reservationMinimumLeadTime = Duration(hours: 24);

bool meetsReservationLeadTime(DateTime scheduledFor, {DateTime? now}) {
  final checkedAt = (now ?? DateTime.now()).toUtc();
  return !scheduledFor.toUtc().isBefore(
    checkedAt.add(reservationMinimumLeadTime),
  );
}

const reservationLeadTimeMessage =
    'Choose a reservation time at least 24 hours from now.';
