import 'dart:typed_data';

import 'package:care_navigator_ph/src/models/user_profile.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
import 'package:care_navigator_ph/src/widgets/async_value_panel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

typedef JsonMap = Map<String, dynamic>;
typedef AvailableSlotLoader =
    Future<List<JsonMap>> Function({
      required String doctorId,
      required DateTime date,
      required String consultationType,
    });

const _standardPatientConsents = <JsonMap>[
  {
    'type': 'care_delivery',
    'version': '1.0',
    'title': 'Healthcare delivery',
    'description':
        'Allows CareNavigator participants to use your information to coordinate consultations and treatment.',
  },
  {
    'type': 'telemedicine',
    'version': '1.0',
    'title': 'Telemedicine consultations',
    'description':
        'Acknowledges the limitations and privacy considerations of remote video consultations.',
  },
  {
    'type': 'medical_record_sharing',
    'version': '1.0',
    'title': 'Medical-record sharing',
    'description':
        'Allows your assigned care team to access the records needed for your care under RLS controls.',
  },
  {
    'type': 'ai_assisted_document_analysis',
    'version': '1.0',
    'title': 'AI-assisted document analysis',
    'description':
        'Allows preliminary AI analysis of submitted medical documents; a licensed doctor must confirm clinical findings.',
  },
  {
    'type': 'care_notifications',
    'version': '1.0',
    'title': 'Care notifications',
    'description':
        'Allows consultation, result, prescription, and appointment notifications using your enabled channels.',
  },
];

class CareWorkspaceScreen extends ConsumerWidget {
  const CareWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateProvider);
    if (ref.read(supabaseClientProvider).auth.currentSession == null) {
      return _SignInRequired(onSignIn: () => context.go('/login'));
    }
    return AsyncValuePanel<UserProfile?>(
      value: ref.watch(currentProfileProvider),
      onRetry: () => ref.invalidate(currentProfileProvider),
      data: (profile) {
        if (profile == null || profile.accountStatus != 'active') {
          return const _SignInRequired(
            message: 'An active CareNavigator profile is required.',
          );
        }
        if (profile.role == 'super_admin') {
          return _SignInRequired(
            message:
                'Super administrators do not receive access to sensitive clinical workspaces.',
            actionLabel: 'Open platform operations',
            onSignIn: () => context.go('/admin/operations'),
          );
        }
        return _WorkspaceBody(profile: profile);
      },
    );
  }
}

