import 'package:supabase/supabase.dart';

import '../models/auth/user_role.dart';

abstract interface class WorkspaceRepository {
  Future<WorkspaceSnapshot> load({
    required UserRole role,
    String? section,
    String? itemId,
    int limit = 100,
  });
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.title,
    required this.description,
    required this.items,
    this.metrics = const [],
    this.hasMore = false,
    this.loadedAt,
  });

  final String title;
  final String description;
  final List<WorkspaceMetric> metrics;
  final List<WorkspaceItem> items;
  final bool hasMore;
  final DateTime? loadedAt;
}

class WorkspaceMetric {
  const WorkspaceMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class WorkspaceItem {
  const WorkspaceItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.status,
    this.timestamp,
    this.isUnread = false,
    this.data = const {},
  });

  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final String? status;
  final DateTime? timestamp;
  final bool isUnread;
  final Map<String, Object?> data;

  WorkspaceItem copyWith({
    String? id,
    String? kind,
    String? title,
    String? subtitle,
    String? status,
    DateTime? timestamp,
    bool? isUnread,
    Map<String, Object?>? data,
  }) => WorkspaceItem(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    status: status ?? this.status,
    timestamp: timestamp ?? this.timestamp,
    isUnread: isUnread ?? this.isUnread,
    data: data ?? this.data,
  );
}

const _onlineAppointmentRoutePrefix = 'online-request~';
const _guestAppointmentRoutePrefix = 'guest-request~';

String workspaceItemRouteId(WorkspaceItem item) => switch (item.kind) {
  'online_consultation_requests' =>
    '$_onlineAppointmentRoutePrefix${Uri.encodeComponent(item.id)}',
  'guest_consultation_requests' =>
    '$_guestAppointmentRoutePrefix${Uri.encodeComponent(item.id)}',
  _ => item.id,
};

({String kind, String id})? _appointmentDetailReference(String? routeId) {
  if (routeId == null) return null;
  if (routeId.startsWith(_onlineAppointmentRoutePrefix)) {
    return (
      kind: 'online_consultation_requests',
      id: Uri.decodeComponent(
        routeId.substring(_onlineAppointmentRoutePrefix.length),
      ),
    );
  }
  if (routeId.startsWith(_guestAppointmentRoutePrefix)) {
    return (
      kind: 'guest_consultation_requests',
      id: Uri.decodeComponent(
        routeId.substring(_guestAppointmentRoutePrefix.length),
      ),
    );
  }
  return null;
}

class SupabaseWorkspaceRepository implements WorkspaceRepository {
  SupabaseWorkspaceRepository(this._client);

  final SupabaseClient _client;

  static const _hospitalScopedTables = <String>{
    'consultations',
    'hospital_beds',
    'hospital_rooms',
    'hospital_facility_status',
    'emergency_room_status',
    'hospital_services',
    'hospital_departments',
    'users',
  };

  @override
  Future<WorkspaceSnapshot> load({
    required UserRole role,
    String? section,
    String? itemId,
    int limit = 100,
  }) async {
    if (role == UserRole.guest) {
      throw StateError('A guest does not have an authenticated workspace.');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Your session has expired. Sign in again to continue.');
    }
    if (section == null) return _loadDashboard(role);
    if (role == UserRole.superAdministrator && section == 'analytics') {
      return _loadAnalytics('platform_analytics', 'Platform analytics');
    }
    if (role == UserRole.hospitalAdministrator && section == 'reports') {
      return _loadAnalytics('hospital_analytics', 'Hospital reports');
    }
    final baseSpec = _specFor(role, section);
    if (baseSpec == null) {
      return WorkspaceSnapshot(
        title: _humanize(section),
        description: 'This workspace module is not available for this role.',
        items: const [],
        loadedAt: DateTime.now(),
      );
    }
    final appointmentDetail = section == 'appointments'
        ? _appointmentDetailReference(itemId)
        : null;
    final requestDetailSpec = appointmentDetail == null
        ? null
        : _appointmentRequestDetailSpec(role, appointmentDetail.kind);
    final spec = requestDetailSpec ?? baseSpec;
    final recordId = requestDetailSpec == null ? itemId : appointmentDetail!.id;
    final doctorId = role == UserRole.doctor ? await _currentDoctorId() : null;
    final hospitalId = role == UserRole.hospitalAdministrator
        ? await _currentHospitalId()
        : null;
    dynamic query = _client.from(spec.table).select(spec.columns);
    if (spec.table == 'doctor_schedules' && doctorId != null) {
      query = query.eq('doctor_id', doctorId);
    }
    if (hospitalId != null && _hospitalScopedTables.contains(spec.table)) {
      query = query.eq('hospital_id', hospitalId);
    }
    if (hospitalId != null && spec.table == 'guest_consultation_requests') {
      query = query.eq('preferred_hospital_id', hospitalId);
    }
    if (recordId != null) query = query.eq(spec.idColumn, recordId);
    if (spec.orderColumn != null) {
      query = query.order(spec.orderColumn!, ascending: spec.ascending);
    }
    final fetchLimit = itemId == null ? limit + 1 : 1;
    final response = await query.limit(fetchLimit);
    var rows = (response as List)
        .cast<Map<String, dynamic>>()
        .map((row) => _mapRow(spec.table, row))
        .toList();
    if (spec.table == 'users') {
      rows = await _attachUserDetails(rows);
    } else if (spec.table == 'hospitals') {
      rows = await _attachHospitalClassifications(rows);
    } else if (spec.table == 'hospital_services') {
      rows = await _attachServiceDepartments(rows);
    } else if (spec.table == 'role_permissions') {
      rows = await _attachPermissionRoles(rows);
    } else if (spec.table == 'chat_conversations') {
      rows = await _attachConversationDetails(rows, role);
    }
    if (spec.table == 'doctor_schedules' && doctorId != null) {
      final reservationRows = await _loadDoctorAppointments(doctorId);
      rows = _annotateSchedules(rows, reservationRows);
    }
    if (spec.table == 'doctor_patient_assignments') {
      if (role == UserRole.doctor && itemId != null) {
        rows = await _attachAuthorizedPatientContexts(rows, assignment: true);
        rows = await _attachPatientCheckupHistory(rows);
        rows = await _attachPatientClinicalHistory(rows);
      } else {
        rows = await _attachPatientDetails(
          rows,
          assignment: true,
          includeCheckupHistory: true,
        );
      }
      if (doctorId != null) {
        rows = await _attachPatientConversationIds(rows, doctorId: doctorId);
      }
    } else if (spec.table == 'consultations' && role == UserRole.doctor) {
      rows = itemId != null
          ? await _attachAuthorizedPatientContexts(rows, assignment: false)
          : await _attachPatientDetails(rows, assignment: false);
    } else if (spec.table == 'medical_records') {
      rows = await _attachMedicalRecordDoctors(rows);
    }
    if (spec.table == 'consultations') {
      rows = await _attachConsultationDetails(rows);
    }
    if (itemId == null &&
        spec.table == 'consultations' &&
        {'appointments', 'consultations'}.contains(section)) {
      dynamic onlineQuery = _client
          .from('online_consultation_requests')
          .select(
            'id,reference_number,patient_id,profile_first_name,profile_last_name,phone_number_snapshot,hospital_id,requested_department_id,requested_doctor_id,assigned_doctor_id,medical_concern,symptom_duration,preferred_schedule,proposed_schedule,confirmed_schedule,consultation_channel,request_status,official_consultation_id,additional_information_request,rejection_reason,cancellation_reason,created_at,updated_at',
          );
      if (hospitalId != null) {
        onlineQuery = onlineQuery.eq('hospital_id', hospitalId);
      }
      final onlineRows = await onlineQuery
          .order('created_at', ascending: false)
          .limit(fetchLimit);
      rows.addAll(
        (onlineRows as List).cast<Map<String, dynamic>>().map<WorkspaceItem>(
          (row) => _mapRow('online_consultation_requests', row),
        ),
      );
      rows.sort(
        (left, right) => (right.timestamp ?? DateTime(1970)).compareTo(
          left.timestamp ?? DateTime(1970),
        ),
      );
    }
    final patientDocumentSection =
        role == UserRole.patient && {'labs', 'prescriptions'}.contains(section);
    final doctorLaboratoryDocuments =
        role == UserRole.doctor && section == 'results-review';
    if (patientDocumentSection || doctorLaboratoryDocuments) {
      final currentUserId = patientDocumentSection
          ? await _currentApplicationUserId()
          : null;
      rows.addAll(
        await _loadPatientCategoryDocuments(
          documentTypes: section == 'prescriptions'
              ? const ['prescription']
              : const ['lab_result', 'diagnostic_result'],
          itemId: itemId,
          currentUserId: currentUserId,
          limit: limit,
        ),
      );
      rows.sort(
        (left, right) => (right.timestamp ?? DateTime(1970)).compareTo(
          left.timestamp ?? DateTime(1970),
        ),
      );
    }
    if (itemId == null &&
        section == 'appointments' &&
        {UserRole.doctor, UserRole.hospitalAdministrator}.contains(role)) {
      dynamic guestQuery = _client
          .from('guest_consultation_requests')
          .select(
            'id,reference_number,first_name,last_name,full_name,birth_date,sex,mobile_number,email,address,symptoms,symptom_duration,consultation_reason,preferred_hospital_id,preferred_department_id,request_status,identity_review_status,assigned_doctor_id,preferred_consultation_type,preferred_schedule,created_at',
          );
      if (hospitalId != null) {
        guestQuery = guestQuery.eq('preferred_hospital_id', hospitalId);
      }
      final guestRows = await guestQuery
          .order('created_at', ascending: false)
          .limit(fetchLimit);
      rows.addAll(
        (guestRows as List).cast<Map<String, dynamic>>().map<WorkspaceItem>(
          (row) => _mapRow('guest_consultation_requests', row),
        ),
      );
      rows.sort(
        (left, right) => (right.timestamp ?? DateTime(1970)).compareTo(
          left.timestamp ?? DateTime(1970),
        ),
      );
    }
    final hasMore = itemId == null && rows.length > limit;
    if (hasMore) rows = rows.take(limit).toList(growable: false);
    return WorkspaceSnapshot(
      title: spec.title,
      description: spec.description,
      metrics: [
        WorkspaceMetric(
          label: _metricLabel(spec.table),
          value: _boundedCount(rows.length + (hasMore ? 1 : 0)),
        ),
      ],
      items: rows,
      hasMore: hasMore,
      loadedAt: DateTime.now(),
    );
  }

