import '../models/hospitals/hospital_models.dart';
import '../models/consultation_type.dart';
import '../models/shared/page_result.dart';
import 'package:supabase/supabase.dart';

import 'repository_failure.dart';

abstract interface class HospitalRepository {
  Future<List<HospitalDirectoryEntry>> loadPublicDirectory();

  Stream<void> watchDirectoryUpdates();

  Future<PageResult<HospitalSummary>> searchHospitals({
    required HospitalSearchCriteria criteria,
    required PageRequest page,
  });

  Future<HospitalSummary> getHospital(String hospitalId);

  Future<List<String>> listDepartments(String hospitalId);

  Future<List<String>> listServices(String hospitalId);

  Stream<HospitalSummary> watchPublicAvailability(String hospitalId);
}

final class SupabaseHospitalRepository implements HospitalRepository {
  SupabaseHospitalRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<void> watchDirectoryUpdates() => _client
      .from('emergency_room_status')
      .stream(primaryKey: ['id'])
      .map<void>((_) {});

  @override
  Future<List<HospitalDirectoryEntry>> loadPublicDirectory() async {
    try {
      final hospitalRows = await _client
          .from('hospitals')
          .select(
            'id,hospital_name,address,city,province,latitude,longitude,contact_number,emergency_contact_number,email,description,image_url,operating_hours,operating_status,updated_at,verification_status,hospital_classifications(classification_name)',
          )
          .eq('verification_status', 'verified')
          .inFilter('operating_status', const ['open', 'limited'])
          .order('hospital_name');
      if (hospitalRows.isEmpty) return const [];

      final hospitalIds = hospitalRows
          .map((row) => row['id'].toString())
          .toList(growable: false);
      final departmentRows = await _client
          .from('hospital_departments')
          .select('id,hospital_id,department_name,availability_status')
          .inFilter('hospital_id', hospitalIds)
          .order('department_name');
      final serviceRows = await _client
          .from('hospital_services')
          .select('hospital_id,service_name,availability_status,delivery_modes')
          .inFilter('hospital_id', hospitalIds)
          .order('service_name');
      final emergencyRows = await _client
          .from('emergency_room_status')
          .select(
            'hospital_id,status,available_beds,current_patient_count,maximum_capacity,occupied_beds,closed_or_unstaffed_beds,reserved_beds,capacity_source,last_updated',
          )
          .inFilter('hospital_id', hospitalIds);
      final facilityRows = await _client
          .from('hospital_facility_status')
          .select(
            'hospital_id,facility_type,status,available_units,notes,last_updated',
          )
          .inFilter('hospital_id', hospitalIds)
          .order('facility_type');
      final bedRows = await _client
          .from('hospital_beds')
          .select('hospital_id,bed_type,total_beds,available_beds,last_updated')
          .inFilter('hospital_id', hospitalIds)
          .order('bed_type');
      final doctorRows = await _client
          .from('doctors')
          .select(
            'id,hospital_id,department_id,display_name,specialization,availability_status',
          )
          .inFilter('hospital_id', hospitalIds)
          .neq('availability_status', 'unavailable')
          .order('display_name');
      final doctorIds = doctorRows
          .map((row) => row['id'].toString())
          .toList(growable: false);
      final scheduleRows = doctorIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client
                .from('doctor_schedules')
                .select(
                  'doctor_id,day_of_week,starts_at,consultation_type,is_active',
                )
                .inFilter('doctor_id', doctorIds)
                .eq('is_active', true);

      final departments = _groupLabels(
        departmentRows,
        labelKey: 'department_name',
      );
      final departmentIds = <String, Map<String, String>>{};
      final departmentNames = <String, String>{};
      for (final row in departmentRows) {
        departmentNames[row['id'].toString()] =
            row['department_name']?.toString() ?? '';
        departmentIds.putIfAbsent(
          row['hospital_id'].toString(),
          () => {},
        )[row['department_name'].toString()] = row['id']
            .toString();
      }
      final services = _groupLabels(serviceRows, labelKey: 'service_name');
      final emergencyByHospital = <String, Map<String, dynamic>>{
        for (final row in emergencyRows)
          row['hospital_id'].toString(): Map<String, dynamic>.from(row),
      };
      final facilitiesByHospital =
          <String, List<HospitalFacilityAvailability>>{};
      for (final row in facilityRows) {
        facilitiesByHospital
            .putIfAbsent(row['hospital_id'].toString(), () => [])
            .add(
              HospitalFacilityAvailability(
                type: row['facility_type']?.toString() ?? 'facility',
                status: row['status']?.toString() ?? 'unknown',
                availableUnits: _intValue(row['available_units']),
                notes: _nullableText(row['notes']),
                lastUpdated: _dateTimeValue(row['last_updated']),
              ),
            );
      }
      final bedsByHospital = <String, List<HospitalBedAvailability>>{};
      for (final row in bedRows) {
        final totalBeds = _intValue(row['total_beds']);
        final availableBeds = _intValue(row['available_beds']);
        if (totalBeds == null || availableBeds == null) continue;
        bedsByHospital
            .putIfAbsent(row['hospital_id'].toString(), () => [])
            .add(
              HospitalBedAvailability(
                type: row['bed_type']?.toString() ?? 'Hospital bed',
                totalBeds: totalBeds,
                availableBeds: availableBeds,
                lastUpdated: _dateTimeValue(row['last_updated']),
              ),
            );
      }
      final schedulesByDoctor = <String, List<Map<String, dynamic>>>{};
      for (final row in scheduleRows) {
        schedulesByDoctor
            .putIfAbsent(row['doctor_id'].toString(), () => [])
            .add(Map<String, dynamic>.from(row));
      }
      final doctorsByHospital = <String, List<DoctorAvailability>>{};
      final now = DateTime.now();
      for (final row in doctorRows) {
        final id = row['id'].toString();
        final schedules = schedulesByDoctor[id] ?? const [];
        // The public patient directory only advertises reservation modes
        // accepted by the legacy patient booking RPC. Emergency and guest-only
        // schedules are operational workflows, not patient self-reservation
        // options.
        final patientSchedules = schedules
            .where(
              (schedule) => ConsultationType.supported.contains(
                schedule['consultation_type']?.toString(),
              ),
            )
            .toList(growable: false);
        final nextAvailability = _nextAvailability(patientSchedules, now);
        if (nextAvailability == null) continue;
        doctorsByHospital
            .putIfAbsent(row['hospital_id'].toString(), () => [])
            .add(
              DoctorAvailability(
                id: id,
                displayLabel: row['display_name']?.toString() ?? 'Doctor',
                specialtyLabel:
                    row['specialization']?.toString() ?? 'General care',
                departmentLabel:
                    departmentNames[row['department_id']?.toString()],
                nextAvailableAt: nextAvailability,
                offersOnlineCare: patientSchedules.any(
                  (schedule) => schedule['consultation_type'] == 'online',
                ),
                consultationTypes: patientSchedules
                    .map((schedule) => schedule['consultation_type'].toString())
                    .toSet()
                    .toList(growable: false),
              ),
            );
      }

      return hospitalRows
          .map((row) {
            final hospitalId = row['id'].toString();
            final classification = _relationMap(
              row['hospital_classifications'],
            );
            final emergency = emergencyByHospital[hospitalId];
            final operatingStatus = row['operating_status']?.toString();
            final erStatus = emergency?['status']?.toString();
            final latitude = _doubleValue(row['latitude']);
            final longitude = _doubleValue(row['longitude']);
            return HospitalDirectoryEntry(
              id: hospitalId,
              name: row['hospital_name']?.toString() ?? 'Hospital',
              city: row['city']?.toString() ?? '',
              province: row['province']?.toString() ?? '',
              careLevel:
                  classification?['classification_name']?.toString() ??
                  'Hospital',
              services: services[hospitalId] ?? const [],
              departments: departments[hospitalId] ?? const [],
              departmentIds: departmentIds[hospitalId] ?? const {},
              doctors: doctorsByHospital[hospitalId] ?? const [],
              isAvailable:
                  (operatingStatus == 'open' || operatingStatus == 'limited') &&
                  erStatus != 'full' &&
                  erStatus != 'temporarily_closed',
              estimatedWaitMinutes: null,
              availableBeds: _intValue(emergency?['available_beds']),
              totalBeds: _intValue(emergency?['maximum_capacity']),
              latitude: latitude,
              longitude: longitude,
              address: _nullableText(row['address']),
              contactNumber: _nullableText(row['contact_number']),
              emergencyContactNumber: _nullableText(
                row['emergency_contact_number'],
              ),
              email: _nullableText(row['email']),
              description: _nullableText(row['description']),
              imageUrl: _nullableText(row['image_url']),
              operatingHours: _stringMap(row['operating_hours']),
              operatingStatus: operatingStatus ?? 'unknown',
              emergencyStatus: erStatus,
              currentEmergencyPatients: _intValue(
                emergency?['current_patient_count'],
              ),
              occupiedEmergencyBeds: _intValue(emergency?['occupied_beds']),
              closedOrUnstaffedEmergencyBeds: _intValue(
                emergency?['closed_or_unstaffed_beds'],
              ),
              reservedEmergencyBeds: _intValue(emergency?['reserved_beds']),
              emergencyCapacitySource: _nullableText(
                emergency?['capacity_source'],
              ),
              updatedAt: _dateTimeValue(row['updated_at']),
              emergencyLastUpdated: _dateTimeValue(emergency?['last_updated']),
              facilities: facilitiesByHospital[hospitalId] ?? const [],
              bedAvailability: bedsByHospital[hospitalId] ?? const [],
            );
          })
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw UnexpectedRepositoryFailure(
        'Live hospital information could not be loaded.',
        cause: error,
      );
    }
  }