class _WorkspaceBody extends ConsumerStatefulWidget {
  const _WorkspaceBody({required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<_WorkspaceBody> createState() => _WorkspaceBodyState();
}

class _WorkspaceBodyState extends ConsumerState<_WorkspaceBody> {
  bool _loading = true;
  bool _busy = false;
  int _selectedTab = 0;
  Object? _error;
  JsonMap _workspace = const {};

  String get _role => widget.profile.role;
  List<JsonMap> get _consultations => _rows(_workspace['consultations']);
  List<JsonMap> get _guestRequests => _rows(_workspace['guest_requests']);
  List<JsonMap> get _patients => _rows(_workspace['patients']);
  List<JsonMap> get _records => _rows(_workspace['medical_records']);
  List<JsonMap> get _diagnoses => _rows(_workspace['diagnoses']);
  List<JsonMap> get _treatmentPlans => _rows(_workspace['treatment_plans']);
  List<JsonMap> get _laboratoryRequests =>
      _rows(_workspace['laboratory_requests']);
  List<JsonMap> get _results => _rows(_workspace['laboratory_results']);
  List<JsonMap> get _prescriptions => _rows(_workspace['prescriptions']);
  List<JsonMap> get _medicalDocuments => _rows(_workspace['medical_documents']);
  List<JsonMap> get _consultationAttachments =>
      _rows(_workspace['consultation_attachments']);
  List<JsonMap> get _patientConsents => _rows(_workspace['patient_consents']);
  List<JsonMap> get _conversations => _rows(_workspace['conversations']);
  bool get _isDoctor => _role == 'doctor';
  bool get _isPatient => _role == 'patient';
  bool get _isHospitalAdmin => _role == 'hospital_admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final value = await ref.read(careRepositoryProvider).loadWorkspace(_role);
      if (!mounted) return;
      setState(() {
        _workspace = value;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppLoadingState(label: 'Loading care workspace');
    }
    if (_error != null) {
      return AppStatePanel(
        kind: AppStateKind.error,
        icon: AppIcons.cloudOffRounded,
        title: 'Unable to load your care workspace',
        message: _error.toString(),
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(AppIcons.refreshRounded),
          label: const Text('Try again'),
        ),
      );
    }
    final tabs = _tabs();
    if (_selectedTab >= tabs.length) _selectedTab = 0;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= AppBreakpoints.medium;
    final selected = tabs[_selectedTab];
    return SafeArea(
      child: Column(
        children: [
          AppPageHeader(
            eyebrow: 'ROLE-BASED CARE OPERATIONS',
            title: _isDoctor
                ? 'Clinical desk'
                : _isHospitalAdmin
                ? 'Hospital care desk'
                : 'My care journey',
            subtitle: 'A focused workspace for ${widget.profile.displayName}',
            icon: _isDoctor
                ? AppIcons.medicalServicesRounded
                : _isHospitalAdmin
                ? AppIcons.localHospitalRounded
                : AppIcons.healthAndSafetyRounded,
            actions: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () => context.go('/notifications'),
                icon: const Icon(AppIcons.notificationsOutlined),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _busy ? null : _load,
                icon: const Icon(AppIcons.refreshRounded),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppPageBody.horizontalPadding(width),
                AppSpacing.lg,
                AppPageBody.horizontalPadding(width),
                desktop ? AppSpacing.xl : 84,
              ),
              child: desktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 286,
                          child: _WorkspaceNavigation(
                            profile: widget.profile,
                            tabs: tabs,
                            selected: _selectedTab,
                            consultationCount: _consultations.length,
                            attentionCount:
                                _guestRequests.length + _results.length,
                            onSelected: (value) =>
                                setState(() => _selectedTab = value),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: _WorkspaceSection(tab: selected)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WorkspaceMobilePulse(
                          role: widget.profile.roleLabel,
                          consultationCount: _consultations.length,
                          attentionCount:
                              _guestRequests.length + _results.length,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          height: 48,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: tabs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: AppSpacing.xs),
                            itemBuilder: (context, index) => ChoiceChip(
                              selected: index == _selectedTab,
                              onSelected: (_) =>
                                  setState(() => _selectedTab = index),
                              avatar: tabs[index].tab.icon,
                              label: Text(tabs[index].tab.text ?? 'Section'),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Expanded(
                          child: _WorkspaceSection(
                            tab: selected,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<_WorkspaceTab> _tabs() {
    if (_isDoctor) {
      return [
        _WorkspaceTab(
          const Tab(icon: Icon(AppIcons.inboxOutlined), text: 'Guest review'),
          _GuestRequestsPanel(
            items: _guestRequests,
            busy: _busy,
            onReview: _reviewGuest,
            onConvert: _createPatientAccount,
          ),
        ),
        _WorkspaceTab(
          const Tab(
            icon: Icon(AppIcons.videoCallOutlined),
            text: 'Consultations',
          ),
          _ConsultationsPanel(
            items: _consultations,
            role: _role,
            busy: _busy,
            onBook: null,
            onTransition: _transitionConsultation,
            onChat: _openChat,
            onJoin: _joinMeeting,
          ),
        ),
        _WorkspaceTab(
          const Tab(icon: Icon(AppIcons.groupsOutlined), text: 'Patients'),
          _PatientsPanel(
            items: _patients,
            historyItems: _records,
            busy: _busy,
            onCreatePatient: _createDirectPatientAccount,
            onRecord: (patient) => _saveRecord(selectedPatient: patient),
            onResult: _uploadResult,
            onPrescription: _savePrescription,
            onLaboratoryRequest: _requestLaboratoryTest,
            onDiagnosis: _createDiagnosis,
            onTreatmentPlan: _createTreatmentPlan,
            onMedicalDocument: _uploadMedicalDocument,
            onConsultationAttachment: _uploadConsultationAttachment,
          ),
        ),
        _WorkspaceTab(
          const Tab(
            icon: Icon(AppIcons.scienceOutlined),
            text: 'Result review',
          ),
          _ResultsPanel(
            items: _results,
            isDoctor: true,
            busy: _busy,
            onAnalyze: _analyzeResult,
            onConfirm: _confirmResult,
            onReject: _rejectResult,
            onOpenFile: _openResultFile,
          ),
        ),
        _WorkspaceTab(
          const Tab(icon: Icon(AppIcons.folderSharedOutlined), text: 'Records'),
          _RecordsPanel(
            items: _records,
            canEdit: true,
            onEdit: (record) => _saveRecord(initial: record),
          ),
        ),
        _WorkspaceTab(
          const Tab(
            icon: Icon(AppIcons.healthAndSafetyOutlined),
            text: 'Clinical',
          ),
          _ClinicalRecordsPanel(
            diagnoses: _diagnoses,
            treatmentPlans: _treatmentPlans,
            laboratoryRequests: _laboratoryRequests,
            medicalDocuments: _medicalDocuments,
            consultationAttachments: _consultationAttachments,
            canManage: true,
            busy: _busy,
            onOpenMedicalDocument: _openMedicalDocument,
            onOpenAttachment: _openConsultationAttachment,
            onEditTreatmentPlan: _editTreatmentPlan,
            onDeleteTreatmentPlan: _deleteTreatmentPlan,
          ),
        ),
        _WorkspaceTab(
          const Tab(icon: Icon(AppIcons.forumOutlined), text: 'Messages'),
          _ConversationsPanel(items: _conversations, onOpen: _openConversation),
        ),
      ];
    }
    if (_isHospitalAdmin) {
      return [
        _WorkspaceTab(
          const Tab(
            icon: Icon(AppIcons.calendarMonthOutlined),
            text: 'Consultations',
          ),
          _ConsultationsPanel(
            items: _consultations,
            role: _role,
            busy: _busy,
            onBook: null,
            onTransition: _transitionConsultation,
            onChat: _openChat,
            onJoin: _joinMeeting,
          ),
        ),
        _WorkspaceTab(
          const Tab(
            icon: Icon(AppIcons.groupsOutlined),
            text: 'Hospital patients',
          ),
          _PatientsPanel(items: _patients, busy: _busy),
        ),
      ];
    }
    if (_isPatient) {
      return [
        _WorkspaceTab(
          const Tab(
            icon: Icon(AppIcons.calendarMonthOutlined),
            text: 'Appointments',
          ),
          _ConsultationsPanel(
            items: _consultations,
            role: _role,
            busy: _busy,
            onBook: _bookConsultation,
            onTransition: _transitionConsultation,
            onChat: _openChat,
            onJoin: _joinMeeting,
            onPatientAttachment: _uploadOwnConsultationAttachment,
          ),
        ),
        _WorkspaceTab(
          const Tab(
            icon: Icon(AppIcons.folderSharedOutlined),
            text: 'Medical records',
          ),
          _RecordsPanel(items: _records),
        ),
        _WorkspaceTab(
          const Tab(icon: Icon(AppIcons.scienceOutlined), text: 'Results'),
          _ResultsPanel(
            items: _results,
            isDoctor: false,
            busy: _busy,
            onOpenFile: _openResultFile,
          ),
        ),
        _WorkspaceTab(
          const Tab(
            icon: Icon(AppIcons.healthAndSafetyOutlined),
            text: 'Clinical',
          ),
          _ClinicalRecordsPanel(
            diagnoses: _diagnoses,
            treatmentPlans: _treatmentPlans,
            laboratoryRequests: _laboratoryRequests,
            medicalDocuments: _medicalDocuments,
            consultationAttachments: _consultationAttachments,
            canManage: false,
            busy: _busy,
            onOpenMedicalDocument: _openMedicalDocument,
            onOpenAttachment: _openConsultationAttachment,
          ),
        ),
        _WorkspaceTab(
          const Tab(
            icon: Icon(AppIcons.medicationOutlined),
            text: 'Prescriptions',
          ),
          _PrescriptionsPanel(items: _prescriptions),
        ),
        _WorkspaceTab(
          const Tab(icon: Icon(AppIcons.policyOutlined), text: 'Consents'),
          _PatientConsentsPanel(
            items: _patientConsents,
            busy: _busy,
            onDecision: _updatePatientConsent,
          ),
        ),
        _WorkspaceTab(
          const Tab(icon: Icon(AppIcons.forumOutlined), text: 'Messages'),
          _ConversationsPanel(items: _conversations, onOpen: _openConversation),
        ),
      ];
    }
    return [
      _WorkspaceTab(
        const Tab(
          icon: Icon(AppIcons.receiptLongOutlined),
          text: 'My requests',
        ),
        _GuestRequestsPanel(items: _guestRequests, busy: _busy),
      ),
      _WorkspaceTab(
        const Tab(
          icon: Icon(AppIcons.videoCallOutlined),
          text: 'Consultations',
        ),
        _ConsultationsPanel(
          items: _consultations,
          role: _role,
          busy: _busy,
          onBook: null,
          onTransition: _transitionConsultation,
          onChat: _openChat,
          onJoin: _joinMeeting,
        ),
      ),
      _WorkspaceTab(
        const Tab(icon: Icon(AppIcons.forumOutlined), text: 'Messages'),
        _ConversationsPanel(items: _conversations, onOpen: _openConversation),
      ),
    ];
  }

  Future<void> _bookConsultation() async {
    if (_patients.isEmpty) {
      _showError('A patient profile is required before booking.');
      return;
    }
    final client = ref.read(supabaseClientProvider);
    try {
      final doctors =
          (await client
                      .from('doctors')
                      .select(
                        'id, hospital_id, display_name, specialization, availability_status, consultation_fee, hospitals(hospital_name)',
                      )
                      .inFilter('availability_status', ['available', 'limited'])
                      .order('display_name')
                  as List)
              .whereType<JsonMap>()
              .toList();
      if (!mounted) return;
      if (doctors.isEmpty) {
        _showError('No doctors are currently available for patient booking.');
        return;
      }
      final repository = ref.read(careRepositoryProvider);
      final values = await _bookDialog(
        context,
        doctors,
        loadSlots:
            ({required doctorId, required date, required consultationType}) =>
                repository.listAvailableDoctorSlots(
                  doctorId: doctorId,
                  date: date,
                  consultationType: consultationType,
                ),
      );
      if (values == null) return;
      await _run(() async {
        await ref
            .read(careRepositoryProvider)
            .bookConsultation(
              doctorId: values['doctor_id'].toString(),
              hospitalId: values['hospital_id'].toString(),
              consultationType: values['consultation_type'].toString(),
              appointmentDate: values['appointment_date'] as DateTime,
              chiefComplaint: values['chief_complaint'].toString(),
              patientId: _patients.first['id'].toString(),
            );
      }, 'Consultation request submitted.');
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _reviewGuest(JsonMap request, String decision) async {
    List<JsonMap> doctors = const [];
    final hospitalId = request['preferred_hospital_id']?.toString();
    if (decision == 'approve') {
      try {
        var query = ref
            .read(supabaseClientProvider)
            .from('doctors')
            .select(
              'id, hospital_id, display_name, specialization, availability_status',
            );
        if (hospitalId != null) query = query.eq('hospital_id', hospitalId);
        doctors = (await query.order('display_name') as List)
            .whereType<JsonMap>()
            .toList();
      } catch (error) {
        _showError(error);
        return;
      }
    }
    if (!mounted) return;
    final values = await _guestReviewDialog(
      context,
      request,
      decision,
      doctors,
    );
    if (values == null) return;
    await _run(
      () async {
        await ref
            .read(careRepositoryProvider)
            .reviewGuestConsultation(
              requestId: request['id'].toString(),
              decision: decision,
              assignedDoctorId: values['doctor_id']?.toString(),
              appointmentDate: values['appointment_date'] as DateTime?,
              notes: values['notes']?.toString(),
            );
      },
      decision == 'approve'
          ? 'Guest consultation approved and scheduled.'
          : 'Guest consultation rejected.',
    );
  }

  Future<void> _createPatientAccount(JsonMap request) async {
    final values = await _patientAccountDialog(context, request);
    if (values == null) return;
    await _run(
      () async {
        await ref
            .read(careRepositoryProvider)
            .createPatientAccount(
              guestRequestId: request['id'].toString(),
              email: values['email'].toString(),
              password: values['password'].toString(),
              firstName: values['first_name']?.toString(),
              lastName: values['last_name']?.toString(),
              assignedDoctorId: request['assigned_doctor_id']?.toString(),
            );
      },
      'Official patient account created. Share the temporary password through an approved secure channel.',
    );
  }

  Future<void> _createDirectPatientAccount() async {
    final values = await _directPatientAccountDialog(context);
    if (values == null) return;
    await _run(
      () async {
        await ref
            .read(careRepositoryProvider)
            .createDirectPatientAccount(
              firstName: values['first_name'].toString(),
              middleName: values['middle_name']?.toString(),
              lastName: values['last_name'].toString(),
              email: values['email'].toString(),
              password: values['password'].toString(),
              birthDate: values['birth_date'] as DateTime?,
              sex: values['sex']?.toString(),
              mobileNumber: values['mobile_number']?.toString(),
              address: values['address']?.toString(),
            );
      },
      'Patient account created and assigned to you. Share the temporary password through an approved secure channel.',
    );
  }

  Future<void> _transitionConsultation(
    JsonMap consultation,
    String status,
  ) async {
    final values = await _transitionDialog(context, consultation, status);
    if (values == null) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .transitionConsultation(
            consultationId: consultation['id'].toString(),
            status: status,
            doctorNotes: values['doctor_notes']?.toString(),
            confirmedDiagnosis: values['confirmed_diagnosis']?.toString(),
            treatmentPlan: values['treatment_plan']?.toString(),
            meetingLink: values['meeting_link']?.toString(),
          );
      if (status == 'scheduled' &&
          consultation['consultation_type'] == 'online') {
        await ref
            .read(careRepositoryProvider)
            .ensureVideoSession(consultation['id'].toString());
      }
    }, 'Consultation marked ${_label(status).toLowerCase()}.');
  }

  Future<void> _openChat(JsonMap consultation) async {
    try {
      final result = await ref
          .read(careRepositoryProvider)
          .ensureConversation(consultation['id'].toString());
      final id = result['conversation_id'] ?? result['id'];
      if (id == null) throw StateError('Conversation could not be opened.');
      if (mounted) context.go('/messages/$id');
    } catch (error) {
      _showError(error);
    }
  }

  void _openConversation(JsonMap conversation) {
    context.go('/messages/${conversation['id']}');
  }

  Future<void> _joinMeeting(JsonMap consultation) async {
    final value = consultation['meeting_link']?.toString();
    if (value == null || value.isEmpty) {
      _showError('The doctor has not provisioned the meeting room yet.');
      return;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !{'https', 'http'}.contains(uri.scheme)) {
      _showError('The meeting link is invalid.');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showError('Could not open the video consultation.');
    }
  }

  Future<void> _saveRecord({JsonMap? initial, JsonMap? selectedPatient}) async {
    if (_patients.isEmpty && initial == null) return;
    final values = await _recordDialog(
      context,
      _patients,
      _consultations,
      initial,
      selectedPatient: selectedPatient,
    );
    if (values == null) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .saveMedicalRecord(
            id: initial?['id']?.toString(),
            patientId: values['patient_id'].toString(),
            hospitalId: values['hospital_id'].toString(),
            recordType: values['record_type'].toString(),
            title: values['title'].toString(),
            consultationId: values['consultation_id']?.toString(),
            description: values['description']?.toString(),
            confirmedDiagnosis: values['confirmed_diagnosis']?.toString(),
            treatmentPlan: values['treatment_plan']?.toString(),
          );
    }, initial == null ? 'Medical record created.' : 'Medical record updated.');
  }

  Future<void> _savePrescription(JsonMap patient) async {
    final patientConsultations = _consultations
        .where((item) => item['patient_id'] == patient['id'])
        .toList();
    final values = await _prescriptionDialog(
      context,
      patient,
      patientConsultations,
    );
    if (values == null) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .savePrescription(
            patientId: patient['id'].toString(),
            consultationId: values['consultation_id'].toString(),
            medicationName: values['medication_name'].toString(),
            dosage: values['dosage'].toString(),
            frequency: values['frequency'].toString(),
            duration: values['duration'].toString(),
            instructions: values['instructions']?.toString(),
          );
    }, 'Prescription saved and the patient was notified.');
  }

  Future<void> _requestLaboratoryTest(JsonMap patient) async {
    final values = await _laboratoryRequestDialog(
      context,
      patient,
      _consultations,
    );
    if (values == null) return;
    final hospitalId =
        patient['primary_hospital_id']?.toString() ?? widget.profile.hospitalId;
    if (hospitalId == null) {
      _showError('This patient does not have an assigned hospital.');
      return;
    }
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .saveLaboratoryRequest(
            patientId: patient['id'].toString(),
            hospitalId: hospitalId,
            testName: values['test_name'].toString(),
            consultationId: values['consultation_id']?.toString(),
            instructions: values['instructions']?.toString(),
            priority: values['priority'].toString(),
            dueAt: values['due_at'] as DateTime?,
          );
    }, 'Laboratory request created and the patient was notified.');
  }

  Future<void> _createDiagnosis(JsonMap patient) async {
    final values = await _diagnosisDialog(context, patient, _consultations);
    if (values == null) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .createDiagnosis(
            patientId: patient['id'].toString(),
            consultationId: values['consultation_id'].toString(),
            diagnosis: values['diagnosis'].toString(),
            diagnosisCode: values['diagnosis_code']?.toString(),
            isPrimary: values['is_primary'] == true,
          );
    }, 'Doctor-confirmed diagnosis saved.');
  }

  Future<void> _createTreatmentPlan(JsonMap patient) async {
    final values = await _treatmentPlanDialog(context, patient, _consultations);
    if (values == null) return;
    await _saveTreatmentPlanValues(patient, values);
  }

  Future<void> _editTreatmentPlan(JsonMap plan) async {
    final matches = _patients
        .where(
          (item) => item['id']?.toString() == plan['patient_id']?.toString(),
        )
        .toList(growable: false);
    final patient = matches.isEmpty ? null : matches.first;
    if (patient == null) {
      _showError('The patient record for this treatment plan is unavailable.');
      return;
    }
    final values = await _treatmentPlanDialog(
      context,
      patient,
      _consultations,
      initial: plan,
    );
    if (values == null) return;
    await _saveTreatmentPlanValues(patient, values, id: plan['id'].toString());
  }

  Future<void> _saveTreatmentPlanValues(
    JsonMap patient,
    JsonMap values, {
    String? id,
  }) async {
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .saveTreatmentPlan(
            id: id,
            patientId: patient['id'].toString(),
            consultationId: values['consultation_id'].toString(),
            plan: values['plan'].toString(),
            status: values['status'].toString(),
            startsOn: values['starts_on'] as DateTime?,
            endsOn: values['ends_on'] as DateTime?,
          );
    }, id == null ? 'Treatment plan created.' : 'Treatment plan updated.');
  }

  Future<void> _deleteTreatmentPlan(JsonMap plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete treatment plan?'),
        content: const Text(
          'This removes the plan from the clinical workspace. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete plan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .deleteTreatmentPlan(plan['id'].toString());
    }, 'Treatment plan deleted.');
  }

  Future<void> _uploadMedicalDocument(JsonMap patient) async {
    final hospitalId =
        patient['primary_hospital_id']?.toString() ?? widget.profile.hospitalId;
    if (hospitalId == null) {
      _showError('This patient does not have an assigned hospital.');
      return;
    }
    final values = await _clinicalDocumentDialog(
      context,
      patient,
      _consultations,
    );
    if (values == null) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .uploadMedicalDocument(
            patientId: patient['id'].toString(),
            hospitalId: hospitalId,
            documentType: values['document_type'].toString(),
            title: values['title'].toString(),
            bytes: values['bytes'] as Uint8List,
            fileName: values['file_name'].toString(),
            mimeType: values['mime_type'].toString(),
            consultationId: values['consultation_id']?.toString(),
          );
    }, 'Medical document uploaded securely.');
  }

  Future<void> _uploadConsultationAttachment(JsonMap patient) async {
    final values = await _consultationAttachmentDialog(
      context,
      patient,
      _consultations,
    );
    if (values == null) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .uploadConsultationAttachment(
            patientId: patient['id'].toString(),
            consultationId: values['consultation_id'].toString(),
            bytes: values['bytes'] as Uint8List,
            fileName: values['file_name'].toString(),
            mimeType: values['mime_type'].toString(),
          );
    }, 'Consultation attachment uploaded securely.');
  }

  Future<void> _uploadOwnConsultationAttachment(JsonMap consultation) async {
    final values = await _patientAttachmentDialog(context, consultation);
    if (values == null) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .uploadPatientConsultationAttachment(
            consultationId: consultation['id'].toString(),
            bytes: values['bytes'] as Uint8List,
            fileName: values['file_name'].toString(),
            mimeType: values['mime_type'].toString(),
          );
    }, 'Attachment uploaded securely for this consultation.');
  }

  Future<void> _uploadResult(JsonMap patient) async {
    final hospitalId =
        patient['primary_hospital_id']?.toString() ?? widget.profile.hospitalId;
    if (hospitalId == null) {
      _showError('This patient does not have an assigned hospital.');
      return;
    }
    final values = await _resultUploadDialog(context, patient, _consultations);
    if (values == null) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .uploadMedicalResult(
            patientId: patient['id'].toString(),
            hospitalId: hospitalId,
            testName: values['test_name'].toString(),
            bytes: values['bytes'] as Uint8List,
            fileName: values['file_name'].toString(),
            mimeType: values['mime_type'].toString(),
            consultationId: values['consultation_id']?.toString(),
            extractedText: values['extracted_text']?.toString(),
          );
    }, 'Medical result uploaded for analysis.');
  }

  Future<void> _analyzeResult(JsonMap result) => _run(() async {
    await ref
        .read(careRepositoryProvider)
        .analyzeMedicalResult(result['id'].toString());
  }, 'Preliminary AI analysis completed. A doctor must still confirm it.');

  Future<void> _confirmResult(JsonMap result) async {
    final values = await _confirmResultDialog(context, result);
    if (values == null) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .confirmMedicalResult(
            resultId: result['id'].toString(),
            confirmedFindings: values['confirmed_findings'].toString(),
            professionalInterpretation: values['professional_interpretation']
                ?.toString(),
            saveToRecord: values['save_to_record'] == true,
          );
    }, 'Result confirmed and patient notified.');
  }

  Future<void> _rejectResult(JsonMap result) async {
    final reason = await _textDialog(
      context,
      title: 'Reject AI findings',
      label: 'Professional reason *',
      initial: result['professional_interpretation']?.toString(),
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _run(() async {
      await ref
          .read(supabaseClientProvider)
          .from('laboratory_results')
          .update({
            'verification_status': 'rejected',
            'professional_interpretation': reason.trim(),
          })
          .eq('id', result['id']);
    }, 'AI findings rejected. No official medical record was created.');
  }

  Future<void> _openResultFile(JsonMap result) async {
    try {
      final url = await ref
          .read(careRepositoryProvider)
          .createAuditedSignedMedicalUrl(
            resourceType: 'laboratory_result',
            resourceId: result['id'].toString(),
            action: 'view',
            bucket: 'laboratory-results',
            path: result['file_path'].toString(),
          );
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('Could not open the medical document.');
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openMedicalDocument(JsonMap document) => _openSecureDocument(
    resourceType: 'medical_document',
    resourceId: document['id']?.toString() ?? '',
    bucket: document['storage_bucket']?.toString() ?? 'medical-documents',
    path: document['storage_path']?.toString() ?? '',
  );

  Future<void> _openConsultationAttachment(JsonMap attachment) =>
      _openSecureDocument(
        resourceType: 'consultation_attachment',
        resourceId: attachment['id']?.toString() ?? '',
        bucket: 'consultation-attachments',
        path: attachment['storage_path']?.toString() ?? '',
      );

  Future<void> _openSecureDocument({
    required String resourceType,
    required String resourceId,
    required String bucket,
    required String path,
  }) async {
    if (path.isEmpty) {
      _showError('The document path is missing.');
      return;
    }
    try {
      final url = await ref
          .read(careRepositoryProvider)
          .createAuditedSignedMedicalUrl(
            resourceType: resourceType,
            resourceId: resourceId,
            action: 'view',
            bucket: bucket,
            path: path,
          );
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('Could not open the secure document.');
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _updatePatientConsent(JsonMap definition, bool isGranted) async {
    final confirmed = await _consentDecisionDialog(
      context,
      definition,
      isGranted,
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref
          .read(careRepositoryProvider)
          .savePatientConsent(
            consentType: definition['type'].toString(),
            consentVersion: definition['version'].toString(),
            isGranted: isGranted,
            policyTitle: definition['title'].toString(),
          );
    }, isGranted ? 'Consent granted.' : 'Consent revoked.');
  }
}

class _WorkspaceNavigation extends StatelessWidget {
  const _WorkspaceNavigation({
    required this.profile,
    required this.tabs,
    required this.selected,
    required this.consultationCount,
    required this.attentionCount,
    required this.onSelected,
  });

  final UserProfile profile;
  final List<_WorkspaceTab> tabs;
  final int selected;
  final int consultationCount;
  final int attentionCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.evergreenDark,
      borderRadius: BorderRadius.circular(AppRadius.extraLarge),
      boxShadow: AppShadows.medium,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppStatusBadge(
          label: 'LIVE CARE WORKSPACE',
          color: AppColors.mint,
          icon: AppIcons.lockRounded,
          inverse: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          profile.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          profile.roleLabel,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.mist),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _WorkspaceNavMetric(
                value: '$consultationCount',
                label: 'consults',
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _WorkspaceNavMetric(
                value: '$attentionCount',
                label: 'attention',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'CARE AREAS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.mist,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: tabs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xxs),
            itemBuilder: (context, index) {
              final active = selected == index;
              return Material(
                color: active ? AppColors.forest : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: InkWell(
                  onTap: () => onSelected(index),
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        IconTheme(
                          data: IconThemeData(
                            color: active ? Colors.white : AppColors.mint,
                            size: 20,
                          ),
                          child:
                              tabs[index].tab.icon ??
                              const Icon(AppIcons.circleOutlined),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            tabs[index].tab.text ?? 'Section',
                            style: TextStyle(
                              color: active ? Colors.white : AppColors.mist,
                              fontWeight: active
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _WorkspaceNavMetric extends StatelessWidget {
  const _WorkspaceNavMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(AppRadius.medium),
      border: Border.all(color: Colors.white.withValues(alpha: .1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(color: Colors.white),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.mist),
        ),
      ],
    ),
  );
}

class _WorkspaceMobilePulse extends StatelessWidget {
  const _WorkspaceMobilePulse({
    required this.role,
    required this.consultationCount,
    required this.attentionCount,
  });

  final String role;
  final int consultationCount;
  final int attentionCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.evergreenDark,
      borderRadius: BorderRadius.circular(AppRadius.extraLarge),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LIVE $role DESK'.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.mint,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Care at a glance',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
        _WorkspaceNavMetric(value: '$consultationCount', label: 'consults'),
        const SizedBox(width: AppSpacing.xs),
        _WorkspaceNavMetric(value: '$attentionCount', label: 'review'),
      ],
    ),
  );
}

class _WorkspaceSection extends StatelessWidget {
  const _WorkspaceSection({required this.tab, this.compact = false});
  final _WorkspaceTab tab;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(AppRadius.extraLarge),
      border: Border.all(color: AppColors.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 18 : 24,
            compact ? 16 : 22,
            compact ? 18 : 24,
            compact ? 12 : 18,
          ),
          child: Row(
            children: [
              AppIconTile(
                icon:
                    (tab.tab.icon as Icon?)?.icon ??
                    AppIcons.healthAndSafetyOutlined,
                color: AppColors.forest,
                size: compact ? 40 : 44,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tab.tab.text ?? 'Care section',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    const Text('Secure, role-scoped records and actions'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: tab.body),
      ],
    ),
  );
}

class _WorkspaceTab {
  const _WorkspaceTab(this.tab, this.body);
  final Tab tab;
  final Widget body;
}

class _ConsultationsPanel extends StatelessWidget {
  const _ConsultationsPanel({
    required this.items,
    required this.role,
    required this.busy,
    required this.onBook,
    required this.onTransition,
    required this.onChat,
    required this.onJoin,
    this.onPatientAttachment,
  });

  final List<JsonMap> items;
  final String role;
  final bool busy;
  final VoidCallback? onBook;
  final void Function(JsonMap, String) onTransition;
  final ValueChanged<JsonMap> onChat;
  final ValueChanged<JsonMap> onJoin;
  final ValueChanged<JsonMap>? onPatientAttachment;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      if (onBook != null)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : onBook,
            icon: const Icon(AppIcons.addRounded),
            label: const Text('Book consultation'),
          ),
        ),
      if (onBook != null) const SizedBox(height: 14),
      if (items.isEmpty)
        const _EmptyCard(
          icon: AppIcons.calendarMonthOutlined,
          message: 'No consultations are available for this account.',
        )
      else
        for (final item in items)
          _ConsultationCard(
            item: item,
            role: role,
            busy: busy,
            onTransition: onTransition,
            onChat: onChat,
            onJoin: onJoin,
            onPatientAttachment: onPatientAttachment,
          ),
    ],
  );
}

class _ConsultationCard extends StatelessWidget {
  const _ConsultationCard({
    required this.item,
    required this.role,
    required this.busy,
    required this.onTransition,
    required this.onChat,
    required this.onJoin,
    this.onPatientAttachment,
  });
  final JsonMap item;
  final String role;
  final bool busy;
  final void Function(JsonMap, String) onTransition;
  final ValueChanged<JsonMap> onChat;
  final ValueChanged<JsonMap> onJoin;
  final ValueChanged<JsonMap>? onPatientAttachment;

  @override
  Widget build(BuildContext context) {
    final status = item['status']?.toString() ?? 'pending';
    final doctor = _relation(item['doctors'], 'display_name');
    final hospital = _relation(item['hospitals'], 'hospital_name');
    final patient = _person(item['patients']);
    final guest = _relation(item['guest_consultation_requests'], 'full_name');
    final canCommunicate = {
      'approved',
      'scheduled',
      'in_progress',
      'completed',
    }.contains(status);
    final transitions = _transitions(role, status);
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    role == 'doctor' || role == 'hospital_admin'
                        ? (patient.isNotEmpty ? patient : guest)
                        : (doctor.isNotEmpty ? doctor : 'Assigned doctor'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$hospital · ${_label(item['consultation_type']?.toString() ?? '')}',
            ),
            Text(_dateTime(item['appointment_date'])),
            const SizedBox(height: 8),
            Text(item['chief_complaint']?.toString() ?? ''),
            if ((item['confirmed_diagnosis']?.toString() ?? '').isNotEmpty) ...[
              const Divider(height: 22),
              Text(
                'Doctor-confirmed diagnosis',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(item['confirmed_diagnosis'].toString()),
            ],
            if ((item['treatment_plan']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                'Treatment plan',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(item['treatment_plan'].toString()),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canCommunicate)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => onChat(item),
                    icon: const Icon(AppIcons.chatBubbleOutlineRounded),
                    label: const Text('Message'),
                  ),
                if (canCommunicate &&
                    (item['meeting_link']?.toString() ?? '').isNotEmpty)
                  FilledButton.icon(
                    onPressed: busy ? null : () => onJoin(item),
                    icon: const Icon(AppIcons.videoCallRounded),
                    label: const Text('Join video'),
                  ),
                if (role == 'patient' &&
                    {'approved', 'scheduled', 'in_progress'}.contains(status) &&
                    onPatientAttachment != null)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => onPatientAttachment!(item),
                    icon: const Icon(AppIcons.attachFileRounded),
                    label: const Text('Add attachment'),
                  ),
                for (final transition in transitions)
                  _transitionButton(
                    transition,
                    busy ? null : () => onTransition(item, transition),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestRequestsPanel extends StatelessWidget {
  const _GuestRequestsPanel({
    required this.items,
    required this.busy,
    this.onReview,
    this.onConvert,
  });
  final List<JsonMap> items;
  final bool busy;
  final void Function(JsonMap, String)? onReview;
  final ValueChanged<JsonMap>? onConvert;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const _EmptyCard(
          icon: AppIcons.inboxOutlined,
          message: 'No guest consultation requests are available.',
        )
      : ListView.builder(
          padding: const EdgeInsets.all(22),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final status = item['request_status']?.toString() ?? 'otp_verified';
            return Card(
              margin: const EdgeInsets.only(bottom: 11),
              child: ExpansionTile(
                leading: const CircleAvatar(
                  child: Icon(AppIcons.personSearchRounded),
                ),
                title: Text(item['full_name']?.toString() ?? 'Guest'),
                subtitle: Text(
                  '${item['reference_number'] ?? ''} · ${_label(status)}\n${item['symptoms'] ?? ''}',
                ),
                trailing: _StatusChip(status: status),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(17, 0, 17, 17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Detail(
                          'Consultation reason',
                          item['consultation_reason'],
                        ),
                        _Detail('Symptom duration', item['symptom_duration']),
                        _Detail(
                          'Preferred schedule',
                          _dateTime(item['preferred_schedule']),
                        ),
                        _Detail('Mobile', item['mobile_number']),
                        _Detail('Email', item['email']),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (onReview != null &&
                                {
                                  'otp_verified',
                                  'pending_doctor_review',
                                }.contains(status)) ...[
                              FilledButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => onReview!(item, 'approve'),
                                icon: const Icon(AppIcons.checkRounded),
                                label: const Text('Approve & schedule'),
                              ),
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => onReview!(item, 'reject'),
                                icon: const Icon(AppIcons.closeRounded),
                                label: const Text('Reject'),
                              ),
                            ],
                            if (onConvert != null &&
                                {
                                  'approved',
                                  'temporary_patient_created',
                                  'consultation_scheduled',
                                  'account_activation_pending',
                                }.contains(status))
                              OutlinedButton.icon(
                                onPressed: busy ? null : () => onConvert!(item),
                                icon: const Icon(AppIcons.personAddAlt1Rounded),
                                label: const Text('Create patient account'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
}

class _PatientsPanel extends StatelessWidget {
  const _PatientsPanel({
    required this.items,
    required this.busy,
    this.historyItems = const [],
    this.onCreatePatient,
    this.onRecord,
    this.onResult,
    this.onPrescription,
    this.onLaboratoryRequest,
    this.onDiagnosis,
    this.onTreatmentPlan,
    this.onMedicalDocument,
    this.onConsultationAttachment,
  });
  final List<JsonMap> items;
  final List<JsonMap> historyItems;
  final bool busy;
  final VoidCallback? onCreatePatient;
  final ValueChanged<JsonMap>? onRecord;
  final ValueChanged<JsonMap>? onResult;
  final ValueChanged<JsonMap>? onPrescription;
  final ValueChanged<JsonMap>? onLaboratoryRequest;
  final ValueChanged<JsonMap>? onDiagnosis;
  final ValueChanged<JsonMap>? onTreatmentPlan;
  final ValueChanged<JsonMap>? onMedicalDocument;
  final ValueChanged<JsonMap>? onConsultationAttachment;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      if (onCreatePatient != null)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : onCreatePatient,
            icon: const Icon(AppIcons.personAddAlt1Rounded),
            label: const Text('Create patient'),
          ),
        ),
      if (onCreatePatient != null) const SizedBox(height: 14),
      if (items.isEmpty)
        const _EmptyCard(
          icon: AppIcons.groupsOutlined,
          message: 'No assigned patients are available.',
        )
      else
        for (final item in items)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              leading: const CircleAvatar(child: Icon(AppIcons.personRounded)),
              title: Text(_person(item['users'])),
              subtitle: Text(
                '${item['patient_number'] ?? 'Temporary patient'} · ${_label(item['account_activation_status']?.toString() ?? '')}',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Detail(
                        'Hospital',
                        _relation(item['hospitals'], 'hospital_name'),
                      ),
                      _Detail('Blood type', item['blood_type']),
                      _Detail(
                        'Conditions',
                        _listText(item['existing_conditions']),
                      ),
                      _Detail('Allergies', _listText(item['allergies'])),
                      _PatientCareHistory(
                        items: historyItems
                            .where(
                              (record) =>
                                  record['patient_id']?.toString() ==
                                  item['id']?.toString(),
                            )
                            .toList(growable: false),
                      ),
                      if (onRecord != null ||
                          onResult != null ||
                          onPrescription != null ||
                          onLaboratoryRequest != null ||
                          onDiagnosis != null ||
                          onTreatmentPlan != null ||
                          onMedicalDocument != null ||
                          onConsultationAttachment != null) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (onRecord != null)
                              OutlinedButton.icon(
                                onPressed: busy ? null : () => onRecord!(item),
                                icon: const Icon(AppIcons.noteAddOutlined),
                                label: const Text('Add record'),
                              ),
                            if (onResult != null)
                              OutlinedButton.icon(
                                onPressed: busy ? null : () => onResult!(item),
                                icon: const Icon(AppIcons.uploadFileRounded),
                                label: const Text('Upload result'),
                              ),
                            if (onPrescription != null)
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => onPrescription!(item),
                                icon: const Icon(AppIcons.medicationOutlined),
                                label: const Text('Prescription'),
                              ),
                            if (onLaboratoryRequest != null)
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => onLaboratoryRequest!(item),
                                icon: const Icon(AppIcons.scienceOutlined),
                                label: const Text('Request laboratory test'),
                              ),
                            if (onDiagnosis != null)
                              FilledButton.tonalIcon(
                                onPressed: busy
                                    ? null
                                    : () => onDiagnosis!(item),
                                icon: const Icon(AppIcons.verifiedOutlined),
                                label: const Text('Confirm diagnosis'),
                              ),
                            if (onTreatmentPlan != null)
                              FilledButton.tonalIcon(
                                onPressed: busy
                                    ? null
                                    : () => onTreatmentPlan!(item),
                                icon: const Icon(
                                  AppIcons.assignmentTurnedInOutlined,
                                ),
                                label: const Text('Treatment plan'),
                              ),
                            if (onMedicalDocument != null)
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => onMedicalDocument!(item),
                                icon: const Icon(AppIcons.fileUploadOutlined),
                                label: const Text('Medical document'),
                              ),
                            if (onConsultationAttachment != null)
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => onConsultationAttachment!(item),
                                icon: const Icon(AppIcons.attachFileRounded),
                                label: const Text('Consultation attachment'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
    ],
  );
}

class _PatientCareHistory extends StatelessWidget {
  const _PatientCareHistory({required this.items});

  final List<JsonMap> items;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8FC),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE5EF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(AppIcons.historyRounded, size: 20, color: AppColors.blue),
            SizedBox(width: 8),
            Text(
              'Care history across hospitals',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          items.isEmpty
              ? 'No doctor-confirmed history has been shared yet.'
              : 'Doctor-confirmed records shared with the assigned care team.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const Divider(height: 18),
            _PatientHistoryEntry(item: items[index]),
          ],
        ],
      ],
    ),
  );
}