  Future<List<WorkspaceItem>> _loadPatientCategoryDocuments({
    required List<String> documentTypes,
    String? itemId,
    String? currentUserId,
    int limit = 100,
  }) async {
    dynamic query = _client
        .from('medical_documents')
        .select()
        .inFilter('document_type', documentTypes);
    if (itemId != null) query = query.eq('id', itemId);
    final response = await query
        .order('created_at', ascending: false)
        .limit(itemId == null ? limit + 1 : 1);
    return (response as List)
        .cast<Map<String, dynamic>>()
        .map((row) {
          final annotated = <String, dynamic>{
            ...row,
            'is_current_user_upload':
                currentUserId != null &&
                row['uploaded_by']?.toString() == currentUserId,
          };
          return _mapRow('medical_documents', annotated);
        })
        .toList(growable: false);
  }

  Future<List<WorkspaceItem>> _attachAuthorizedPatientContexts(
    List<WorkspaceItem> items, {
    required bool assignment,
  }) async {
    return Future.wait(
      items.map((item) async {
        final consultationId = assignment
            ? item.data['consultation_id']?.toString()
            : item.id;
        if (consultationId == null || consultationId.isEmpty) {
          return item.copyWith(
            data: {
              ...item.data,
              'patient_context_unavailable':
                  'No active consultation is linked to this assignment.',
            },
          );
        }
        try {
          final context = await _client.rpc<Map<String, dynamic>>(
            'get_consultation_patient_context',
            params: {'target_consultation_id': consultationId},
          );
          final rawDemographics = context['demographics'];
          final demographics = rawDemographics is Map
              ? Map<String, dynamic>.from(rawDemographics)
              : const <String, dynamic>{};
          final patientName = [
            demographics['first_name']?.toString(),
            demographics['last_name']?.toString(),
          ].whereType<String>().where((value) => value.isNotEmpty).join(' ');
          return item.copyWith(
            title: patientName.isEmpty ? item.title : patientName,
            data: {
              ...item.data,
              ...demographics,
              if (patientName.isNotEmpty) 'patient_name': patientName,
              'patient_context': context,
            },
          );
        } on PostgrestException catch (error) {
          return item.copyWith(
            data: {...item.data, 'patient_context_unavailable': error.message},
          );
        }
      }),
    );
  }

