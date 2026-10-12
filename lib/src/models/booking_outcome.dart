class BookingOutcome {
  const BookingOutcome({
    this.requestId,
    this.consultationId,
    required this.status,
    required this.slotReserved,
  });

  final String? requestId;
  final String? consultationId;
  final String status;
  final bool slotReserved;

  factory BookingOutcome.fromJson(Map<String, dynamic> json) => BookingOutcome(
    requestId: json['request_id'] as String?,
    consultationId: json['consultation_id'] as String?,
    status: json['status'] as String,
    slotReserved: json['slot_reserved'] as bool,
  );

  String get message => slotReserved
      ? 'Appointment reserved. Current status: ${status.replaceAll('_', ' ')}.'
      : 'Request submitted for hospital review. The preferred slot is not reserved until confirmation.';
}