class _PatientHistoryEntry extends StatelessWidget {
  const _PatientHistoryEntry({required this.item});

  final JsonMap item;

  @override
  Widget build(BuildContext context) {
    final hospital = _relation(item['hospitals'], 'hospital_name');
    final doctor = _relation(item['doctors'], 'display_name');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(AppIcons.localHospitalOutlined, size: 18),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['title']?.toString() ?? 'Medical record',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                [
                  _recordDate(item['record_date']),
                  if (hospital.isNotEmpty) hospital,
                ].join(' · '),
              ),
              if (doctor.isNotEmpty)
                Text(
                  'Attending physician: $doctor',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if ((item['confirmed_diagnosis']?.toString() ?? '').isNotEmpty)
                Text(
                  'Diagnosis: ${item['confirmed_diagnosis']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if ((item['treatment_plan']?.toString() ?? '').isNotEmpty)
                Text(
                  'Plan: ${item['treatment_plan']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({
    required this.items,
    required this.isDoctor,
    required this.busy,
    required this.onOpenFile,
    this.onAnalyze,
    this.onConfirm,
    this.onReject,
  });
  final List<JsonMap> items;
  final bool isDoctor;
  final bool busy;
  final ValueChanged<JsonMap> onOpenFile;
  final ValueChanged<JsonMap>? onAnalyze;
  final ValueChanged<JsonMap>? onConfirm;
  final ValueChanged<JsonMap>? onReject;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const _EmptyCard(
          icon: AppIcons.scienceOutlined,
          message: 'No laboratory or scanned results are available.',
        )
      : ListView.builder(
          padding: const EdgeInsets.all(22),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final status =
                item['verification_status']?.toString() ?? 'uploaded';
            final canAnalyze = {
              'uploaded',
              'ai_analysis_pending',
            }.contains(status);
            final canReview = {
              'pending_doctor_review',
              'doctor_modified',
            }.contains(status);
            return Card(
              margin: const EdgeInsets.only(bottom: 11),
              child: ExpansionTile(
                leading: const CircleAvatar(
                  child: Icon(AppIcons.biotechOutlined),
                ),
                title: Text(item['test_name']?.toString() ?? 'Medical result'),
                subtitle: Text(
                  '${_dateTime(item['uploaded_at'])} · ${_relation(item['doctors'], 'display_name')}',
                ),
                trailing: _StatusChip(status: status),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(17, 0, 17, 17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Detail('Extracted text', item['extracted_text']),
                        _Detail('Preliminary AI summary', item['ai_summary']),
                        _Detail(
                          'Possible AI findings',
                          _jsonText(item['ai_possible_findings']),
                        ),
                        _Detail(
                          'Doctor-confirmed findings',
                          item['doctor_confirmed_findings'],
                        ),
                        _Detail(
                          'Professional interpretation',
                          item['professional_interpretation'],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: busy ? null : () => onOpenFile(item),
                              icon: const Icon(AppIcons.openInNewRounded),
                              label: const Text('Open document'),
                            ),
                            if (isDoctor && canAnalyze && onAnalyze != null)
                              FilledButton.icon(
                                onPressed: busy ? null : () => onAnalyze!(item),
                                icon: const Icon(AppIcons.symptomCheck),
                                label: const Text(
                                  'Run preliminary AI analysis',
                                ),
                              ),
                            if (isDoctor && canReview && onConfirm != null)
                              FilledButton.icon(
                                onPressed: busy ? null : () => onConfirm!(item),
                                icon: const Icon(AppIcons.verifiedRounded),
                                label: const Text('Confirm findings'),
                              ),
                            if (isDoctor && canReview && onReject != null)
                              OutlinedButton.icon(
                                onPressed: busy ? null : () => onReject!(item),
                                icon: const Icon(AppIcons.blockRounded),
                                label: const Text('Reject AI findings'),
                              ),
                          ],
                        ),
                        if (!isDoctor &&
                            !{
                              'doctor_confirmed',
                              'doctor_modified',
                              'saved_to_patient_record',
                            }.contains(status)) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'This result is preliminary and is waiting for licensed-doctor review.',
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
}

class _RecordsPanel extends StatelessWidget {
  const _RecordsPanel({required this.items, this.canEdit = false, this.onEdit});
  final List<JsonMap> items;
  final bool canEdit;
  final ValueChanged<JsonMap>? onEdit;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const _EmptyCard(
          icon: AppIcons.folderSharedOutlined,
          message: 'No doctor-confirmed medical records are available.',
        )
      : ListView.builder(
          padding: const EdgeInsets.all(22),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(AppIcons.descriptionOutlined),
                ),
                title: Text(item['title']?.toString() ?? 'Medical record'),
                subtitle: Text(
                  '${_label(item['record_type']?.toString() ?? '')} · ${item['record_date'] ?? ''}\n'
                  '${item['confirmed_diagnosis'] ?? item['description'] ?? ''}',
                ),
                isThreeLine: true,
                trailing: canEdit && onEdit != null
                    ? IconButton(
                        tooltip: 'Edit medical record',
                        onPressed: () => onEdit!(item),
                        icon: const Icon(AppIcons.editRounded),
                      )
                    : null,
              ),
            );
          },
        );
}

