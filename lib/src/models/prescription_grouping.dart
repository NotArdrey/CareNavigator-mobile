List<List<T>> groupPrescriptionOrders<T>(
  List<T> rows,
  Map<String, Object?> Function(T) dataOf,
) {
  final groups = <String, List<T>>{};
  for (var index = 0; index < rows.length; index++) {
    final data = dataOf(rows[index]);
    final order = data['order_id']?.toString();
    final key = order != null && order.isNotEmpty
        ? 'order:$order'
        : 'legacy:${data['id'] ?? index}';
    groups.putIfAbsent(key, () => []).add(rows[index]);
  }
  return groups.values.toList(growable: false);
}

bool isPrescriptionOrderAttachment(
  Map<String, Object?> document,
  List<Map<String, Object?>> medications,
) {
  final reference = document['reference_id']?.toString();
  if (reference == null || reference.isEmpty) return false;
  return medications.any(
    (medication) =>
        (document['reference_type'] == 'prescription_order' &&
            medication['order_id']?.toString() == reference) ||
        (document['reference_type'] == 'prescription' &&
            medication['id']?.toString() == reference),
  );
}
