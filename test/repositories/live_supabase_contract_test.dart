import 'dart:io';

import 'package:care_navigator_ph/src/repositories/hospital_repository.dart';
import 'package:care_navigator_ph/src/models/hospitals/hospital_models.dart';
import 'package:care_navigator_ph/src/repositories/public_settings_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['CNPH_TEST_SUPABASE_URL'] ?? '';
  final key = Platform.environment['CNPH_TEST_SUPABASE_PUBLISHABLE_KEY'] ?? '';
  final configured = url.isNotEmpty && key.isNotEmpty;

  test(
    'anonymous public directory maps the verified live contract',
    () async {
      final repository = SupabaseHospitalRepository(SupabaseClient(url, key));
      final hospitals = await repository.loadPublicDirectory();

      expect(hospitals, isNotEmpty);
      expect(hospitals, everyElement(isA<HospitalDirectoryEntry>()));
      for (final hospital in hospitals) {
        expect(
          hospital.imageUrl,
          startsWith(
            '$url/storage/v1/object/public/hospital-images/directory/',
          ),
          reason: '${hospital.name} must use a managed directory photo.',
        );
        for (final department in hospital.departments) {
          expect(
            hospital.departmentIds[department],
            isNotEmpty,
            reason:
                'Guest consultation intake requires an exact department ID.',
          );
        }
      }
      expect(
        hospitals,
        everyElement(
          isA<dynamic>()
              .having((hospital) => hospital.id, 'id', isNotEmpty)
              .having((hospital) => hospital.name, 'name', isNotEmpty),
        ),
      );
      expect(
        hospitals.any(
          (hospital) =>
              hospital.name == 'CareNavigator Primary Hospital (Demo)',
        ),
        isFalse,
        reason:
            'Synthetic facilities must not appear in the patient directory.',
      );

      final settings = await SupabasePublicSettingsRepository(
        SupabaseClient(url, key),
      ).load();
      expect(settings.emergencyNumber, isNotEmpty);
      expect(settings.emergencyRegion, isNotEmpty);
      expect(settings.medicalDisclaimer, isNotEmpty);
    },
    skip: configured
        ? false
        : 'Public Supabase dart-defines were not supplied.',
  );
}
