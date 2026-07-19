import 'package:supabase_flutter/supabase_flutter.dart';

typedef JsonMap = Map<String, dynamic>;

class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<JsonMap>> listClassifications() async => _rows(
    await _client
        .from('hospital_classifications')
        .select('id, classification_name, description')
        .order('classification_name'),
  );

  Future<List<JsonMap>> listServiceCategories() async => _rows(
    await _client
        .from('healthcare_service_categories')
        .select()
        .order('display_order')
        .order('category_name'),
  );

  Future<List<JsonMap>> listHospitals() async => _rows(
    await _client
        .from('hospitals')
        .select(
          'id, hospital_name, classification_id, address, city, province, '
          'contact_number, emergency_contact_number, email, description, '
          'latitude, longitude, operating_hours, operating_status, verification_status, '
          'hospital_classifications(classification_name)',
        )
        .order('created_at', ascending: false),
  );

  Future<JsonMap> getHospital(String hospitalId) async => JsonMap.from(
    await _client
        .from('hospitals')
        .select(
          'id, hospital_name, classification_id, address, city, province, '
          'contact_number, emergency_contact_number, email, description, '
          'latitude, longitude, operating_hours, operating_status, verification_status',
        )
        .eq('id', hospitalId)
        .single(),
  );

  Future<List<JsonMap>> listHospitalAdmins() async => _rows(
    await _client
        .from('users')
        .select(
          'id, first_name, last_name, email, hospital_id, account_status, '
          'roles!inner(role_name), hospitals(hospital_name)',
        )
        .eq('roles.role_name', 'hospital_admin')
        .order('created_at', ascending: false),
  );

  Future<void> createHospital(JsonMap values) async {
    await _client.from('hospitals').insert({
      ...values,
      'created_by': _client.auth.currentUser!.id,
    });
  }

  Future<void> updateHospital(String id, JsonMap values) async {
    await _client.from('hospitals').update(values).eq('id', id);
  }

  Future<void> deleteHospital(String id) async {
    await _client.from('hospitals').delete().eq('id', id);
  }

  Future<void> createHospitalAdmin({
    required String hospitalId,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) => _invokeAdmin({
    'action': 'create_hospital_admin',
    'hospital_id': hospitalId,
    'email': email,
    'password': password,
    'first_name': firstName,
    'last_name': lastName,
  });

  Future<void> updateUserStatus(String userId, String status) => _invokeAdmin({
    'action': 'update_user_status',
    'user_id': userId,
    'account_status': status,
  });

  Future<List<JsonMap>> listDepartments(String hospitalId) async => _rows(
    await _client
        .from('hospital_departments')
        .select()
        .eq('hospital_id', hospitalId)
        .order('department_name'),
  );

  Future<List<JsonMap>> listServices(String hospitalId) async => _rows(
    await _client
        .from('hospital_services')
        .select(
          '*, hospital_departments(department_name), '
          'healthcare_service_categories(category_name, icon_name), '
          'hospital_service_doctors(doctor_id, is_primary)',
        )
        .eq('hospital_id', hospitalId)
        .order('service_name'),
  );

  Future<List<JsonMap>> listRooms(String hospitalId) async => _rows(
    await _client
        .from('hospital_rooms')
        .select()
        .eq('hospital_id', hospitalId)
        .order('room_type'),
  );

  Future<List<JsonMap>> listBeds(String hospitalId) async => _rows(
    await _client
        .from('hospital_beds')
        .select('*, hospital_departments(department_name)')
        .eq('hospital_id', hospitalId)
        .order('bed_type'),
  );

  Future<JsonMap?> getEmergencyStatus(String hospitalId) async {
    final value = await _client
        .from('emergency_room_status')
        .select()
        .eq('hospital_id', hospitalId)
        .maybeSingle();
    return value == null ? null : JsonMap.from(value);
  }

  Future<List<JsonMap>> listFacilities(String hospitalId) async => _rows(
    await _client
        .from('hospital_facility_status')
        .select()
        .eq('hospital_id', hospitalId)
        .order('facility_type'),
  );

  Future<List<JsonMap>> listDoctors(String hospitalId) async => _rows(
    await _client
        .from('doctors')
        .select(
          'id, user_id, hospital_id, department_id, display_name, specialization, '
          'license_number, availability_status, consultation_fee, biography, '
          'hospital_departments(department_name), '
          'users!doctors_user_id_fkey(account_status, email)',
        )
        .eq('hospital_id', hospitalId)
        .order('display_name'),
  );

  Future<void> saveDepartment({String? id, required JsonMap values}) =>
      _save('hospital_departments', id, values);

  Future<void> saveService({
    String? id,
    required JsonMap values,
    List<String> doctorIds = const [],
    String? primaryDoctorId,
  }) async {
    await _client.rpc(
      'save_hospital_service',
      params: {
        'service_payload': {...values, 'id': id},
        'target_doctor_ids': doctorIds,
        'target_primary_doctor_id': primaryDoctorId,
      },
    );
  }

  Future<void> saveServiceCategory({String? id, required JsonMap values}) =>
      _save('healthcare_service_categories', id, values);

  Future<void> saveClassification({String? id, required JsonMap values}) =>
      _save('hospital_classifications', id, values);

  Future<void> deleteClassification(String id) async {
    try {
      await _client.from('hospital_classifications').delete().eq('id', id);
    } on PostgrestException catch (error) {
      if (error.code == '23503') {
        throw Exception(
          'This classification is assigned to a hospital. Reclassify that hospital before deleting it.',
        );
      }
      rethrow;
    }
  }

  Future<void> saveRoom({String? id, required JsonMap values}) =>
      _save('hospital_rooms', id, values);

  Future<void> saveBed({String? id, required JsonMap values}) =>
      _save('hospital_beds', id, values);

  Future<void> saveFacility({String? id, required JsonMap values}) =>
      _save('hospital_facility_status', id, values);

  Future<void> saveEmergencyStatus(JsonMap values) async {
    await _client
        .from('emergency_room_status')
        .upsert(values, onConflict: 'hospital_id');
  }

  Future<void> deleteRecord(String table, String id) async {
    const allowed = {
      'hospital_departments',
      'hospital_services',
      'hospital_rooms',
      'hospital_beds',
      'hospital_facility_status',
      'healthcare_service_categories',
      'doctor_schedules',
    };
    if (!allowed.contains(table)) throw ArgumentError('Unsupported table');
    await _client.from(table).delete().eq('id', id);
  }

  Future<void> createDoctor({
    required String hospitalId,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String specialization,
    required String licenseNumber,
    String? departmentId,
    double? consultationFee,
    String? biography,
  }) => _invokeAdmin({
    'action': 'create_doctor',
    'hospital_id': hospitalId,
    'email': email,
    'password': password,
    'first_name': firstName,
    'last_name': lastName,
    'specialization': specialization,
    'license_number': licenseNumber,
    'department_id': departmentId,
    'consultation_fee': consultationFee,
    'biography': biography,
  });

  Future<void> updateDoctorStatus(String doctorId, String status) =>
      _invokeAdmin({
        'action': 'update_doctor_status',
        'doctor_id': doctorId,
        'availability_status': status,
      });

  Future<List<JsonMap>> listDoctorSchedules(String doctorId) async => _rows(
    await _client
        .from('doctor_schedules')
        .select()
        .eq('doctor_id', doctorId)
        .order('day_of_week')
        .order('starts_at'),
  );

  Future<void> saveDoctorSchedule({String? id, required JsonMap values}) =>
      _save('doctor_schedules', id, values);

  Future<void> _save(String table, String? id, JsonMap values) async {
    if (id == null) {
      await _client.from(table).insert(values);
    } else {
      await _client.from(table).update(values).eq('id', id);
    }
  }

  Future<void> _invokeAdmin(JsonMap body) async {
    final response = await _client.functions.invoke('admin-users', body: body);
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error']?.toString() : null;
      throw Exception(message ?? 'The administrator operation failed.');
    }
  }
}

List<JsonMap> _rows(dynamic value) => (value as List)
    .map((row) => JsonMap.from(row as Map))
    .toList(growable: false);