  @override
  Future<PageResult<HospitalSummary>> searchHospitals({
    required HospitalSearchCriteria criteria,
    required PageRequest page,
  }) async {
    final directory = await loadPublicDirectory();
    final query = criteria.query.trim().toLowerCase();
    final filtered = directory
        .where((hospital) {
          final searchable = [
            hospital.name,
            hospital.city,
            hospital.province,
            hospital.careLevel,
            ...hospital.services,
          ].join(' ').toLowerCase();
          return (query.isEmpty || searchable.contains(query)) &&
              (criteria.province == null ||
                  hospital.province == criteria.province) &&
              (criteria.city == null || hospital.city == criteria.city) &&
              (criteria.careLevel == null ||
                  hospital.careLevel == criteria.careLevel) &&
              (criteria.service == null ||
                  hospital.services.contains(criteria.service)) &&
              (!criteria.onlyAvailable || hospital.isAvailable);
        })
        .toList(growable: false);
    final offset = int.tryParse(page.cursor ?? '') ?? 0;
    final end = (offset + page.limit).clamp(0, filtered.length);
    final items = offset >= filtered.length
        ? const <HospitalSummary>[]
        : filtered.sublist(offset, end).map(_summary).toList(growable: false);
    return PageResult(
      items: items,
      nextCursor: end < filtered.length ? end.toString() : null,
    );
  }