class _ClinicalRecordsPanel extends StatelessWidget {
  const _ClinicalRecordsPanel({
    required this.diagnoses,
    required this.treatmentPlans,
    required this.laboratoryRequests,
    required this.medicalDocuments,
    required this.consultationAttachments,
    required this.canManage,
    required this.busy,
    required this.onOpenMedicalDocument,
    required this.onOpenAttachment,
    this.onEditTreatmentPlan,
    this.onDeleteTreatmentPlan,
  });

  final List<JsonMap> diagnoses;
  final List<JsonMap> treatmentPlans;
  final List<JsonMap> laboratoryRequests;
  final List<JsonMap> medicalDocuments;
  final List<JsonMap> consultationAttachments;
  final bool canManage;
  final bool busy;
  final ValueChanged<JsonMap> onOpenMedicalDocument;
  final ValueChanged<JsonMap> onOpenAttachment;
  final ValueChanged<JsonMap>? onEditTreatmentPlan;
  final ValueChanged<JsonMap>? onDeleteTreatmentPlan;

  bool get _isEmpty =>
      diagnoses.isEmpty &&
      treatmentPlans.isEmpty &&
      laboratoryRequests.isEmpty &&
      medicalDocuments.isEmpty &&
      consultationAttachments.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isEmpty) {
      return const _EmptyCard(
        icon: AppIcons.healthAndSafetyOutlined,
        message: 'No RLS-authorized clinical records are available.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Card(
          color: Color(0xFFEAF7F4),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Diagnoses and treatment plans shown here are entered and confirmed by the assigned licensed doctor. Files use short-lived signed links.',
            ),
          ),
        ),
        const SizedBox(height: 10),
        _clinicalSection(
          context,
          title: 'Doctor-confirmed diagnoses',
          icon: AppIcons.verifiedOutlined,
          emptyMessage: 'No confirmed diagnoses.',
          children: diagnoses
              .map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['diagnosis']?.toString() ?? 'Diagnosis'),
                  subtitle: Text(
                    '${item['is_primary'] == true ? 'Primary diagnosis · ' : ''}'
                    '${item['diagnosis_code'] ?? 'No diagnosis code'}\n'
                    'Confirmed ${_dateTime(item['confirmed_at'])} by '
                    '${_relation(item['doctors'], 'display_name')}',
                  ),
                  isThreeLine: true,
                ),
              )
              .toList(growable: false),
        ),
        _clinicalSection(
          context,
          title: 'Treatment plans',
          icon: AppIcons.assignmentTurnedInOutlined,
          emptyMessage: 'No treatment plans.',
          children: treatmentPlans
              .map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['plan']?.toString() ?? 'Treatment plan'),
                  subtitle: Text(
                    '${_label(item['status']?.toString() ?? 'active')} · '
                    '${_dateRange(item['starts_on'], item['ends_on'])}\n'
                    'Confirmed by ${_relation(item['doctors'], 'display_name')}',
                  ),
                  isThreeLine: true,
                  trailing: canManage
                      ? PopupMenuButton<String>(
                          tooltip: 'Manage treatment plan',
                          enabled: !busy,
                          onSelected: (value) {
                            if (value == 'edit') {
                              onEditTreatmentPlan?.call(item);
                            }
                            if (value == 'delete') {
                              onDeleteTreatmentPlan?.call(item);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        )
                      : null,
                ),
              )
              .toList(growable: false),
        ),
        _clinicalSection(
          context,
          title: 'Laboratory requests',
          icon: AppIcons.scienceOutlined,
          emptyMessage: 'No laboratory requests.',
          children: laboratoryRequests
              .map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item['test_name']?.toString() ?? 'Laboratory test',
                  ),
                  subtitle: Text(
                    '${_label(item['priority']?.toString() ?? 'routine')} priority · '
                    '${_label(item['status']?.toString() ?? 'requested')}\n'
                    '${item['instructions'] ?? ''}',
                  ),
                  trailing: _StatusChip(
                    status: item['status']?.toString() ?? 'requested',
                  ),
                ),
              )
              .toList(growable: false),
        ),
        _clinicalSection(
          context,
          title: 'Medical documents',
          icon: AppIcons.folderCopyOutlined,
          emptyMessage: 'No medical documents.',
          children: medicalDocuments
              .map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['title']?.toString() ?? 'Medical document'),
                  subtitle: Text(
                    '${_label(item['document_type']?.toString() ?? 'document')} · '
                    '${_fileSize(item['size_bytes'])} · ${_dateTime(item['created_at'])}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Open secure medical document',
                    onPressed: busy ? null : () => onOpenMedicalDocument(item),
                    icon: const Icon(AppIcons.openInNewRounded),
                  ),
                ),
              )
              .toList(growable: false),
        ),
        _clinicalSection(
          context,
          title: 'Consultation attachments',
          icon: AppIcons.attachFileRounded,
          emptyMessage: 'No consultation attachments.',
          children: consultationAttachments
              .map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item['file_name']?.toString() ?? 'Consultation attachment',
                  ),
                  subtitle: Text(
                    '${_fileSize(item['size_bytes'])} · ${_dateTime(item['created_at'])}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Open secure consultation attachment',
                    onPressed: busy ? null : () => onOpenAttachment(item),
                    icon: const Icon(AppIcons.openInNewRounded),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _clinicalSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String emptyMessage,
    required List<Widget> children,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ExpansionTile(
      initiallyExpanded: true,
      leading: Icon(icon),
      title: Text('$title (${children.length})'),
      childrenPadding: const EdgeInsets.fromLTRB(17, 0, 17, 12),
      children: children.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(emptyMessage),
                ),
              ),
            ]
          : children,
    ),
  );
}