  Future<List<WorkspaceItem>> _attachPatientCheckupHistory(
    List<WorkspaceItem> items,
  ) async {
    final patientIds = items
        .map((item) => item.data['patient_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (patientIds.isEmpty) return items;

    final medicalRows =
        (await _client
                .from('medical_records')
                .select(
                  'id,patient_id,doctor_id,consultation_id,record_type,title,description,record_date,reason_for_visit,confirmed_diagnosis,treatment_plan,height_cm,weight_kg,bmi,blood_pressure_systolic,blood_pressure_diastolic,body_temperature_c,heart_rate_bpm,respiratory_rate_bpm,oxygen_saturation_percent,vitals_recorded_at,current_symptoms,known_medical_conditions,allergies,current_medications,relevant_medical_history,previous_surgeries,smoking_status,alcohol_use,pregnancy_status,doctor_notes,created_at,updated_at',
                )
                .inFilter('patient_id', patientIds)
                .inFilter('record_type', const [
                  'checkup',
                  'consultation_checkup',
                ]))
            .cast<Map<String, dynamic>>();
    final doctorIds = medicalRows
        .map((row) => row['doctor_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final doctorRows = doctorIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('doctors')
                  .select('id,display_name')
                  .inFilter('id', doctorIds))
              .cast<Map<String, dynamic>>();
    final doctorsById = <String, String>{
      for (final row in doctorRows)
        row['id'].toString(): row['display_name']?.toString() ?? '',
    };
    final checkupsByPatient = <String, List<Map<String, Object?>>>{};
    for (final row in medicalRows) {
      final patientId = row['patient_id']?.toString() ?? '';
      if (patientId.isEmpty) continue;
      checkupsByPatient.putIfAbsent(patientId, () => []).add({
        ...row,
        'doctor_display_name': doctorsById[row['doctor_id']?.toString()],
      });
    }
    for (final checkups in checkupsByPatient.values) {
      checkups.sort(
        (left, right) => _recordDate(
          Map<String, dynamic>.from(right),
        ).compareTo(_recordDate(Map<String, dynamic>.from(left))),
      );
    }

    return [
      for (final item in items)
        item.copyWith(
          data: {
            ...item.data,
            'checkup_history':
                checkupsByPatient[item.data['patient_id']?.toString()] ??
                const <Map<String, Object?>>[],
          },
        ),
    ];
  }

  Future<List<WorkspaceItem>> _attachPatientClinicalHistory(
    List<WorkspaceItem> items,
  ) async {
    final patientIds = items
        .map((item) => item.data['patient_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (patientIds.isEmpty) return items;

    final responses = await Future.wait<dynamic>([
      _client
          .from('prescriptions')
          .select()
          .inFilter('patient_id', patientIds)
          .order('created_at', ascending: false),
      _client
          .from('laboratory_results')
          .select()
          .inFilter('patient_id', patientIds)
          .order('uploaded_at', ascending: false),
      _client
          .from('medical_documents')
          .select()
          .inFilter('patient_id', patientIds)
          .inFilter('document_type', const [
            'prescription',
            'diagnostic_result',
            'lab_result',
          ])
          .order('created_at', ascending: false),
    ]);
    final prescriptionRows = (responses[0] as List)
        .cast<Map<String, dynamic>>();
    final laboratoryRows = (responses[1] as List).cast<Map<String, dynamic>>();
    final documentRows = (responses[2] as List).cast<Map<String, dynamic>>();
    final prescriptionsByPatient = <String, List<Map<String, Object?>>>{};
    final diagnosticsByPatient = <String, List<Map<String, Object?>>>{};

    for (final row in prescriptionRows) {
      final patientId = row['patient_id']?.toString() ?? '';
      if (patientId.isEmpty) continue;
      prescriptionsByPatient.putIfAbsent(patientId, () => []).add({
        ...row,
        'history_source': 'prescriptions',
      });
    }
    for (final row in laboratoryRows) {
      final patientId = row['patient_id']?.toString() ?? '';
      if (patientId.isEmpty) continue;
      diagnosticsByPatient.putIfAbsent(patientId, () => []).add({
        ...row,
        'history_source': 'laboratory_results',
      });
    }
    for (final row in documentRows) {
      final patientId = row['patient_id']?.toString() ?? '';
      if (patientId.isEmpty) continue;
      final target = row['document_type'] == 'prescription'
          ? prescriptionsByPatient
          : diagnosticsByPatient;
      target.putIfAbsent(patientId, () => []).add({
        ...row,
        'history_source': 'medical_documents',
      });
    }
    for (final records in [
      ...prescriptionsByPatient.values,
      ...diagnosticsByPatient.values,
    ]) {
      records.sort(
        (left, right) =>
            _clinicalHistoryDate(right).compareTo(_clinicalHistoryDate(left)),
      );
    }

    return [
      for (final item in items)
        item.copyWith(
          data: {
            ...item.data,
            'prescription_history':
                prescriptionsByPatient[item.data['patient_id']?.toString()] ??
                const <Map<String, Object?>>[],
            'diagnostic_result_history':
                diagnosticsByPatient[item.data['patient_id']?.toString()] ??
                const <Map<String, Object?>>[],
          },
        ),
    ];
  }

  Future<List<WorkspaceItem>> _attachPatientConversationIds(
    List<WorkspaceItem> items, {
    required String doctorId,
  }) async {
    if (items.isEmpty) return items;
    final patientIds = items
        .map((item) => item.data['patient_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (patientIds.isEmpty) return items;

    final conversationRows =
        (await _client
                .from('chat_conversations')
                .select('id,consultation_id,doctor_id,patient_id,updated_at')
                .eq('doctor_id', doctorId)
                .inFilter('patient_id', patientIds)
                .order('updated_at', ascending: false))
            .cast<Map<String, dynamic>>();
    final conversationByPatient = <String, String>{};
    for (final row in conversationRows) {
      final patientId = row['patient_id']?.toString() ?? '';
      final conversationId = row['id']?.toString() ?? '';
      if (patientId.isEmpty || conversationId.isEmpty) continue;
      conversationByPatient.putIfAbsent(patientId, () => conversationId);
    }

    return [
      for (final item in items)
        () {
          final patientId = item.data['patient_id']?.toString() ?? '';
          final conversationId = conversationByPatient[patientId];
          if (conversationId == null) return item;
          return item.copyWith(
            data: {...item.data, 'conversation_id': conversationId},
          );
        }(),
    ];
  }

  Future<String> _currentApplicationUserId() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null || authUser.isAnonymous) {
      throw StateError('An authenticated account is required.');
    }
    final appUser = await _client
        .from('users')
        .select('id')
        .eq('auth_user_id', authUser.id)
        .single();
    return appUser['id'].toString();
  }

  Future<List<WorkspaceItem>> _attachPatientDetails(
    List<WorkspaceItem> items, {
    required bool assignment,
    bool includeCheckupHistory = false,
  }) async {
    final patientIds = items
        .map((item) => item.data['patient_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (patientIds.isEmpty) return items;

    final patientRows = await _client
        .from('patients')
        .select(
          'id,user_id,guest_request_id,patient_number,blood_type,allergies,existing_conditions,identity_verification_status,profile_status',
        )
        .inFilter('id', patientIds);
    final userIds = patientRows
        .map((row) => row['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final userRows = userIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('users')
                  .select(
                    'id,first_name,last_name,email,mobile_number,birth_date,sex,address',
                  )
                  .inFilter('id', userIds))
              .cast<Map<String, dynamic>>();
    final patientsById = <String, Map<String, dynamic>>{
      for (final row in patientRows) row['id'].toString(): row,
    };
    final usersById = <String, Map<String, dynamic>>{
      for (final row in userRows) row['id'].toString(): row,
    };
    final guestRequestIds = [
      ...patientRows.map((row) => row['guest_request_id']?.toString() ?? ''),
      ...items.map((item) => item.data['guest_request_id']?.toString() ?? ''),
    ].where((id) => id.isNotEmpty).toSet().toList(growable: false);
    final guestRows = guestRequestIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('guest_consultation_requests')
                  .select(
                    'id,first_name,last_name,birth_date,sex,mobile_number,email,address',
                  )
                  .inFilter('id', guestRequestIds))
              .cast<Map<String, dynamic>>();
    final guestsById = <String, Map<String, dynamic>>{
      for (final row in guestRows) row['id'].toString(): row,
    };

    final medicalColumns = includeCheckupHistory
        ? 'id,patient_id,doctor_id,consultation_id,record_type,title,description,record_date,reason_for_visit,confirmed_diagnosis,treatment_plan,height_cm,weight_kg,bmi,blood_pressure_systolic,blood_pressure_diastolic,body_temperature_c,heart_rate_bpm,respiratory_rate_bpm,oxygen_saturation_percent,vitals_recorded_at,current_symptoms,known_medical_conditions,allergies,current_medications,relevant_medical_history,previous_surgeries,smoking_status,alcohol_use,pregnancy_status,doctor_notes,created_at,updated_at'
        : 'patient_id,doctor_id,height_cm,weight_kg,bmi,blood_pressure_systolic,blood_pressure_diastolic,body_temperature_c,heart_rate_bpm,respiratory_rate_bpm,oxygen_saturation_percent,vitals_recorded_at,created_at';
    final medicalRows =
        (await _client
                .from('medical_records')
                .select(medicalColumns)
                .inFilter('patient_id', patientIds))
            .cast<Map<String, dynamic>>();
    final latestByPatient = <String, Map<String, dynamic>>{};
    for (final row in medicalRows) {
      if (!_hasVitalValue(row)) continue;
      final patientId = row['patient_id']?.toString() ?? '';
      if (patientId.isEmpty) continue;
      final current = latestByPatient[patientId];
      if (current == null || _recordDate(row).isAfter(_recordDate(current))) {
        latestByPatient[patientId] = row;
      }
    }
    final recordDoctorIds = medicalRows
        .map((row) => row['doctor_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final recordDoctorRows = recordDoctorIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('doctors')
                  .select('id,display_name')
                  .inFilter('id', recordDoctorIds))
              .cast<Map<String, dynamic>>();
    final recordDoctorsById = <String, String>{
      for (final row in recordDoctorRows)
        row['id'].toString(): row['display_name']?.toString() ?? '',
    };
    final checkupsByPatient = <String, List<Map<String, Object?>>>{};
    if (includeCheckupHistory) {
      for (final row in medicalRows) {
        if (!{'checkup', 'consultation_checkup'}.contains(row['record_type'])) {
          continue;
        }
        final patientId = row['patient_id']?.toString() ?? '';
        if (patientId.isEmpty) continue;
        checkupsByPatient.putIfAbsent(patientId, () => []).add({
          ...row,
          'doctor_display_name':
              recordDoctorsById[row['doctor_id']?.toString()],
        });
      }
      for (final checkups in checkupsByPatient.values) {
        checkups.sort(
          (left, right) => _recordDate(
            Map<String, dynamic>.from(right),
          ).compareTo(_recordDate(Map<String, dynamic>.from(left))),
        );
      }
    }

    return [
      for (final item in items)
        () {
          final patientId = item.data['patient_id']?.toString() ?? '';
          final patient = patientsById[patientId];
          final user = usersById[patient?['user_id']?.toString()];
          final guest =
              guestsById[item.data['guest_request_id']?.toString() ??
                  patient?['guest_request_id']?.toString()];
          if (patient == null && user == null && guest == null) return item;
          final patientName = _join([
            user?['first_name']?.toString().trim() ?? '',
            user?['last_name']?.toString().trim() ?? '',
            if (user == null) guest?['first_name']?.toString().trim() ?? '',
            if (user == null) guest?['last_name']?.toString().trim() ?? '',
          ]);
          final data = <String, Object?>{
            ...item.data,
            'patient_name': patientName,
          };
          if (patient != null) {
            for (final entry in patient.entries) {
              if (entry.key != 'id') data[entry.key] = entry.value;
            }
          }
          if (user != null) {
            for (final entry in user.entries) {
              if (entry.key != 'id') data[entry.key] = entry.value;
            }
          }
          if (guest != null && user == null) {
            for (final entry in guest.entries) {
              if (entry.key != 'id') data[entry.key] = entry.value;
            }
          }
          final latest = latestByPatient[patientId];
          if (latest != null) {
            for (final key in _latestVitalKeys) {
              data['latest_$key'] = latest[key];
            }
            data['latest_vitals_recorded_at'] = latest['vitals_recorded_at'];
            data['latest_recorded_by'] =
                recordDoctorsById[latest['doctor_id']?.toString()];
            data['latest_vitals_summary'] = _vitalsSummary(latest);
          }
          if (assignment) {
            if (includeCheckupHistory) {
              data['checkup_history'] =
                  checkupsByPatient[patientId] ??
                  const <Map<String, Object?>>[];
            }
            return item.copyWith(
              title: patientName.isEmpty ? item.title : patientName,
              subtitle: _join([
                data['patient_number']?.toString() ?? '',
                data['mobile_number']?.toString() ?? '',
                data['latest_vitals_summary']?.toString() ?? '',
                data['identity_verification_status']?.toString() ?? '',
              ]),
              data: data,
            );
          }
          return item.copyWith(
            subtitle: _join([
              patientName,
              item.subtitle,
              data['latest_vitals_summary']?.toString() ?? '',
            ]),
            data: data,
          );
        }(),
    ];
  }

  Future<List<WorkspaceItem>> _attachUserDetails(
    List<WorkspaceItem> items,
  ) async {
    final userIds = items.map((item) => item.id).toList(growable: false);
    if (userIds.isEmpty) return items;

    final roleIds = items
        .map((item) => item.data['role_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final hospitalIds = items
        .map((item) => item.data['hospital_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final roleRows = roleIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('roles')
                  .select('id,role_name')
                  .inFilter('id', roleIds))
              .cast<Map<String, dynamic>>();
    final hospitalRows = hospitalIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('hospitals')
                  .select('id,hospital_name,image_url')
                  .inFilter('id', hospitalIds))
              .cast<Map<String, dynamic>>();
    final doctorRows =
        (await _client
                .from('doctors')
                .select(
                  'user_id,department_id,display_name,specialization,license_number,availability_status,consultation_fee,biography',
                )
                .inFilter('user_id', userIds))
            .cast<Map<String, dynamic>>();
    final departmentIds = doctorRows
        .map((row) => row['department_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final departmentRows = departmentIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('hospital_departments')
                  .select('id,department_name')
                  .inFilter('id', departmentIds))
              .cast<Map<String, dynamic>>();

    final roleNames = <String, String>{
      for (final row in roleRows)
        row['id'].toString(): row['role_name']?.toString() ?? '',
    };
    final hospitalNames = <String, String>{
      for (final row in hospitalRows)
        row['id'].toString(): row['hospital_name']?.toString() ?? '',
    };
    final hospitalImages = <String, String?>{
      for (final row in hospitalRows)
        row['id'].toString(): row['image_url']?.toString(),
    };
    final departmentNames = <String, String>{
      for (final row in departmentRows)
        row['id'].toString(): row['department_name']?.toString() ?? '',
    };
    final doctorsByUser = <String, Map<String, dynamic>>{
      for (final row in doctorRows) row['user_id'].toString(): row,
    };

    return [
      for (final item in items)
        () {
          final doctor = doctorsByUser[item.id];
          final departmentId = doctor?['department_id']?.toString();
          return item.copyWith(
            data: {
              ...item.data,
              'role_name': roleNames[item.data['role_id']?.toString()],
              'hospital_name':
                  hospitalNames[item.data['hospital_id']?.toString()],
              'hospital_image_url':
                  hospitalImages[item.data['hospital_id']?.toString()],
              ...?doctor,
              if (departmentId != null)
                'department_name': departmentNames[departmentId],
            },
          );
        }(),
    ];
  }

  Future<List<WorkspaceItem>> _attachHospitalClassifications(
    List<WorkspaceItem> items,
  ) async {
    final classificationIds = items
        .map((item) => item.data['classification_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (classificationIds.isEmpty) return items;
    final rows =
        (await _client
                .from('hospital_classifications')
                .select('id,classification_name')
                .inFilter('id', classificationIds))
            .cast<Map<String, dynamic>>();
    final names = <String, String>{
      for (final row in rows)
        row['id'].toString(): row['classification_name']?.toString() ?? '',
    };
    return [
      for (final item in items)
        item.copyWith(
          data: {
            ...item.data,
            'classification_name':
                names[item.data['classification_id']?.toString()],
          },
        ),
    ];
  }

  Future<List<WorkspaceItem>> _attachServiceDepartments(
    List<WorkspaceItem> items,
  ) async {
    final departmentIds = items
        .map((item) => item.data['department_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (departmentIds.isEmpty) return items;
    final rows =
        (await _client
                .from('hospital_departments')
                .select('id,department_name')
                .inFilter('id', departmentIds))
            .cast<Map<String, dynamic>>();
    final names = <String, String>{
      for (final row in rows)
        row['id'].toString(): row['department_name']?.toString() ?? '',
    };
    return [
      for (final item in items)
        item.copyWith(
          data: {
            ...item.data,
            'department_name': names[item.data['department_id']?.toString()],
          },
        ),
    ];
  }

  Future<List<WorkspaceItem>> _attachPermissionRoles(
    List<WorkspaceItem> items,
  ) async {
    final roleIds = items
        .map((item) => item.data['role_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (roleIds.isEmpty) return items;
    final rows =
        (await _client
                .from('roles')
                .select('id,role_name')
                .inFilter('id', roleIds))
            .cast<Map<String, dynamic>>();
    final names = <String, String>{
      for (final row in rows)
        row['id'].toString(): row['role_name']?.toString() ?? '',
    };
    return [
      for (final item in items)
        item.copyWith(
          subtitle: names[item.data['role_id']?.toString()] ?? item.subtitle,
          data: {
            ...item.data,
            'role_name': names[item.data['role_id']?.toString()],
          },
        ),
    ];
  }

  Future<List<WorkspaceItem>> _attachMedicalRecordDoctors(
    List<WorkspaceItem> records,
  ) async {
    final doctorIds = records
        .map((item) => item.data['doctor_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (doctorIds.isEmpty) return records;
    final doctorRows =
        (await _client
                .from('doctors')
                .select('id,display_name')
                .inFilter('id', doctorIds))
            .cast<Map<String, dynamic>>();
    final names = <String, String>{
      for (final row in doctorRows)
        row['id'].toString(): row['display_name']?.toString() ?? '',
    };
    return [
      for (final item in records)
        item.copyWith(
          data: {
            ...item.data,
            'doctor_display_name': names[item.data['doctor_id']?.toString()],
          },
        ),
    ];
  }

  Future<List<WorkspaceItem>> _attachConversationDetails(
    List<WorkspaceItem> conversations,
    UserRole role,
  ) async {
    if (conversations.isEmpty) return conversations;

    final consultationIds = conversations
        .map((item) => item.data['consultation_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final consultationRows = consultationIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('consultations')
                  .select('id,doctor_id,patient_id')
                  .inFilter('id', consultationIds))
              .cast<Map<String, dynamic>>();
    final consultationsById = <String, Map<String, dynamic>>{
      for (final row in consultationRows) row['id'].toString(): row,
    };

    final doctorIds = <String>{
      ...consultationRows
          .map((row) => row['doctor_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty),
      ...conversations
          .map((item) => item.data['doctor_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty),
    }.toList(growable: false);
    final doctorRows = doctorIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('doctors')
                  .select('id,display_name,specialization')
                  .inFilter('id', doctorIds))
              .cast<Map<String, dynamic>>();
    final doctorsById = <String, Map<String, dynamic>>{
      for (final row in doctorRows) row['id'].toString(): row,
    };

    final patientIds = <String>{
      ...consultationRows
          .map((row) => row['patient_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty),
      ...conversations
          .map((item) => item.data['patient_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty),
    }.toList(growable: false);
    final patientRows = patientIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('patients')
                  .select('id,user_id')
                  .inFilter('id', patientIds))
              .cast<Map<String, dynamic>>();
    final userIds = patientRows
        .map((row) => row['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final userRows = userIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('users')
                  .select('id,first_name,last_name')
                  .inFilter('id', userIds))
              .cast<Map<String, dynamic>>();
    final usersById = <String, Map<String, dynamic>>{
      for (final row in userRows) row['id'].toString(): row,
    };
    final patientsById = <String, Map<String, dynamic>>{
      for (final row in patientRows) row['id'].toString(): row,
    };

    final conversationIds = conversations
        .map((item) => item.id)
        .toList(growable: false);
    final messageRows =
        (await _client
                .from('chat_messages')
                .select('conversation_id,sender_id,message,sent_at,read_at')
                .inFilter('conversation_id', conversationIds)
                .order('sent_at', ascending: false))
            .cast<Map<String, dynamic>>();
    final authUserId = _client.auth.currentUser?.id;
    final currentUser = authUserId == null
        ? null
        : await _client
              .from('users')
              .select('id')
              .eq('auth_user_id', authUserId)
              .maybeSingle();
    final currentUserId = currentUser?['id']?.toString();
    final latestByConversation = <String, Map<String, dynamic>>{};
    final unreadByConversation = <String, int>{};
    for (final row in messageRows) {
      final conversationId = row['conversation_id']?.toString() ?? '';
      if (conversationId.isEmpty) continue;
      latestByConversation.putIfAbsent(conversationId, () => row);
      if (row['read_at'] == null &&
          row['sender_id']?.toString() != currentUserId) {
        unreadByConversation.update(
          conversationId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    return [
      for (final item in conversations)
        () {
          final consultation =
              consultationsById[item.data['consultation_id']?.toString()];
          final doctor =
              doctorsById[consultation?['doctor_id']?.toString() ??
                  item.data['doctor_id']?.toString() ??
                  ''];
          final patient =
              patientsById[consultation?['patient_id']?.toString() ??
                  item.data['patient_id']?.toString() ??
                  ''];
          final patientUser = usersById[patient?['user_id']?.toString() ?? ''];
          final patientName = _join([
            patientUser?['first_name']?.toString() ?? '',
            patientUser?['last_name']?.toString() ?? '',
          ]);
          final doctorName = doctor?['display_name']?.toString().trim() ?? '';
          final participantName = role == UserRole.doctor
              ? patientName
              : doctorName;
          final latest = latestByConversation[item.id];
          final preview = latest?['message']?.toString().trim() ?? '';
          final latestIsMine =
              latest?['sender_id']?.toString() == currentUserId;
          final unreadCount = unreadByConversation[item.id] ?? 0;
          final latestAt = latest == null
              ? item.timestamp
              : DateTime.tryParse(latest['sent_at']?.toString() ?? '') ??
                    item.timestamp;
          return item.copyWith(
            title: participantName.isEmpty ? item.title : participantName,
            subtitle: preview.isEmpty
                ? 'No messages yet'
                : '${latestIsMine ? 'You: ' : ''}$preview',
            timestamp: latestAt,
            isUnread: unreadCount > 0,
            data: {
              ...item.data,
              'participant_name': participantName,
              'participant_role': role == UserRole.doctor
                  ? 'Patient'
                  : 'Doctor',
              'doctor_display_name': doctorName,
              'doctor_specialization': doctor?['specialization'],
              'patient_name': patientName,
              'last_message': preview,
              'unread_count': unreadCount,
            },
          );
        }(),
    ];
  }

  Future<List<WorkspaceItem>> _attachConsultationDetails(
    List<WorkspaceItem> consultations,
  ) async {
    final doctorIds = consultations
        .map((item) => item.data['doctor_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final hospitalIds = consultations
        .map((item) => item.data['hospital_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final doctorRows = doctorIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('doctors')
                  .select('id,department_id,display_name,profile_image_url')
                  .inFilter('id', doctorIds))
              .cast<Map<String, dynamic>>();
    final hospitalRows = hospitalIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('hospitals')
                  .select('id,hospital_name,address,city,province,image_url')
                  .inFilter('id', hospitalIds))
              .cast<Map<String, dynamic>>();
    final departmentIds = <String>{
      ...consultations
          .map((item) => item.data['department_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty),
      ...doctorRows
          .map((row) => row['department_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty),
    }.toList(growable: false);
    final departmentRows = departmentIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _client
                  .from('hospital_departments')
                  .select('id,department_name')
                  .inFilter('id', departmentIds))
              .cast<Map<String, dynamic>>();
    final doctorNames = <String, String>{
      for (final row in doctorRows)
        row['id'].toString(): row['display_name']?.toString() ?? '',
    };
    final doctorImages = <String, String?>{
      for (final row in doctorRows)
        row['id'].toString(): row['profile_image_url']?.toString(),
    };
    final doctorDepartments = <String, String?>{
      for (final row in doctorRows)
        row['id'].toString(): row['department_id']?.toString(),
    };
    final hospitalNames = <String, String>{
      for (final row in hospitalRows)
        row['id'].toString(): row['hospital_name']?.toString() ?? '',
    };
    final hospitalImages = <String, String?>{
      for (final row in hospitalRows)
        row['id'].toString(): row['image_url']?.toString(),
    };
    final hospitalLocations = <String, String>{
      for (final row in hospitalRows)
        row['id'].toString(): _join([
          row['address']?.toString() ?? '',
          if ((row['address']?.toString().trim() ?? '').isEmpty)
            row['city']?.toString() ?? '',
          if ((row['address']?.toString().trim() ?? '').isEmpty)
            row['province']?.toString() ?? '',
        ]),
    };
    final departmentNames = <String, String>{
      for (final row in departmentRows)
        row['id'].toString(): row['department_name']?.toString() ?? '',
    };

    return [
      for (final item in consultations)
        item.copyWith(
          data: {
            ...item.data,
            'doctor_display_name':
                doctorNames[item.data['doctor_id']?.toString()],
            'doctor_profile_image_url':
                doctorImages[item.data['doctor_id']?.toString()],
            'hospital_name':
                hospitalNames[item.data['hospital_id']?.toString()],
            'hospital_image_url':
                hospitalImages[item.data['hospital_id']?.toString()],
            'hospital_location':
                hospitalLocations[item.data['hospital_id']?.toString()],
            'department_name':
                departmentNames[item.data['department_id']?.toString() ??
                    doctorDepartments[item.data['doctor_id']?.toString()]],
          },
        ),
    ];
  }

  Future<String> _currentDoctorId() async {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('An authenticated doctor is required.');
    }
    final appUser = await _client
        .from('users')
        .select('id')
        .eq('auth_user_id', user.id)
        .single();
    final doctor = await _client
        .from('doctors')
        .select('id')
        .eq('user_id', appUser['id'])
        .single();
    return doctor['id'].toString();
  }

  Future<String> _currentHospitalId() async {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('An authenticated hospital administrator is required.');
    }
    final appUser = await _client
        .from('users')
        .select('hospital_id')
        .eq('auth_user_id', user.id)
        .single();
    final hospitalId = appUser['hospital_id']?.toString();
    if (hospitalId == null || hospitalId.isEmpty) {
      throw StateError('This administrator is not assigned to a hospital.');
    }
    return hospitalId;
  }

  Future<List<Map<String, dynamic>>> _loadDoctorAppointments(
    String doctorId,
  ) async =>
      (await _client
              .from('consultations')
              .select('appointment_date,consultation_type,status')
              .eq('doctor_id', doctorId)
              .neq('status', 'rejected')
              .neq('status', 'cancelled'))
          .cast<Map<String, dynamic>>();

  List<WorkspaceItem> _annotateSchedules(
    List<WorkspaceItem> schedules,
    List<Map<String, dynamic>> appointments,
  ) => [
    for (final schedule in schedules)
      schedule.copyWith(
        status: _reservedCount(schedule.data, appointments) > 0
            ? 'reserved / protected'
            : schedule.status,
        data: {
          ...schedule.data,
          'reserved_consultation_count': _reservedCount(
            schedule.data,
            appointments,
          ),
        },
      ),
  ];

  int _reservedCount(
    Map<String, Object?> schedule,
    List<Map<String, dynamic>> appointments,
  ) => appointments
      .where(
        (appointment) => _appointmentMatchesSchedule(schedule, appointment),
      )
      .length;

  Future<WorkspaceSnapshot> _loadDashboard(UserRole role) async {
    final specs = switch (role) {
      UserRole.patient => const [
        _WorkspaceTableSpec.compact('consultations'),
        _WorkspaceTableSpec.compact('notifications'),
        _WorkspaceTableSpec.compact('prescriptions'),
        _WorkspaceTableSpec.compact('laboratory_results'),
      ],
      UserRole.doctor => const [
        _WorkspaceTableSpec.compact('consultations'),
        _WorkspaceTableSpec.compact('doctor_patient_assignments'),
        _WorkspaceTableSpec.compact('doctor_schedules'),
        _WorkspaceTableSpec.compact('laboratory_results'),
      ],
      UserRole.hospitalAdministrator => const [
        _WorkspaceTableSpec.compact('consultations'),
        _WorkspaceTableSpec.compact('hospital_beds'),
        _WorkspaceTableSpec.compact('hospital_rooms'),
        _WorkspaceTableSpec.compact('emergency_room_status'),
      ],
      UserRole.superAdministrator => const [
        _WorkspaceTableSpec.compact('hospitals'),
        _WorkspaceTableSpec.compact('users'),
        _WorkspaceTableSpec.compact('security_logs'),
        _WorkspaceTableSpec.compact('maintenance_windows'),
      ],
      UserRole.guest => const <_WorkspaceTableSpec>[],
    };
    final doctorId = role == UserRole.doctor ? await _currentDoctorId() : null;
    final hospitalId = role == UserRole.hospitalAdministrator
        ? await _currentHospitalId()
        : null;
    final responses = await Future.wait(
      specs.map((spec) async {
        dynamic query = _client.from(spec.table).select(spec.columns);
        if (spec.table == 'doctor_schedules' && doctorId != null) {
          query = query.eq('doctor_id', doctorId);
        }
        if (hospitalId != null && _hospitalScopedTables.contains(spec.table)) {
          query = query.eq('hospital_id', hospitalId);
        }
        if (spec.orderColumn != null) {
          query = query.order(spec.orderColumn!, ascending: false);
        }
        final response = await query.limit(100);
        return (response as List).cast<Map<String, dynamic>>();
      }),
    );
    final metrics = <WorkspaceMetric>[];
    for (var index = 0; index < specs.length; index++) {
      metrics.add(
        WorkspaceMetric(
          label: _metricLabel(specs[index].table),
          value: _boundedCount(responses[index].length),
        ),
      );
    }
    final primary = responses.isEmpty
        ? const <Map<String, dynamic>>[]
        : responses.first;
    var dashboardItems = primary
        .take(8)
        .map((row) => _mapRow(specs.first.table, row))
        .toList(growable: false);
    if (specs.first.table == 'consultations') {
      if (role == UserRole.doctor) {
        dashboardItems = await _attachPatientDetails(
          dashboardItems,
          assignment: false,
        );
      }
      dashboardItems = await _attachConsultationDetails(dashboardItems);
    }
    return WorkspaceSnapshot(
      title: switch (role) {
        UserRole.patient => 'Your care at a glance',
        UserRole.doctor => 'Clinical work queue',
        UserRole.hospitalAdministrator => 'Assigned-hospital operations',
        UserRole.superAdministrator => 'Platform governance',
        UserRole.guest => 'CareNavigator PH',
      },
      description:
          'Current information available to your CareNavigator PH account.',
      metrics: metrics,
      items: dashboardItems,
      loadedAt: DateTime.now(),
    );
  }

  Future<WorkspaceSnapshot> _loadAnalytics(
    String functionName,
    String title,
  ) async {
    final data = await _client.rpc<Map<String, dynamic>>(functionName);
    final metrics = <WorkspaceMetric>[];
    final items = <WorkspaceItem>[];
    for (final entry in data.entries) {
      if (entry.key == 'generated_at' || entry.key == 'hospital_id') continue;
      final value = entry.value;
      if (value is num || value is String || value is bool) {
        metrics.add(
          WorkspaceMetric(label: _humanize(entry.key), value: '$value'),
        );
      } else {
        items.add(
          WorkspaceItem(
            id: entry.key,
            kind: 'analytics',
            title: _humanize(entry.key),
            subtitle: _analyticsSummary(value),
          ),
        );
      }
    }
    return WorkspaceSnapshot(
      title: title,
      description: 'Current analytics available to your account.',
      metrics: metrics,
      items: items,
      loadedAt: DateTime.now(),
    );
  }
}

class _WorkspaceTableSpec {
  const _WorkspaceTableSpec({
    required this.table,
    required this.title,
    required this.description,
    this.columns = '*',
    this.orderColumn,
    this.idColumn = 'id',
  }) : ascending = false;

  const _WorkspaceTableSpec.compact(this.table)
    : title = '',
      description = '',
      columns = '*',
      orderColumn = null,
      ascending = false,
      idColumn = 'id';

  final String table;
  final String title;
  final String description;
  final String columns;
  final String? orderColumn;
  final bool ascending;
  final String idColumn;
}

_WorkspaceTableSpec? _specFor(UserRole role, String section) {
  final table = switch ((role, section)) {
    (UserRole.patient, 'appointments') ||
    (UserRole.patient, 'consultations') => 'consultations',
    (UserRole.patient, 'messages') => 'chat_conversations',
    (UserRole.patient, 'records') => 'medical_records',
    (UserRole.patient, 'prescriptions') => 'prescriptions',
    (UserRole.patient, 'labs') => 'laboratory_results',
    (UserRole.patient, 'notifications') => 'notifications',
    (UserRole.patient, 'profile') => 'patients',
    (UserRole.doctor, 'schedule') => 'doctor_schedules',
    (UserRole.doctor, 'appointments') ||
    (UserRole.doctor, 'consultations') => 'consultations',
    (UserRole.doctor, 'patients') => 'doctor_patient_assignments',
    (UserRole.doctor, 'results-review') => 'laboratory_results',
    (UserRole.doctor, 'prescriptions') => 'prescriptions',
    (UserRole.doctor, 'laboratory') => 'laboratory_requests',
    (UserRole.doctor, 'messages') => 'chat_conversations',
    (UserRole.doctor, 'notifications') => 'notifications',
    (UserRole.doctor, 'profile') => 'doctors',
    (UserRole.hospitalAdministrator, 'appointments') => 'consultations',
    (UserRole.hospitalAdministrator, 'availability') =>
      'hospital_facility_status',
    (UserRole.hospitalAdministrator, 'beds') => 'hospital_beds',
    (UserRole.hospitalAdministrator, 'rooms') => 'hospital_rooms',
    (UserRole.hospitalAdministrator, 'emergency-room') =>
      'emergency_room_status',
    (UserRole.hospitalAdministrator, 'services') => 'hospital_services',
    (UserRole.hospitalAdministrator, 'departments') => 'hospital_departments',
    (UserRole.hospitalAdministrator, 'staff') => 'users',
    (UserRole.hospitalAdministrator, 'audit') => 'audit_logs',
    (UserRole.hospitalAdministrator, 'reports') => 'consultations',
    (UserRole.hospitalAdministrator, 'notifications') => 'notifications',
    (UserRole.superAdministrator, 'hospitals') ||
    (UserRole.superAdministrator, 'approvals') => 'hospitals',
    (UserRole.superAdministrator, 'accounts') => 'users',
    (UserRole.superAdministrator, 'permissions') => 'role_permissions',
    (UserRole.superAdministrator, 'settings') => 'system_settings',
    (UserRole.superAdministrator, 'analytics') => 'audit_logs',
    (UserRole.superAdministrator, 'security') => 'security_logs',
    (UserRole.superAdministrator, 'maintenance') => 'maintenance_windows',
    (UserRole.superAdministrator, 'audit') => 'audit_logs',
    (UserRole.superAdministrator, 'notifications') => 'notifications',
    _ => null,
  };
  if (table == null) return null;
  return _WorkspaceTableSpec(
    table: table,
    title: role == UserRole.patient && section == 'labs'
        ? 'Diagnostics'
        : _humanize(section),
    description: _descriptionFor(role, section),
    orderColumn: _orderColumn(table),
    idColumn: table == 'system_settings' ? 'key' : 'id',
  );
}

_WorkspaceTableSpec? _appointmentRequestDetailSpec(UserRole role, String kind) {
  if (kind == 'online_consultation_requests' &&
      {
        UserRole.patient,
        UserRole.doctor,
        UserRole.hospitalAdministrator,
      }.contains(role)) {
    return const _WorkspaceTableSpec(
      table: 'online_consultation_requests',
      title: 'Appointment Details',
      description: 'Review this appointment request.',
      columns:
          'id,reference_number,patient_id,profile_first_name,profile_last_name,phone_number_snapshot,hospital_id,requested_department_id,requested_doctor_id,assigned_doctor_id,medical_concern,symptom_duration,preferred_schedule,proposed_schedule,confirmed_schedule,consultation_channel,request_status,official_consultation_id,additional_information_request,rejection_reason,cancellation_reason,created_at,updated_at',
      orderColumn: 'created_at',
    );
  }
  if (kind == 'guest_consultation_requests' &&
      {UserRole.doctor, UserRole.hospitalAdministrator}.contains(role)) {
    return const _WorkspaceTableSpec(
      table: 'guest_consultation_requests',
      title: 'Appointment Details',
      description: 'Review this appointment request.',
      columns:
          'id,reference_number,first_name,last_name,full_name,birth_date,sex,mobile_number,email,address,symptoms,symptom_duration,consultation_reason,preferred_hospital_id,preferred_department_id,request_status,identity_review_status,assigned_doctor_id,preferred_consultation_type,preferred_schedule,created_at',
      orderColumn: 'created_at',
    );
  }
  return null;
}

String? _orderColumn(String table) => switch (table) {
  'consultations' => 'appointment_date',
  'notifications' ||
  'prescriptions' ||
  'medical_documents' ||
  'medical_records' ||
  'audit_logs' ||
  'security_logs' ||
  'maintenance_windows' => 'created_at',
  'laboratory_results' => 'uploaded_at',
  'laboratory_requests' => 'requested_at',
  'doctor_patient_assignments' => 'assigned_at',
  'chat_conversations' || 'hospitals' || 'users' || 'doctors' => 'updated_at',
  'doctor_schedules' => 'day_of_week',
  'hospital_beds' ||
  'hospital_rooms' ||
  'emergency_room_status' ||
  'hospital_facility_status' => 'last_updated',
  'hospital_services' ||
  'hospital_departments' ||
  'role_permissions' ||
  'system_settings' => 'updated_at',
  _ => null,
};

WorkspaceItem _mapRow(String table, Map<String, dynamic> row) {
  String value(String key, [String fallback = '']) =>
      row[key]?.toString().trim().isNotEmpty == true
      ? row[key].toString().trim()
      : fallback;
  final id = value('id', value('key', 'record'));
  final timestamp = _firstDate(row, const [
    'appointment_date',
    'sent_at',
    'vitals_recorded_at',
    'created_at',
    'updated_at',
    'confirmed_schedule',
    'proposed_schedule',
    'preferred_schedule',
    'last_updated',
    'requested_at',
    'uploaded_at',
    'assigned_at',
  ]);
  return switch (table) {
    'consultations' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('chief_complaint', 'Consultation'),
      subtitle: _join([value('consultation_type'), value('appointment_date')]),
      status: value('status'),
      timestamp: timestamp,
      data: row,
    ),
    'guest_consultation_requests' => WorkspaceItem(
      id: id,
      kind: table,
      title: _join([value('first_name'), value('last_name')]).isNotEmpty
          ? _join([value('first_name'), value('last_name')])
          : value('full_name', value('reference_number', 'Guest request')),
      subtitle: value('consultation_reason', value('symptoms')),
      status: value('request_status'),
      timestamp: timestamp,
      data: row,
    ),
    'notifications' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('title', 'Notification'),
      subtitle: value('message'),
      status: row['is_read'] == true ? 'read' : 'unread',
      isUnread: row['is_read'] != true,
      timestamp: timestamp,
      data: row,
    ),
    'prescriptions' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('medication_name', 'Prescription'),
      subtitle: _join([value('dosage'), value('frequency'), value('duration')]),
      timestamp: timestamp,
      data: row,
    ),
    'laboratory_results' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('test_name', 'Laboratory result'),
      subtitle: value(
        'professional_interpretation',
        value('ai_summary', 'Awaiting interpretation'),
      ),
      status: value('verification_status'),
      timestamp: timestamp,
      data: row,
    ),
    'laboratory_requests' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('test_name', 'Laboratory request'),
      subtitle: value(
        'instructions',
        _humanizeWorkspaceValue(value('priority')),
      ),
      status: value('status'),
      timestamp: timestamp,
      data: row,
    ),
    'medical_documents' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('title', 'Medical document'),
      subtitle: _join([
        _humanizeWorkspaceValue(value('document_type')),
        _fileSize(row['size_bytes']),
        value('ai_summary', switch (value('ai_analysis_status')) {
          'pending' || 'processing' => 'Groq AI summary is being prepared.',
          'failed' => value(
            'ai_analysis_error',
            'AI summary unavailable. Please use the original document.',
          ),
          _ => '',
        }),
      ]),
      status: switch (value('ai_analysis_status')) {
        '' || 'not_requested' || 'completed' => null,
        final status => status,
      },
      timestamp: timestamp,
      data: row,
    ),
    'online_consultation_requests' => WorkspaceItem(
      id: id,
      kind: table,
      title: _join([
        value('reference_number', 'Online request'),
        _join([value('profile_first_name'), value('profile_last_name')]),
      ]),
      subtitle: _join([
        value('medical_concern'),
        value('confirmed_schedule', value('preferred_schedule')),
      ]),
      status: value('request_status'),
      timestamp: timestamp,
      data: row,
    ),
    'medical_records' => WorkspaceItem(
      id: id,
      kind: table,
      title: value(
        'title',
        _humanizeWorkspaceValue(value('record_type', 'Medical record')),
      ),
      subtitle: value('description', value('confirmed_diagnosis')),
      status: row['is_ai_assisted'] == true
          ? 'AI-assisted, doctor confirmed'
          : null,
      timestamp: timestamp,
      data: row,
    ),
    'chat_conversations' => WorkspaceItem(
      id: id,
      kind: table,
      title: 'Care conversation',
      subtitle: value('consultation_id').isEmpty
          ? 'Direct care conversation'
          : 'Consultation ${_shortId(value('consultation_id'))}',
      status: value('status'),
      timestamp: timestamp,
      data: row,
    ),
    'doctor_schedules' => WorkspaceItem(
      id: id,
      kind: table,
      title: _dayLabel(value('day_of_week')),
      subtitle: _join([
        value('starts_at'),
        value('ends_at'),
        _humanizeWorkspaceValue(value('consultation_type')),
      ]),
      status: row['is_active'] == true ? 'active' : 'inactive',
      data: row,
    ),
    'doctor_patient_assignments' => WorkspaceItem(
      id: id,
      kind: table,
      title: 'Assigned patient ${_shortId(value('patient_id'))}',
      subtitle: value('notes', 'Active care assignment'),
      status: row['ended_at'] == null ? 'active' : 'ended',
      timestamp: timestamp,
      data: row,
    ),
    'patients' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('patient_number', 'Patient profile'),
      subtitle: _join([
        value('blood_type'),
        _humanizeWorkspaceValue(value('identity_verification_status')),
      ]),
      status: value('profile_status', value('account_activation_status')),
      timestamp: timestamp,
      data: row,
    ),
    'doctors' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('display_name', 'Doctor profile'),
      subtitle: value('specialization'),
      status: value('availability_status'),
      timestamp: timestamp,
      data: row,
    ),
    'hospital_beds' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('bed_type', 'Hospital beds'),
      subtitle:
          '${value('available_beds', 'Not published')} available of ${value('total_beds', 'Not published')}',
      status: '${value('occupied_beds', 'Not published')} occupied',
      timestamp: timestamp,
      data: row,
    ),
    'hospital_rooms' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('room_type', 'Hospital rooms'),
      subtitle:
          '${value('available_rooms', 'Not published')} available of ${value('total_rooms', 'Not published')}',
      status: value('status'),
      timestamp: timestamp,
      data: row,
    ),
    'emergency_room_status' => WorkspaceItem(
      id: id,
      kind: table,
      title: 'Emergency room',
      subtitle:
          '${value('available_beds', 'Not published')} beds available · ${value('current_patient_count', 'Not published')} current patients',
      status: value('status'),
      timestamp: timestamp,
      data: row,
    ),
    'hospital_facility_status' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('facility_type', 'Facility'),
      subtitle: _join([value('available_units'), value('notes')]),
      status: value('status'),
      timestamp: timestamp,
      data: row,
    ),
    'hospital_services' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('service_name', 'Hospital service'),
      subtitle: value('description'),
      status: value('availability_status'),
      timestamp: timestamp,
      data: row,
    ),
    'hospital_departments' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('department_name', 'Department'),
      subtitle: value('description'),
      status: value('availability_status'),
      timestamp: timestamp,
      data: row,
    ),
    'hospitals' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('hospital_name', 'Hospital'),
      subtitle: _join([value('address'), value('city'), value('province')]),
      status: _join([value('verification_status'), value('operating_status')]),
      timestamp: timestamp,
      data: row,
    ),
    'users' => WorkspaceItem(
      id: id,
      kind: table,
      title: _join([value('first_name'), value('last_name')]),
      subtitle: value('email', 'No email address'),
      status: value('account_status'),
      timestamp: timestamp,
      data: row,
    ),
    'role_permissions' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('permission', 'Permission'),
      subtitle: 'Role ${_shortId(value('role_id'))}',
      status: row['is_allowed'] == true ? 'allowed' : 'denied',
      timestamp: timestamp,
      data: row,
    ),
    'system_settings' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('key', 'Setting'),
      subtitle: value('description'),
      status: _settingValueLabel(row['value']),
      timestamp: timestamp,
      data: row,
    ),
    'security_logs' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('event_type', 'Security event'),
      subtitle: row['success'] == true ? 'Successful event' : 'Failed event',
      status: value('severity'),
      timestamp: timestamp,
      data: row,
    ),
    'maintenance_windows' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('title', 'Maintenance window'),
      subtitle: value('message'),
      status: row['is_active'] == true ? 'active' : 'inactive',
      timestamp: timestamp,
      data: row,
    ),
    'audit_logs' => WorkspaceItem(
      id: id,
      kind: table,
      title: value('action', 'Audit event'),
      subtitle: value('module'),
      timestamp: timestamp,
      data: row,
    ),
    _ => WorkspaceItem(
      id: id,
      kind: table,
      title: _humanize(table),
      subtitle: 'Record ${_shortId(id)}',
      timestamp: timestamp,
    ),
  };
}

bool _appointmentMatchesSchedule(
  Map<String, Object?> schedule,
  Map<String, dynamic> appointment,
) {
  final date = DateTime.tryParse(
    appointment['appointment_date']?.toString() ?? '',
  );
  if (date == null ||
      appointment['consultation_type']?.toString() !=
          schedule['consultation_type']?.toString()) {
    return false;
  }
  final local = date.toLocal();
  final day = int.tryParse(schedule['day_of_week']?.toString() ?? '');
  final start = _scheduleTimeMinutes(schedule['starts_at']);
  final end = _scheduleTimeMinutes(schedule['ends_at']);
  if (day == null || start == null || end == null || local.weekday % 7 != day) {
    return false;
  }
  final minute = local.hour * 60 + local.minute;
  return minute >= start && minute < end;
}

int? _scheduleTimeMinutes(Object? value) {
  final parts = (value?.toString() ?? '').split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}

String _dayLabel(String value) => switch (int.tryParse(value)) {
  0 => 'Sunday',
  1 => 'Monday',
  2 => 'Tuesday',
  3 => 'Wednesday',
  4 => 'Thursday',
  5 => 'Friday',
  6 => 'Saturday',
  _ => 'Schedule day',
};

String _descriptionFor(UserRole role, String section) => switch (role) {
  UserRole.patient =>
    {'appointments', 'consultations'}.contains(section)
        ? 'View your past and upcoming consultations.'
        : 'View the care information available to your account.',
  UserRole.doctor =>
    'Live clinical information limited to assigned and consultation relationships.',
  UserRole.hospitalAdministrator =>
    'Live operational information limited to your assigned hospital.',
  UserRole.superAdministrator =>
    section == 'analytics'
        ? 'Live platform activity indicators; clinical records remain limited to appropriate care relationships.'
        : 'Live platform governance information with authorized access.',
  UserRole.guest => 'Public CareNavigator PH information.',
};

String _metricLabel(String table) => switch (table) {
  'consultations' => 'Visible consultations',
  'notifications' => 'Notifications',
  'prescriptions' => 'Prescriptions',
  'laboratory_results' => 'Diagnostic results',
  'doctor_patient_assignments' => 'Assigned patients',
  'doctor_schedules' => 'Schedule slots',
  'hospital_beds' => 'Bed types',
  'hospital_rooms' => 'Room types',
  'emergency_room_status' => 'ER status records',
  'hospitals' => 'Hospitals',
  'users' => 'Accounts',
  'security_logs' => 'Security events',
  'maintenance_windows' => 'Maintenance windows',
  _ => _humanize(table),
};

String _humanize(String value) => value
    .replaceAll('-', ' ')
    .replaceAll('_', ' ')
    .split(' ')
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

const _latestVitalKeys = <String>[
  'height_cm',
  'weight_kg',
  'bmi',
  'blood_pressure_systolic',
  'blood_pressure_diastolic',
  'body_temperature_c',
  'heart_rate_bpm',
  'respiratory_rate_bpm',
  'oxygen_saturation_percent',
];

bool _hasVitalValue(Map<String, dynamic> row) =>
    _latestVitalKeys.any((key) => row[key] != null);

DateTime _recordDate(Map<String, dynamic> row) =>
    _firstDate(row, const ['vitals_recorded_at', 'created_at']) ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime _clinicalHistoryDate(Map<String, Object?> row) {
  for (final key in const [
    'electronically_signed_at',
    'result_date',
    'uploaded_at',
    'created_at',
    'start_date',
  ]) {
    final parsed = DateTime.tryParse(row[key]?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

String _vitalsSummary(Map<String, dynamic> row) => _join([
  if (row['blood_pressure_systolic'] != null &&
      row['blood_pressure_diastolic'] != null)
    'BP ${row['blood_pressure_systolic']}/${row['blood_pressure_diastolic']} mmHg',
  if (row['heart_rate_bpm'] != null) 'Pulse ${row['heart_rate_bpm']} bpm',
  if (row['oxygen_saturation_percent'] != null)
    'SpO₂ ${row['oxygen_saturation_percent']}%',
  if (row['body_temperature_c'] != null) 'Temp ${row['body_temperature_c']} °C',
  if (row['bmi'] != null) 'BMI ${row['bmi']}',
  if (row['height_cm'] != null) 'Height ${row['height_cm']} cm',
  if (row['weight_kg'] != null) 'Weight ${row['weight_kg']} kg',
]);

DateTime? _firstDate(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

String _join(Iterable<String> values) =>
    values.where((value) => value.isNotEmpty).join(' · ');

String _shortId(String value) =>
    value.length <= 8 ? value : value.substring(0, 8).toUpperCase();

String _fileSize(Object? value) {
  final bytes = value is num ? value.toInt() : int.tryParse('$value');
  if (bytes == null) return '';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes bytes';
}

String _settingValueLabel(Object? value) {
  if (value is bool) return value ? 'enabled' : 'disabled';
  final label = value?.toString() ?? 'not set';
  return label.length > 32 ? '${label.substring(0, 29)}...' : label;
}

String _humanizeWorkspaceValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return switch (trimmed.toLowerCase()) {
    'face_to_face' || 'in_person' || 'in-person' => 'Face-to-face',
    'online' || 'teleconsultation' || 'telemedicine' => 'Online',
    _ =>
      trimmed
          .replaceAll('_', ' ')
          .split(RegExp(r'\s+'))
          .map(
            (word) => word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1)}',
          )
          .join(' '),
  };
}

String _analyticsSummary(Object? value) {
  if (value is List) return '${value.length} grouped records';
  if (value is Map) {
    return value.entries
        .take(6)
        .map((entry) => '${_humanize(entry.key.toString())}: ${entry.value}')
        .join(' · ');
  }
  return value?.toString() ?? 'No data';
}

String _boundedCount(int count) => count >= 100 ? '100+' : '$count';
