import 'package:care_navigator_ph/src/models/hospital.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HospitalRepository {
  HospitalRepository(this._client);

  final SupabaseClient _client;

  static const _directorySelect = '''
    id,
    hospital_name,
    address,
    city,
    province,
    description,
    contact_number,
    emergency_contact_number,
    email,
    image_url,
    latitude,
    longitude,
    operating_hours,
    operating_status,
    verification_status,
    hospital_classifications(classification_name),
    emergency_room_status(status, available_beds),
    hospital_beds(available_beds, total_beds),
    hospital_rooms(available_rooms, total_rooms)
    ,hospital_services(service_name, tags, availability_status)
  ''';

  Future<List<Hospital>> listHospitals({String query = ''}) async {
    final response = await _client
        .from('hospitals')
        .select(_directorySelect)
        .order('hospital_name');
    return (response as List)
        .whereType<Map<String, dynamic>>()
        .map(Hospital.fromJson)
        .where((hospital) => hospital.matches(query))
        .toList();
  }

  Future<Hospital> getHospital(String id) async {
    final response = await _client
        .from('hospitals')
        .select(_directorySelect)
        .eq('id', id)
        .single();
    return Hospital.fromJson(response);
  }

  Future<Map<String, dynamic>> getHospitalServices(String id) async {
    final results = await Future.wait<dynamic>([
      _client
          .from('hospital_departments')
          .select('id, department_name, description, availability_status')
          .eq('hospital_id', id)
          .order('department_name'),
      _client
          .from('hospital_services')
          .select(
            'id, department_id, category_id, service_name, service_code, '
            'description, availability_status, operating_hours, delivery_modes, '
            'appointment_required, accepts_walk_ins, fee_min, fee_max, fee_notes, '
            'contact_number, booking_url, preparation_instructions, tags, last_updated, '
            'hospital_departments(department_name), '
            'healthcare_service_categories(category_name)',
          )
          .eq('hospital_id', id)
          .order('service_name'),
      _client
          .from('doctors')
          .select(
            'id, display_name, specialization, availability_status, consultation_fee, '
            'doctor_schedules(day_of_week, starts_at, ends_at, consultation_type, slot_minutes)',
          )
          .eq('hospital_id', id)
          .order('display_name'),
      _client
          .from('hospital_facility_status')
          .select('facility_type, status, available_units, notes')
          .eq('hospital_id', id)
          .order('facility_type'),
      _client
          .from('hospital_service_doctors')
          .select(
            'service_id, is_primary, doctors(id, display_name, specialization, '
            'availability_status, consultation_fee)',
          )
          .eq('hospital_id', id),
      _client
          .from('hospital_announcements')
          .select('id, title, message, is_global, published_at, expires_at')
          .or('hospital_id.eq.$id,is_global.eq.true')
          .lte('published_at', DateTime.now().toUtc().toIso8601String())
          .order('published_at', ascending: false)
          .limit(20),
    ]);
    final departments = results[0];
    final services = (results[1] as List)
        .whereType<Map<String, dynamic>>()
        .map((service) {
          final assignedDoctors = (results[4] as List)
              .whereType<Map<String, dynamic>>()
              .where((assignment) => assignment['service_id'] == service['id'])
              .toList(growable: false);
          return {...service, 'assigned_doctors': assignedDoctors};
        })
        .toList(growable: false);
    final doctors = results[2];
    final facilities = results[3];
    final announcements = results[5];
    return {
      'departments': departments,
      'services': services,
      'doctors': doctors,
      'facilities': facilities,
      'announcements': announcements,
    };
  }
}