class _PatientConsentsPanel extends StatelessWidget {
  const _PatientConsentsPanel({
    required this.items,
    required this.busy,
    required this.onDecision,
  });

  final List<JsonMap> items;
  final bool busy;
  final void Function(JsonMap definition, bool isGranted) onDecision;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const Card(
        color: Color(0xFFE8F1FD),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'You control these consent decisions. Each decision is stored with the displayed policy version, timestamp, and authenticated capture identity.',
          ),
        ),
      ),
      const SizedBox(height: 10),
      for (final definition in _standardPatientConsents)
        _consentCard(context, definition),
      if (items.isNotEmpty)
        Card(
          child: ExpansionTile(
            leading: const Icon(AppIcons.historyRounded),
            title: const Text('Consent decision history'),
            children: items
                .map(
                  (item) => ListTile(
                    title: Text(_label(item['consent_type']?.toString() ?? '')),
                    subtitle: Text(
                      'Version ${item['consent_version'] ?? ''} · '
                      '${item['is_granted'] == true ? 'Granted' : 'Revoked'} · '
                      '${_dateTime(item['updated_at'])}',
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
    ],
  );

  Widget _consentCard(BuildContext context, JsonMap definition) {
    final matching = items.where(
      (item) =>
          item['consent_type']?.toString() == definition['type'] &&
          item['consent_version']?.toString() == definition['version'],
    );
    final record = matching.isEmpty ? null : matching.first;
    final granted = record?['is_granted'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    definition['title'].toString(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(
                  status: record == null
                      ? 'not_recorded'
                      : granted
                      ? 'granted'
                      : 'revoked',
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(definition['description'].toString()),
            const SizedBox(height: 7),
            Text(
              'Policy version ${definition['version']} · '
              '${record == null ? 'No decision recorded' : 'Updated ${_dateTime(record['updated_at'])}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: busy || granted
                      ? null
                      : () => onDecision(definition, true),
                  icon: const Icon(AppIcons.checkCircleOutlineRounded),
                  label: Text(record == null ? 'Review & grant' : 'Grant'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || !granted
                      ? null
                      : () => onDecision(definition, false),
                  icon: const Icon(AppIcons.blockOutlined),
                  label: const Text('Review & revoke'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrescriptionsPanel extends StatelessWidget {
  const _PrescriptionsPanel({required this.items});
  final List<JsonMap> items;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const _EmptyCard(
          icon: AppIcons.medicationOutlined,
          message: 'No prescriptions are available.',
        )
      : ListView.builder(
          padding: const EdgeInsets.all(22),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(AppIcons.medicationRounded),
                ),
                title: Text(
                  item['medication_name']?.toString() ?? 'Medication',
                ),
                subtitle: Text(
                  '${item['dosage'] ?? ''} · ${item['frequency'] ?? ''} · ${item['duration'] ?? ''}\n'
                  '${item['instructions'] ?? ''}\nPrescribed by ${_relation(item['doctors'], 'display_name')}',
                ),
                isThreeLine: true,
              ),
            );
          },
        );
}

class _ConversationsPanel extends StatelessWidget {
  const _ConversationsPanel({required this.items, required this.onOpen});
  final List<JsonMap> items;
  final ValueChanged<JsonMap> onOpen;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const _EmptyCard(
          icon: AppIcons.forumOutlined,
          message:
              'No active care conversations. A conversation becomes available after consultation approval.',
        )
      : ListView.builder(
          padding: const EdgeInsets.all(22),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final other = _relation(item['doctors'], 'display_name').isNotEmpty
                ? _relation(item['doctors'], 'display_name')
                : _person(item['patients']);
            return Card(
              margin: const EdgeInsets.only(bottom: 9),
              child: ListTile(
                onTap: () => onOpen(item),
                leading: const CircleAvatar(
                  child: Icon(AppIcons.chatBubbleOutlineRounded),
                ),
                title: Text(other.isEmpty ? 'Care conversation' : other),
                subtitle: Text(
                  '${_label(item['status']?.toString() ?? '')} · Updated ${_dateTime(item['updated_at'])}',
                ),
                trailing: const Icon(AppIcons.chevronRightRounded),
              ),
            );
          },
        );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          SelectableText(text),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' ||
      'scheduled' ||
      'doctor_confirmed' ||
      'saved_to_patient_record' ||
      'completed' ||
      'granted' => AppColors.teal,
      'rejected' || 'cancelled' || 'emergency' || 'revoked' => AppColors.danger,
      'in_progress' ||
      'pending_doctor_review' ||
      'pending' => const Color(0xFFD05A29),
      _ => AppColors.blue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: AppStatePanel(
      compact: true,
      icon: icon,
      title: 'Nothing to show yet',
      message: message,
    ),
  );
}

class _BookingSlotState extends StatelessWidget {
  const _BookingSlotState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8FB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFDCE5ED)),
    ),
    child: Column(
      children: [
        Icon(icon, color: const Color(0xFF607D94)),
        const SizedBox(height: 7),
        Text(message, textAlign: TextAlign.center),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(AppIcons.refreshRounded),
            label: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}

class _SignInRequired extends StatelessWidget {
  const _SignInRequired({
    this.onSignIn,
    this.message = 'Sign in to open your care workspace.',
    this.actionLabel = 'Sign in',
  });
  final VoidCallback? onSignIn;
  final String message;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => AppStatePanel(
    kind: AppStateKind.restricted,
    icon: AppIcons.lockOutlineRounded,
    title: 'Care workspace unavailable',
    message: message,
    action: onSignIn == null
        ? null
        : FilledButton(onPressed: onSignIn, child: Text(actionLabel)),
  );
}

Future<JsonMap?> _bookDialog(
  BuildContext context,
  List<JsonMap> doctors, {
  required AvailableSlotLoader loadSlots,
}) async {
  String? doctorId;
  var type = 'online';
  var selectedDate = DateTime.now().add(const Duration(days: 1));
  List<JsonMap> slots = const [];
  String? selectedSlotStart;
  Object? slotError;
  var slotsLoading = false;
  final complaint = TextEditingController();
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> refreshSlots() async {
          final targetDoctorId = doctorId;
          if (targetDoctorId == null) {
            setDialogState(() {
              slots = const [];
              selectedSlotStart = null;
              slotError = null;
            });
            return;
          }
          setDialogState(() {
            slotsLoading = true;
            slots = const [];
            selectedSlotStart = null;
            slotError = null;
          });
          try {
            final value = await loadSlots(
              doctorId: targetDoctorId,
              date: selectedDate,
              consultationType: type,
            );
            if (!context.mounted) return;
            setDialogState(() {
              slots = value;
              slotsLoading = false;
            });
          } catch (error) {
            if (!context.mounted) return;
            setDialogState(() {
              slotError = error;
              slotsLoading = false;
            });
          }
        }

        final selectedDoctor = doctors
            .where((item) => item['id']?.toString() == doctorId)
            .firstOrNull;
        final selectedSlot = slots
            .where(
              (item) => item['slot_start']?.toString() == selectedSlotStart,
            )
            .firstOrNull;
        final appointment = DateTime.tryParse(
          selectedSlot?['slot_start']?.toString() ?? '',
        );

        return AlertDialog(
          title: const Text('Book a consultation'),
          content: SizedBox(
            width: 590,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: doctorId,
                    decoration: const InputDecoration(labelText: 'Doctor *'),
                    items: doctors
                        .map(
                          (doctor) => DropdownMenuItem(
                            value: doctor['id'].toString(),
                            child: Text(
                              '${doctor['display_name']} · ${doctor['specialization']}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: slotsLoading
                        ? null
                        : (value) async {
                            setDialogState(() {
                              doctorId = value;
                              slots = const [];
                              selectedSlotStart = null;
                              slotError = null;
                            });
                            await refreshSlots();
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Consultation type',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'online',
                        child: Text('Online video consultation'),
                      ),
                      DropdownMenuItem(
                        value: 'face_to_face',
                        child: Text('Face-to-face consultation'),
                      ),
                    ],
                    onChanged: slotsLoading
                        ? null
                        : (value) async {
                            setDialogState(() {
                              type = value ?? 'online';
                              slots = const [];
                              selectedSlotStart = null;
                              slotError = null;
                            });
                            await refreshSlots();
                          },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(AppIcons.eventRounded),
                    title: const Text('Appointment date'),
                    subtitle: Text(DateFormat.yMMMd().format(selectedDate)),
                    trailing: const Icon(AppIcons.editCalendarRounded),
                    enabled: !slotsLoading,
                    onTap: slotsLoading
                        ? null
                        : () async {
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(
                                DateTime.now().year,
                                DateTime.now().month,
                                DateTime.now().day,
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 180),
                              ),
                            );
                            if (selected == null || !context.mounted) return;
                            setDialogState(() {
                              selectedDate = selected;
                              slots = const [];
                              selectedSlotStart = null;
                              slotError = null;
                            });
                            await refreshSlots();
                          },
                  ),
                  const SizedBox(height: 8),
                  if (doctorId == null)
                    const _BookingSlotState(
                      icon: AppIcons.personSearchOutlined,
                      message: 'Choose a doctor to load available slots.',
                    )
                  else if (slotsLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text('Checking the doctor’s live schedule…'),
                        ],
                      ),
                    )
                  else if (slotError != null)
                    _BookingSlotState(
                      icon: AppIcons.errorOutlineRounded,
                      message:
                          'Available slots could not be loaded: $slotError',
                      actionLabel: 'Retry',
                      onAction: refreshSlots,
                    )
                  else if (slots.isEmpty)
                    _BookingSlotState(
                      icon: AppIcons.eventBusyOutlined,
                      message:
                          'No ${_label(type).toLowerCase()} slots are available on ${DateFormat.yMMMd().format(selectedDate)}.',
                      actionLabel: 'Check again',
                      onAction: refreshSlots,
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: selectedSlotStart,
                      decoration: const InputDecoration(
                        labelText: 'Available time slot *',
                        helperText:
                            'Times are from the doctor’s current live schedule.',
                      ),
                      items: slots
                          .map(
                            (slot) => DropdownMenuItem(
                              value: slot['slot_start'].toString(),
                              child: Text(_slotLabel(slot)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) =>
                          setDialogState(() => selectedSlotStart = value),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: complaint,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Consultation reason or chief complaint *',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: slotsLoading
                  ? null
                  : () {
                      if (selectedDoctor == null ||
                          appointment == null ||
                          complaint.text.trim().isEmpty ||
                          !appointment.isAfter(DateTime.now())) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Choose a future available slot and enter the consultation reason.',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        'doctor_id': doctorId,
                        'hospital_id': selectedDoctor['hospital_id'],
                        'consultation_type': type,
                        'appointment_date': appointment,
                        'chief_complaint': complaint.text.trim(),
                      });
                    },
              child: const Text('Submit request'),
            ),
          ],
        );
      },
    ),
  );
  complaint.dispose();
  return result;
}

