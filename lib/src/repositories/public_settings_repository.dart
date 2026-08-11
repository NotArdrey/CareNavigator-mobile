import 'package:supabase/supabase.dart';

class PublicAppSettings {
  const PublicAppSettings({
    this.emergencyNumber,
    this.emergencyRegion,
    this.medicalDisclaimer,
  });

  final String? emergencyNumber;
  final String? emergencyRegion;
  final String? medicalDisclaimer;

  String get emergencyCallInstruction {
    final number = emergencyNumber?.trim() ?? '';
    final region = emergencyRegion?.trim() ?? '';
    if (number.isEmpty) return 'Contact your local emergency services';
    return region.isEmpty ? 'Call $number' : 'Call $number in $region';
  }

  String get emergencyHelpText =>
      '$emergencyCallInstruction or go to the nearest emergency department.';
}

abstract interface class PublicSettingsRepository {
  Future<PublicAppSettings> load();
}

final class SupabasePublicSettingsRepository
    implements PublicSettingsRepository {
  SupabasePublicSettingsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PublicAppSettings> load() async {
    final rows = await _client
        .from('system_settings')
        .select('key,value')
        .eq('is_public', true)
        .inFilter('key', const [
          'emergency_number',
          'emergency_region',
          'medical_disclaimer',
        ]);
    final values = <String, Object?>{
      for (final row in rows) row['key'].toString(): row['value'],
    };
    return PublicAppSettings(
      emergencyNumber: _textValue(values['emergency_number']),
      emergencyRegion: _textValue(values['emergency_region']),
      medicalDisclaimer: _textValue(values['medical_disclaimer']),
    );
  }

  static String? _textValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
