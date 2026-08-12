abstract final class ConsultationType {
  static const online = 'online';
  static const faceToFace = 'face_to_face';

  static const supported = <String>{online, faceToFace};

  /// Converts UI and legacy aliases to the values accepted by Postgres.
  static String normalize(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );
    return switch (normalized) {
      online => online,
      faceToFace || 'in_person' || 'inperson' => faceToFace,
      _ => throw ArgumentError.value(
        value,
        'consultationType',
        'Unsupported consultation type.',
      ),
    };
  }

  static String label(String value) =>
      normalize(value) == online ? 'Online' : 'In person';
}