Future<JsonMap?> _guestReviewDialog(
  BuildContext context,
  JsonMap request,
  String decision,
  List<JsonMap> doctors,
) async {
  String? doctorId = request['assigned_doctor_id']?.toString();
  var appointment =
      DateTime.tryParse(request['preferred_schedule']?.toString() ?? '') ??
      DateTime.now().add(const Duration(days: 1));
  final notes = TextEditingController();
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          decision == 'approve'
              ? 'Approve guest consultation'
              : 'Reject guest consultation',
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (decision == 'approve') ...[
                DropdownButtonFormField<String>(
                  initialValue: doctors.any((item) => item['id'] == doctorId)
                      ? doctorId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Assigned doctor *',
                  ),
                  items: doctors
                      .map(
                        (doctor) => DropdownMenuItem(
                          value: doctor['id'].toString(),
                          child: Text(
                            '${doctor['display_name']} · ${doctor['specialization']}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => doctorId = value),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AppIcons.eventRounded),
                  title: const Text('Scheduled appointment *'),
                  subtitle: Text(
                    DateFormat.yMMMd().add_jm().format(appointment),
                  ),
                  onTap: () async {
                    final value = await _pickDateTime(context, appointment);
                    if (value != null) {
                      setDialogState(() => appointment = value);
                    }
                  },
                ),
              ],
              TextField(
                controller: notes,
                minLines: 3,
                maxLines: 7,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: decision == 'approve'
                      ? 'Review notes'
                      : 'Rejection reason *',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if ((decision == 'approve' &&
                      (doctorId == null ||
                          !appointment.isAfter(DateTime.now()))) ||
                  (decision == 'reject' && notes.text.trim().isEmpty)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Complete all required review fields.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'doctor_id': doctorId,
                'appointment_date': decision == 'approve' ? appointment : null,
                'notes': notes.text.trim(),
              });
            },
            child: Text(
              decision == 'approve' ? 'Approve & schedule' : 'Reject request',
            ),
          ),
        ],
      ),
    ),
  );
  notes.dispose();
  return result;
}

Future<JsonMap?> _patientAccountDialog(
  BuildContext context,
  JsonMap request,
) async {
  final fullName =
      request['full_name']?.toString().trim().split(RegExp(r'\s+')) ??
      const <String>[];
  final first = TextEditingController(
    text: fullName.isEmpty ? '' : fullName.first,
  );
  final last = TextEditingController(
    text: fullName.length < 2 ? '' : fullName.sublist(1).join(' '),
  );
  final email = TextEditingController(text: request['email']?.toString() ?? '');
  final password = TextEditingController();
  var obscure = true;
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Create official patient account'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                decoration: const InputDecoration(labelText: 'First name *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: last,
                decoration: const InputDecoration(labelText: 'Last name *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Verified email *',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: password,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Temporary password *',
                  helperText:
                      'At least 12 characters. The patient must change it securely.',
                  suffixIcon: IconButton(
                    tooltip: obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setDialogState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? AppIcons.visibilityOutlined
                          : AppIcons.visibilityOffOutlined,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (first.text.trim().isEmpty ||
                  last.text.trim().isEmpty ||
                  !RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(email.text.trim()) ||
                  password.text.length < 12) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Enter complete names, a valid email, and a 12-character password.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'first_name': first.text.trim(),
                'last_name': last.text.trim(),
                'email': email.text.trim().toLowerCase(),
                'password': password.text,
              });
            },
            child: const Text('Create account'),
          ),
        ],
      ),
    ),
  );
  first.dispose();
  last.dispose();
  email.dispose();
  password.dispose();
  return result;
}

Future<JsonMap?> _directPatientAccountDialog(BuildContext context) async {
  final first = TextEditingController();
  final last = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final mobile = TextEditingController();
  final address = TextEditingController();
  DateTime? birthDate;
  String? sex;
  var obscure = true;
  final result = await showDialog<JsonMap>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Create patient account'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Card(
                  color: Color(0xFFFFF6DF),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'This creates an active official patient account and assigns it to you. Verify the identity and share the temporary password only through an approved secure channel.',
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: first,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'First name *',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: last,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'Last name *',
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: email,
                  maxLength: 320,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email *'),
                ),
                TextField(
                  controller: password,
                  obscureText: obscure,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: 'Strong temporary password *',
                    helperText:
                        '12+ characters with upper/lower case, number, and symbol.',
                    suffixIcon: IconButton(
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      onPressed: () => setDialogState(() => obscure = !obscure),
                      icon: Icon(
                        obscure
                            ? AppIcons.visibilityOutlined
                            : AppIcons.visibilityOffOutlined,
                      ),
                    ),
                  ),
                ),
                TextField(
                  controller: confirmPassword,
                  obscureText: obscure,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Confirm temporary password *',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(AppIcons.cakeOutlined),
                  title: const Text('Birth date (optional)'),
                  subtitle: Text(_dateOnlyLabel(birthDate)),
                  trailing: birthDate == null
                      ? const Icon(AppIcons.editCalendarOutlined)
                      : IconButton(
                          tooltip: 'Clear birth date',
                          onPressed: () =>
                              setDialogState(() => birthDate = null),
                          icon: const Icon(AppIcons.clearRounded),
                        ),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: birthDate ?? DateTime(1990),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (selected != null) {
                      setDialogState(() => birthDate = selected);
                    }
                  },
                ),
                DropdownButtonFormField<String?>(
                  initialValue: sex,
                  decoration: const InputDecoration(
                    labelText: 'Sex (optional)',
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Not provided'),
                    ),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(
                      value: 'intersex',
                      child: Text('Intersex'),
                    ),
                    DropdownMenuItem(
                      value: 'prefer_not_to_say',
                      child: Text('Prefer not to say'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() => sex = value),
                ),
                TextField(
                  controller: mobile,
                  maxLength: 30,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile number (optional)',
                  ),
                ),
                TextField(
                  controller: address,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Address (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final cleanEmail = email.text.trim().toLowerCase();
              final mobileDigits = mobile.text.replaceAll(RegExp(r'\D'), '');
              if (first.text.trim().isEmpty || last.text.trim().isEmpty) {
                _dialogError(context, 'First and last name are required.');
                return;
              }
              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(cleanEmail)) {
                _dialogError(context, 'Enter a valid patient email address.');
                return;
              }
              if (!_isStrongPassword(password.text)) {
                _dialogError(
                  context,
                  'Use at least 12 characters with upper-case, lower-case, number, and symbol characters.',
                );
                return;
              }
              if (password.text != confirmPassword.text) {
                _dialogError(context, 'The temporary passwords do not match.');
                return;
              }
              if (mobile.text.trim().isNotEmpty &&
                  (mobileDigits.length < 7 || mobileDigits.length > 15)) {
                _dialogError(context, 'Enter a valid mobile number.');
                return;
              }
              Navigator.pop(context, {
                'first_name': first.text.trim(),
                'last_name': last.text.trim(),
                'email': cleanEmail,
                'password': password.text,
                'birth_date': birthDate,
                'sex': sex,
                'mobile_number': mobile.text.trim(),
                'address': address.text.trim(),
              });
            },
            child: const Text('Create & assign patient'),
          ),
        ],
      ),
    ),
  );
  first.dispose();
  last.dispose();
  email.dispose();
  password.dispose();
  confirmPassword.dispose();
  mobile.dispose();
  address.dispose();
  return result;
}

Future<JsonMap?> _transitionDialog(
  BuildContext context,
  JsonMap item,
  String status,
) async {
  final notes = TextEditingController(
    text: item['doctor_notes']?.toString() ?? '',
  );
  final diagnosis = TextEditingController(
    text: item['confirmed_diagnosis']?.toString() ?? '',
  );
  final treatment = TextEditingController(
    text: item['treatment_plan']?.toString() ?? '',
  );
  final meeting = TextEditingController(
    text: item['meeting_link']?.toString() ?? '',
  );
  final isCompletion = status == 'completed';
  final needsReason = {'rejected', 'cancelled'}.contains(status);
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Mark consultation ${_label(status).toLowerCase()}'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCompletion) ...[
                TextField(
                  controller: diagnosis,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Doctor-confirmed diagnosis *',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: treatment,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    labelText: 'Treatment plan *',
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: notes,
                minLines: 2,
                maxLines: 6,
                maxLength: 3000,
                decoration: InputDecoration(
                  labelText: needsReason
                      ? 'Reason *'
                      : 'Doctor or scheduling notes',
                ),
              ),
              if (status == 'scheduled') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: meeting,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Meeting link (optional)',
                    helperText:
                        'Leave blank to provision a secure CareNavigator Jitsi room.',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if ((isCompletion &&
                    (diagnosis.text.trim().isEmpty ||
                        treatment.text.trim().isEmpty)) ||
                (needsReason && notes.text.trim().isEmpty)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Complete the required clinical or reason fields.',
                  ),
                ),
              );
              return;
            }
            final link = meeting.text.trim();
            if (link.isNotEmpty && !(Uri.tryParse(link)?.hasScheme ?? false)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enter a valid meeting URL.')),
              );
              return;
            }
            Navigator.pop(context, {
              'doctor_notes': notes.text.trim(),
              'confirmed_diagnosis': diagnosis.text.trim(),
              'treatment_plan': treatment.text.trim(),
              'meeting_link': link,
            });
          },
          child: const Text('Confirm status'),
        ),
      ],
    ),
  );
  notes.dispose();
  diagnosis.dispose();
  treatment.dispose();
  meeting.dispose();
  return result;
}