  @override
  Future<HospitalSummary> getHospital(String hospitalId) async {
    final directory = await loadPublicDirectory();
    for (final hospital in directory) {
      if (hospital.id == hospitalId) return _summary(hospital);
    }
    throw const ContractUnavailableFailure('Hospital was not found.');
  }

  @override
  Future<List<String>> listDepartments(String hospitalId) async {
    final rows = await _client
        .from('hospital_departments')
        .select('department_name')
        .eq('hospital_id', hospitalId)
        .order('department_name');
    return rows
        .map((row) => row['department_name'].toString())
        .toList(growable: false);
  }

  @override
  Future<List<String>> listServices(String hospitalId) async {
    final rows = await _client
        .from('hospital_services')
        .select('service_name')
        .eq('hospital_id', hospitalId)
        .order('service_name');
    return rows
        .map((row) => row['service_name'].toString())
        .toList(growable: false);
  }

  @override
  Stream<HospitalSummary> watchPublicAvailability(String hospitalId) => _client
      .from('hospitals')
      .stream(primaryKey: ['id'])
      .eq('id', hospitalId)
      .asyncMap((_) => getHospital(hospitalId));

  static HospitalSummary _summary(HospitalDirectoryEntry hospital) =>
      HospitalSummary(
        id: hospital.id,
        name: hospital.name,
        locationLabel: hospital.locationLabel,
        isVerified: true,
        imageUrl: hospital.imageUrl,
        latitude: hospital.latitude,
        longitude: hospital.longitude,
      );

  static Map<String, List<String>> _groupLabels(
    List<Map<String, dynamic>> rows, {
    required String labelKey,
  }) {
    final result = <String, List<String>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['hospital_id'].toString(), () => [])
          .add(row[labelKey].toString());
    }
    return result;
  }

  static Map<String, dynamic>? _relationMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  static int? _intValue(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static double? _doubleValue(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _dateTimeValue(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.value != null) entry.key.toString(): entry.value.toString(),
    };
  }

  static DateTime? _nextAvailability(
    List<Map<String, dynamic>> schedules,
    DateTime now,
  ) {
    DateTime? earliest;
    for (final schedule in schedules) {
      final databaseDay = _intValue(schedule['day_of_week']);
      final time = schedule['starts_at']?.toString().split(':');
      if (databaseDay == null || time == null || time.length < 2) continue;
      final weekday = databaseDay == 0 ? DateTime.sunday : databaseDay;
      final hour = int.tryParse(time[0]);
      final minute = int.tryParse(time[1]);
      if (hour == null || minute == null) continue;
      for (var offset = 0; offset < 14; offset++) {
        final date = now.add(Duration(days: offset));
        if (date.weekday != weekday) continue;
        final candidate = DateTime(
          date.year,
          date.month,
          date.day,
          hour,
          minute,
        );
        if (!candidate.isAfter(now)) continue;
        if (earliest == null || candidate.isBefore(earliest)) {
          earliest = candidate;
        }
        break;
      }
    }
    return earliest;
  }
}
