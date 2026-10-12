class PrescriptionOrderOutcome {
  const PrescriptionOrderOutcome({
    required this.orderId,
    required this.medicationIds,
    required this.notificationStatus,
  });
  final String orderId;
  final List<String> medicationIds;
  final String notificationStatus;

  factory PrescriptionOrderOutcome.fromJson(Map<String, dynamic> json) =>
      PrescriptionOrderOutcome(
        orderId: json['order_id'] as String,
        medicationIds: (json['medication_ids'] as List).cast<String>(),
        notificationStatus: json['notification_status'] as String,
      );
}