Future<JsonMap?> _recordDialog(
  BuildContext context,
  List<JsonMap> patients,
  List<JsonMap> consultations,
  JsonMap? initial, {
  JsonMap? selectedPatient,
}) async {
  String? patientId =
      selectedPatient?['id']?.toString() ?? initial?['patient_id']?.toString();
  String? consultationId = initial?['consultation_id']?.toString();
  final type = TextEditingController(
    text: initial?['record_type']?.toString() ?? 'consultation_summary',
  );
  final title = TextEditingController(
    text: initial?['title']?.toString() ?? '',
  );
  final description = TextEditingController(
    text: initial?['description']?.toString() ?? '',
  );
  final diagnosis = TextEditingController(
    text: initial?['confirmed_diagnosis']?.toString() ?? '',
  );
  final treatment = TextEditingController(
    text: initial?['treatment_plan']?.toString() ?? '',
  );
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final availableConsultations = consultations
            .where(
              (item) =>
                  patientId == null ||
                  item['patient_id']?.toString() == patientId,
            )
            .toList();
        return AlertDialog(
          title: Text(
            initial == null ? 'Add medical record' : 'Edit medical record',
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue:
                        patients.any(
                          (item) => item['id']?.toString() == patientId,
                        )
                        ? patientId
                        : null,
                    decoration: const InputDecoration(labelText: 'Patient *'),
                    items: patients
                        .map(
                          (patient) => DropdownMenuItem(
                            value: patient['id'].toString(),
                            child: Text(_person(patient['users'])),
                          ),
                        )
                        .toList(),
                    onChanged: initial == null
                        ? (value) => setDialogState(() {
                            patientId = value;
                            consultationId = null;
                          })
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue:
                        availableConsultations.any(
                          (item) => item['id']?.toString() == consultationId,
                        )
                        ? consultationId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Related consultation',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No linked consultation'),
                      ),
                      ...availableConsultations.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item['id'].toString(),
                          child: Text(
                            '${_dateTime(item['appointment_date'])} · ${_label(item['status']?.toString() ?? '')}',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => consultationId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: type,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Record type *',
                    ),
                  ),
                  TextField(
                    controller: title,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Title *'),
                  ),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 3000,
                    decoration: const InputDecoration(
                      labelText: 'Clinical description',
                    ),
                  ),
                  TextField(
                    controller: diagnosis,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Doctor-confirmed diagnosis',
                    ),
                  ),
                  TextField(
                    controller: treatment,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 3000,
                    decoration: const InputDecoration(
                      labelText: 'Treatment plan',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (patientId == null ||
                    type.text.trim().isEmpty ||
                    title.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Patient, record type, and title are required.',
                      ),
                    ),
                  );
                  return;
                }
                final patient = patients.firstWhere(
                  (item) => item['id'].toString() == patientId,
                );
                final hospitalId = patient['primary_hospital_id']?.toString();
                if (hospitalId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'The patient must have a primary hospital.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'patient_id': patientId,
                  'hospital_id': hospitalId,
                  'consultation_id': consultationId,
                  'record_type': type.text.trim(),
                  'title': title.text.trim(),
                  'description': description.text.trim(),
                  'confirmed_diagnosis': diagnosis.text.trim(),
                  'treatment_plan': treatment.text.trim(),
                });
              },
              child: const Text('Save record'),
            ),
          ],
        );
      },
    ),
  );
  type.dispose();
  title.dispose();
  description.dispose();
  diagnosis.dispose();
  treatment.dispose();
  return result;
}

Future<JsonMap?> _prescriptionDialog(
  BuildContext context,
  JsonMap patient,
  List<JsonMap> consultations,
) async {
  String? consultationId;
  final medication = TextEditingController();
  final dosage = TextEditingController();
  final frequency = TextEditingController();
  final duration = TextEditingController();
  final instructions = TextEditingController();
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Prescription for ${_person(patient['users'])}'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: consultationId,
                  decoration: const InputDecoration(
                    labelText: 'Consultation *',
                  ),
                  items: consultations
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id'].toString(),
                          child: Text(
                            '${_dateTime(item['appointment_date'])} · ${_label(item['status']?.toString() ?? '')}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => consultationId = value),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: medication,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Medication *'),
                ),
                TextField(
                  controller: dosage,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Dosage *'),
                ),
                TextField(
                  controller: frequency,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Frequency *'),
                ),
                TextField(
                  controller: duration,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Duration *'),
                ),
                TextField(
                  controller: instructions,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(labelText: 'Instructions'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (consultationId == null ||
                  [
                    medication,
                    dosage,
                    frequency,
                    duration,
                  ].any((controller) => controller.text.trim().isEmpty)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Consultation and all medication directions are required.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'consultation_id': consultationId,
                'medication_name': medication.text.trim(),
                'dosage': dosage.text.trim(),
                'frequency': frequency.text.trim(),
                'duration': duration.text.trim(),
                'instructions': instructions.text.trim(),
              });
            },
            child: const Text('Save prescription'),
          ),
        ],
      ),
    ),
  );
  medication.dispose();
  dosage.dispose();
  frequency.dispose();
  duration.dispose();
  instructions.dispose();
  return result;
}

Future<bool?> _consentDecisionDialog(
  BuildContext context,
  JsonMap definition,
  bool isGranted,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AlertDialog(
    title: Text(isGranted ? 'Grant consent?' : 'Revoke consent?'),
    content: SizedBox(
      width: 540,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            definition['title'].toString(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(definition['description'].toString()),
          const SizedBox(height: 12),
          Text('Policy version ${definition['version']}'),
          if (!isGranted) ...[
            const SizedBox(height: 12),
            const Text(
              'Revocation takes effect for future processing and is retained as an auditable decision.',
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(isGranted ? 'I grant consent' : 'I revoke consent'),
      ),
    ],
  ),
);

Future<JsonMap?> _diagnosisDialog(
  BuildContext context,
  JsonMap patient,
  List<JsonMap> allConsultations,
) async {
  final consultations = _doctorClinicalConsultations(patient, allConsultations);
  String? consultationId = consultations.length == 1
      ? consultations.first['id']?.toString()
      : null;
  var isPrimary = false;
  final diagnosis = TextEditingController();
  final code = TextEditingController();
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Confirm diagnosis for ${_person(patient['users'])}'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Card(
                  color: Color(0xFFFFF6DF),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'This becomes an immutable, doctor-confirmed diagnosis. Verify the patient and consultation before saving.',
                    ),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: consultationId,
                  decoration: const InputDecoration(
                    labelText: 'In-progress or completed consultation *',
                  ),
                  items: consultations
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id'].toString(),
                          child: Text(
                            '${_dateTime(item['appointment_date'])} · ${_label(item['status']?.toString() ?? '')}',
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) =>
                      setDialogState(() => consultationId = value),
                ),
                TextField(
                  controller: diagnosis,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Doctor-confirmed diagnosis *',
                  ),
                ),
                TextField(
                  controller: code,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Diagnosis code (optional)',
                  ),
                ),
                SwitchListTile(
                  value: isPrimary,
                  onChanged: (value) => setDialogState(() => isPrimary = value),
                  title: const Text('Primary diagnosis for this consultation'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (consultationId == null || diagnosis.text.trim().length < 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Choose a clinical consultation and enter the confirmed diagnosis.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'consultation_id': consultationId,
                'diagnosis': diagnosis.text.trim(),
                'diagnosis_code': code.text.trim(),
                'is_primary': isPrimary,
              });
            },
            child: const Text('Save confirmed diagnosis'),
          ),
        ],
      ),
    ),
  );
  diagnosis.dispose();
  code.dispose();
  return result;
}

Future<JsonMap?> _treatmentPlanDialog(
  BuildContext context,
  JsonMap patient,
  List<JsonMap> allConsultations, {
  JsonMap? initial,
}) async {
  final consultations = _doctorClinicalConsultations(patient, allConsultations);
  String? consultationId = initial?['consultation_id']?.toString();
  consultationId ??= consultations.length == 1
      ? consultations.first['id']?.toString()
      : null;
  var status = initial?['status']?.toString() ?? 'active';
  DateTime? startsOn = DateTime.tryParse(
    initial?['starts_on']?.toString() ?? '',
  );
  DateTime? endsOn = DateTime.tryParse(initial?['ends_on']?.toString() ?? '');
  final plan = TextEditingController(text: initial?['plan']?.toString() ?? '');
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          initial == null ? 'Create treatment plan' : 'Update treatment plan',
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: consultationId,
                  decoration: const InputDecoration(
                    labelText: 'Clinical consultation *',
                  ),
                  items: consultations
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id'].toString(),
                          child: Text(
                            '${_dateTime(item['appointment_date'])} · ${_label(item['status']?.toString() ?? '')}',
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: initial == null
                      ? (value) => setDialogState(() => consultationId = value)
                      : null,
                ),
                TextField(
                  controller: plan,
                  minLines: 4,
                  maxLines: 12,
                  maxLength: 10000,
                  decoration: const InputDecoration(
                    labelText: 'Doctor-confirmed treatment plan *',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'planned', child: Text('Planned')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completed'),
                    ),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('Cancelled'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => status = value ?? 'active'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Starts'),
                        subtitle: Text(_dateOnlyLabel(startsOn)),
                        onTap: () async {
                          final value = await _pickCalendarDate(
                            context,
                            startsOn ?? DateTime.now(),
                          );
                          if (value != null) {
                            setDialogState(() => startsOn = value);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ends'),
                        subtitle: Text(_dateOnlyLabel(endsOn)),
                        onTap: () async {
                          final value = await _pickCalendarDate(
                            context,
                            endsOn ?? startsOn ?? DateTime.now(),
                          );
                          if (value != null) {
                            setDialogState(() => endsOn = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (consultationId == null || plan.text.trim().length < 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Consultation and treatment plan are required.',
                    ),
                  ),
                );
                return;
              }
              if (startsOn != null &&
                  endsOn != null &&
                  endsOn!.isBefore(startsOn!)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'The end date cannot precede the start date.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'consultation_id': consultationId,
                'plan': plan.text.trim(),
                'status': status,
                'starts_on': startsOn,
                'ends_on': endsOn,
              });
            },
            child: Text(initial == null ? 'Create plan' : 'Update plan'),
          ),
        ],
      ),
    ),
  );
  plan.dispose();
  return result;
}

Future<JsonMap?> _clinicalDocumentDialog(
  BuildContext context,
  JsonMap patient,
  List<JsonMap> allConsultations,
) async {
  final consultations = allConsultations
      .where(
        (item) => item['patient_id']?.toString() == patient['id']?.toString(),
      )
      .toList(growable: false);
  String? consultationId;
  var documentType = 'clinical_note';
  PlatformFile? file;
  final title = TextEditingController();
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Medical document for ${_person(patient['users'])}'),
        content: SizedBox(
          width: 610,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: documentType,
                  decoration: const InputDecoration(labelText: 'Document type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'clinical_note',
                      child: Text('Clinical note'),
                    ),
                    DropdownMenuItem(
                      value: 'referral',
                      child: Text('Referral'),
                    ),
                    DropdownMenuItem(
                      value: 'discharge_summary',
                      child: Text('Discharge summary'),
                    ),
                    DropdownMenuItem(
                      value: 'medical_certificate',
                      child: Text('Medical certificate'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) => setDialogState(
                    () => documentType = value ?? 'clinical_note',
                  ),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: consultationId,
                  decoration: const InputDecoration(
                    labelText: 'Related consultation (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('General patient document'),
                    ),
                    ...consultations.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item['id'].toString(),
                        child: Text(_dateTime(item['appointment_date'])),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => consultationId = value),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickClinicalFile(context);
                    if (picked != null) setDialogState(() => file = picked);
                  },
                  icon: const Icon(AppIcons.fileUploadOutlined),
                  label: Text(
                    file == null ? 'Choose JPEG, PNG, or PDF *' : file!.name,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Private storage · maximum 20 MB'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty || file?.bytes == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Title and file are required.')),
                );
                return;
              }
              Navigator.pop(context, {
                'document_type': documentType,
                'title': title.text.trim(),
                'consultation_id': consultationId,
                'bytes': file!.bytes!,
                'file_name': file!.name,
                'mime_type': _clinicalMime(file!.extension),
              });
            },
            child: const Text('Upload securely'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  return result;
}

Future<JsonMap?> _patientAttachmentDialog(
  BuildContext context,
  JsonMap consultation,
) async {
  PlatformFile? file;
  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add consultation attachment'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_dateTime(consultation['appointment_date'])} · '
                '${_relation(consultation['doctors'], 'display_name')}',
              ),
              const SizedBox(height: 10),
              const Text(
                'Only attach a document intended for this appointment. It is stored privately and shared only with authorized consultation participants.',
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await _pickClinicalFile(context);
                  if (picked != null) setDialogState(() => file = picked);
                },
                icon: const Icon(AppIcons.attachFileRounded),
                label: Text(
                  file == null ? 'Choose JPEG, PNG, or PDF *' : file!.name,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Private consultation storage · maximum 20 MB'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: file?.bytes == null
                ? null
                : () => Navigator.pop(context, {
                    'bytes': file!.bytes!,
                    'file_name': file!.name,
                    'mime_type': _clinicalMime(file!.extension),
                  }),
            child: const Text('Upload securely'),
          ),
        ],
      ),
    ),
  );
}

Future<JsonMap?> _consultationAttachmentDialog(
  BuildContext context,
  JsonMap patient,
  List<JsonMap> allConsultations,
) async {
  final consultations = allConsultations
      .where(
        (item) =>
            item['patient_id']?.toString() == patient['id']?.toString() &&
            {
              'approved',
              'scheduled',
              'in_progress',
              'completed',
            }.contains(item['status']?.toString()),
      )
      .toList(growable: false);
  String? consultationId = consultations.length == 1
      ? consultations.first['id']?.toString()
      : null;
  PlatformFile? file;
  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Upload consultation attachment'),
        content: SizedBox(
          width: 590,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: consultationId,
                decoration: const InputDecoration(labelText: 'Consultation *'),
                items: consultations
                    .map(
                      (item) => DropdownMenuItem(
                        value: item['id'].toString(),
                        child: Text(
                          '${_dateTime(item['appointment_date'])} · ${_label(item['status']?.toString() ?? '')}',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) =>
                    setDialogState(() => consultationId = value),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await _pickClinicalFile(context);
                  if (picked != null) setDialogState(() => file = picked);
                },
                icon: const Icon(AppIcons.attachFileRounded),
                label: Text(
                  file == null ? 'Choose JPEG, PNG, or PDF *' : file!.name,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Private consultation storage · maximum 20 MB'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (consultationId == null || file?.bytes == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Consultation and attachment are required.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'consultation_id': consultationId,
                'bytes': file!.bytes!,
                'file_name': file!.name,
                'mime_type': _clinicalMime(file!.extension),
              });
            },
            child: const Text('Upload securely'),
          ),
        ],
      ),
    ),
  );
}

Future<JsonMap?> _laboratoryRequestDialog(
  BuildContext context,
  JsonMap patient,
  List<JsonMap> allConsultations,
) async {
  final consultations = allConsultations
      .where((item) => item['patient_id'] == patient['id'])
      .toList();
  String? consultationId;
  var priority = 'routine';
  DateTime? dueAt;
  final testName = TextEditingController();
  final instructions = TextEditingController();
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Laboratory request for ${_person(patient['users'])}'),
        content: SizedBox(
          width: 580,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: testName,
                maxLength: 180,
                decoration: const InputDecoration(
                  labelText: 'Requested test *',
                ),
              ),
              DropdownButtonFormField<String?>(
                initialValue: consultationId,
                decoration: const InputDecoration(
                  labelText: 'Related consultation',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No linked consultation'),
                  ),
                  ...consultations.map(
                    (item) => DropdownMenuItem<String?>(
                      value: item['id'].toString(),
                      child: Text(_dateTime(item['appointment_date'])),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => consultationId = value),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: const [
                  DropdownMenuItem(value: 'routine', child: Text('Routine')),
                  DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  DropdownMenuItem(
                    value: 'stat',
                    child: Text('STAT / immediate'),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => priority = value ?? 'routine'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  dueAt == null
                      ? 'No due date'
                      : 'Due ${DateFormat.yMMMd().add_jm().format(dueAt!)}',
                ),
                trailing: const Icon(AppIcons.eventRounded),
                onTap: () async {
                  final value = await _pickDateTime(
                    context,
                    dueAt ?? DateTime.now().add(const Duration(days: 7)),
                  );
                  if (value != null) {
                    setDialogState(() => dueAt = value);
                  }
                },
              ),
              TextField(
                controller: instructions,
                minLines: 2,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Preparation or collection instructions',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (testName.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Test name is required.')),
                );
                return;
              }
              Navigator.pop(context, {
                'test_name': testName.text.trim(),
                'consultation_id': consultationId,
                'priority': priority,
                'due_at': dueAt,
                'instructions': instructions.text.trim(),
              });
            },
            child: const Text('Create request'),
          ),
        ],
      ),
    ),
  );
  testName.dispose();
  instructions.dispose();
  return result;
}

Future<JsonMap?> _resultUploadDialog(
  BuildContext context,
  JsonMap patient,
  List<JsonMap> allConsultations,
) async {
  final consultations = allConsultations
      .where((item) => item['patient_id'] == patient['id'])
      .toList();
  String? consultationId;
  PlatformFile? file;
  final testName = TextEditingController();
  final extracted = TextEditingController();
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Upload result for ${_person(patient['users'])}'),
        content: SizedBox(
          width: 590,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: testName,
                  maxLength: 180,
                  decoration: const InputDecoration(
                    labelText: 'Test or document name *',
                  ),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: consultationId,
                  decoration: const InputDecoration(
                    labelText: 'Related consultation',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No linked consultation'),
                    ),
                    ...consultations.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item['id'].toString(),
                        child: Text(_dateTime(item['appointment_date'])),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => consultationId = value),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await FilePicker.platform.pickFiles(
                      withData: true,
                      allowMultiple: false,
                      type: FileType.custom,
                      allowedExtensions: const [
                        'jpg',
                        'jpeg',
                        'png',
                        'webp',
                        'pdf',
                        'txt',
                      ],
                    );
                    if (picked != null && picked.files.single.bytes != null) {
                      if (picked.files.single.size > 15 * 1024 * 1024) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Medical result files must be 15 MB or smaller.',
                              ),
                            ),
                          );
                        }
                        return;
                      }
                      setDialogState(() => file = picked.files.single);
                    }
                  },
                  icon: const Icon(AppIcons.uploadFileRounded),
                  label: Text(
                    file == null
                        ? 'Choose image, PDF, or text file *'
                        : file!.name,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: extracted,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 10000,
                  decoration: const InputDecoration(
                    labelText: 'Extracted text (required for PDF analysis)',
                    helperText:
                        'Images can be read by the configured vision model. Review OCR text before analysis.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (testName.text.trim().isEmpty || file?.bytes == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Test name and file are required.'),
                  ),
                );
                return;
              }
              if (file!.extension?.toLowerCase() == 'pdf' &&
                  extracted.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Paste reviewed OCR text before analyzing a PDF.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'test_name': testName.text.trim(),
                'consultation_id': consultationId,
                'bytes': file!.bytes!,
                'file_name': file!.name,
                'mime_type': _medicalMime(file!.extension),
                'extracted_text': extracted.text.trim(),
              });
            },
            child: const Text('Upload securely'),
          ),
        ],
      ),
    ),
  );
  testName.dispose();
  extracted.dispose();
  return result;
}

Future<JsonMap?> _confirmResultDialog(
  BuildContext context,
  JsonMap result,
) async {
  final findings = TextEditingController(
    text:
        result['doctor_confirmed_findings']?.toString() ??
        result['ai_summary']?.toString() ??
        '',
  );
  final interpretation = TextEditingController(
    text: result['professional_interpretation']?.toString() ?? '',
  );
  var saveToRecord = true;
  final value = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Confirm medical findings'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Card(
                  color: Color(0xFFFFF6DF),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'AI output is preliminary. Confirm only findings you independently reviewed as a licensed doctor.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: findings,
                  minLines: 3,
                  maxLines: 9,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    labelText: 'Doctor-confirmed findings *',
                  ),
                ),
                TextField(
                  controller: interpretation,
                  minLines: 3,
                  maxLines: 9,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    labelText: 'Professional interpretation',
                  ),
                ),
                SwitchListTile(
                  value: saveToRecord,
                  onChanged: (value) =>
                      setDialogState(() => saveToRecord = value),
                  title: const Text(
                    'Save as an official patient medical record',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (findings.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Doctor-confirmed findings are required.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'confirmed_findings': findings.text.trim(),
                'professional_interpretation': interpretation.text.trim(),
                'save_to_record': saveToRecord,
              });
            },
            child: const Text('Confirm as doctor'),
          ),
        ],
      ),
    ),
  );
  findings.dispose();
  interpretation.dispose();
  return value;
}

Future<String?> _textDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? initial,
}) async {
  final controller = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          maxLength: 3000,
          decoration: InputDecoration(labelText: label),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    initialDate: initial.isBefore(DateTime.now()) ? DateTime.now() : initial,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<DateTime?> _pickCalendarDate(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: initial,
    );

Future<PlatformFile?> _pickClinicalFile(BuildContext context) async {
  final picked = await FilePicker.platform.pickFiles(
    withData: true,
    allowMultiple: false,
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
  );
  if (picked == null || picked.files.single.bytes == null) return null;
  if (picked.files.single.size > 20 * 1024 * 1024) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clinical documents must be 20 MB or smaller.'),
        ),
      );
    }
    return null;
  }
  return picked.files.single;
}

List<JsonMap> _doctorClinicalConsultations(
  JsonMap patient,
  List<JsonMap> consultations,
) => consultations
    .where(
      (item) =>
          item['patient_id']?.toString() == patient['id']?.toString() &&
          {'in_progress', 'completed'}.contains(item['status']?.toString()),
    )
    .toList(growable: false);

List<String> _transitions(String role, String status) {
  if (role == 'doctor' || role == 'hospital_admin') {
    return switch (status) {
      'pending' => const ['approved', 'rejected'],
      'approved' => const ['scheduled', 'cancelled'],
      'scheduled' => const ['in_progress', 'cancelled'],
      'in_progress' => const ['completed'],
      _ => const [],
    };
  }
  if (role == 'patient' || role == 'guest') {
    return {'pending', 'approved', 'scheduled'}.contains(status)
        ? const ['cancelled']
        : const [];
  }
  return const [];
}

Widget _transitionButton(String status, VoidCallback? onPressed) {
  final destructive = {'rejected', 'cancelled'}.contains(status);
  return destructive
      ? OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(AppIcons.closeRounded),
          label: Text(_label(status)),
        )
      : FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: Icon(
            status == 'completed'
                ? AppIcons.taskAltRounded
                : status == 'in_progress'
                ? AppIcons.playArrowRounded
                : AppIcons.arrowForwardRounded,
          ),
          label: Text(_label(status)),
        );
}

List<JsonMap> _rows(dynamic value) => value is List
    ? value.whereType<JsonMap>().toList(growable: false)
    : const [];

String _relation(dynamic value, String key) {
  final relation = value is List ? (value.isEmpty ? null : value.first) : value;
  return relation is Map ? relation[key]?.toString() ?? '' : '';
}

String _person(dynamic value) {
  final relation = value is List ? (value.isEmpty ? null : value.first) : value;
  if (relation is! Map) return '';
  final nested = relation['users'];
  final user = nested is List ? (nested.isEmpty ? null : nested.first) : nested;
  final target = user is Map ? user : relation;
  final first = target['first_name']?.toString() ?? '';
  final last = target['last_name']?.toString() ?? '';
  final name = '$first $last'.trim();
  return name.isEmpty ? relation['patient_number']?.toString() ?? '' : name;
}

String _label(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _dateTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? 'Not scheduled'
      : DateFormat.yMMMd().add_jm().format(date.toLocal());
}

String _recordDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? 'Date unavailable' : DateFormat.yMMMd().format(date);
}

String _dateOnlyLabel(DateTime? value) =>
    value == null ? 'Not set' : DateFormat.yMMMd().format(value);

String _slotLabel(JsonMap slot) {
  final start = DateTime.tryParse(slot['slot_start']?.toString() ?? '');
  final end = DateTime.tryParse(slot['slot_end']?.toString() ?? '');
  if (start == null || end == null) return 'Unavailable slot';
  final formatter = DateFormat.jm();
  return '${formatter.format(start.toLocal())} – ${formatter.format(end.toLocal())}';
}

String _dateRange(dynamic startsOn, dynamic endsOn) {
  final start = DateTime.tryParse(startsOn?.toString() ?? '');
  final end = DateTime.tryParse(endsOn?.toString() ?? '');
  if (start == null && end == null) return 'No date range';
  if (end == null) return 'From ${DateFormat.yMMMd().format(start!)}';
  if (start == null) return 'Until ${DateFormat.yMMMd().format(end)}';
  return '${DateFormat.yMMMd().format(start)} – ${DateFormat.yMMMd().format(end)}';
}

String _fileSize(dynamic value) {
  final bytes = int.tryParse(value?.toString() ?? '');
  if (bytes == null) return 'Size unavailable';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _listText(dynamic value) => value is List
    ? value.where((item) => item != null).join(', ')
    : value?.toString() ?? '';

String _jsonText(dynamic value) {
  if (value == null) return '';
  if (value is List) {
    return value
        .map(
          (item) => item is Map
              ? item.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join(', ')
              : item.toString(),
        )
        .join('\n');
  }
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
  }
  return value.toString();
}

String _medicalMime(String? extension) => switch (extension?.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'webp' => 'image/webp',
  'pdf' => 'application/pdf',
  'txt' => 'text/plain',
  _ => 'application/octet-stream',
};

String _clinicalMime(String? extension) => switch (extension?.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'pdf' => 'application/pdf',
  _ => 'application/octet-stream',
};

bool _isStrongPassword(String value) =>
    value.length >= 12 &&
    RegExp('[a-z]').hasMatch(value) &&
    RegExp('[A-Z]').hasMatch(value) &&
    RegExp('[0-9]').hasMatch(value) &&
    RegExp(r'[^A-Za-z0-9]').hasMatch(value);

void _dialogError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
