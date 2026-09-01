import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/auth/user_role.dart';
import '../../models/clinical_checkup.dart';
import '../../models/consultation_scheduling.dart';
import '../../models/consultation_type.dart';
import '../../models/hospitals/hospital_models.dart';
import '../../providers/core_providers.dart';
import '../../providers/hospital_directory_provider.dart';
import '../../repositories/admin_repository.dart';
import '../../repositories/care_repository.dart';
import '../../repositories/consultation_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../repositories/repository_failure.dart';
import '../../repositories/workspace_repository.dart';
import '../../routing/root_overlay.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/data_display/content_panel.dart';
import '../../widgets/data_display/hospital_image.dart';
import '../../widgets/forms/patient_details_fields.dart';
import '../../widgets/layout/page_header.dart';
import '../../widgets/overlays/action_dialogs.dart';
import '../public/public_home_screen.dart';
import 'live_profile_view.dart';

class LiveWorkspaceView extends ConsumerStatefulWidget {
  const LiveWorkspaceView({
    super.key,
    required this.role,
    this.section,
    this.itemId,
    this.isTab = false,
    this.showDetailHeader = true,
    this.requestReservation = false,
    this.initialReservationHospitalId,
    this.initialReservationDoctorId,
  });

  final UserRole role;
  final String? section;
  final String? itemId;
  final bool isTab;
  final bool showDetailHeader;
  final bool requestReservation;
  final String? initialReservationHospitalId;
  final String? initialReservationDoctorId;

  @override
  ConsumerState<LiveWorkspaceView> createState() => _LiveWorkspaceViewState();
}

class _LiveWorkspaceViewState extends ConsumerState<LiveWorkspaceView> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _query = '';
  final Set<String> _busyItems = {};
  String? _handledReservationIntent;
  WorkspaceSnapshot? _expandedSnapshot;
  bool _loadingMore = false;

  WorkspaceRequest get _request =>
      (role: widget.role, section: _dataSection, itemId: widget.itemId);

  String? get _dataSection =>
      widget.role == UserRole.patient && widget.section == 'medical-records'
      ? 'records'
      : widget.section;

  @override
  void initState() {
    super.initState();
    _scheduleRequestedReservation();
  }

  @override
  void didUpdateWidget(covariant LiveWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role ||
        oldWidget.section != widget.section ||
        oldWidget.itemId != widget.itemId) {
      _expandedSnapshot = null;
    }
    _scheduleRequestedReservation();
  }

  void _scheduleRequestedReservation() {
    if (!widget.requestReservation ||
        widget.role != UserRole.patient ||
        widget.section != 'appointments') {
      return;
    }
    final intent =
        '${widget.initialReservationHospitalId ?? ''}:${widget.initialReservationDoctorId ?? ''}';
    if (_handledReservationIntent == intent) return;
    _handledReservationIntent = intent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _reserveConsultation(
          initialHospitalId: widget.initialReservationHospitalId,
          initialDoctorId: widget.initialReservationDoctorId,
        ),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role == UserRole.patient && widget.section == null) {
      return const PatientCareHomeContent();
    }

    if (!widget.isTab) {
      if (widget.role == UserRole.doctor && widget.section == 'scheduling') {
        return _buildTabs(
          tabs: const ['Availability', 'Appointments'],
          sections: const ['schedule', 'appointments'],
        );
      }
      if (widget.role == UserRole.doctor && widget.section == 'laboratory') {
        return _buildTabs(
          tabs: const ['Orders', 'Results Review'],
          sections: const ['laboratory', 'results-review'],
        );
      }
      if (widget.role == UserRole.hospitalAdministrator &&
          widget.section == 'facility') {
        return _buildTabs(
          tabs: const ['Capacity', 'Rooms'],
          sections: const ['beds', 'rooms'],
        );
      }
      if (widget.role == UserRole.hospitalAdministrator &&
          widget.section == 'services-departments') {
        return _buildTabs(
          tabs: const ['Services', 'Departments'],
          sections: const ['services', 'departments'],
        );
      }
      if (widget.role == UserRole.hospitalAdministrator &&
          widget.section == 'audit-reports') {
        return _buildTabs(
          tabs: const ['Audit', 'Reports'],
          sections: const ['audit', 'reports'],
        );
      }
      if (widget.role == UserRole.superAdministrator &&
          widget.section == 'system') {
        return _buildTabs(
          tabs: const [
            'Permissions',
            'Settings',
            'Security',
            'Maintenance',
            'Audit',
          ],
          sections: const [
            'permissions',
            'settings',
            'security',
            'maintenance',
            'audit',
          ],
        );
      }
    }

    if ({'profile', 'preferences'}.contains(widget.section)) {
      return LiveProfileView(role: widget.role);
    }
    if (widget.section == 'messages' && widget.itemId != null) {
      return _LiveConversationView(
        conversationId: widget.itemId!,
        role: widget.role,
      );
    }
    if (widget.section == 'notifications' && widget.itemId == null) {
      final notifications = ref.watch(careNotificationsProvider);
      return notifications.when(
        loading: () => const _LiveLoadingState(),
        error: (error, _) => _LiveErrorState(
          message: _friendlyError(error),
          onRetry: () => ref.invalidate(careNotificationsProvider),
        ),
        data: (items) {
          final visibleNotifications = collapseNotificationThreads(items);
          return _buildSnapshot(
            WorkspaceSnapshot(
              title: 'Notifications',
              description: 'Live account and care updates for your account.',
              items: visibleNotifications
                  .map(
                    (item) => WorkspaceItem(
                      id: item.id,
                      kind: 'notifications',
                      title: item.title,
                      subtitle: item.message,
                      status: item.isRead ? 'read' : 'unread',
                      timestamp: item.createdAt,
                      isUnread: !item.isRead,
                      data: {
                        'notification_type': item.type,
                        'title': item.title,
                        'message': item.message,
                        'is_read': item.isRead,
                        'created_at': item.createdAt.toIso8601String(),
                        'reference_id': item.referenceId,
                        'data': item.data,
                        ...item.data,
                      },
                    ),
                  )
                  .toList(growable: false),
              loadedAt: DateTime.now(),
            ),
          );
        },
      );
    }
    final snapshot = ref.watch(workspaceSnapshotProvider(_request));
    return snapshot.when(
      loading: () => const _LiveLoadingState(),
      error: (error, _) => _LiveErrorState(
        message: _friendlyError(error),
        onRetry: () => ref.invalidate(workspaceSnapshotProvider(_request)),
      ),
      data: (value) {
        final expanded = _expandedSnapshot;
        final effective =
            expanded != null &&
                (expanded.loadedAt ?? DateTime(1970)).isAfter(
                  value.loadedAt ?? DateTime(1970),
                )
            ? expanded
            : value;
        return widget.section == 'messages' && widget.itemId == null
            ? _buildMessagesInbox(effective)
            : _buildSnapshot(effective);
      },
    );
  }

  Future<void> _loadMore(WorkspaceSnapshot snapshot) async {
    final repository = ref.read(workspaceRepositoryProvider);
    if (repository == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final expanded = await repository.load(
        role: widget.role,
        section: _dataSection,
        itemId: widget.itemId,
        limit: snapshot.items.length + 100,
      );
      if (mounted) setState(() => _expandedSnapshot = expanded);
    } catch (error) {
      showRootMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _refreshSnapshot() {
    setState(() => _expandedSnapshot = null);
    ref.invalidate(workspaceSnapshotProvider(_request));
  }

  Widget _buildMessagesInbox(WorkspaceSnapshot snapshot) {
    final normalizedQuery = _query.trim().toLowerCase();
    final conversations = normalizedQuery.isEmpty
        ? snapshot.items
        : snapshot.items
              .where(
                (item) =>
                    item.title.toLowerCase().contains(normalizedQuery) ||
                    item.subtitle.toLowerCase().contains(normalizedQuery),
              )
              .toList(growable: false);
    final isPatient = widget.role == UserRole.patient;

    return SingleChildScrollView(
      child: PageContent(
        maxWidth: 980,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Messages',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Start a conversation',
                  onPressed: _startConversation,
                  icon: const Icon(Icons.edit_square),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              isPatient
                  ? 'Chat with your care team.'
                  : 'Chat with patients in your care.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.x5),
            TextField(
              key: const Key('conversation-search'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(
                    color: AppColors.focus,
                    width: 1.5,
                  ),
                ),
                suffixIcon: normalizedQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.x5),
            if (conversations.isEmpty)
              _MessagesEmptyState(
                isSearch: normalizedQuery.isNotEmpty,
                isPatient: isPatient,
                onStart: _startConversation,
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(AppRadius.sheet),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A102A3A),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sheet),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < conversations.length;
                        index++
                      ) ...[
                        _ConversationInboxRow(
                          item: conversations[index],
                          onTap: () => _open(conversations[index]),
                        ),
                        if (index != conversations.length - 1)
                          const Divider(height: 1, indent: 84),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _startConversation() {
    context.go(
      widget.role == UserRole.doctor
          ? '${widget.role.homeLocation}/patients'
          : '${widget.role.homeLocation}/consultations',
    );
  }

  Widget _buildTabs({
    required List<String> tabs,
    required List<String> sections,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 600
        ? 16.0
        : width < 1000
        ? 24.0
        : 32.0;
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surface,
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: TabBar(
                  isScrollable: true,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textMuted,
                  indicatorColor: AppColors.primary,
                  tabs: [for (final tab in tabs) Tab(text: tab)],
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final sec in sections)
                  LiveWorkspaceView(
                    role: widget.role,
                    section: sec,
                    itemId: widget.itemId,
                    isTab: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshot(WorkspaceSnapshot snapshot) {
    final normalizedQuery = _query.trim().toLowerCase();
    final isConsultationView =
        {'appointments', 'consultations'}.contains(widget.section) &&
        (snapshot.items.isEmpty ||
            snapshot.items.any((item) => item.kind == 'consultations'));
    final isPatientConsultationView =
        widget.role == UserRole.patient && isConsultationView;
    final isPatientConsultationsPage =
        isPatientConsultationView && widget.section == 'consultations';
    final isPatientConsultationDetail =
        isPatientConsultationView && widget.itemId != null;
    final isDoctorScheduleView =
        widget.role == UserRole.doctor &&
        widget.section == 'schedule' &&
        widget.itemId == null;
    final isDoctorAppointmentsView =
        widget.role == UserRole.doctor &&
        widget.section == 'appointments' &&
        widget.itemId == null;
    final isNotificationDetail =
        widget.section == 'notifications' && widget.itemId != null;
    final isConnectionRequestDetail =
        isNotificationDetail && snapshot.items.any(_isPatientConnectionRequest);
    final consultationCount = snapshot.items
        .where((item) => item.kind == 'consultations')
        .length;
    final items = normalizedQuery.isEmpty
        ? snapshot.items
        : snapshot.items
              .where(
                (item) =>
                    item.title.toLowerCase().contains(normalizedQuery) ||
                    item.subtitle.toLowerCase().contains(normalizedQuery) ||
                    (item.status?.toLowerCase().contains(normalizedQuery) ??
                        false),
              )
              .toList(growable: false);
    return SingleChildScrollView(
      child: PageContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isPatientConsultationDetail && widget.showDetailHeader)
              _AppointmentDetailPageHeader(
                consultationCount: consultationCount,
                onBack: () =>
                    context.go('${widget.role.homeLocation}/${widget.section}'),
              )
            else if (!isPatientConsultationDetail)
              PageHeader(
                title: isConnectionRequestDetail
                    ? 'Connection request'
                    : isPatientConsultationsPage
                    ? 'Consultations'
                    : isDoctorScheduleView
                    ? 'Availability'
                    : snapshot.title,
                description: isConnectionRequestDetail
                    ? 'Review who wants to connect and choose what you are comfortable with.'
                    : isPatientConsultationsPage
                    ? 'View your past and upcoming consultations.'
                    : isDoctorScheduleView
                    ? 'Choose when patients can reserve a consultation with you.'
                    : snapshot.description,
                actions: [
                  if (isPatientConsultationView && widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('consultation-reserve')
                          ? null
                          : _reserveConsultation,
                      icon: const Icon(Icons.event_available_outlined),
                      label: const Text('Reserve consultation'),
                    ),
                  if (isPatientConsultationView)
                    Semantics(
                      label: _consultationCountLabel(consultationCount),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.x2,
                          vertical: 10,
                        ),
                        child: Text(
                          _consultationCountLabel(consultationCount),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                  if (widget.role == UserRole.doctor &&
                      widget.section == 'schedule')
                    FilledButton.icon(
                      onPressed: _busyItems.contains('schedule-create')
                          ? null
                          : _createScheduleSlot,
                      icon: const Icon(Icons.add),
                      label: const Text('Add slot'),
                    ),
                  if (widget.role == UserRole.doctor &&
                      widget.section == 'patients' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('patient-account-create')
                          ? null
                          : _createPatientAccount,
                      icon: const Icon(Icons.person_add_alt_outlined),
                      label: const Text('Register patient'),
                    ),
                  if (widget.role == UserRole.doctor &&
                      widget.section == 'prescriptions' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('prescription-create')
                          ? null
                          : _createPrescription,
                      icon: const Icon(Icons.medication_outlined),
                      label: const Text('Issue prescription'),
                    ),
                  if (widget.role == UserRole.patient &&
                      widget.section == 'prescriptions' &&
                      widget.itemId == null &&
                      snapshot.items.isNotEmpty)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('email-daily-reminders')
                          ? null
                          : _emailDailyMedicationSchedule,
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Email daily schedule'),
                    ),
                  if (widget.role == UserRole.doctor &&
                      widget.section == 'laboratory' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed:
                          _busyItems.contains('laboratory-request-create')
                          ? null
                          : _createLaboratoryRequest,
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('Request test'),
                    ),
                  if (widget.role == UserRole.doctor &&
                      widget.section == 'results-review' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('lab-result-upload')
                          ? null
                          : _uploadDoctorLaboratoryResult,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Upload diagnostic result'),
                    ),
                  if (widget.role == UserRole.hospitalAdministrator &&
                      widget.section == 'availability' &&
                      widget.itemId == null &&
                      _missingFacilityTypes(snapshot.items).isNotEmpty)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('facility-status-create')
                          ? null
                          : () => _createFacilityStatus(snapshot.items),
                      icon: const Icon(Icons.add),
                      label: const Text('Add facility status'),
                    ),
                  if (widget.role == UserRole.hospitalAdministrator &&
                      widget.section == 'beds' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('hospital-bed-create')
                          ? null
                          : () => _createCapacityRecord(beds: true),
                      icon: const Icon(Icons.add),
                      label: const Text('Add bed type'),
                    ),
                  if (widget.role == UserRole.hospitalAdministrator &&
                      widget.section == 'rooms' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('hospital-room-create')
                          ? null
                          : () => _createCapacityRecord(beds: false),
                      icon: const Icon(Icons.add),
                      label: const Text('Add room type'),
                    ),
                  if (widget.role == UserRole.hospitalAdministrator &&
                      widget.section == 'emergency-room' &&
                      widget.itemId == null &&
                      snapshot.items.isEmpty)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('emergency-room-create')
                          ? null
                          : _createEmergencyRoomRecord,
                      icon: const Icon(Icons.add),
                      label: const Text('Add ER capacity'),
                    ),
                  if (widget.role == UserRole.hospitalAdministrator &&
                      widget.section == 'staff' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('doctor-account-create')
                          ? null
                          : _createDoctorAccount,
                      icon: const Icon(Icons.person_add_alt_outlined),
                      label: const Text('Add doctor'),
                    ),
                  if (widget.role == UserRole.hospitalAdministrator &&
                      widget.section == 'services' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('hospital-service-create')
                          ? null
                          : _createHospitalService,
                      icon: const Icon(Icons.add),
                      label: const Text('Add service'),
                    ),
                  if (widget.role == UserRole.hospitalAdministrator &&
                      widget.section == 'departments' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed:
                          _busyItems.contains('hospital-department-create')
                          ? null
                          : _createHospitalDepartment,
                      icon: const Icon(Icons.add),
                      label: const Text('Add department'),
                    ),
                  if (widget.role == UserRole.superAdministrator &&
                      {'approvals', 'hospitals'}.contains(widget.section) &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('hospital-create')
                          ? null
                          : _createHospitalRecord,
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Add hospital'),
                    ),
                  if (widget.role == UserRole.superAdministrator &&
                      widget.section == 'permissions' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('permission-create')
                          ? null
                          : _createPermissionRecord,
                      icon: const Icon(Icons.add),
                      label: const Text('Add permission'),
                    ),
                  if (widget.role == UserRole.superAdministrator &&
                      widget.section == 'settings' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('setting-create')
                          ? null
                          : _createSystemSettingRecord,
                      icon: const Icon(Icons.add),
                      label: const Text('Add setting'),
                    ),
                  if (widget.role == UserRole.superAdministrator &&
                      widget.section == 'maintenance' &&
                      widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('maintenance-create')
                          ? null
                          : _createMaintenanceWindow,
                      icon: const Icon(Icons.add),
                      label: const Text('Schedule maintenance'),
                    ),
                  if (widget.role != UserRole.patient)
                    OutlinedButton.icon(
                      onPressed: _refreshSnapshot,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.x3),
            if (isDoctorScheduleView) ...[
              const SizedBox(height: AppSpacing.x5),
              _ScheduleSummary(items: snapshot.items),
            ] else if (!isPatientConsultationView &&
                !isNotificationDetail &&
                widget.itemId == null &&
                snapshot.metrics.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x5),
              _MetricGrid(
                metrics: isDoctorAppointmentsView
                    ? [
                        WorkspaceMetric(
                          label: 'Active appointments',
                          value:
                              '${snapshot.items.where((item) => !_isPastConsultation(item)).length}',
                        ),
                      ]
                    : snapshot.metrics,
              ),
            ],
            const SizedBox(height: AppSpacing.x5),
            if (isDoctorAppointmentsView)
              _buildDoctorAppointmentPanels(
                items: items,
                snapshot: snapshot,
                normalizedQuery: normalizedQuery,
              )
            else
              ContentPanel(
                title: isPatientConsultationView
                    ? null
                    : isDoctorScheduleView
                    ? 'Your weekly hours'
                    : widget.itemId == null
                    ? 'Current records'
                    : isConnectionRequestDetail
                    ? 'Review request'
                    : 'Record detail',
                subtitle: isDoctorScheduleView
                    ? '${snapshot.items.length} ${snapshot.items.length == 1 ? 'time slot' : 'time slots'} · ${snapshot.items.where((item) => item.data['is_active'] == true).length} open for reservation'
                    : isPatientConsultationView || snapshot.loadedAt == null
                    ? null
                    : 'Updated ${DateFormat('MMM d, y · h:mm a').format(snapshot.loadedAt!.toLocal())}',
                action:
                    !isDoctorScheduleView &&
                        snapshot.items.length > 5 &&
                        widget.itemId == null
                    ? SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: isPatientConsultationView
                                ? 'Search consultations'
                                : isDoctorScheduleView
                                ? 'Search day or type'
                                : 'Search visible records',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                        ),
                      )
                    : null,
                child: isDoctorScheduleView
                    ? _ScheduleWeekView(
                        items: snapshot.items,
                        busyItems: _busyItems,
                        actionsFor: _actionsFor,
                      )
                    : items.isEmpty
                    ? DataState(
                        icon: normalizedQuery.isEmpty
                            ? Icons.inbox_outlined
                            : Icons.search_off_outlined,
                        title: normalizedQuery.isEmpty
                            ? isPatientConsultationView
                                  ? 'No consultations yet'
                                  : 'No records available'
                            : 'No matching records',
                        message: normalizedQuery.isEmpty
                            ? isPatientConsultationView
                                  ? 'Your consultations will appear here when they are available.'
                                  : 'There is no information to show in this section yet.'
                            : 'Try a different search term.',
                        action: normalizedQuery.isEmpty
                            ? null
                            : TextButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                child: const Text('Clear search'),
                              ),
                      )
                    : isPatientConsultationView && widget.itemId == null
                    ? _buildPatientConsultationSections(items)
                    : Column(
                        children: [
                          for (
                            var index = 0;
                            index < items.length;
                            index++
                          ) ...[
                            if (widget.itemId == null ||
                                items[index].kind != 'prescriptions')
                              _LiveRecordRow(
                                item: items[index],
                                busy: _busyItems.contains(items[index].id),
                                onOpen: _canOpen(items[index])
                                    ? () => _open(items[index])
                                    : null,
                                trailing: _actionsFor(items[index]),
                              ),
                            if (widget.itemId != null)
                              _LiveRecordDetails(
                                item: items[index],
                                role: widget.role,
                                topActions: _buildDetailActions(items[index]),
                              ),
                            if (widget.itemId == null &&
                                index != items.length - 1)
                              const Divider(height: 1),
                          ],
                          if (snapshot.hasMore &&
                              widget.itemId == null &&
                              normalizedQuery.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.x4,
                              ),
                              child: Center(
                                child: OutlinedButton.icon(
                                  onPressed: _loadingMore
                                      ? null
                                      : () => _loadMore(snapshot),
                                  icon: _loadingMore
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.expand_more),
                                  label: Text(
                                    _loadingMore ? 'Loading...' : 'Load more',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorAppointmentPanels({
    required List<WorkspaceItem> items,
    required WorkspaceSnapshot snapshot,
    required String normalizedQuery,
  }) {
    final active = items
        .where((item) => !_isPastConsultation(item))
        .toList(growable: false);
    final history = items.where(_isPastConsultation).toList(growable: false)
      ..sort(_comparePastConsultations);
    final updatedLabel = snapshot.loadedAt == null
        ? null
        : 'Updated ${DateFormat('MMM d, y Â· h:mm a').format(snapshot.loadedAt!.toLocal())}';

    Widget recordsOrEmpty(
      List<WorkspaceItem> sectionItems, {
      required String emptyTitle,
      required String emptyMessage,
    }) {
      if (sectionItems.isEmpty) {
        return DataState(
          icon: normalizedQuery.isEmpty
              ? Icons.inbox_outlined
              : Icons.search_off_outlined,
          title: normalizedQuery.isEmpty ? emptyTitle : 'No matching records',
          message: normalizedQuery.isEmpty
              ? emptyMessage
              : 'Try a different search term.',
        );
      }
      return Column(
        children: [
          for (var index = 0; index < sectionItems.length; index++) ...[
            _LiveRecordRow(
              item: sectionItems[index],
              busy: _busyItems.contains(sectionItems[index].id),
              onOpen: _canOpen(sectionItems[index])
                  ? () => _open(sectionItems[index])
                  : null,
              trailing: _actionsFor(sectionItems[index]),
            ),
            if (index != sectionItems.length - 1) const Divider(height: 1),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContentPanel(
          key: const ValueKey('doctor-current-appointments-panel'),
          title: 'Current appointments',
          subtitle: updatedLabel,
          action: snapshot.items.length > 5
              ? SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search appointments',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                )
              : null,
          child: recordsOrEmpty(
            active,
            emptyTitle: 'No current appointments',
            emptyMessage: 'New and upcoming appointments will appear here.',
          ),
        ),
        const SizedBox(height: AppSpacing.x5),
        ContentPanel(
          key: const ValueKey('doctor-appointment-history-panel'),
          title: 'History',
          subtitle: history.isEmpty
              ? null
              : '${history.length} ${history.length == 1 ? 'record' : 'records'}',
          child: recordsOrEmpty(
            history,
            emptyTitle: 'No appointment history',
            emptyMessage:
                'Completed, cancelled, and declined appointments will appear here.',
          ),
        ),
        if (snapshot.hasMore && normalizedQuery.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.x4),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _loadingMore ? null : () => _loadMore(snapshot),
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(_loadingMore ? 'Loading...' : 'Load more'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPatientConsultationSections(List<WorkspaceItem> items) {
    final upcoming =
        items
            .where((item) => !_isPastConsultation(item))
            .toList(growable: false)
          ..sort(_compareUpcomingConsultations);
    final past = items.where(_isPastConsultation).toList(growable: false)
      ..sort(_comparePastConsultations);

    Widget section(String title, List<WorkspaceItem> sectionItems) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.x2),
        if (sectionItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
            child: Text(
              title == 'Upcoming'
                  ? 'No upcoming appointments.'
                  : 'No past appointments yet.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (var index = 0; index < sectionItems.length; index++) ...[
            _LiveRecordRow(
              item: sectionItems[index],
              busy: _busyItems.contains(sectionItems[index].id),
              onOpen: () => _open(sectionItems[index]),
              trailing: _actionsFor(sectionItems[index]),
            ),
            if (index != sectionItems.length - 1) const Divider(height: 1),
          ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('Upcoming', upcoming),
        const Divider(height: AppSpacing.x8),
        section('Past', past),
      ],
    );
  }

  Widget? _buildPatientQuickActions(WorkspaceItem item) {
    if (widget.role != UserRole.doctor ||
        item.kind != 'doctor_patient_assignments') {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Patient Actions',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: AppSpacing.x3),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = AppSpacing.x2;
            final availableWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 760.0;
            final columnCount = availableWidth >= 760
                ? 4
                : availableWidth >= 340
                ? 2
                : 1;
            final buttonWidth =
                (availableWidth - gap * (columnCount - 1)) / columnCount;

            Widget action({
              required IconData icon,
              required String label,
              required VoidCallback? onPressed,
            }) => SizedBox(
              width: buttonWidth,
              height: 48,
              child: FilledButton.icon(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: Icon(icon, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1),
                ),
              ),
            );

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                action(
                  icon: Icons.chat_bubble_outline,
                  label: 'Message Patient',
                  onPressed: _busyItems.contains(item.id)
                      ? null
                      : () => _messagePatient(item),
                ),
                action(
                  icon: Icons.folder_shared_outlined,
                  label: 'Add Record',
                  onPressed: _busyItems.contains(item.id)
                      ? null
                      : () => _recordPatientCheckup(item),
                ),
                action(
                  icon: Icons.medication_outlined,
                  label: 'Issue Prescription',
                  onPressed: _busyItems.contains('prescription-create')
                      ? null
                      : () => _createPrescription(item),
                ),
                action(
                  icon: Icons.upload_file_outlined,
                  label: 'Upload diagnostic result',
                  onPressed: _busyItems.contains(item.id)
                      ? null
                      : () => _uploadDoctorLaboratoryResult(item),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget? _buildDetailActions(WorkspaceItem item) {
    if (_isPatientConnectionRequest(item)) {
      return _ConnectionRequestCard(
        item: item,
        busy: _busyItems.contains(item.id),
        onAccept: widget.role == UserRole.patient
            ? () => _decidePatientConnectionRequest(item, approve: true)
            : null,
        onDecline: widget.role == UserRole.patient
            ? () => _decidePatientConnectionRequest(item, approve: false)
            : null,
      );
    }
    return _buildPatientQuickActions(item);
  }

  bool _canOpen(WorkspaceItem item) =>
      !_usesExplicitAdminTableActions &&
      widget.section != null &&
      widget.itemId == null &&
      item.id != 'record';

  bool get _usesExplicitAdminTableActions =>
      {
        UserRole.hospitalAdministrator,
        UserRole.superAdministrator,
      }.contains(widget.role) &&
      widget.section != null &&
      widget.itemId == null;

  void _open(WorkspaceItem item) {
    final section = widget.section;
    if (section == null) return;
    context.go(
      '${widget.role.homeLocation}/$section/${workspaceItemRouteId(item)}',
    );
  }

  Widget? _actionsFor(WorkspaceItem item) {
    final recordActions = _recordActionsFor(item);
    if (!_usesExplicitAdminTableActions) return recordActions;
    final canEdit = _canEditAdminRecord(item);
    final canDelete = _canDeleteAdminRecord(item);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Wrap(
        spacing: AppSpacing.x2,
        runSpacing: AppSpacing.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            key: ValueKey('view-record-${item.id}'),
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _showRecordDetails(item),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('View'),
          ),
          if (canEdit)
            OutlinedButton.icon(
              key: ValueKey('edit-record-${item.id}'),
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _editAdminRecord(item),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
          if (canDelete)
            TextButton.icon(
              key: ValueKey('delete-record-${item.id}'),
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _deleteManagedRecord(item),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.destructive,
              ),
            ),
          ?recordActions,
        ],
      ),
    );
  }

  bool _canEditAdminRecord(WorkspaceItem item) => const {
    'hospital_beds',
    'hospital_rooms',
    'emergency_room_status',
    'hospital_facility_status',
    'hospital_services',
    'hospital_departments',
    'hospitals',
    'users',
    'role_permissions',
    'system_settings',
    'maintenance_windows',
  }.contains(item.kind);

  bool _canDeleteAdminRecord(WorkspaceItem item) => const {
    'hospital_beds',
    'hospital_rooms',
    'emergency_room_status',
    'hospital_facility_status',
    'hospital_services',
    'hospital_departments',
    'hospitals',
    'role_permissions',
    'system_settings',
    'maintenance_windows',
  }.contains(item.kind);

  Future<void> _showRecordDetails(WorkspaceItem item) => showRootDialog<void>(
    builder: (context) =>
        _AdminRecordDetailsDialog(item: item, role: widget.role),
  );

  Widget? _recordActionsFor(WorkspaceItem item) {
    if (item.kind == 'notifications' && item.isUnread) {
      return TextButton(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _markNotificationRead(item),
        child: const Text('Mark read'),
      );
    }
    if (item.kind == 'medical_documents') {
      final canManage =
          widget.role == UserRole.patient &&
          item.data['is_current_user_upload'] == true;
      return Wrap(
        spacing: AppSpacing.x1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _downloadFile(item),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Download'),
          ),
          if (canManage) ...[
            IconButton(
              tooltip: 'Edit file title',
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _renameMedicalFile(item),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete file',
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _deleteMedicalFile(item),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      );
    }
    if (item.kind == 'consultations') {
      return _consultationActions(item);
    }
    if (item.kind == 'online_consultation_requests') {
      if (widget.role == UserRole.patient &&
          !{
            'completed',
            'rejected',
            'cancelled',
            'no_show',
            'in_progress',
          }.contains(item.status)) {
        return TextButton.icon(
          onPressed: _busyItems.contains(item.id)
              ? null
              : () => _cancelOnlineRequest(item),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Cancel request'),
        );
      }
      if (widget.role == UserRole.hospitalAdministrator &&
          {
            'submitted',
            'under_review',
            'more_information_required',
            'schedule_proposed',
          }.contains(item.status)) {
        return Wrap(
          spacing: AppSpacing.x2,
          children: [
            TextButton(
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _reviewOnlineRequest(item, approve: false),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _reviewOnlineRequest(item, approve: true),
              child: const Text('Confirm request'),
            ),
          ],
        );
      }
      return null;
    }
    if (widget.role == UserRole.doctor &&
        widget.section == 'patients' &&
        item.kind == 'doctor_patient_assignments') {
      if (widget.itemId != null) return null;
      return FilledButton.icon(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _recordPatientCheckup(item),
        icon: const Icon(Icons.monitor_heart_outlined, size: 18),
        label: const Text('Follow-up checkup'),
      );
    }
    if (item.kind == 'guest_consultation_requests' &&
        {'otp_verified', 'pending_doctor_review'}.contains(item.status)) {
      final assignedDoctor = item.data['assigned_doctor_id']?.toString();
      final canApprove =
          widget.role == UserRole.doctor ||
          widget.role == UserRole.hospitalAdministrator;
      return Wrap(
        spacing: AppSpacing.x2,
        children: [
          TextButton(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _reviewGuestRequest(item, approve: false),
            child: const Text('Reject'),
          ),
          Tooltip(
            message:
                widget.role == UserRole.hospitalAdministrator &&
                    (assignedDoctor == null || assignedDoctor.isEmpty)
                ? 'Choose an eligible doctor before approval'
                : canApprove
                ? 'Approve and schedule request'
                : 'This request is assigned to another doctor',
            child: FilledButton(
              onPressed: !canApprove || _busyItems.contains(item.id)
                  ? null
                  : () => _reviewGuestRequest(item, approve: true),
              child: const Text('Approve'),
            ),
          ),
        ],
      );
    }
    if (widget.role == UserRole.doctor &&
        widget.section == 'results-review' &&
        item.kind == 'laboratory_results') {
      return _laboratoryReviewActions(item);
    }
    if (item.kind == 'doctor_schedules') {
      final active = item.data['is_active'] == true;
      final reservedCount =
          int.tryParse(
            item.data['reserved_consultation_count']?.toString() ?? '',
          ) ??
          0;
      return Wrap(
        spacing: AppSpacing.x2,
        runSpacing: AppSpacing.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _setScheduleActive(item, !active),
            child: Text(active ? 'Unpublish' : 'Publish'),
          ),
          if (reservedCount == 0)
            IconButton(
              tooltip: 'Delete availability',
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _deleteScheduleSlot(item),
              icon: const Icon(Icons.delete_outline),
            )
          else
            Tooltip(
              message:
                  '$reservedCount appointment${reservedCount == 1 ? '' : 's'} use this availability; deletion is protected.',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Reserved'),
              ),
            ),
        ],
      );
    }
    if (widget.role == UserRole.doctor && item.kind == 'laboratory_requests') {
      return IconButton(
        tooltip: 'Cancel laboratory request',
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _deleteCareRecord(item),
        icon: const Icon(Icons.cancel_outlined),
      );
    }
    if (item.kind == 'maintenance_windows') {
      final active = item.data['is_active'] == true;
      return TextButton(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _setMaintenanceActive(item, !active),
        child: Text(active ? 'Deactivate' : 'Activate'),
      );
    }
    if (widget.role == UserRole.superAdministrator &&
        widget.section == 'approvals' &&
        item.kind == 'hospitals' &&
        (item.status?.contains('pending') ?? false)) {
      return Wrap(
        spacing: AppSpacing.x2,
        children: [
          TextButton(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _decideHospital(item, approve: false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _decideHospital(item, approve: true),
            child: const Text('Approve'),
          ),
        ],
      );
    }
    return null;
  }

  Widget? _consultationActions(WorkspaceItem item) {
    final status = item.status?.toLowerCase() ?? '';
    final online = item.subtitle.toLowerCase().contains('online');
    final appointmentDate = DateTime.tryParse(
      item.data['appointment_date']?.toString() ?? '',
    );
    final joinWindowOpen =
        appointmentDate != null &&
        isConsultationJoinWindowOpen(appointmentDate);
    final actions = <Widget>[];
    if (online && {'approved', 'scheduled', 'in_progress'}.contains(status)) {
      actions.add(
        Tooltip(
          message: joinWindowOpen
              ? 'Open the secure video room'
              : 'Available 15 minutes before the appointment',
          child: TextButton.icon(
            onPressed: _busyItems.contains(item.id) || !joinWindowOpen
                ? null
                : () => _joinConsultation(item),
            icon: const Icon(Icons.video_call_outlined, size: 18),
            label: const Text('Join'),
          ),
        ),
      );
    }
    if (widget.role == UserRole.patient &&
        {'pending', 'approved', 'scheduled'}.contains(status)) {
      final conversationId = item.data['conversation_id']?.toString();
      if (conversationId != null && conversationId.isNotEmpty) {
        actions.add(
          TextButton.icon(
            onPressed: () => context.go(
              '${widget.role.homeLocation}/messages/$conversationId',
            ),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Message doctor'),
          ),
        );
      }
      if ({'approved', 'scheduled'}.contains(status)) {
        actions.add(
          SizedBox(
            width: 112,
            height: 48,
            child: OutlinedButton(
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _rescheduleConsultation(item),
              child: const Text('Reschedule'),
            ),
          ),
        );
      }
      actions.add(
        SizedBox(
          width: 112,
          height: 48,
          child: OutlinedButton(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _cancelConsultation(item),
            child: const Text('Cancel'),
          ),
        ),
      );
    }
    if (widget.role == UserRole.doctor) {
      final nextStatus = switch (status) {
        'pending' => 'approved',
        'approved' || 'scheduled' => 'in_progress',
        'in_progress' => 'completed',
        _ => null,
      };
      if (nextStatus != null) {
        actions.add(
          FilledButton(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _advanceConsultation(item, nextStatus),
            child: Text(switch (nextStatus) {
              'approved' => 'Approve',
              'in_progress' => 'Start',
              _ => 'Complete',
            }),
          ),
        );
      }
    }
    return actions.isEmpty
        ? null
        : Wrap(spacing: AppSpacing.x2, children: actions);
  }

  Widget? _laboratoryReviewActions(WorkspaceItem item) {
    final status = item.status?.toLowerCase() ?? '';
    if ({
      'uploaded',
      'ocr_processing',
      'ai_analysis_pending',
    }.contains(status)) {
      return FilledButton.icon(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _analyzeMedicalResult(item),
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
        label: const Text('Analyze'),
      );
    }
    if (status == 'pending_doctor_review') {
      return Wrap(
        spacing: AppSpacing.x2,
        children: [
          TextButton(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _reviewMedicalResult(item, confirm: false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _reviewMedicalResult(item, confirm: true),
            child: const Text('Confirm'),
          ),
        ],
      );
    }
    return null;
  }

  Future<void> _markNotificationRead(WorkspaceItem item) => _runItemAction(
    item.id,
    () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final groupedIds = item.data['notification_ids'];
      final notificationIds = groupedIds is Iterable
          ? groupedIds
                .map((id) => id.toString().trim())
                .where((id) => id.isNotEmpty)
                .toSet()
          : {item.id};
      for (final notificationId in notificationIds) {
        await repository.markNotificationRead(notificationId);
      }
      ref.invalidate(careNotificationsProvider);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Notification marked as read.');
    },
  );

  Future<void> _decidePatientConnectionRequest(
    WorkspaceItem item, {
    required bool approve,
  }) async {
    final requestId =
        _connectionRequestData(
          item,
        )['connection_request_id']?.toString().trim() ??
        item.data['reference_id']?.toString().trim() ??
        '';
    if (requestId.isEmpty) {
      showRootMessage('This connection request is missing its reference.');
      return;
    }
    final confirmed = await confirmRootAction(
      title: approve ? 'Accept this connection?' : 'Decline this connection?',
      message: approve
          ? 'This gives the verified clinician access to the care information needed to support you for up to 90 days.'
          : 'The clinician will not be connected to your account. This will not affect your account or current care.',
      confirmLabel: approve ? 'Accept request' : 'Decline request',
      destructive: !approve,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.decidePatientConnectionRequest(
        requestId: requestId,
        approve: approve,
      );
      ref.invalidate(careNotificationsProvider);
      ref.invalidate(workspaceSnapshotProvider(_request));
      ref.invalidate(hospitalDirectoryProvider);
      showRootMessage(
        approve
            ? 'Connection accepted. The clinician can now support your care.'
            : 'Connection request declined.',
      );
    });
  }

  Future<void> _downloadFile(WorkspaceItem item) => _runItemAction(
    item.id,
    () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final url = await repository.createSignedFileUrl(item.id);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('The secure file link could not be opened.');
      }
    },
  );

  Future<void> _renameMedicalFile(WorkspaceItem item) async {
    final title = await showRootDialog<String>(
      barrierDismissible: false,
      builder: (context) =>
          _MedicalDocumentTitleDialog(initialValue: item.title),
    );
    if (title == null || title == item.title) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.renameOwnMedicalFile(fileId: item.id, title: title);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('File title updated.');
    });
  }

  Future<void> _deleteMedicalFile(WorkspaceItem item) async {
    final confirmed = await confirmRootAction(
      title: 'Delete ${item.title}?',
      message:
          'This permanently removes the file you uploaded. Doctor-uploaded files cannot be deleted by patients.',
      confirmLabel: 'Delete file',
      destructive: true,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.deleteOwnMedicalFile(fileId: item.id);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Uploaded file deleted.');
    });
  }

  Future<void> _createScheduleSlot() async {
    final value = await showRootDialog<_ScheduleDraft>(
      barrierDismissible: false,
      builder: (context) => const _ScheduleDialog(),
    );
    if (value == null) return;
    await _runItemAction('schedule-create', () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.createScheduleSlot(
        dayOfWeek: value.dayOfWeek,
        startsAt: value.startsAt,
        endsAt: value.endsAt,
        consultationType: value.consultationType,
        slotMinutes: value.slotMinutes,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      ref.invalidate(hospitalDirectoryProvider);
      showRootMessage('Schedule slot published.');
    });
  }

  Future<void> _setScheduleActive(WorkspaceItem item, bool active) async {
    final confirmed = await confirmRootAction(
      title: '${active ? 'Publish' : 'Unpublish'} schedule slot?',
      message:
          'This changes whether patients can see and use this recurring availability.',
      confirmLabel: active ? 'Publish slot' : 'Unpublish slot',
      destructive: !active,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.setScheduleActive(scheduleId: item.id, active: active);
      ref.invalidate(workspaceSnapshotProvider(_request));
      ref.invalidate(hospitalDirectoryProvider);
      showRootMessage('Schedule availability updated.');
    });
  }

  Future<void> _deleteScheduleSlot(WorkspaceItem item) async {
    final confirmed = await confirmRootAction(
      title: 'Delete availability?',
      message:
          'This permanently removes the recurring availability from your published schedule.',
      confirmLabel: 'Delete availability',
      destructive: true,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.deleteScheduleSlot(scheduleId: item.id);
      ref.invalidate(workspaceSnapshotProvider(_request));
      ref.invalidate(hospitalDirectoryProvider);
      showRootMessage('Schedule availability deleted.');
    });
  }

  Future<void> _createPrescription([
    WorkspaceItem? selectedPatient,
  ]) => _runItemAction('prescription-create', () async {
    final repository = ref.read(careRepositoryProvider);
    if (repository == null) throw StateError('Care service is unavailable.');
    final relationships = _relationshipsForPatient(
      await repository.listClinicalRelationships(),
      selectedPatient,
    );
    if (relationships.isEmpty) {
      throw StateError(
        selectedPatient == null
            ? 'No active doctor-patient relationship is available for prescribing.'
            : 'This patient is not currently assigned to you for prescribing.',
      );
    }
    PrescriberDetails? prescriber;
    try {
      prescriber = await repository.currentPrescriberDetails();
    } catch (_) {
      // The dialog still opens so the clinician can see which profile detail
      // must be completed before issuance.
    }
    final draft = await showRootDialog<_PrescriptionDraft>(
      barrierDismissible: false,
      builder: (context) => _PrescriptionDialog(
        relationships: relationships,
        repository: repository,
        prescriber: prescriber,
        showRelationshipField: selectedPatient == null,
      ),
    );
    if (draft == null) return;
    for (var index = 0; index < draft.medications.length; index++) {
      final medication = draft.medications[index];
      await repository.createPrescription(
        relationship: draft.relationship,
        medicationName: medication.medicationName,
        dosage: medication.exactDose,
        frequency: medication.frequency,
        duration: medication.duration,
        diagnosisReason: draft.diagnosisReason,
        medicationFormStrength: medication.medicationFormStrength,
        route: medication.route,
        exactDose: medication.exactDose,
        quantityToDispense: medication.quantityToDispense,
        refills: medication.refills,
        startDate: medication.startDate,
        endDate: medication.endDate,
        isPrn: medication.isPrn,
        prnReason: medication.prnReason,
        maximumDailyDose: medication.maximumDailyDose,
        instructions: medication.instructions,
        attachment: index == 0 ? draft.attachment : null,
      );
    }
    await repository.sendPrescriptionNotificationEmail(
      relationship: draft.relationship,
      medications: draft.medications
          .map(
            (m) => PrescriptionNotificationMedication(
              medicationName: m.medicationName,
              medicationFormStrength: m.medicationFormStrength,
              exactDose: m.exactDose,
              dosage: m.exactDose,
              frequency: m.frequency,
              duration: m.duration,
              quantityToDispense: m.quantityToDispense,
              refills: m.refills,
              instructions: m.instructions,
              isPrn: m.isPrn,
              prnReason: m.prnReason,
              startDate: m.startDate,
              endDate: m.endDate,
            ),
          )
          .toList(growable: false),
      diagnosisReason: draft.diagnosisReason,
    );
    ref.invalidate(workspaceSnapshotProvider(_request));
    final medicationCount = draft.medications.length;
    showRootMessage(
      draft.attachment == null
          ? '$medicationCount medication${medicationCount == 1 ? '' : 's'} issued to the selected patient. An email notification was sent.'
          : '$medicationCount medication${medicationCount == 1 ? '' : 's'} issued and emailed. The attachment and its AI summary status are available to the patient and care team.',
    );
  });

  Future<void> _emailDailyMedicationSchedule() => _runItemAction(
    'email-daily-reminders',
    () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.sendDailyMedicationReminderEmail();
      showRootMessage(
        'Your daily medication intake reminder schedule was sent to your email.',
      );
    },
  );

  Future<void> _createLaboratoryRequest() => _runItemAction(
    'laboratory-request-create',
    () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final relationships = (await repository.listClinicalRelationships())
          .where((relationship) => relationship.hasConsultation)
          .toList(growable: false);
      if (relationships.isEmpty) {
        throw StateError(
          'No active patient consultation is available for a laboratory request.',
        );
      }
      final draft = await showRootDialog<_LaboratoryRequestDraft>(
        barrierDismissible: false,
        builder: (context) =>
            _LaboratoryRequestDialog(relationships: relationships),
      );
      if (draft == null) return;
      await repository.createLaboratoryRequest(
        relationship: draft.relationship,
        testName: draft.testName,
        priority: draft.priority,
        instructions: draft.instructions,
        attachment: draft.attachment,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Laboratory request created for the selected patient.');
    },
  );

  Future<void> _uploadDoctorLaboratoryResult([
    WorkspaceItem? selectedPatient,
  ]) => _runItemAction(selectedPatient?.id ?? 'lab-result-upload', () async {
    final repository = ref.read(careRepositoryProvider);
    if (repository == null) throw StateError('Care service is unavailable.');
    final relationships = _relationshipsForPatient(
      await repository.listClinicalRelationships(),
      selectedPatient,
    );
    if (relationships.isEmpty) {
      throw StateError(
        selectedPatient == null
            ? 'No active doctor-patient relationship is available for a diagnostic result.'
            : 'This patient is not currently assigned to you for a diagnostic result.',
      );
    }
    final draft = await showRootDialog<_LaboratoryResultUploadDraft>(
      barrierDismissible: false,
      builder: (context) => _LaboratoryResultUploadDialog(
        relationships: relationships,
        repository: repository,
        showRelationshipField: selectedPatient == null,
      ),
    );
    if (draft == null) return;
    for (final report in draft.reports) {
      await repository.uploadMedicalFile(
        patientId: draft.relationship.patientId,
        fileName: report.attachment.name,
        title: report.testProcedureName,
        documentType: 'diagnostic_result',
        bytes: report.attachment.bytes,
        referenceId: draft.relationship.clinicalReferenceId,
        referenceType: draft.relationship.clinicalReferenceType,
        diagnosticResult: DiagnosticResultDetails(
          category: report.category,
          testProcedureName: report.testProcedureName,
          testProcedureNameAiGenerated: report.testProcedureNameAiGenerated,
          performedOrCollectedDate: report.performedOrCollectedDate,
          performedOrCollectedDateText: report.performedOrCollectedDateText,
          resultDate: report.resultDate,
          resultDateText: report.resultDateText,
          facility: report.facility,
          requestingDoctor: report.requestingDoctor,
          patientNameOnReport: report.patientNameOnReport,
          procedureDetails: report.procedureDetails,
          resultDetails: report.resultDetails,
          officialFindingsImpression: report.officialFindingsImpression,
          recommendations: report.recommendations,
          technicalSummary: report.technicalSummary,
          patientFriendlySummary: report.patientFriendlySummary,
          verificationNotes: report.verificationNotes,
          findingsImpression: report.officialFindingsImpression,
          notes: report.notes,
        ),
      );
    }
    ref.invalidate(workspaceSnapshotProvider(_request));
    showRootMessage(
      '${draft.reports.length} diagnostic ${draft.reports.length == 1 ? 'result' : 'results'} uploaded for ${draft.relationship.patientLabel}. AI-filled information was saved after review.',
    );
  });

  List<ClinicalRelationship> _relationshipsForPatient(
    List<ClinicalRelationship> relationships,
    WorkspaceItem? selectedPatient,
  ) {
    if (selectedPatient == null) return relationships;
    final patientId = selectedPatient.data['patient_id']?.toString() ?? '';
    final selectedPatientLabel =
        selectedPatient.data['patient_name']?.toString().trim() ?? '';
    return relationships
        .where((relationship) => relationship.patientId == patientId)
        .map(
          (relationship) => ClinicalRelationship(
            patientId: relationship.patientId,
            patientLabel: selectedPatientLabel.isEmpty
                ? selectedPatient.title
                : selectedPatientLabel,
            consultationId: relationship.consultationId,
            consultationLabel: relationship.consultationLabel,
            assignmentId: relationship.assignmentId,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _reserveConsultation({
    String? initialHospitalId,
    String? initialDoctorId,
  }) => _runItemAction('consultation-reserve', () async {
    await ref.read(hospitalDirectoryProvider.notifier).refresh();
    final directory = ref.read(hospitalDirectoryProvider);
    if (directory.errorMessage != null) {
      throw StateError(directory.errorMessage!);
    }
    final clinicians = <DoctorDirectoryEntry>[
      for (final hospital in directory.entries)
        for (final doctor in hospital.doctors)
          if (doctor.publishedConsultationTypes.isNotEmpty)
            DoctorDirectoryEntry(
              doctor: doctor,
              hospitalId: hospital.id,
              hospitalName: hospital.name,
              city: hospital.city,
              province: hospital.province,
              hospitalIsAvailable: hospital.isAvailable,
              hospitalImageUrl: hospital.imageUrl,
            ),
    ];
    if (clinicians.isEmpty) {
      throw StateError(
        'No clinician with published availability is available for reservations.',
      );
    }
    if (initialHospitalId != null &&
        !clinicians.any((entry) => entry.hospitalId == initialHospitalId)) {
      throw StateError(
        'No clinician with published availability is available at this hospital.',
      );
    }
    final repository = ref.read(consultationRepositoryProvider);
    if (repository == null) {
      throw StateError('Consultation service is unavailable.');
    }
    final profile = await ref.read(careProfileProvider.future);
    if (profile.mobileNumber?.trim().isEmpty ?? true) {
      throw StateError(
        'Add a registered phone number to your account profile before requesting care.',
      );
    }
    final draft = await showRootDialog<_ReservationDraft>(
      barrierDismissible: false,
      builder: (context) => _ReservationDialog(
        clinicians: clinicians,
        repository: repository,
        profile: profile,
        initialHospitalId: initialHospitalId,
        initialDoctorId: initialDoctorId,
      ),
    );
    if (draft == null) return;
    await repository.reserveConsultation(
      doctorId: draft.clinician.doctor.id,
      hospitalId: draft.clinician.hospitalId,
      consultationType: draft.consultationType,
      appointmentDate: draft.appointmentDate,
      chiefComplaint: draft.chiefComplaint,
      symptomDuration: draft.symptomDuration,
      sharedCategories: draft.sharedCategories,
    );
    ref.invalidate(workspaceSnapshotProvider(_request));
    showRootMessage(
      draft.consultationType == 'online'
          ? 'Online consultation request submitted for hospital review. The preferred slot is not reserved until confirmation.'
          : 'Face-to-face consultation reserved and pending approval.',
    );
  });

  Future<void> _joinConsultation(WorkspaceItem item) =>
      _runItemAction(item.id, () async {
        final repository = ref.read(consultationRepositoryProvider);
        if (repository == null) {
          throw StateError('Consultation service is unavailable.');
        }
        if (widget.role == UserRole.doctor) {
          await repository.ensureVideoRoom(item.id);
        }
        final url = await repository.getApprovedVideoRoom(item.id);
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw StateError('The approved video room could not be opened.');
        }
      });

  Future<void> _cancelConsultation(WorkspaceItem item) async {
    final confirmed = await confirmRootAction(
      title: 'Cancel consultation?',
      message:
          'This action updates the official consultation record and may notify the care team.',
      confirmLabel: 'Cancel consultation',
      destructive: true,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(consultationRepositoryProvider);
      if (repository == null) {
        throw StateError('Consultation service is unavailable.');
      }
      await repository.cancelConsultation(item.id);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Consultation cancelled.');
    });
  }

  Future<void> _rescheduleConsultation(WorkspaceItem item) async {
    final current = DateTime.tryParse(
      item.data['appointment_date']?.toString() ?? '',
    );
    final minimum = DateTime.now().add(reservationMinimumLeadTime);
    final selected = await requestRootDateTime(
      initial: current?.toLocal() ?? minimum.add(const Duration(days: 1)),
      minimum: minimum,
    );
    if (selected == null || selected == current?.toLocal()) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(consultationRepositoryProvider);
      if (repository == null) {
        throw StateError('Consultation service is unavailable.');
      }
      await repository.rescheduleConsultation(
        consultationId: item.id,
        scheduledFor: selected,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Consultation rescheduled.');
    });
  }

  Future<void> _advanceConsultation(
    WorkspaceItem item,
    String nextStatus,
  ) async {
    _ConsultationCompletionDraft? completion;
    if (nextStatus == 'completed') {
      completion = await showRootDialog<_ConsultationCompletionDraft>(
        barrierDismissible: false,
        builder: (context) => _ConsultationCompletionDialog(patient: item.data),
      );
      if (completion == null) return;
    } else {
      final confirmed = await confirmRootAction(
        title: nextStatus == 'approved'
            ? 'Approve consultation?'
            : 'Start consultation?',
        message:
            'This updates the official consultation lifecycle for the assigned patient.',
        confirmLabel: nextStatus == 'approved'
            ? 'Approve consultation'
            : 'Start consultation',
      );
      if (!confirmed) return;
    }
    await _runItemAction(item.id, () async {
      final repository = ref.read(consultationRepositoryProvider);
      if (repository == null) {
        throw StateError('Consultation service is unavailable.');
      }
      await repository.transitionConsultation(
        consultationId: item.id,
        status: nextStatus,
        notes: completion?.summary,
        clinicalPayload: completion == null
            ? const {}
            : {
                ...completion.checkup.toPayload(),
                'consultation_summary': completion.summary,
                'confirmed_diagnosis': completion.confirmedDiagnosis,
                'treatment_plan': completion.treatmentPlan,
                'doctor_notes': completion.doctorNotes,
              },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Consultation updated.');
    });
  }

  Future<void> _recordPatientCheckup(WorkspaceItem item) async {
    await _runItemAction(item.id, () async {
      final patientId = item.data['patient_id']?.toString() ?? '';
      if (patientId.isEmpty) {
        throw StateError('The selected patient is missing a clinical link.');
      }
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final draft =
          await showRootDialog<
            ({
              ClinicalCheckupDraft checkup,
              List<({List<int> bytes, String name})> attachments,
            })
          >(
            barrierDismissible: false,
            builder: (context) => _PatientCheckupDialog(
              patient: item.data,
              repository: repository,
            ),
          );
      if (draft == null) return;
      await repository.recordPatientCheckup(
        patientId: patientId,
        checkup: draft.checkup,
        attachments: draft.attachments,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Follow-up checkup recorded.');
    });
  }

  Future<void> _messagePatient(WorkspaceItem item) async {
    await _runItemAction(item.id, () async {
      final patientId = item.data['patient_id']?.toString() ?? '';
      if (patientId.isEmpty) {
        throw StateError('The selected patient is missing a clinical link.');
      }
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final existingConversationId =
          item.data['conversation_id']?.toString() ?? '';
      final conversationId = existingConversationId.isNotEmpty
          ? existingConversationId
          : await repository.ensurePatientConversation(patientId);
      ref.invalidate(
        workspaceSnapshotProvider((
          role: widget.role,
          section: 'messages',
          itemId: null,
        )),
      );
      if (!mounted) return;
      context.go('${widget.role.homeLocation}/messages/$conversationId');
    });
  }

  Future<void> _analyzeMedicalResult(WorkspaceItem item) async {
    final confirmed = await confirmRootAction(
      title: 'Run preliminary analysis?',
      message:
          'Groq will generate preliminary assistance from this private result. It remains non-diagnostic until a licensed doctor reviews it.',
      confirmLabel: 'Start analysis',
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.analyzeMedicalResult(item.id);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Preliminary analysis is ready for doctor review.');
    });
  }

  Future<void> _reviewMedicalResult(
    WorkspaceItem item, {
    required bool confirm,
  }) async {
    final note = await requestDecisionNote(
      title: confirm ? 'Confirm medical result' : 'Reject preliminary result',
      message: confirm
          ? 'Enter your licensed clinical findings. Confirmation may create an official patient record.'
          : 'Explain why the preliminary result must not become an official record.',
      confirmLabel: confirm ? 'Confirm findings' : 'Reject result',
      destructive: !confirm,
      minimumLength: 10,
    );
    if (note == null) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      if (confirm) {
        await repository.confirmMedicalResult(
          resultId: item.id,
          findings: note,
        );
      } else {
        await repository.rejectMedicalResult(resultId: item.id, reason: note);
      }
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage(
        confirm ? 'Medical result confirmed.' : 'Preliminary result rejected.',
      );
    });
  }

  Future<void> _cancelOnlineRequest(WorkspaceItem item) async {
    final reason = await requestDecisionNote(
      title: 'Cancel online consultation request',
      message:
          'The preferred slot is released if the hospital already confirmed it. Give the care team a brief reason.',
      confirmLabel: 'Cancel request',
      destructive: true,
    );
    if (reason == null) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(consultationRepositoryProvider);
      if (repository == null) {
        throw StateError('Consultation service is unavailable.');
      }
      await repository.cancelOnlineRequest(requestId: item.id, reason: reason);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Online consultation request cancelled.');
    });
  }

  Future<void> _reviewOnlineRequest(
    WorkspaceItem item, {
    required bool approve,
  }) async {
    String? notes;
    String? selectedDoctorId;
    DateTime? confirmedSchedule;
    String? channel;

    if (!approve) {
      notes = await requestDecisionNote(
        title: 'Reject online consultation request',
        message:
            'Explain why the hospital cannot accept this request so the patient can choose the next step.',
        confirmLabel: 'Reject request',
        destructive: true,
      );
      if (notes == null) return;
    } else {
      try {
        final repository = ref.read(consultationRepositoryProvider);
        if (repository == null) {
          throw StateError('Consultation service is unavailable.');
        }
        final hospitalId = item.data['hospital_id']?.toString();
        if (hospitalId == null || hospitalId.isEmpty) {
          throw StateError('The request is missing its receiving hospital.');
        }
        final doctors = await repository.listGuestReviewDoctors(
          hospitalId: hospitalId,
          departmentId: item.data['requested_department_id']?.toString(),
        );
        if (doctors.isEmpty) {
          throw StateError(
            'No verified doctor is available for this hospital and department.',
          );
        }
        final currentDoctorId =
            item.data['assigned_doctor_id']?.toString() ??
            item.data['requested_doctor_id']?.toString();
        final matchingDoctors = doctors.where(
          (doctor) => doctor.id == currentDoctorId,
        );
        GuestReviewDoctor? selectedDoctor = matchingDoctors.isEmpty
            ? null
            : matchingDoctors.first;
        selectedDoctor ??= await showRootDialog<GuestReviewDoctor>(
          barrierDismissible: false,
          builder: (context) => _GuestDoctorSelectionDialog(doctors: doctors),
        );
        if (selectedDoctor == null) return;
        selectedDoctorId = selectedDoctor.id;

        final proposed = DateTime.tryParse(
          item.data['proposed_schedule']?.toString() ??
              item.data['preferred_schedule']?.toString() ??
              '',
        );
        if (proposed == null) {
          throw StateError('The request is missing a preferred schedule.');
        }
        final minimum = DateTime.now().add(reservationMinimumLeadTime);
        confirmedSchedule = await requestRootDateTime(
          initial: proposed.toLocal(),
          minimum: minimum,
        );
        if (confirmedSchedule == null) return;

        channel = await showRootDialog<String>(
          barrierDismissible: false,
          builder: (context) => SimpleDialog(
            title: const Text('Confirm consultation channel'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop('call'),
                child: const ListTile(
                  leading: Icon(Icons.call_outlined),
                  title: Text('Phone call'),
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop('email'),
                child: const ListTile(
                  leading: Icon(Icons.email_outlined),
                  title: Text('Email'),
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop('video'),
                child: const ListTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text('Video'),
                ),
              ),
            ],
          ),
        );
        if (channel == null) return;
        final confirmed = await confirmRootAction(
          title: 'Confirm online consultation?',
          message:
              'The hospital will create the official appointment only after rechecking this doctor and time.',
          confirmLabel: 'Confirm appointment',
        );
        if (!confirmed) return;
      } catch (error) {
        showRootMessage(_friendlyError(error));
        return;
      }
    }

    await _runItemAction(item.id, () async {
      final repository = ref.read(consultationRepositoryProvider);
      if (repository == null) {
        throw StateError('Consultation service is unavailable.');
      }
      await repository.reviewOnlineRequest(
        requestId: item.id,
        decision: approve ? 'confirmed' : 'rejected',
        doctorId: selectedDoctorId,
        confirmedSchedule: confirmedSchedule,
        channel: channel,
        notes: notes,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage(
        approve
            ? 'Online request confirmed and official appointment created.'
            : 'Online consultation request rejected.',
      );
    });
  }

  Future<void> _reviewGuestRequest(
    WorkspaceItem item, {
    required bool approve,
  }) async {
    String? notes;
    if (approve) {
      final confirmed = await confirmRootAction(
        title: 'Approve guest consultation?',
        message:
            'This creates the temporary patient relationship and schedules the preferred authorized doctor slot.',
        confirmLabel: 'Approve and schedule',
      );
      if (!confirmed) return;
    } else {
      notes = await requestDecisionNote(
        title: 'Reject guest consultation',
        message: 'Explain why this request cannot proceed.',
        confirmLabel: 'Reject request',
        destructive: true,
      );
      if (notes == null) return;
    }
    final preferred = DateTime.tryParse(
      item.data['preferred_schedule']?.toString() ?? '',
    );
    if (approve && preferred == null) {
      showRootMessage('Choose a valid appointment time before approval.');
      return;
    }
    if (approve &&
        preferred!.isBefore(DateTime.now().add(reservationMinimumLeadTime))) {
      showRootMessage(
        'Guest consultations must be scheduled at least 24 hours in advance.',
      );
      return;
    }
    var selectedDoctorId = item.data['assigned_doctor_id']?.toString();
    if (approve &&
        widget.role == UserRole.hospitalAdministrator &&
        (selectedDoctorId == null || selectedDoctorId.isEmpty)) {
      try {
        final repository = ref.read(consultationRepositoryProvider);
        if (repository == null) {
          throw StateError('Consultation service is unavailable.');
        }
        final hospitalId = item.data['preferred_hospital_id']?.toString();
        if (hospitalId == null || hospitalId.isEmpty) {
          throw StateError('The request is missing its preferred hospital.');
        }
        final doctors = await repository.listGuestReviewDoctors(
          hospitalId: hospitalId,
          departmentId: item.data['preferred_department_id']?.toString(),
        );
        if (doctors.isEmpty) {
          throw StateError(
            'No eligible doctor is available for this hospital and department.',
          );
        }
        final selected = await showRootDialog<GuestReviewDoctor>(
          barrierDismissible: false,
          builder: (context) => _GuestDoctorSelectionDialog(doctors: doctors),
        );
        if (selected == null) return;
        selectedDoctorId = selected.id;
      } catch (error) {
        showRootMessage(_friendlyError(error));
        return;
      }
    }
    await _runItemAction(item.id, () async {
      final repository = ref.read(consultationRepositoryProvider);
      if (repository == null) {
        throw StateError('Consultation service is unavailable.');
      }
      await repository.reviewGuestRequest(
        requestId: item.id,
        decision: approve ? 'approved' : 'rejected',
        doctorId: widget.role == UserRole.hospitalAdministrator
            ? selectedDoctorId
            : null,
        appointmentDate: approve ? preferred : null,
        notes: notes,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage(
        approve
            ? 'Guest consultation approved and scheduled.'
            : 'Guest consultation rejected.',
      );
    });
  }

  Future<void> _decideHospital(
    WorkspaceItem item, {
    required bool approve,
  }) async {
    String reason = 'Verified against the submitted hospital information.';
    if (approve) {
      final confirmed = await confirmRootAction(
        title: 'Approve hospital?',
        message:
            'This makes the hospital eligible for the public directory. Confirm that its submitted information has been reviewed.',
        confirmLabel: 'Approve hospital',
      );
      if (!confirmed) return;
    } else {
      final note = await requestDecisionNote(
        title: 'Reject hospital application',
        message:
            'Give the hospital team a clear reason for this governance decision.',
        confirmLabel: 'Reject application',
        destructive: true,
      );
      if (note == null) return;
      reason = note;
    }
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      if (approve) {
        await repository.approveHospital(item.id);
      } else {
        await repository.rejectHospital(hospitalId: item.id, reason: reason);
      }
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage(
        approve ? 'Hospital approved.' : 'Hospital application rejected.',
      );
    });
  }

  Future<void> _editAdminRecord(WorkspaceItem item) async {
    switch (item.kind) {
      case 'hospital_beds':
      case 'hospital_rooms':
        await _editCapacity(item);
        return;
      case 'emergency_room_status':
        await _editEmergencyCapacity(item);
        return;
      case 'hospital_services':
      case 'hospital_departments':
        await _editNamedOperationalRecord(item);
        return;
      case 'hospital_facility_status':
        await _editFacilityStatus(item);
        return;
      case 'users':
        await _editAccountRecord(item);
        return;
      case 'role_permissions':
        await _editPermissionRecord(item);
        return;
      case 'system_settings':
        await _editSystemSetting(item);
        return;
      case 'maintenance_windows':
        await _editMaintenanceWindow(item);
        return;
      case 'hospitals':
        await _editHospitalRecord(item);
        return;
    }
  }

  Future<void> _editAccountRecord(WorkspaceItem item) async {
    final isHospitalDoctor =
        widget.role == UserRole.hospitalAdministrator &&
        (item.data['display_name']?.toString().trim().isNotEmpty ?? false);
    final action = await showRootDialog<String>(
      builder: (context) => SimpleDialog(
        title: Text('Edit ${item.title}'),
        children: [
          for (final status in const ['active', 'inactive', 'suspended'])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(status),
              child: ListTile(
                leading: Icon(_statusIcon(status)),
                title: Text('Set status to ${_statusLabel(status)}'),
                trailing: item.status == status
                    ? const Icon(Icons.check)
                    : null,
              ),
            ),
          if (isHospitalDoctor)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('department'),
              child: const ListTile(
                leading: Icon(Icons.account_tree_outlined),
                title: Text('Change department'),
              ),
            ),
        ],
      ),
    );
    if (action == null) return;
    if (action == 'department') {
      await _changeDoctorDepartment(item);
    } else {
      await _updateAccountStatus(item, action);
    }
  }

  Future<void> _editPermissionRecord(WorkspaceItem item) async {
    final allowed = await showRootDialog<bool>(
      builder: (context) => SimpleDialog(
        title: Text('Edit ${item.title}'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(true),
            child: const ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Allow permission'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(false),
            child: const ListTile(
              leading: Icon(Icons.block_outlined),
              title: Text('Deny permission'),
            ),
          ),
        ],
      ),
    );
    if (allowed != null && allowed != (item.data['is_allowed'] == true)) {
      await _updatePermission(item, allowed);
    }
  }

  Future<void> _editNamedOperationalRecord(WorkspaceItem item) async {
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) throw StateError('Admin service is unavailable.');
    final isService = item.kind == 'hospital_services';
    final adminContext = isService
        ? await repository.loadHospitalAdminContext()
        : null;
    final draft = await showRootDialog<_NamedRecordDraft>(
      barrierDismissible: false,
      builder: (context) => _NamedRecordDialog(
        title: 'Edit ${isService ? 'service' : 'department'}',
        nameLabel: isService ? 'Service name' : 'Department name',
        confirmLabel: 'Save changes',
        initialName: item.title,
        initialDescription: item.data['description']?.toString() ?? '',
        initialDepartmentId: item.data['department_id']?.toString(),
        initialStatus:
            item.data['availability_status']?.toString() ?? item.status,
        departments: adminContext?.departments ?? const [],
      ),
    );
    if (draft == null) return;
    await _runItemAction(item.id, () async {
      await repository.updateOperationalRecord(
        table: item.kind,
        recordId: item.id,
        changes: isService
            ? {
                'service_name': draft.name,
                'description': draft.description,
                'department_id': draft.departmentId,
                if (draft.status != null) 'availability_status': draft.status,
              }
            : {
                'department_name': draft.name,
                'description': draft.description,
                if (draft.status != null) 'availability_status': draft.status,
              },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      await ref.read(hospitalDirectoryProvider.notifier).refresh();
      showRootMessage('${isService ? 'Service' : 'Department'} updated.');
    });
  }

  Future<void> _editFacilityStatus(WorkspaceItem item) async {
    final draft = await showRootDialog<_FacilityStatusDraft>(
      barrierDismissible: false,
      builder: (context) => _FacilityStatusDialog(item: item),
    );
    if (draft == null) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.updateOperationalRecord(
        table: 'hospital_facility_status',
        recordId: item.id,
        changes: {
          'status': draft.status,
          'available_units': draft.availableUnits,
          'notes': draft.notes,
        },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      await ref.read(hospitalDirectoryProvider.notifier).refresh();
      showRootMessage('Facility status updated.');
    });
  }

  Future<void> _editHospitalRecord(WorkspaceItem item) async {
    final draft = await showRootDialog<_HospitalRecordDraft>(
      barrierDismissible: false,
      builder: (context) => _HospitalRecordDialog(item: item),
    );
    if (draft == null) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.updateManagedRecord(
        table: 'hospitals',
        recordId: item.id,
        changes: draft.toValues(includeVerification: false),
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      await ref.read(hospitalDirectoryProvider.notifier).refresh();
      showRootMessage('Hospital information updated.');
    });
  }

  Future<void> _editMaintenanceWindow(WorkspaceItem item) async {
    final draft = await showRootDialog<_MaintenanceCopyDraft>(
      barrierDismissible: false,
      builder: (context) => _MaintenanceCopyDialog(
        title: 'Edit maintenance window',
        confirmLabel: 'Continue',
        initialTitle: item.title,
        initialMessage: item.data['message']?.toString() ?? item.subtitle,
      ),
    );
    if (draft == null) return;
    final currentStart = DateTime.tryParse(
      item.data['starts_at']?.toString() ?? '',
    );
    final startsAt = await requestRootDateTime(
      initial: currentStart ?? DateTime.now().add(const Duration(hours: 1)),
    );
    if (startsAt == null) return;
    final currentEnd = DateTime.tryParse(
      item.data['ends_at']?.toString() ?? '',
    );
    final endsAt = await requestRootDateTime(
      initial: currentEnd ?? startsAt.add(const Duration(hours: 1)),
    );
    if (endsAt == null) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.updateManagedRecord(
        table: 'maintenance_windows',
        recordId: item.id,
        changes: {
          'title': draft.title,
          'message': draft.message,
          'starts_at': startsAt.toUtc().toIso8601String(),
          'ends_at': endsAt.toUtc().toIso8601String(),
          'is_active': item.data['is_active'] == true,
        },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Maintenance window updated.');
    });
  }

  Future<void> _updateAccountStatus(WorkspaceItem item, String status) async {
    if (item.status == status) return;
    final confirmed = await confirmRootAction(
      title: 'Change account status?',
      message:
          'This will mark ${item.title} as ${_statusLabel(status)} and update authentication access through the protected admin workflow.',
      confirmLabel: 'Update account',
      destructive: status != 'active',
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.updateAccountStatus(userId: item.id, status: status);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Account status updated.');
    });
  }

  Future<void> _editCapacity(WorkspaceItem item) async {
    final isBed = item.kind == 'hospital_beds';
    final currentTotal = _intValue(
      item.data[isBed ? 'total_beds' : 'total_rooms'],
    );
    final currentAvailable = _intValue(
      item.data[isBed ? 'available_beds' : 'available_rooms'],
    );
    final values = await showRootDialog<({int total, int available})>(
      barrierDismissible: false,
      builder: (context) => _CapacityDialog(
        resourceLabel: item.title,
        initialTotal: currentTotal,
        initialAvailable: currentAvailable,
      ),
    );
    if (values == null) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.updateOperationalRecord(
        table: item.kind,
        recordId: item.id,
        changes: isBed
            ? {
                'total_beds': values.total,
                'available_beds': values.available,
                'occupied_beds': values.total - values.available,
              }
            : {
                'total_rooms': values.total,
                'available_rooms': values.available,
                'occupied_rooms': values.total - values.available,
                'status': values.available == 0
                    ? 'unavailable'
                    : values.available < values.total
                    ? 'limited'
                    : 'available',
              },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      ref.invalidate(hospitalDirectoryProvider);
      showRootMessage('${item.title} capacity updated.');
    });
  }

  Future<void> _editEmergencyCapacity(WorkspaceItem item) async {
    final total = _intValue(item.data['maximum_capacity']);
    final available = _intValue(item.data['available_beds']);
    final publishedOccupied = item.data['occupied_beds'];
    final inferredOccupied = (total - available).clamp(0, total);
    final values = await showRootDialog<_EmergencyCapacityDraft>(
      barrierDismissible: false,
      builder: (context) => _EmergencyCapacityDialog(
        initialTotal: total,
        initialOccupied: publishedOccupied == null
            ? inferredOccupied
            : _intValue(publishedOccupied),
        initialClosedOrUnstaffed: _intValue(
          item.data['closed_or_unstaffed_beds'],
        ),
        initialReserved: _intValue(item.data['reserved_beds']),
        initialPatientCount: _intValue(item.data['current_patient_count']),
        initialStatusOverride: item.data['status_override']?.toString(),
        initialOverrideReason: item.data['override_reason']?.toString(),
      ),
    );
    if (values == null) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.updateEmergencyCapacity(
        recordId: item.id,
        totalCapacity: values.total,
        occupiedCapacity: values.occupied,
        closedOrUnstaffedCapacity: values.closedOrUnstaffed,
        reservedCapacity: values.reserved,
        currentPatientCount: values.currentPatients,
        statusOverride: values.statusOverride,
        overrideReason: values.overrideReason,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      ref.invalidate(hospitalDirectoryProvider);
      showRootMessage(
        'Emergency capacity confirmed. The public timestamp has been refreshed.',
      );
    });
  }

  Future<void> _updatePermission(WorkspaceItem item, bool allowed) async {
    final confirmed = await confirmRootAction(
      title: '${allowed ? 'Allow' : 'Deny'} permission?',
      message:
          'This changes the live role permission “${item.title}” for all affected accounts.',
      confirmLabel: allowed ? 'Allow permission' : 'Deny permission',
      destructive: !allowed,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.updatePermission(
        permissionId: item.id,
        allowed: allowed,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Role permission updated.');
    });
  }

  Future<void> _editSystemSetting(WorkspaceItem item) async {
    final current = item.data['value'];
    Object? nextValue;
    if (current is bool) {
      final confirmed = await confirmRootAction(
        title: '${current ? 'Disable' : 'Enable'} setting?',
        message:
            'This changes the live platform setting “${item.title}” for affected users.',
        confirmLabel: current ? 'Disable setting' : 'Enable setting',
        destructive: current,
      );
      if (!confirmed) return;
      nextValue = !current;
    } else {
      nextValue = await showRootDialog<String>(
        barrierDismissible: false,
        builder: (context) => _TextValueDialog(
          title: 'Edit ${item.title}',
          initialValue: current?.toString() ?? '',
        ),
      );
      if (nextValue == null) return;
    }
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.updateSystemSetting(key: item.id, value: nextValue!);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Platform setting updated.');
    });
  }

  Future<void> _setMaintenanceActive(WorkspaceItem item, bool active) async {
    final confirmed = await confirmRootAction(
      title: '${active ? 'Activate' : 'Deactivate'} maintenance window?',
      message:
          'This changes the live maintenance notice “${item.title}” for the platform.',
      confirmLabel: active ? 'Activate window' : 'Deactivate window',
      destructive: active,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.setMaintenanceActive(
        maintenanceId: item.id,
        active: active,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Maintenance window updated.');
    });
  }

  Future<void> _createDoctorAccount() => _runItemAction(
    'doctor-account-create',
    () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      final adminContext = await repository.loadHospitalAdminContext();
      if (adminContext.departments.isEmpty) {
        throw StateError(
          'Add at least one hospital department before creating a doctor.',
        );
      }
      final draft = await showRootDialog<_DoctorAccountDraft>(
        barrierDismissible: false,
        builder: (context) => _DoctorAccountDialog(context: adminContext),
      );
      if (draft == null) return;
      try {
        await repository.createDoctorAccount(
          hospitalId: adminContext.hospitalId,
          firstName: draft.firstName,
          lastName: draft.lastName,
          email: draft.email,
          temporaryPassword: draft.temporaryPassword,
          specialization: draft.specialization,
          licenseNumber: draft.licenseNumber,
          departmentId: draft.departmentId,
          consultationFee: draft.consultationFee,
          biography: draft.biography,
          profileImageBytes: draft.profileImageBytes,
          profileImageFileName: draft.profileImageFileName,
        );
      } on AdminMutationPartialSuccess catch (error) {
        ref.invalidate(workspaceSnapshotProvider(_request));
        ref.invalidate(hospitalDirectoryProvider);
        showRootMessage(error.message);
        return;
      }
      ref.invalidate(workspaceSnapshotProvider(_request));
      ref.invalidate(hospitalDirectoryProvider);
      showRootMessage('Doctor account created for the assigned hospital.');
    },
  );

  Future<void> _changeDoctorDepartment(WorkspaceItem item) async {
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      final adminContext = await repository.loadHospitalAdminContext();
      if (adminContext.departments.isEmpty) {
        throw StateError(
          'Add at least one hospital department before assigning a doctor.',
        );
      }
      final departmentId = await showRootDialog<String>(
        barrierDismissible: false,
        builder: (context) => _DoctorDepartmentDialog(
          doctorName: item.data['display_name']?.toString() ?? item.title,
          departments: adminContext.departments,
          currentDepartmentId: item.data['department_id']?.toString(),
        ),
      );
      if (departmentId == null) return;
      await repository.updateDoctorDepartment(
        userId: item.id,
        departmentId: departmentId,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Doctor department updated.');
    });
  }

  Future<void> _createPatientAccount() => _runItemAction(
    'patient-account-create',
    () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final draft = await showRootDialog<_PatientAccountDraft>(
        barrierDismissible: false,
        builder: (context) => _PatientAccountDialog(
          searchPatients: repository.searchExistingPatients,
        ),
      );
      if (draft == null) return;

      if (draft.isExistingAccount) {
        await repository.linkExistingPatient(draft.patientId);
        ref.invalidate(workspaceSnapshotProvider(_request));
        showRootMessage('Connection request sent to the existing patient.');
      } else {
        await repository.createPatientAccount(
          firstName: draft.firstName,
          lastName: draft.lastName,
          birthDate: draft.birthDate!,
          sex: draft.sex,
          mobileNumber: draft.mobileNumber,
          email: draft.email,
          address: draft.address,
          password: draft.password,
        );
        ref.invalidate(workspaceSnapshotProvider(_request));
        showRootMessage(
          'Patient account registered with standard identity details.',
        );
      }
    },
  );

  Future<void> _createCapacityRecord({required bool beds}) => _runItemAction(
    beds ? 'hospital-bed-create' : 'hospital-room-create',
    () async {
      final draft = await showRootDialog<_CapacityResourceDraft>(
        barrierDismissible: false,
        builder: (context) => _CapacityResourceDialog(beds: beds),
      );
      if (draft == null) return;
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.createManagedRecord(
        table: beds ? 'hospital_beds' : 'hospital_rooms',
        values: beds
            ? {
                'bed_type': draft.type,
                'total_beds': draft.total,
                'available_beds': draft.available,
                'occupied_beds': draft.total - draft.available,
              }
            : {
                'room_type': draft.type,
                'total_rooms': draft.total,
                'available_rooms': draft.available,
                'occupied_rooms': draft.total - draft.available,
                'status': draft.available == 0
                    ? 'unavailable'
                    : draft.available < draft.total
                    ? 'limited'
                    : 'available',
              },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      ref.invalidate(hospitalDirectoryProvider);
      showRootMessage('${beds ? 'Bed' : 'Room'} type added.');
    },
  );

  Future<void> _createFacilityStatus(List<WorkspaceItem> items) =>
      _runItemAction('facility-status-create', () async {
        final facilityTypes = _missingFacilityTypes(items);
        if (facilityTypes.isEmpty) {
          showRootMessage('All supported facility types are already listed.');
          return;
        }
        final draft = await showRootDialog<_FacilityStatusDraft>(
          barrierDismissible: false,
          builder: (context) =>
              _FacilityStatusDialog(facilityTypes: facilityTypes),
        );
        if (draft == null) return;
        final repository = ref.read(adminRepositoryProvider);
        if (repository == null) {
          throw StateError('Admin service is unavailable.');
        }
        await repository.createManagedRecord(
          table: 'hospital_facility_status',
          values: {
            'facility_type': draft.facilityType,
            'status': draft.status,
            'available_units': draft.availableUnits,
            'notes': draft.notes,
          },
        );
        ref.invalidate(workspaceSnapshotProvider(_request));
        await ref.read(hospitalDirectoryProvider.notifier).refresh();
        showRootMessage('Facility status added.');
      });

  Future<void> _createEmergencyRoomRecord() => _runItemAction(
    'emergency-room-create',
    () async {
      final draft = await showRootDialog<_EmergencyCapacityDraft>(
        barrierDismissible: false,
        builder: (context) => const _EmergencyCapacityDialog(
          initialTotal: 0,
          initialOccupied: 0,
          initialClosedOrUnstaffed: 0,
          initialReserved: 0,
          initialPatientCount: 0,
        ),
      );
      if (draft == null) return;
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      final available =
          draft.total -
          draft.occupied -
          draft.closedOrUnstaffed -
          draft.reserved;
      await repository.createManagedRecord(
        table: 'emergency_room_status',
        values: {
          'status':
              draft.statusOverride ??
              (available == 0
                  ? 'full'
                  : available * 5 <= draft.total
                  ? 'limited'
                  : 'available'),
          'maximum_capacity': draft.total,
          'available_beds': available,
          'occupied_beds': draft.occupied,
          'closed_or_unstaffed_beds': draft.closedOrUnstaffed,
          'reserved_beds': draft.reserved,
          'current_patient_count': draft.currentPatients,
        },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      ref.invalidate(hospitalDirectoryProvider);
      showRootMessage('Emergency capacity record added.');
    },
  );

  Future<void> _createHospitalRecord() => _runItemAction(
    'hospital-create',
    () async {
      final draft = await showRootDialog<_HospitalRecordDraft>(
        barrierDismissible: false,
        builder: (context) => const _HospitalRecordDialog(),
      );
      if (draft == null) return;
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.createManagedRecord(
        table: 'hospitals',
        values: draft.toValues(includeVerification: true),
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      await ref.read(hospitalDirectoryProvider.notifier).refresh();
      showRootMessage('Hospital record added for review.');
    },
  );

  Future<void> _createPermissionRecord() => _runItemAction(
    'permission-create',
    () async {
      final draft = await showRootDialog<_PermissionRecordDraft>(
        barrierDismissible: false,
        builder: (context) => const _PermissionRecordDialog(),
      );
      if (draft == null) return;
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.createManagedRecord(
        table: 'role_permissions',
        values: {
          'role_id': draft.roleId,
          'permission': draft.permission,
          'is_allowed': draft.allowed,
        },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Role permission added.');
    },
  );

  Future<void> _createSystemSettingRecord() => _runItemAction(
    'setting-create',
    () async {
      final draft = await showRootDialog<_SystemSettingRecordDraft>(
        barrierDismissible: false,
        builder: (context) => const _SystemSettingRecordDialog(),
      );
      if (draft == null) return;
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.createManagedRecord(
        table: 'system_settings',
        values: {
          'key': draft.key,
          'value': draft.value,
          'description': draft.description,
          'is_public': draft.isPublic,
        },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('System setting added.');
    },
  );

  Future<void> _createHospitalDepartment() => _runItemAction(
    'hospital-department-create',
    () async {
      final draft = await showRootDialog<_NamedRecordDraft>(
        barrierDismissible: false,
        builder: (context) => const _NamedRecordDialog(
          title: 'Add department',
          nameLabel: 'Department name',
          confirmLabel: 'Add department',
        ),
      );
      if (draft == null) return;
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.createHospitalDepartment(
        name: draft.name,
        description: draft.description,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      await ref.read(hospitalDirectoryProvider.notifier).refresh();
      showRootMessage('Hospital department added.');
    },
  );

  Future<void> _createHospitalService() => _runItemAction(
    'hospital-service-create',
    () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      final adminContext = await repository.loadHospitalAdminContext();
      final draft = await showRootDialog<_NamedRecordDraft>(
        barrierDismissible: false,
        builder: (context) => _NamedRecordDialog(
          title: 'Add service',
          nameLabel: 'Service name',
          confirmLabel: 'Add service',
          departments: adminContext.departments,
        ),
      );
      if (draft == null) return;
      await repository.createHospitalService(
        name: draft.name,
        description: draft.description,
        departmentId: draft.departmentId,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      await ref.read(hospitalDirectoryProvider.notifier).refresh();
      showRootMessage('Hospital service added.');
    },
  );

  Future<void> _createMaintenanceWindow() => _runItemAction(
    'maintenance-create',
    () async {
      final draft = await showRootDialog<_MaintenanceCopyDraft>(
        barrierDismissible: false,
        builder: (context) => const _MaintenanceCopyDialog(),
      );
      if (draft == null) return;
      final startsAt = await requestRootDateTime(
        initial: DateTime.now().add(const Duration(hours: 1)),
      );
      if (startsAt == null) return;
      final endsAt = await requestRootDateTime(
        initial: startsAt.add(const Duration(hours: 1)),
      );
      if (endsAt == null) return;
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.createMaintenanceWindow(
        title: draft.title,
        message: draft.message,
        startsAt: startsAt,
        endsAt: endsAt,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Maintenance window scheduled.');
    },
  );

  Future<void> _deleteManagedRecord(WorkspaceItem item) async {
    final confirmed = await confirmRootAction(
      title: 'Delete ${item.title}?',
      message:
          'This permanently removes the selected managed record. Related records may prevent deletion.',
      confirmLabel: 'Delete record',
      destructive: true,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.deleteManagedRecord(table: item.kind, recordId: item.id);
      ref.invalidate(workspaceSnapshotProvider(_request));
      if ({
        'hospital_beds',
        'hospital_rooms',
        'emergency_room_status',
        'hospital_facility_status',
        'hospital_services',
        'hospital_departments',
        'hospitals',
      }.contains(item.kind)) {
        await ref.read(hospitalDirectoryProvider.notifier).refresh();
      }
      showRootMessage('Managed record deleted.');
    });
  }

  Future<void> _deleteCareRecord(WorkspaceItem item) async {
    final confirmed = await confirmRootAction(
      title: 'Cancel ${item.title}?',
      message:
          'This keeps the order and its attachments in the clinical audit trail, but marks the request cancelled.',
      confirmLabel: 'Cancel request',
      destructive: true,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.deleteCareRecord(table: item.kind, recordId: item.id);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Laboratory request cancelled.');
    });
  }

  Future<void> _runItemAction(
    String itemId,
    Future<void> Function() action,
  ) async {
    setState(() => _busyItems.add(itemId));
    try {
      await action();
    } catch (error) {
      showRootMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _busyItems.remove(itemId));
    }
  }
}

class _MessagesEmptyState extends StatelessWidget {
  const _MessagesEmptyState({
    required this.isSearch,
    required this.isPatient,
    required this.onStart,
    required this.onClear,
  });

  final bool isSearch;
  final bool isPatient;
  final VoidCallback onStart;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x12),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.selected,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSearch ? Icons.search_off_outlined : Icons.forum_outlined,
              size: 30,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.x5),
          Text(
            isSearch ? 'No conversations found' : 'No conversations yet',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.x2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Text(
              isSearch
                  ? 'Try a different name or message.'
                  : isPatient
                  ? 'Your conversations with healthcare providers will appear here.'
                  : 'Your conversations with patients will appear here.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.x6),
          if (isSearch)
            TextButton(onPressed: onClear, child: const Text('Clear search'))
          else
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Start a conversation'),
            ),
        ],
      ),
    );
  }
}

class _ConversationInboxRow extends StatelessWidget {
  const _ConversationInboxRow({required this.item, required this.onTap});

  final WorkspaceItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = item.data['unread_count'] as int? ?? 0;
    return Semantics(
      button: true,
      label:
          '${item.title}, ${item.subtitle}${unread > 0 ? ', $unread unread' : ''}',
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.selected.withValues(alpha: .65),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x3,
          ),
          child: Row(
            children: [
              _ConversationAvatar(name: item.title, size: 52),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: item.isUnread
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: item.isUnread
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: item.isUnread
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _inboxTime(item.timestamp),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: item.isUnread
                          ? AppColors.primary
                          : AppColors.textMuted,
                      fontWeight: item.isUnread
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  if (unread > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.primaryForeground,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.name, this.size = 48});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+'));
    final initials = words
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand, AppColors.primary],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? 'C' : initials,
        style: TextStyle(
          color: AppColors.primaryForeground,
          fontSize: size * .34,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _inboxTime(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final days = today.difference(date).inDays;
  if (days == 0) return DateFormat('h:mm a').format(local);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(local);
  return DateFormat('MMM d').format(local);
}

class _LiveConversationView extends ConsumerStatefulWidget {
  const _LiveConversationView({
    required this.conversationId,
    required this.role,
  });

  final String conversationId;
  final UserRole role;

  @override
  ConsumerState<_LiveConversationView> createState() =>
      _LiveConversationViewState();
}

class _LiveConversationViewState extends ConsumerState<_LiveConversationView> {
  final _messageController = TextEditingController();
  ({List<int> bytes, String name})? _attachment;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    _messageController.removeListener(_onDraftChanged);
    _messageController.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _messageController.text.trim().isNotEmpty || _attachment != null;

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _markRead() async {
    try {
      await ref
          .read(careRepositoryProvider)
          ?.markConversationRead(widget.conversationId);
      _refreshConversationSnapshots();
    } catch (_) {
      // Reading remains available even if the best-effort receipt update fails.
    }
  }

  void _refreshConversationSnapshots() {
    ref.invalidate(
      workspaceSnapshotProvider((
        role: widget.role,
        section: 'messages',
        itemId: null,
      )),
    );
    ref.invalidate(
      workspaceSnapshotProvider((
        role: widget.role,
        section: 'messages',
        itemId: widget.conversationId,
      )),
    );
  }

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if (!_canSend || _sending) return;
    setState(() => _sending = true);
    try {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.sendMessage(
        conversationId: widget.conversationId,
        body: body,
        attachment: _attachment,
      );
      _messageController.clear();
      if (mounted) setState(() => _attachment = null);
      _refreshConversationSnapshots();
    } catch (error) {
      showRootMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAttachment() async {
    const acceptedTypes = XTypeGroup(
      label: 'Secure care attachments',
      extensions: ['pdf', 'jpg', 'jpeg', 'png'],
      mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
    );
    final selected = await openFile(acceptedTypeGroups: const [acceptedTypes]);
    if (selected == null) return;
    final bytes = await selected.readAsBytes();
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      showRootMessage('Attachments must be between 1 byte and 20 MB.');
      return;
    }
    if (mounted) {
      setState(() => _attachment = (bytes: bytes, name: selected.name));
    }
  }

  Future<void> _openAttachment(CareMessage message) async {
    try {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final url = await repository.createSignedMessageAttachmentUrl(message.id);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('The secure attachment link could not be opened.');
      }
    } catch (error) {
      showRootMessage(_friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(
      conversationMessagesProvider(widget.conversationId),
    );
    final conversation = ref.watch(
      workspaceSnapshotProvider((
        role: widget.role,
        section: 'messages',
        itemId: widget.conversationId,
      )),
    );
    final currentUserId = ref.watch(careProfileProvider).asData?.value.userId;
    final item = conversation.asData?.value.items.firstOrNull;
    final participantName = item?.title ?? 'Care conversation';
    final participantRole =
        item?.data['participant_role']?.toString() ?? 'Care team';
    final specialization =
        item?.data['doctor_specialization']?.toString().trim() ?? '';
    final subtitle = [
      participantRole,
      if (widget.role == UserRole.patient && specialization.isNotEmpty)
        specialization,
    ].join(' · ');

    return ColoredBox(
      color: AppColors.surfaceMuted,
      child: Column(
        children: [
          Material(
            color: AppColors.surface,
            elevation: 2,
            shadowColor: const Color(0x18102A3A),
            child: SafeArea(
              bottom: false,
              child: Container(
                constraints: const BoxConstraints(minHeight: 72),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x3,
                  vertical: AppSpacing.x2,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to conversations',
                      onPressed: () =>
                          context.go('${widget.role.homeLocation}/messages'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    _ConversationAvatar(name: participantName, size: 44),
                    const SizedBox(width: AppSpacing.x3),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            participantName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                size: 13,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: AppSpacing.x1),
                              Flexible(
                                child: Text(
                                  '$subtitle · Secure conversation',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: messages.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  error: (error, _) => DataState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Conversation unavailable',
                    message: _friendlyError(error),
                    action: FilledButton.icon(
                      onPressed: () => ref.invalidate(
                        conversationMessagesProvider(widget.conversationId),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
                  data: (items) {
                    final newestFirst = items.toList()
                      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
                    return newestFirst.isEmpty
                        ? _NewConversationState(
                            participantName: participantName,
                            participantRole: participantRole,
                          )
                        : ListView.separated(
                            key: const Key('conversation-message-list'),
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.x3,
                              AppSpacing.x6,
                              AppSpacing.x3,
                              AppSpacing.x6,
                            ),
                            itemCount: newestFirst.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.x2),
                            itemBuilder: (context, index) {
                              final message = newestFirst[index];
                              return _LiveMessageBubble(
                                message: message,
                                mine: message.senderId == currentUserId,
                                participantName: participantName,
                                onOpenAttachment: message.attachmentPath == null
                                    ? null
                                    : () => _openAttachment(message),
                              );
                            },
                          );
                  },
                ),
              ),
            ),
          ),
          Material(
            color: AppColors.surface,
            elevation: 8,
            shadowColor: const Color(0x1F102A3A),
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_attachment != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.attachment, size: 18),
                            const SizedBox(width: AppSpacing.x2),
                            Expanded(
                              child: Text(
                                _attachment!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove attachment',
                              onPressed: _sending
                                  ? null
                                  : () => setState(() => _attachment = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: _attachment == null
                              ? 'Add attachment'
                              : 'Change attachment',
                          onPressed: _sending ? null : _pickAttachment,
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.primary,
                          ),
                          icon: Icon(
                            _attachment == null
                                ? Icons.add_circle_outline
                                : Icons.attach_file,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            key: const Key('message-composer'),
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: 'Aa',
                              counterText: '',
                              filled: true,
                              fillColor: AppColors.surfaceMuted,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.x4,
                                vertical: AppSpacing.x3,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(
                                  color: AppColors.focus,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.x2),
                        IconButton.filled(
                          tooltip: 'Send message',
                          onPressed: _sending || !_canSend ? null : _send,
                          icon: _sending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryForeground,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewConversationState extends StatelessWidget {
  const _NewConversationState({
    required this.participantName,
    required this.participantRole,
  });

  final String participantName;
  final String participantRole;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConversationAvatar(name: participantName, size: 72),
            const SizedBox(height: AppSpacing.x4),
            Text(
              participantName,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              participantRole,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.x4),
            const Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.x1,
              children: [
                Icon(Icons.lock_outline, size: 15, color: AppColors.textMuted),
                Text(
                  'Messages and attachments are shared securely.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveMessageBubble extends StatelessWidget {
  const _LiveMessageBubble({
    required this.message,
    required this.mine,
    required this.participantName,
    this.onOpenAttachment,
  });

  final CareMessage message;
  final bool mine;
  final String participantName;
  final VoidCallback? onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${mine ? 'Your' : participantName} message, ${message.message ?? 'Attachment'}',
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: AppSpacing.x3,
            ),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(mine ? 20 : 5),
                bottomRight: Radius.circular(mine ? 5 : 20),
              ),
              boxShadow: mine
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x0F102A3A),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.message ?? 'Secure attachment',
                  style: TextStyle(
                    color: mine
                        ? AppColors.primaryForeground
                        : AppColors.textPrimary,
                  ),
                ),
                if (onOpenAttachment != null) ...[
                  const SizedBox(height: AppSpacing.x2),
                  TextButton.icon(
                    onPressed: onOpenAttachment,
                    style: TextButton.styleFrom(
                      foregroundColor: mine
                          ? AppColors.primaryForeground
                          : AppColors.primary,
                    ),
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Open secure attachment'),
                  ),
                ],
                const SizedBox(height: AppSpacing.x1),
                Text(
                  '${DateFormat('h:mm a').format(message.sentAt.toLocal())}${mine && message.readAt != null ? ' · Seen' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: mine
                        ? AppColors.primaryForeground.withValues(alpha: .78)
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientAccountDraft {
  const _PatientAccountDraft({
    this.firstName = '',
    this.lastName = '',
    this.birthDate,
    this.sex = '',
    this.mobileNumber = '',
    required this.email,
    this.address = '',
    this.password = '',
    this.patientId = '',
    this.isExistingAccount = false,
  });

  final String firstName;
  final String lastName;
  final DateTime? birthDate;
  final String sex;
  final String mobileNumber;
  final String email;
  final String address;
  final String password;
  final String patientId;
  final bool isExistingAccount;
}

enum _PatientRegistrationMode { newAccount, existingAccount }

class _PatientAccountDialog extends StatefulWidget {
  const _PatientAccountDialog({required this.searchPatients});

  final Future<List<ExistingPatientMatch>> Function(String query)
  searchPatients;

  @override
  State<_PatientAccountDialog> createState() => _PatientAccountDialogState();
}

class _PatientAccountDialogState extends State<_PatientAccountDialog> {
  _PatientRegistrationMode _mode = _PatientRegistrationMode.newAccount;
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _patientSearchController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  DateTime? _birthDate;
  String? _sex;
  Timer? _searchDebounce;
  List<ExistingPatientMatch> _searchResults = const [];
  ExistingPatientMatch? _selectedPatient;
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _searchError;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _patientSearchController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _schedulePatientSearch(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    final generation = ++_searchGeneration;
    setState(() {
      _selectedPatient = null;
      _searchError = null;
      _searchResults = const [];
      _isSearching = false;
      _hasSearched = false;
    });
    if (query.length < 2) return;
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchPatients(query, generation),
    );
  }

  Future<void> _searchPatients(String query, int generation) async {
    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _searchError = null;
    });
    try {
      final results = await widget.searchPatients(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = const [];
        _isSearching = false;
        _searchError = error is StateError
            ? error.message
            : 'Could not search patient accounts.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.person_add_alt_outlined),
      title: const Text('Register patient'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_PatientRegistrationMode>(
                  segments: const [
                    ButtonSegment(
                      value: _PatientRegistrationMode.newAccount,
                      icon: Icon(Icons.person_add_alt_outlined),
                      label: Text('New account'),
                    ),
                    ButtonSegment(
                      value: _PatientRegistrationMode.existingAccount,
                      icon: Icon(Icons.search),
                      label: Text('Existing patient'),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setState(() {
                      _mode = selection.single;
                      _selectedPatient = null;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.x4),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.x3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.panel),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'The existing-patient directory searches active CareNavigator identities by name or email. Finding a patient does not reveal medical records; record access still requires an approved care relationship.',
                  ),
                ),
                const SizedBox(height: AppSpacing.x6),
                if (_mode == _PatientRegistrationMode.newAccount) ...[
                  const Text(
                    'Use the same identity details collected in account registration and consultation intake.',
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  PatientDetailsFields(
                    firstNameController: _firstNameController,
                    lastNameController: _lastNameController,
                    mobileController: _mobileController,
                    addressController: _addressController,
                    emailController: _emailController,
                    birthDate: _birthDate,
                    sex: _sex,
                    onBirthDateChanged: (value) =>
                        setState(() => _birthDate = value),
                    onSexChanged: (value) => setState(() => _sex = value),
                    stackNameFields: true,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Temporary patient password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: _patientPasswordValidator,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  TextFormField(
                    controller: _confirmationController,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (value) => value != _passwordController.text
                        ? 'Passwords must match.'
                        : null,
                  ),
                ] else ...[
                  const Text(
                    'Search the global patient directory for an active CareNavigator account. Patients with the same name are listed separately by email.',
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  TextFormField(
                    controller: _patientSearchController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    onChanged: _schedulePatientSearch,
                    onFieldSubmitted: (value) {
                      _searchDebounce?.cancel();
                      final query = value.trim();
                      if (query.length < 2) return;
                      final generation = ++_searchGeneration;
                      _searchPatients(query, generation);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Patient name or email address',
                      hintText: 'Enter at least 2 characters',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  if (_isSearching)
                    const Center(child: CircularProgressIndicator())
                  else if (_searchError != null)
                    Text(
                      _searchError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else if (_hasSearched && _searchResults.isEmpty)
                    const Text('No matching active patient accounts found.')
                  else
                    ..._searchResults.map(
                      (patient) => Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.x2),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          selected:
                              _selectedPatient?.patientId == patient.patientId,
                          leading: Icon(
                            _selectedPatient?.patientId == patient.patientId
                                ? Icons.check_circle
                                : Icons.person_outline,
                          ),
                          title: Text(patient.displayName),
                          subtitle: Text(patient.email),
                          onTap: () =>
                              setState(() => _selectedPatient = patient),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_mode == _PatientRegistrationMode.existingAccount) {
              final patient = _selectedPatient;
              if (patient == null) {
                showRootMessage('Search for and select a patient account.');
                return;
              }
              Navigator.of(context).pop(
                _PatientAccountDraft(
                  email: patient.email,
                  patientId: patient.patientId,
                  isExistingAccount: true,
                ),
              );
              return;
            }
            if (!(_formKey.currentState?.validate() ?? false) ||
                _birthDate == null ||
                _sex == null) {
              _formKey.currentState?.validate();
              return;
            }
            Navigator.of(context).pop(
              _PatientAccountDraft(
                firstName: _firstNameController.text.trim(),
                lastName: _lastNameController.text.trim(),
                birthDate: _birthDate!,
                sex: _sex!,
                mobileNumber: _mobileController.text.trim(),
                email: _emailController.text.trim(),
                address: _addressController.text.trim(),
                password: _passwordController.text,
              ),
            );
          },
          child: Text(
            _mode == _PatientRegistrationMode.existingAccount
                ? 'Send request'
                : 'Register patient',
          ),
        ),
      ],
    );
  }
}

String? _patientPasswordValidator(String? value) {
  final password = value ?? '';
  if (password.length < 12) return 'Use at least 12 characters.';
  if (!RegExp('[a-z]').hasMatch(password)) {
    return 'Add at least one lowercase letter.';
  }
  if (!RegExp('[A-Z]').hasMatch(password)) {
    return 'Add at least one uppercase letter.';
  }
  if (!RegExp(r'\d').hasMatch(password)) {
    return 'Add at least one number.';
  }
  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    return 'Add at least one symbol.';
  }
  return null;
}

class _DoctorAccountDraft {
  const _DoctorAccountDraft({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.temporaryPassword,
    required this.specialization,
    required this.licenseNumber,
    required this.departmentId,
    required this.consultationFee,
    required this.biography,
    required this.profileImageBytes,
    required this.profileImageFileName,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String temporaryPassword;
  final String specialization;
  final String licenseNumber;
  final String? departmentId;
  final double? consultationFee;
  final String biography;
  final List<int>? profileImageBytes;
  final String? profileImageFileName;
}

class _DoctorAccountDialog extends StatefulWidget {
  const _DoctorAccountDialog({required this.context});

  final HospitalAdminContext context;

  @override
  State<_DoctorAccountDialog> createState() => _DoctorAccountDialogState();
}

class _DoctorAccountDialogState extends State<_DoctorAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmationController = TextEditingController();
  final _specializationController = TextEditingController();
  final _licenseController = TextEditingController();
  final _feeController = TextEditingController();
  final _biographyController = TextEditingController();
  String? _departmentId;
  XFile? _profileImage;
  List<int>? _profileImageBytes;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
    _specializationController.dispose();
    _licenseController.dispose();
    _feeController.dispose();
    _biographyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.person_add_alt_outlined),
      title: const Text('Add doctor account'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DoctorImagePicker(
                  image: _profileImageBytes,
                  fileName: _profileImage?.name,
                  onPick: _pickProfileImage,
                ),
                const SizedBox(height: AppSpacing.x4),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstNameController,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                        ),
                        validator: _requiredClinicalValue,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x3),
                    Expanded(
                      child: TextFormField(
                        controller: _lastNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                        ),
                        validator: _requiredClinicalValue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Work email'),
                  validator: (value) =>
                      RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Enter a valid email address.',
                ),
                const SizedBox(height: AppSpacing.x4),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Temporary password',
                        ),
                        validator: (value) => (value?.length ?? 0) < 12
                            ? 'Use at least 12 characters.'
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x3),
                    Expanded(
                      child: TextFormField(
                        controller: _passwordConfirmationController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                        ),
                        validator: (value) => value != _passwordController.text
                            ? 'Passwords must match.'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _specializationController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Specialization',
                  ),
                  validator: _requiredClinicalValue,
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _licenseController,
                  decoration: const InputDecoration(
                    labelText: 'Professional license number',
                  ),
                  validator: _requiredClinicalValue,
                ),
                const SizedBox(height: AppSpacing.x4),
                DropdownButtonFormField<String>(
                  initialValue: _departmentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [
                    for (final department in widget.context.departments)
                      DropdownMenuItem(
                        value: department.id,
                        child: Text(
                          department.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Select a department.'
                      : null,
                  onChanged: (value) => setState(() => _departmentId = value),
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _feeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Consultation fee (optional)',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    final fee = double.tryParse(value!);
                    return fee == null || fee < 0
                        ? 'Enter zero or a positive amount.'
                        : null;
                  },
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _biographyController,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Professional biography (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _DoctorAccountDraft(
                firstName: _firstNameController.text.trim(),
                lastName: _lastNameController.text.trim(),
                email: _emailController.text.trim(),
                temporaryPassword: _passwordController.text,
                specialization: _specializationController.text.trim(),
                licenseNumber: _licenseController.text.trim(),
                departmentId: _departmentId,
                consultationFee: double.tryParse(_feeController.text.trim()),
                biography: _biographyController.text.trim(),
                profileImageBytes: _profileImageBytes,
                profileImageFileName: _profileImage?.name,
              ),
            );
          },
          child: const Text('Create doctor'),
        ),
      ],
    );
  }

  Future<void> _pickProfileImage() async {
    const imageTypes = XTypeGroup(
      label: 'Doctor profile images',
      extensions: ['jpg', 'jpeg', 'png'],
    );
    final selected = await openFile(acceptedTypeGroups: const [imageTypes]);
    if (selected == null) return;
    final bytes = await selected.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an image smaller than 5 MB.')),
      );
      return;
    }
    setState(() {
      _profileImage = selected;
      _profileImageBytes = bytes;
    });
  }
}

class _DoctorDepartmentDialog extends StatefulWidget {
  const _DoctorDepartmentDialog({
    required this.doctorName,
    required this.departments,
    this.currentDepartmentId,
  });

  final String doctorName;
  final List<HospitalDepartmentOption> departments;
  final String? currentDepartmentId;

  @override
  State<_DoctorDepartmentDialog> createState() =>
      _DoctorDepartmentDialogState();
}

class _DoctorDepartmentDialogState extends State<_DoctorDepartmentDialog> {
  late String? _departmentId =
      widget.departments.any(
        (department) => department.id == widget.currentDepartmentId,
      )
      ? widget.currentDepartmentId
      : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.account_tree_outlined),
    title: const Text('Change doctor department'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assign ${widget.doctorName} to a hospital department.'),
          const SizedBox(height: AppSpacing.x4),
          DropdownButtonFormField<String>(
            initialValue: _departmentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Department'),
            items: [
              for (final department in widget.departments)
                DropdownMenuItem(
                  value: department.id,
                  child: Text(department.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _departmentId = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            _departmentId == null || _departmentId == widget.currentDepartmentId
            ? null
            : () => Navigator.of(context).pop(_departmentId),
        child: const Text('Save department'),
      ),
    ],
  );
}

class _DoctorImagePicker extends StatelessWidget {
  const _DoctorImagePicker({
    required this.image,
    required this.fileName,
    required this.onPick,
  });
  final List<int>? image;
  final String? fileName;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 32,
        backgroundColor: AppColors.surfaceMuted,
        child: image == null
            ? const Icon(Icons.person_outline, size: 32)
            : ClipOval(
                child: Image.memory(
                  Uint8List.fromList(image!),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
      ),
      const SizedBox(width: AppSpacing.x3),
      Expanded(child: Text(fileName ?? 'Add a profile photo (optional)')),
      OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.upload_outlined),
        label: const Text('Choose'),
      ),
    ],
  );
}

class _NamedRecordDraft {
  const _NamedRecordDraft({
    required this.name,
    required this.description,
    required this.departmentId,
    required this.status,
  });

  final String name;
  final String description;
  final String? departmentId;
  final String? status;
}

class _NamedRecordDialog extends StatefulWidget {
  const _NamedRecordDialog({
    required this.title,
    required this.nameLabel,
    required this.confirmLabel,
    this.departments = const [],
    this.initialName = '',
    this.initialDescription = '',
    this.initialDepartmentId,
    this.initialStatus,
  });

  final String title;
  final String nameLabel;
  final String confirmLabel;
  final List<HospitalDepartmentOption> departments;
  final String initialName;
  final String initialDescription;
  final String? initialDepartmentId;
  final String? initialStatus;

  @override
  State<_NamedRecordDialog> createState() => _NamedRecordDialogState();
}

class _NamedRecordDialogState extends State<_NamedRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  String? _departmentId;
  String? _status;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _departmentId = widget.initialDepartmentId;
    _status = widget.initialStatus;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.add_business_outlined),
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: widget.nameLabel),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? 'Enter at least 2 characters.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
            ),
            if (widget.departments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x4),
              DropdownButtonFormField<String?>(
                initialValue: _departmentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Department (optional)',
                ),
                items: [
                  const DropdownMenuItem(child: Text('No department')),
                  for (final department in widget.departments)
                    DropdownMenuItem(
                      value: department.id,
                      child: Text(
                        department.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _departmentId = value),
              ),
            ],
            if (widget.initialStatus != null) ...[
              const SizedBox(height: AppSpacing.x4),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Availability'),
                items: const [
                  DropdownMenuItem(
                    value: 'available',
                    child: Text('Available'),
                  ),
                  DropdownMenuItem(value: 'limited', child: Text('Limited')),
                  DropdownMenuItem(
                    value: 'unavailable',
                    child: Text('Unavailable'),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          Navigator.of(context).pop(
            _NamedRecordDraft(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim(),
              departmentId: _departmentId,
              status: _status,
            ),
          );
        },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

const _facilityTypes = <String>[
  'icu',
  'operating_room',
  'ambulance',
  'laboratory',
  'pharmacy',
];

List<String> _missingFacilityTypes(List<WorkspaceItem> items) {
  final existing = items
      .map((item) => item.data['facility_type']?.toString())
      .whereType<String>()
      .toSet();
  return _facilityTypes
      .where((facilityType) => !existing.contains(facilityType))
      .toList(growable: false);
}

String _facilityTypeLabel(String value) => switch (value) {
  'icu' => 'Intensive care unit',
  'operating_room' => 'Operating room',
  'ambulance' => 'Ambulance',
  'laboratory' => 'Laboratory',
  'pharmacy' => 'Pharmacy',
  _ => _detailLabel(value),
};

class _FacilityStatusDraft {
  const _FacilityStatusDraft({
    required this.facilityType,
    required this.status,
    required this.availableUnits,
    required this.notes,
  });

  final String facilityType;
  final String status;
  final int? availableUnits;
  final String? notes;
}

class _FacilityStatusDialog extends StatefulWidget {
  const _FacilityStatusDialog({this.item, this.facilityTypes = _facilityTypes});

  final WorkspaceItem? item;
  final List<String> facilityTypes;

  @override
  State<_FacilityStatusDialog> createState() => _FacilityStatusDialogState();
}

class _FacilityStatusDialogState extends State<_FacilityStatusDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _availableController;
  late final TextEditingController _notesController;
  late String _facilityType;
  late String _status;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _facilityType =
        item?.data['facility_type']?.toString() ?? widget.facilityTypes.first;
    _status = item?.status ?? item?.data['status']?.toString() ?? 'available';
    _availableController = TextEditingController(
      text: item?.data['available_units']?.toString() ?? '',
    );
    _notesController = TextEditingController(
      text: item?.data['notes']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _availableController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.local_hospital_outlined),
    title: Text(widget.item == null ? 'Add facility status' : 'Edit facility'),
    content: Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _facilityType,
              decoration: const InputDecoration(labelText: 'Facility type'),
              items: [
                for (final facilityType in widget.facilityTypes)
                  DropdownMenuItem(
                    value: facilityType,
                    child: Text(_facilityTypeLabel(facilityType)),
                  ),
              ],
              onChanged: widget.item == null
                  ? (value) => setState(() => _facilityType = value!)
                  : null,
            ),
            const SizedBox(height: AppSpacing.x4),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'available', child: Text('Available')),
                DropdownMenuItem(value: 'limited', child: Text('Limited')),
                DropdownMenuItem(
                  value: 'unavailable',
                  child: Text('Unavailable'),
                ),
              ],
              onChanged: (value) => setState(() => _status = value!),
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _availableController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Available units (optional)',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                final units = int.tryParse(text);
                return units == null || units < 0
                    ? 'Enter zero or a positive whole number.'
                    : null;
              },
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          final availableText = _availableController.text.trim();
          final notes = _notesController.text.trim();
          Navigator.of(context).pop(
            _FacilityStatusDraft(
              facilityType: _facilityType,
              status: _status,
              availableUnits: availableText.isEmpty
                  ? null
                  : int.parse(availableText),
              notes: notes.isEmpty ? null : notes,
            ),
          );
        },
        child: Text(widget.item == null ? 'Add facility' : 'Save changes'),
      ),
    ],
  );
}

class _CapacityResourceDraft {
  const _CapacityResourceDraft({
    required this.type,
    required this.total,
    required this.available,
  });

  final String type;
  final int total;
  final int available;
}

class _CapacityResourceDialog extends StatefulWidget {
  const _CapacityResourceDialog({required this.beds});

  final bool beds;

  @override
  State<_CapacityResourceDialog> createState() =>
      _CapacityResourceDialogState();
}

class _CapacityResourceDialogState extends State<_CapacityResourceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _typeController = TextEditingController();
  final _totalController = TextEditingController(text: '0');
  final _availableController = TextEditingController(text: '0');

  @override
  void dispose() {
    _typeController.dispose();
    _totalController.dispose();
    _availableController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: Icon(widget.beds ? Icons.bed_outlined : Icons.meeting_room_outlined),
    title: Text('Add ${widget.beds ? 'bed' : 'room'} type'),
    content: Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _typeController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.beds ? 'Bed type' : 'Room type',
              ),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? 'Enter at least 2 characters.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _totalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total capacity'),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                return parsed == null || parsed < 0
                    ? 'Enter zero or a positive whole number.'
                    : null;
              },
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _availableController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Available capacity',
              ),
              validator: (value) {
                final total = int.tryParse(_totalController.text);
                final available = int.tryParse(value ?? '');
                if (available == null || available < 0) {
                  return 'Enter zero or a positive whole number.';
                }
                return total != null && available > total
                    ? 'Available capacity cannot exceed total capacity.'
                    : null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          Navigator.of(context).pop(
            _CapacityResourceDraft(
              type: _typeController.text.trim(),
              total: int.parse(_totalController.text),
              available: int.parse(_availableController.text),
            ),
          );
        },
        child: const Text('Add record'),
      ),
    ],
  );
}

class _HospitalRecordDraft {
  const _HospitalRecordDraft({
    required this.name,
    required this.address,
    required this.city,
    required this.province,
    required this.contactNumber,
    required this.emergencyContactNumber,
    required this.email,
    required this.description,
    required this.operatingStatus,
  });

  final String name;
  final String address;
  final String city;
  final String province;
  final String contactNumber;
  final String emergencyContactNumber;
  final String email;
  final String description;
  final String operatingStatus;

  Map<String, Object?> toValues({required bool includeVerification}) => {
    'hospital_name': name,
    'address': address,
    'city': city.trim().isEmpty ? null : city.trim(),
    'province': province.trim().isEmpty ? null : province.trim(),
    'contact_number': contactNumber.trim().isEmpty
        ? null
        : contactNumber.trim(),
    'emergency_contact_number': emergencyContactNumber.trim().isEmpty
        ? null
        : emergencyContactNumber.trim(),
    'email': email.trim().isEmpty ? null : email.trim(),
    'description': description,
    'operating_status': operatingStatus,
    if (includeVerification) 'verification_status': 'pending',
  };
}

class _HospitalRecordDialog extends StatefulWidget {
  const _HospitalRecordDialog({this.item});

  final WorkspaceItem? item;

  @override
  State<_HospitalRecordDialog> createState() => _HospitalRecordDialogState();
}

class _HospitalRecordDialogState extends State<_HospitalRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _contactController;
  late final TextEditingController _emergencyContactController;
  late final TextEditingController _emailController;
  late final TextEditingController _descriptionController;
  late String _operatingStatus;

  @override
  void initState() {
    super.initState();
    final data = widget.item?.data ?? const <String, Object?>{};
    _nameController = TextEditingController(
      text: data['hospital_name']?.toString() ?? widget.item?.title ?? '',
    );
    _addressController = TextEditingController(
      text: data['address']?.toString() ?? '',
    );
    _cityController = TextEditingController(
      text: data['city']?.toString() ?? '',
    );
    _provinceController = TextEditingController(
      text: data['province']?.toString() ?? '',
    );
    _contactController = TextEditingController(
      text: data['contact_number']?.toString() ?? '',
    );
    _emergencyContactController = TextEditingController(
      text: data['emergency_contact_number']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: data['email']?.toString() ?? '',
    );
    _descriptionController = TextEditingController(
      text: data['description']?.toString() ?? '',
    );
    _operatingStatus = data['operating_status']?.toString() ?? 'open';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _contactController.dispose();
    _emergencyContactController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.local_hospital_outlined),
    title: Text(widget.item == null ? 'Add hospital' : 'Edit hospital'),
    content: Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Hospital name'),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? 'Enter at least 3 characters.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.x4),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                validator: (value) => (value?.trim().length ?? 0) < 5
                    ? 'Enter a complete address.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.x4),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: TextFormField(
                      controller: _provinceController,
                      decoration: const InputDecoration(labelText: 'Province'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x4),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _contactController,
                      decoration: const InputDecoration(
                        labelText: 'Contact number',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: TextFormField(
                      controller: _emergencyContactController,
                      decoration: const InputDecoration(
                        labelText: 'Emergency number',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x4),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: AppSpacing.x4),
              DropdownButtonFormField<String>(
                initialValue: _operatingStatus,
                decoration: const InputDecoration(
                  labelText: 'Operating status',
                ),
                items: [
                  for (final status in const [
                    'open',
                    'limited',
                    'temporarily_closed',
                    'closed',
                  ])
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(status)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _operatingStatus = value);
                },
              ),
              const SizedBox(height: AppSpacing.x4),
              TextFormField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          Navigator.of(context).pop(
            _HospitalRecordDraft(
              name: _nameController.text.trim(),
              address: _addressController.text.trim(),
              city: _cityController.text.trim(),
              province: _provinceController.text.trim(),
              contactNumber: _contactController.text.trim(),
              emergencyContactNumber: _emergencyContactController.text.trim(),
              email: _emailController.text.trim(),
              description: _descriptionController.text.trim(),
              operatingStatus: _operatingStatus,
            ),
          );
        },
        child: Text(widget.item == null ? 'Add hospital' : 'Save changes'),
      ),
    ],
  );
}

class _PermissionRecordDraft {
  const _PermissionRecordDraft({
    required this.roleId,
    required this.permission,
    required this.allowed,
  });

  final int roleId;
  final String permission;
  final bool allowed;
}

class _PermissionRecordDialog extends StatefulWidget {
  const _PermissionRecordDialog();

  @override
  State<_PermissionRecordDialog> createState() =>
      _PermissionRecordDialogState();
}

class _PermissionRecordDialogState extends State<_PermissionRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _roleController = TextEditingController();
  final _permissionController = TextEditingController();
  bool _allowed = true;

  @override
  void dispose() {
    _roleController.dispose();
    _permissionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.admin_panel_settings_outlined),
    title: const Text('Add permission'),
    content: Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _roleController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Role ID'),
              validator: (value) => int.tryParse(value ?? '') == null
                  ? 'Enter a valid role ID.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _permissionController,
              decoration: const InputDecoration(labelText: 'Permission key'),
              validator: (value) => (value?.trim().length ?? 0) < 3
                  ? 'Enter at least 3 characters.'
                  : null,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allowed'),
              value: _allowed,
              onChanged: (value) => setState(() => _allowed = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          Navigator.of(context).pop(
            _PermissionRecordDraft(
              roleId: int.parse(_roleController.text),
              permission: _permissionController.text.trim(),
              allowed: _allowed,
            ),
          );
        },
        child: const Text('Add permission'),
      ),
    ],
  );
}

class _SystemSettingRecordDraft {
  const _SystemSettingRecordDraft({
    required this.key,
    required this.value,
    required this.description,
    required this.isPublic,
  });

  final String key;
  final Object value;
  final String description;
  final bool isPublic;
}

class _SystemSettingRecordDialog extends StatefulWidget {
  const _SystemSettingRecordDialog();

  @override
  State<_SystemSettingRecordDialog> createState() =>
      _SystemSettingRecordDialogState();
}

class _SystemSettingRecordDialogState
    extends State<_SystemSettingRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isPublic = false;

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.settings_outlined),
    title: const Text('Add setting'),
    content: Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _keyController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Setting key'),
              validator: (value) =>
                  RegExp(
                    r'^[a-z0-9][a-z0-9_.-]{2,}$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Use at least 3 lowercase letters, numbers, dots, dashes, or underscores.',
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _valueController,
              decoration: const InputDecoration(
                labelText: 'Value',
                helperText: 'JSON values are stored with their native type.',
              ),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter a setting value.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Public setting'),
              subtitle: const Text('Visible without an administrator session'),
              value: _isPublic,
              onChanged: (value) => setState(() => _isPublic = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          final rawValue = _valueController.text.trim();
          Object parsedValue;
          try {
            parsedValue = jsonDecode(rawValue) ?? rawValue;
          } on FormatException {
            parsedValue = rawValue;
          }
          Navigator.of(context).pop(
            _SystemSettingRecordDraft(
              key: _keyController.text.trim(),
              value: parsedValue,
              description: _descriptionController.text.trim(),
              isPublic: _isPublic,
            ),
          );
        },
        child: const Text('Add setting'),
      ),
    ],
  );
}

class _MaintenanceCopyDraft {
  const _MaintenanceCopyDraft({required this.title, required this.message});

  final String title;
  final String message;
}

class _MaintenanceCopyDialog extends StatefulWidget {
  const _MaintenanceCopyDialog({
    this.title = 'Schedule maintenance',
    this.confirmLabel = 'Choose schedule',
    this.initialTitle = '',
    this.initialMessage = '',
  });

  final String title;
  final String confirmLabel;
  final String initialTitle;
  final String initialMessage;

  @override
  State<_MaintenanceCopyDialog> createState() => _MaintenanceCopyDialogState();
}

class _MaintenanceCopyDialogState extends State<_MaintenanceCopyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _messageController = TextEditingController(text: widget.initialMessage);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.build_outlined),
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) => (value?.trim().length ?? 0) < 3
                  ? 'Enter at least 3 characters.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: _messageController,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'User-facing message',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value?.trim().length ?? 0) < 5
                  ? 'Enter at least 5 characters.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          Navigator.of(context).pop(
            _MaintenanceCopyDraft(
              title: _titleController.text.trim(),
              message: _messageController.text.trim(),
            ),
          );
        },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

class _ScheduleDraft {
  const _ScheduleDraft({
    required this.dayOfWeek,
    required this.startsAt,
    required this.endsAt,
    required this.consultationType,
    required this.slotMinutes,
  });

  final int dayOfWeek;
  final String startsAt;
  final String endsAt;
  final String consultationType;
  final int slotMinutes;
}

class _PrescriptionDraft {
  const _PrescriptionDraft({
    required this.relationship,
    required this.diagnosisReason,
    required this.medications,
    this.attachment,
  });

  final ClinicalRelationship relationship;
  final String diagnosisReason;
  final List<_PrescriptionMedicationDraft> medications;
  final ({List<int> bytes, String name})? attachment;
}

class _PrescriptionMedicationDraft {
  const _PrescriptionMedicationDraft({
    required this.medicationName,
    required this.medicationFormStrength,
    required this.route,
    required this.exactDose,
    required this.frequency,
    required this.duration,
    required this.quantityToDispense,
    required this.refills,
    required this.startDate,
    required this.endDate,
    required this.isPrn,
    required this.prnReason,
    required this.maximumDailyDose,
    required this.instructions,
  });

  final String medicationName;
  final String medicationFormStrength;
  final String route;
  final String exactDose;
  final String frequency;
  final String duration;
  final String quantityToDispense;
  final int refills;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isPrn;
  final String prnReason;
  final String maximumDailyDose;
  final String instructions;
}

class _ReservationDraft {
  const _ReservationDraft({
    required this.clinician,
    required this.consultationType,
    required this.chiefComplaint,
    required this.symptomDuration,
    required this.sharedCategories,
    required this.appointmentDate,
  });

  final DoctorDirectoryEntry clinician;
  final String consultationType;
  final String chiefComplaint;
  final String symptomDuration;
  final List<String> sharedCategories;
  final DateTime appointmentDate;
}

class _ConsultationCompletionDraft {
  const _ConsultationCompletionDraft({
    required this.summary,
    required this.confirmedDiagnosis,
    required this.treatmentPlan,
    required this.doctorNotes,
    required this.checkup,
  });

  final String summary;
  final String confirmedDiagnosis;
  final String treatmentPlan;
  final String doctorNotes;
  final ClinicalCheckupDraft checkup;
}

class _ConsultationCompletionDialog extends StatefulWidget {
  const _ConsultationCompletionDialog({required this.patient});

  final Map<String, Object?> patient;

  @override
  State<_ConsultationCompletionDialog> createState() =>
      _ConsultationCompletionDialogState();
}

class _ConsultationCompletionDialogState
    extends State<_ConsultationCompletionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _summaryController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _treatmentController = TextEditingController();
  final _notesController = TextEditingController();
  final _checkupControllers = _CheckupFormControllers();

  @override
  void initState() {
    super.initState();
    _checkupControllers.reasonForVisit.text =
        widget.patient['chief_complaint']?.toString() ?? '';
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _diagnosisController.dispose();
    _treatmentController.dispose();
    _notesController.dispose();
    _checkupControllers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.assignment_turned_in_outlined),
      title: const Text('Complete consultation'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PatientIdentitySummary(patient: widget.patient),
                const SizedBox(height: AppSpacing.x4),
                _ClinicalDocumentationField(
                  controller: _summaryController,
                  label: 'Consultation summary',
                  requiredLength: 10,
                ),
                const SizedBox(height: AppSpacing.x4),
                _ClinicalDocumentationField(
                  controller: _diagnosisController,
                  label: 'Confirmed diagnosis',
                  requiredLength: 3,
                ),
                const SizedBox(height: AppSpacing.x4),
                _ClinicalDocumentationField(
                  controller: _treatmentController,
                  label: 'Treatment plan',
                  requiredLength: 5,
                ),
                const SizedBox(height: AppSpacing.x4),
                _ClinicalDocumentationField(
                  controller: _notesController,
                  label: 'Doctor notes',
                  requiredLength: 3,
                ),
                const SizedBox(height: AppSpacing.x5),
                _CheckupSectionTitle(
                  title: 'Optional measurements and medical information',
                  subtitle:
                      'Leave any field blank when it is not needed for this consultation. BMI is calculated from height and weight.',
                ),
                const SizedBox(height: AppSpacing.x3),
                _ClinicalCheckupFields(
                  controllers: _checkupControllers,
                  showReasonForVisit: true,
                  reasonReadOnly: true,
                  showDoctorNotes: false,
                  stackFields: true,
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _ConsultationCompletionDraft(
                summary: _summaryController.text.trim(),
                confirmedDiagnosis: _diagnosisController.text.trim(),
                treatmentPlan: _treatmentController.text.trim(),
                doctorNotes: _notesController.text.trim(),
                checkup: _checkupControllers.draft(
                  doctorNotesOverride: _notesController.text,
                ),
              ),
            );
          },
          child: const Text('Complete consultation'),
        ),
      ],
    );
  }
}

class _PatientCheckupDialog extends StatefulWidget {
  const _PatientCheckupDialog({
    required this.patient,
    required this.repository,
  });

  final Map<String, Object?> patient;
  final CareRepository repository;

  @override
  State<_PatientCheckupDialog> createState() => _PatientCheckupDialogState();
}

class _PatientCheckupDialogState extends State<_PatientCheckupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = _CheckupFormControllers();
  final List<({List<int> bytes, String name})> _attachments = [];
  bool _scanning = false;
  String? _scanStatus;
  String? _scanError;

  Future<void> _pickAttachments() async {
    const acceptedTypes = XTypeGroup(
      label: 'Medical files',
      extensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
      mimeTypes: [
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'image/jpeg',
        'image/png',
      ],
    );
    final selected = await openFiles(acceptedTypeGroups: const [acceptedTypes]);
    if (selected.isEmpty) return;
    final files = await Future.wait(
      selected.map(
        (file) async => (bytes: await file.readAsBytes(), name: file.name),
      ),
    );
    if (mounted) {
      setState(() {
        _attachments.addAll(files);
        _scanStatus = null;
        _scanError = null;
      });
    }
  }

  Future<void> _scanAttachments() async {
    if (_attachments.isEmpty) {
      setState(() {
        _scanStatus = null;
        _scanError = 'Attach at least one medical file to scan.';
      });
      return;
    }
    if (_attachments.length > 5) {
      setState(() {
        _scanStatus = null;
        _scanError = 'Select up to 5 medical files for each AI scan.';
      });
      return;
    }

    setState(() {
      _scanning = true;
      _scanStatus = null;
      _scanError = null;
    });
    try {
      final draft = await widget.repository.extractCheckupFromAttachments(
        attachments: _attachments,
      );
      if (!mounted) return;
      final filled = _controllers.applyAiDraft(draft);
      setState(() {
        _scanStatus = filled == 0
            ? 'The scan found no new details to add. Existing entries were kept.'
            : 'AI filled $filled ${filled == 1 ? 'field' : 'fields'}. Review and edit every value before saving.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _controllers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.monitor_heart_outlined),
    title: const Text('Follow-up patient checkup'),
    content: Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PatientIdentitySummary(patient: widget.patient),
              const SizedBox(height: AppSpacing.x4),
              _CheckupSectionTitle(
                title: 'Attachments and AI auto-fill',
                subtitle:
                    'Attach up to 5 PDF, Word, JPG, or PNG files. Groq AI reads them together and fills empty fields, including notes and observations.',
              ),
              const SizedBox(height: AppSpacing.x3),
              if (_attachments.isNotEmpty) ...[
                for (var index = 0; index < _attachments.length; index++)
                  Row(
                    children: [
                      const Icon(Icons.attachment, size: 16),
                      const SizedBox(width: AppSpacing.x2),
                      Expanded(
                        child: Text(
                          _attachments[index].name,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove attachment',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: _scanning
                            ? null
                            : () => setState(() {
                                _attachments.removeAt(index);
                                _scanStatus = null;
                                _scanError = null;
                              }),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.x2),
              ],
              Wrap(
                spacing: AppSpacing.x2,
                runSpacing: AppSpacing.x2,
                children: [
                  OutlinedButton.icon(
                    onPressed: _scanning ? null : _pickAttachments,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text(
                      _attachments.isEmpty ? 'Attach Files' : 'Add More Files',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _scanning || _attachments.isEmpty
                        ? null
                        : _scanAttachments,
                    icon: _scanning
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(
                      _scanning ? 'Scanning files...' : 'Scan & Auto-fill',
                    ),
                  ),
                ],
              ),
              if (_scanStatus != null) ...[
                const SizedBox(height: AppSpacing.x2),
                Text(
                  _scanStatus!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.success),
                ),
              ],
              if (_scanError != null) ...[
                const SizedBox(height: AppSpacing.x2),
                Text(
                  _scanError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (widget.patient['checkup_history']
                  case final List history) ...[
                const SizedBox(height: AppSpacing.x4),
                _PatientCheckupHistory(
                  records: history
                      .whereType<Map>()
                      .map((record) => Map<String, Object?>.from(record))
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: AppSpacing.x4),
              _CheckupSectionTitle(
                title: 'Optional measurements and medical information',
                subtitle:
                    'Record only what is clinically needed. This creates a new history entry and does not change patient identity details.',
              ),
              const SizedBox(height: AppSpacing.x3),
              _ClinicalCheckupFields(
                controllers: _controllers,
                showReasonForVisit: true,
                stackFields: true,
                onChanged: () => setState(() {}),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          final checkup = _controllers.draft();
          if (!checkup.hasAnyData) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Add at least one checkup detail before saving.'),
              ),
            );
            return;
          }
          Navigator.of(
            context,
          ).pop((checkup: checkup, attachments: List.of(_attachments)));
        },
        child: const Text('Save follow-up'),
      ),
    ],
  );
}

class _CheckupFormControllers {
  final reasonForVisit = TextEditingController();
  final heightCm = TextEditingController();
  final weightKg = TextEditingController();
  final bloodPressureSystolic = TextEditingController();
  final bloodPressureDiastolic = TextEditingController();
  final bodyTemperatureC = TextEditingController();
  final heartRateBpm = TextEditingController();
  final respiratoryRateBpm = TextEditingController();
  final oxygenSaturationPercent = TextEditingController();
  final currentSymptoms = TextEditingController();
  final knownMedicalConditions = TextEditingController();
  final allergies = TextEditingController();
  final currentMedications = TextEditingController();
  final relevantMedicalHistory = TextEditingController();
  final previousSurgeries = TextEditingController();
  final smokingStatus = TextEditingController();
  final alcoholUse = TextEditingController();
  final pregnancyStatus = TextEditingController();
  final doctorNotes = TextEditingController();

  int applyAiDraft(ClinicalCheckupDraft draft) {
    var filled = 0;
    void fill(TextEditingController controller, Object? value) {
      if (controller.text.trim().isNotEmpty || value == null) return;
      final text = switch (value) {
        final double number when number == number.roundToDouble() =>
          number.toInt().toString(),
        _ => value.toString().trim(),
      };
      if (text.isEmpty) return;
      controller.text = text;
      filled++;
    }

    fill(reasonForVisit, draft.reasonForVisit);
    fill(heightCm, draft.heightCm);
    fill(weightKg, draft.weightKg);
    fill(bloodPressureSystolic, draft.bloodPressureSystolic);
    fill(bloodPressureDiastolic, draft.bloodPressureDiastolic);
    fill(bodyTemperatureC, draft.bodyTemperatureC);
    fill(heartRateBpm, draft.heartRateBpm);
    fill(respiratoryRateBpm, draft.respiratoryRateBpm);
    fill(oxygenSaturationPercent, draft.oxygenSaturationPercent);
    fill(currentSymptoms, draft.currentSymptoms);
    fill(knownMedicalConditions, draft.knownMedicalConditions.join(', '));
    fill(allergies, draft.allergies.join(', '));
    fill(currentMedications, draft.currentMedications.join(', '));
    fill(relevantMedicalHistory, draft.relevantMedicalHistory);
    fill(previousSurgeries, draft.previousSurgeries);
    fill(smokingStatus, draft.smokingStatus);
    fill(alcoholUse, draft.alcoholUse);
    fill(pregnancyStatus, draft.pregnancyStatus);
    fill(doctorNotes, draft.doctorNotes);
    return filled;
  }

  ClinicalCheckupDraft draft({String? doctorNotesOverride}) =>
      ClinicalCheckupDraft(
        reasonForVisit: _optionalText(reasonForVisit.text),
        heightCm: double.tryParse(heightCm.text.trim()),
        weightKg: double.tryParse(weightKg.text.trim()),
        bloodPressureSystolic: int.tryParse(bloodPressureSystolic.text.trim()),
        bloodPressureDiastolic: int.tryParse(
          bloodPressureDiastolic.text.trim(),
        ),
        bodyTemperatureC: double.tryParse(bodyTemperatureC.text.trim()),
        heartRateBpm: int.tryParse(heartRateBpm.text.trim()),
        respiratoryRateBpm: int.tryParse(respiratoryRateBpm.text.trim()),
        oxygenSaturationPercent: double.tryParse(
          oxygenSaturationPercent.text.trim(),
        ),
        currentSymptoms: _optionalText(currentSymptoms.text),
        knownMedicalConditions: clinicalListValues(knownMedicalConditions.text),
        allergies: clinicalListValues(allergies.text),
        currentMedications: clinicalListValues(currentMedications.text),
        relevantMedicalHistory: _optionalText(relevantMedicalHistory.text),
        previousSurgeries: _optionalText(previousSurgeries.text),
        smokingStatus: _optionalText(smokingStatus.text),
        alcoholUse: _optionalText(alcoholUse.text),
        pregnancyStatus: _optionalText(pregnancyStatus.text),
        doctorNotes: _optionalText(doctorNotesOverride ?? doctorNotes.text),
      );

  void dispose() {
    reasonForVisit.dispose();
    heightCm.dispose();
    weightKg.dispose();
    bloodPressureSystolic.dispose();
    bloodPressureDiastolic.dispose();
    bodyTemperatureC.dispose();
    heartRateBpm.dispose();
    respiratoryRateBpm.dispose();
    oxygenSaturationPercent.dispose();
    currentSymptoms.dispose();
    knownMedicalConditions.dispose();
    allergies.dispose();
    currentMedications.dispose();
    relevantMedicalHistory.dispose();
    previousSurgeries.dispose();
    smokingStatus.dispose();
    alcoholUse.dispose();
    pregnancyStatus.dispose();
    doctorNotes.dispose();
  }
}

class _ClinicalCheckupFields extends StatelessWidget {
  const _ClinicalCheckupFields({
    required this.controllers,
    this.showReasonForVisit = false,
    this.reasonReadOnly = false,
    this.showDoctorNotes = true,
    this.stackFields = false,
    this.onChanged,
  });

  final _CheckupFormControllers controllers;
  final bool showReasonForVisit;
  final bool reasonReadOnly;
  final bool showDoctorNotes;
  final bool stackFields;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final height = double.tryParse(controllers.heightCm.text.trim());
    final weight = double.tryParse(controllers.weightKg.text.trim());
    final bmi = height != null && weight != null && height > 0
        ? weight / ((height / 100) * (height / 100))
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showReasonForVisit) ...[
          TextFormField(
            controller: controllers.reasonForVisit,
            readOnly: reasonReadOnly,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason for visit / chief complaint',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
        ],
        const _CheckupSectionTitle(
          title: 'Basic measurements / vitals',
          subtitle: 'All measurements are optional.',
        ),
        const SizedBox(height: AppSpacing.x3),
        _CheckupWrap(
          stacked: stackFields,
          children: [
            _optionalNumberField(
              controller: controllers.heightCm,
              label: 'Height (cm)',
              min: 30,
              max: 250,
              decimal: true,
              onChanged: onChanged,
            ),
            _optionalNumberField(
              controller: controllers.weightKg,
              label: 'Weight (kg)',
              min: 1,
              max: 500,
              decimal: true,
              onChanged: onChanged,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'BMI (calculated)',
            helperText: 'Automatically recalculates from height and weight.',
          ),
          child: Text(bmi == null ? '—' : bmi.toStringAsFixed(2)),
        ),
        const SizedBox(height: AppSpacing.x3),
        _CheckupWrap(
          stacked: stackFields,
          children: [
            _optionalNumberField(
              controller: controllers.bloodPressureSystolic,
              label: 'Blood pressure — systolic (mmHg)',
              min: 50,
              max: 300,
              decimal: false,
              onChanged: onChanged,
              validator: (value) => _bloodPressureValidator(
                value,
                other: controllers.bloodPressureDiastolic.text,
                systolic: true,
              ),
            ),
            _optionalNumberField(
              controller: controllers.bloodPressureDiastolic,
              label: 'Blood pressure — diastolic (mmHg)',
              min: 30,
              max: 200,
              decimal: false,
              onChanged: onChanged,
              validator: (value) => _bloodPressureValidator(
                value,
                other: controllers.bloodPressureSystolic.text,
                systolic: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x3),
        _CheckupWrap(
          stacked: stackFields,
          children: [
            _optionalNumberField(
              controller: controllers.bodyTemperatureC,
              label: 'Body temperature (°C)',
              min: 25,
              max: 45,
              decimal: true,
              onChanged: onChanged,
            ),
            _optionalNumberField(
              controller: controllers.heartRateBpm,
              label: 'Heart rate / pulse (bpm)',
              min: 20,
              max: 250,
              decimal: false,
              onChanged: onChanged,
            ),
            _optionalNumberField(
              controller: controllers.respiratoryRateBpm,
              label: 'Respiratory rate (breaths/min)',
              min: 5,
              max: 80,
              decimal: false,
              onChanged: onChanged,
            ),
            _optionalNumberField(
              controller: controllers.oxygenSaturationPercent,
              label: 'Oxygen saturation / SpO₂ (%)',
              min: 50,
              max: 100,
              decimal: true,
              onChanged: onChanged,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x5),
        const _CheckupSectionTitle(
          title: 'Basic medical information',
          subtitle:
              'Use separate fields so the patient history stays searchable.',
        ),
        const SizedBox(height: AppSpacing.x3),
        _optionalDocumentationField(
          controller: controllers.currentSymptoms,
          label: 'Current symptoms',
        ),
        const SizedBox(height: AppSpacing.x3),
        _optionalDocumentationField(
          controller: controllers.knownMedicalConditions,
          label: 'Known medical conditions',
          hint: 'Separate multiple conditions with commas or new lines.',
        ),
        const SizedBox(height: AppSpacing.x3),
        _optionalDocumentationField(
          controller: controllers.allergies,
          label: 'Allergies',
          hint: 'Separate multiple allergies with commas or new lines.',
        ),
        const SizedBox(height: AppSpacing.x3),
        _optionalDocumentationField(
          controller: controllers.currentMedications,
          label: 'Current medications',
          hint: 'Separate multiple medicines with commas or new lines.',
        ),
        const SizedBox(height: AppSpacing.x3),
        _optionalDocumentationField(
          controller: controllers.relevantMedicalHistory,
          label: 'Relevant medical history',
        ),
        const SizedBox(height: AppSpacing.x3),
        _optionalDocumentationField(
          controller: controllers.previousSurgeries,
          label: 'Previous surgeries, if applicable',
        ),
        const SizedBox(height: AppSpacing.x3),
        _CheckupWrap(
          stacked: stackFields,
          children: [
            _checkupDropdown(
              controller: controllers.smokingStatus,
              label: 'Smoking status',
              values: const {
                'never': 'Never',
                'former': 'Former smoker',
                'current': 'Current smoker',
                'unknown': 'Unknown',
              },
              onChanged: onChanged,
            ),
            _checkupDropdown(
              controller: controllers.alcoholUse,
              label: 'Alcohol use',
              values: const {
                'none': 'None',
                'occasional': 'Occasional',
                'regular': 'Regular',
                'unknown': 'Unknown',
              },
              onChanged: onChanged,
            ),
            _checkupDropdown(
              controller: controllers.pregnancyStatus,
              label: 'Pregnancy status, when applicable',
              values: const {
                'not_applicable': 'Not applicable',
                'not_pregnant': 'Not pregnant',
                'pregnant': 'Pregnant',
                'unknown': 'Unknown',
              },
              onChanged: onChanged,
            ),
          ],
        ),
        if (showDoctorNotes) ...[
          const SizedBox(height: AppSpacing.x3),
          _optionalDocumentationField(
            controller: controllers.doctorNotes,
            label: 'Doctor notes / observations',
          ),
        ],
      ],
    );
  }
}

class _CheckupWrap extends StatelessWidget {
  const _CheckupWrap({required this.children, this.stacked = false});

  final List<Widget> children;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const SizedBox(height: AppSpacing.x3),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 660
            ? (constraints.maxWidth - AppSpacing.x3) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.x3,
          runSpacing: AppSpacing.x3,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _CheckupSectionTitle extends StatelessWidget {
  const _CheckupSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      const SizedBox(height: AppSpacing.x1),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

class _PatientIdentitySummary extends StatelessWidget {
  const _PatientIdentitySummary({required this.patient});

  final Map<String, Object?> patient;

  @override
  Widget build(BuildContext context) {
    final firstName = patient['first_name']?.toString().trim() ?? '';
    final lastName = patient['last_name']?.toString().trim() ?? '';
    final name = patient['patient_name']?.toString().trim().isNotEmpty == true
        ? patient['patient_name'].toString().trim()
        : [firstName, lastName].where((value) => value.isNotEmpty).join(' ');
    final birthDate = DateTime.tryParse(
      patient['birth_date']?.toString() ?? '',
    );
    final entries = <String, String>{
      'Name': name,
      'Birth date': birthDate == null
          ? ''
          : DateFormat('MMM d, y').format(birthDate.toLocal()),
      'Sex': patient['sex']?.toString() ?? '',
      'Mobile': patient['mobile_number']?.toString() ?? '',
      'Email': patient['email']?.toString() ?? '',
      'Home address': patient['address']?.toString() ?? '',
    };
    final visible = entries.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Patient identity',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            spacing: AppSpacing.x4,
            runSpacing: AppSpacing.x2,
            children: [
              for (final entry in visible)
                SizedBox(
                  width: 250,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${entry.key}: ',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        TextSpan(text: entry.value),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            'Identity details are read-only here and come from the patient profile.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

Widget _optionalNumberField({
  required TextEditingController controller,
  required String label,
  required double min,
  required double max,
  required bool decimal,
  VoidCallback? onChanged,
  String? Function(String?)? validator,
}) => TextFormField(
  controller: controller,
  keyboardType: TextInputType.numberWithOptions(decimal: decimal),
  decoration: InputDecoration(labelText: label),
  validator:
      validator ??
      (value) =>
          _optionalRangeValidator(value, min: min, max: max, decimal: decimal),
  onChanged: (_) => onChanged?.call(),
);

Widget _optionalDocumentationField({
  required TextEditingController controller,
  required String label,
  String? hint,
}) => TextFormField(
  controller: controller,
  minLines: 2,
  maxLines: 4,
  maxLength: 2000,
  decoration: InputDecoration(
    labelText: label,
    hintText: hint,
    alignLabelWithHint: true,
  ),
);

Widget _checkupDropdown({
  required TextEditingController controller,
  required String label,
  required Map<String, String> values,
  VoidCallback? onChanged,
}) => DropdownButtonFormField<String>(
  initialValue: controller.text.isEmpty ? null : controller.text,
  isExpanded: true,
  decoration: InputDecoration(labelText: label),
  items: [
    const DropdownMenuItem<String>(child: Text('Not recorded')),
    for (final entry in values.entries)
      DropdownMenuItem(value: entry.key, child: Text(entry.value)),
  ],
  onChanged: (value) {
    controller.text = value ?? '';
    onChanged?.call();
  },
);

String? _optionalRangeValidator(
  String? value, {
  required double min,
  required double max,
  required bool decimal,
}) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final parsed = decimal
      ? double.tryParse(normalized)
      : int.tryParse(normalized);
  if (parsed == null) return 'Enter a valid number.';
  if (parsed < min || parsed > max) {
    return 'Enter a value from $min to $max.';
  }
  return null;
}

String? _bloodPressureValidator(
  String? value, {
  required String other,
  required bool systolic,
}) {
  final normalized = value?.trim() ?? '';
  final otherValue = int.tryParse(other.trim());
  final current = int.tryParse(normalized);
  final rangeError = _optionalRangeValidator(
    value,
    min: systolic ? 50 : 30,
    max: systolic ? 300 : 200,
    decimal: false,
  );
  if (rangeError != null) return rangeError;
  if (current != null && otherValue != null) {
    final valid = systolic ? current > otherValue : otherValue > current;
    if (!valid) return 'Systolic must be higher than diastolic.';
  }
  return null;
}

String? _optionalText(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

class _ClinicalDocumentationField extends StatelessWidget {
  const _ClinicalDocumentationField({
    required this.controller,
    required this.label,
    required this.requiredLength,
  });

  final TextEditingController controller;
  final String label;
  final int requiredLength;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    minLines: 2,
    maxLines: 5,
    maxLength: 4000,
    decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
    validator: (value) => (value?.trim().length ?? 0) < requiredLength
        ? 'Enter at least $requiredLength characters.'
        : null,
  );
}

class _ReservationDialog extends StatefulWidget {
  const _ReservationDialog({
    required this.clinicians,
    required this.repository,
    required this.profile,
    this.initialHospitalId,
    this.initialDoctorId,
  });

  final List<DoctorDirectoryEntry> clinicians;
  final ConsultationRepository repository;
  final CareProfile profile;
  final String? initialHospitalId;
  final String? initialDoctorId;

  @override
  State<_ReservationDialog> createState() => _ReservationDialogState();
}

class _ReservationDialogState extends State<_ReservationDialog> {
  static const _consultationAccessCategory = 'consultations';
  static const _recordCategoryLabels = <String, String>{
    'medical_records': 'Medical records',
    'diagnoses': 'Diagnoses',
    'prescriptions': 'Prescriptions',
    'laboratory_requests': 'Laboratory requests',
    'laboratory_results': 'Diagnostic results',
    'medical_documents': 'Medical documents',
    'allergies_medications': 'Allergies and medications',
    'treatment_plans': 'Treatment plans',
  };

  final _formKey = GlobalKey<FormState>();
  final _complaintController = TextEditingController();
  final _symptomDurationController = TextEditingController();
  final Set<String> _sharedCategories = {..._recordCategoryLabels.keys};
  late String _hospitalId;
  late DoctorDirectoryEntry _clinician;
  late String _consultationType;
  List<AvailableConsultationSlot> _slots = const [];
  DateTime? _selectedDate;
  AvailableConsultationSlot? _selectedSlot;
  String? _availabilityError;
  bool _loadingSlots = true;

  List<DoctorDirectoryEntry> get _hospitalChoices {
    final choices = <String, DoctorDirectoryEntry>{};
    for (final entry in widget.clinicians) {
      choices.putIfAbsent(entry.hospitalId, () => entry);
    }
    return choices.values.toList(growable: false);
  }

  List<DoctorDirectoryEntry> get _hospitalClinicians => widget.clinicians
      .where((entry) => entry.hospitalId == _hospitalId)
      .toList(growable: false);

  DateTime _philippineTime(DateTime value) =>
      value.toUtc().add(const Duration(hours: 8));

  @override
  void initState() {
    super.initState();
    DoctorDirectoryEntry? preferredClinician;
    if (widget.initialHospitalId != null) {
      final hospitalClinicians = widget.clinicians
          .where((entry) => entry.hospitalId == widget.initialHospitalId)
          .toList(growable: false);
      if (widget.initialDoctorId != null) {
        for (final entry in hospitalClinicians) {
          if (entry.hospitalIsAvailable &&
              entry.doctor.id == widget.initialDoctorId) {
            preferredClinician = entry;
            break;
          }
        }
      }
      if (preferredClinician == null) {
        for (final entry in hospitalClinicians) {
          if (entry.hospitalIsAvailable) {
            preferredClinician = entry;
            break;
          }
        }
      }
    } else if (widget.initialDoctorId != null) {
      for (final entry in widget.clinicians) {
        if (entry.hospitalIsAvailable &&
            entry.doctor.id == widget.initialDoctorId) {
          preferredClinician = entry;
          break;
        }
      }
    }
    _clinician =
        preferredClinician ??
        widget.clinicians.firstWhere(
          (entry) => entry.hospitalIsAvailable,
          orElse: () => widget.clinicians.first,
        );
    _hospitalId = _clinician.hospitalId;
    _consultationType = _clinician.doctor.publishedConsultationTypes.first;
    _loadSlots();
  }

  void _selectHospital(String hospitalId) {
    final clinicians = widget.clinicians
        .where((entry) => entry.hospitalId == hospitalId)
        .toList(growable: false);
    final clinician = clinicians.firstWhere(
      (entry) => entry.hospitalIsAvailable,
      orElse: () => clinicians.first,
    );
    setState(() {
      _hospitalId = hospitalId;
      _clinician = clinician;
      _consultationType = clinician.doctor.publishedConsultationTypes.first;
    });
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    final doctorId = _clinician.doctor.id;
    final consultationType = _consultationType;
    setState(() {
      _loadingSlots = true;
      _availabilityError = null;
      _slots = const [];
      _selectedDate = null;
      _selectedSlot = null;
    });
    if (!_clinician.hospitalIsAvailable) {
      setState(() => _loadingSlots = false);
      return;
    }
    try {
      final slots = await widget.repository.listAvailableSlots(
        doctorId: doctorId,
        consultationType: consultationType,
      );
      if (!mounted ||
          doctorId != _clinician.doctor.id ||
          consultationType != _consultationType) {
        return;
      }
      setState(() {
        _slots = slots;
        _selectedDate = slots.isEmpty
            ? null
            : DateUtils.dateOnly(_philippineTime(slots.first.startsAt));
        _selectedSlot = slots.isEmpty ? null : slots.first;
        _loadingSlots = false;
      });
    } catch (error) {
      if (!mounted ||
          doctorId != _clinician.doctor.id ||
          consultationType != _consultationType) {
        return;
      }
      setState(() {
        _availabilityError = error is RepositoryFailure
            ? error.message
            : 'Available appointment times could not be loaded.';
        _loadingSlots = false;
      });
    }
  }

  List<DateTime> get _availableDates {
    final dates = <DateTime>{};
    for (final slot in _slots) {
      dates.add(DateUtils.dateOnly(_philippineTime(slot.startsAt)));
    }
    return dates.toList()..sort();
  }

  List<AvailableConsultationSlot> get _slotsForSelectedDate => _slots
      .where(
        (slot) =>
            DateUtils.isSameDay(_philippineTime(slot.startsAt), _selectedDate),
      )
      .toList(growable: false);

  bool get _selectedSlotIsAvailable =>
      _clinician.hospitalIsAvailable &&
      !_loadingSlots &&
      _selectedSlot != null &&
      _slots.contains(_selectedSlot) &&
      meetsReservationLeadTime(_selectedSlot!.startsAt);

  @override
  void dispose() {
    _complaintController.dispose();
    _symptomDurationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = _clinician.doctor.publishedConsultationTypes;
    final hospitalChoices = _hospitalChoices;
    final hospitalClinicians = _hospitalClinicians;
    final hasAvailableHospitals = hospitalChoices.any(
      (entry) => entry.hospitalIsAvailable,
    );
    final hasAvailableClinicians = hospitalClinicians.any(
      (entry) => entry.hospitalIsAvailable,
    );
    return AlertDialog(
      icon: const Icon(Icons.event_available_outlined),
      title: const Text('Reserve consultation'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.x3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account profile used for this request',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        '${widget.profile.firstName} ${widget.profile.lastName}',
                      ),
                      Text(
                        [widget.profile.mobileNumber, widget.profile.email]
                            .whereType<String>()
                            .where((value) => value.trim().isNotEmpty)
                            .join(' • '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (widget.profile.birthDate != null)
                        Text(
                          'Birth date: ${DateFormat('MMM d, y').format(widget.profile.birthDate!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (widget.profile.address?.trim().isNotEmpty ?? false)
                        Text(
                          widget.profile.address!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            context.go('/patient/profile');
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Update profile'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.x4),
                DropdownButtonFormField<String>(
                  key: const Key('reservation-hospital-dropdown'),
                  initialValue: _hospitalId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Hospital',
                    prefixIcon: Icon(Icons.local_hospital_outlined),
                  ),
                  items: [
                    for (final entry in hospitalChoices)
                      DropdownMenuItem(
                        value: entry.hospitalId,
                        enabled: entry.hospitalIsAvailable,
                        child: Text(
                          entry.hospitalIsAvailable
                              ? '${entry.hospitalName} — ${entry.locationLabel}'
                              : '${entry.hospitalName} (unavailable)',
                          overflow: TextOverflow.ellipsis,
                          style: entry.hospitalIsAvailable
                              ? null
                              : const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                  ],
                  onChanged: !hasAvailableHospitals
                      ? null
                      : (value) {
                          if (value != null && value != _hospitalId) {
                            _selectHospital(value);
                          }
                        },
                ),
                const SizedBox(height: AppSpacing.x4),
                DropdownButtonFormField<DoctorDirectoryEntry>(
                  key: ValueKey('reservation-clinician-$_hospitalId'),
                  initialValue: _clinician,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Clinician',
                    prefixIcon: Icon(Icons.medical_services_outlined),
                  ),
                  items: [
                    for (final entry in hospitalClinicians)
                      DropdownMenuItem(
                        value: entry,
                        enabled: entry.hospitalIsAvailable,
                        child: Text(
                          entry.hospitalIsAvailable
                              ? '${entry.doctor.displayLabel} — ${entry.doctor.specialtyLabel}'
                              : '${entry.doctor.displayLabel} (unavailable)',
                          overflow: TextOverflow.ellipsis,
                          style: entry.hospitalIsAvailable
                              ? null
                              : const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                  ],
                  onChanged: !hasAvailableClinicians
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _clinician = value;
                            _consultationType =
                                value.doctor.publishedConsultationTypes.first;
                          });
                          _loadSlots();
                        },
                ),
                const SizedBox(height: AppSpacing.x4),
                DropdownButtonFormField<String>(
                  key: ValueKey('${_clinician.doctor.id}-$_consultationType'),
                  initialValue: _consultationType,
                  decoration: const InputDecoration(labelText: 'Care mode'),
                  items: [
                    for (final type in types)
                      DropdownMenuItem(
                        value: type,
                        child: Text(type == 'online' ? 'Online' : 'In person'),
                      ),
                  ],
                  onChanged: !_clinician.hospitalIsAvailable
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _consultationType = value);
                            _loadSlots();
                          }
                        },
                ),
                const SizedBox(height: AppSpacing.x4),
                if (_consultationType == 'online') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.x3),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: const Text(
                      'This submits a preferred schedule for hospital review. It does not reserve the slot or create an official appointment until the hospital confirms a doctor, time, and channel.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  TextFormField(
                    controller: _symptomDurationController,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'How long have you had these symptoms?',
                      hintText: 'For example: 3 days',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter the symptom duration.'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Records to share for this care relationship',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Records from another hospital remain read-only and keep their original hospital and author.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  for (final entry in _recordCategoryLabels.entries)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _sharedCategories.contains(entry.key),
                      title: Text(entry.value),
                      onChanged: (selected) => setState(() {
                        if (selected == true) {
                          _sharedCategories.add(entry.key);
                        } else {
                          _sharedCategories.remove(entry.key);
                        }
                      }),
                    ),
                  if (_sharedCategories.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose at least one record category.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.x4),
                ],
                TextFormField(
                  controller: _complaintController,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Primary care concern',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    final minimum = _consultationType == 'online' ? 10 : 5;
                    return (value?.trim().length ?? 0) < minimum
                        ? 'Describe the concern in at least $minimum characters.'
                        : null;
                  },
                ),
                const SizedBox(height: AppSpacing.x4),
                if (_loadingSlots)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.x4),
                    child: CircularProgressIndicator(),
                  )
                else if (_availabilityError != null)
                  Column(
                    children: [
                      Text(
                        _availabilityError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _loadSlots,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry availability'),
                      ),
                    ],
                  )
                else if (_slots.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No reservable appointment times are published for this clinician and care mode in the next 30 days. Reservations require at least 24 hours of notice.',
                    ),
                  )
                else ...[
                  DropdownButtonFormField<DateTime>(
                    key: ValueKey(
                      '${_clinician.doctor.id}-$_consultationType-${_slots.length}',
                    ),
                    initialValue: _selectedDate,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _consultationType == 'online'
                          ? 'Preferred date'
                          : 'Available date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    items: [
                      for (final date in _availableDates)
                        DropdownMenuItem(
                          value: date,
                          child: Text(
                            DateFormat('EEEE, MMMM d, y').format(date),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedDate = value;
                        _selectedSlot = _slots.firstWhere(
                          (slot) => DateUtils.isSameDay(
                            _philippineTime(slot.startsAt),
                            value,
                          ),
                        );
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Available time',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: AppSpacing.x2,
                      runSpacing: AppSpacing.x2,
                      children: [
                        for (final slot in _slotsForSelectedDate)
                          ChoiceChip(
                            label: Text(
                              DateFormat(
                                'h:mm a',
                              ).format(_philippineTime(slot.startsAt)),
                            ),
                            selected: identical(slot, _selectedSlot),
                            onSelected: (_) =>
                                setState(() => _selectedSlot = slot),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _consultationType == 'online'
                          ? 'Times shown are preferred options only. The hospital rechecks availability during review (Philippine time).'
                          : "Times shown are the clinician's published, currently unoccupied slots at least 24 hours away (Philippine time).",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('reserve-consultation-submit'),
          style: FilledButton.styleFrom(
            disabledBackgroundColor: AppColors.border,
            disabledForegroundColor: AppColors.textMuted,
          ),
          onPressed:
              !_selectedSlotIsAvailable ||
                  (_consultationType == 'online' && _sharedCategories.isEmpty)
              ? null
              : () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  Navigator.of(context).pop(
                    _ReservationDraft(
                      clinician: _clinician,
                      consultationType: _consultationType,
                      chiefComplaint: _complaintController.text.trim(),
                      symptomDuration: _consultationType == 'online'
                          ? _symptomDurationController.text.trim()
                          : 'Not specified',
                      sharedCategories: _consultationType == 'online'
                          ? [_consultationAccessCategory, ..._sharedCategories]
                          : const [],
                      appointmentDate: _selectedSlot!.startsAt,
                    ),
                  );
                },
          child: Text(
            _consultationType == 'online'
                ? 'Submit request for review'
                : 'Reserve consultation',
          ),
        ),
      ],
    );
  }
}

class _GuestDoctorSelectionDialog extends StatelessWidget {
  const _GuestDoctorSelectionDialog({required this.doctors});

  final List<GuestReviewDoctor> doctors;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.person_search_outlined),
    title: const Text('Choose an eligible doctor'),
    content: SizedBox(
      width: 520,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: doctors.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doctor = doctors[index];
            return ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.medical_services_outlined),
              ),
              title: Text(doctor.displayName),
              subtitle: Text(doctor.specialization),
              onTap: () => Navigator.of(context).pop(doctor),
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _PrescriptionDialog extends StatefulWidget {
  const _PrescriptionDialog({
    required this.relationships,
    required this.repository,
    required this.prescriber,
    required this.showRelationshipField,
  });

  final List<ClinicalRelationship> relationships;
  final CareRepository repository;
  final PrescriberDetails? prescriber;
  final bool showRelationshipField;

  @override
  State<_PrescriptionDialog> createState() => _PrescriptionDialogState();
}

class _PrescriptionDialogState extends State<_PrescriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _diagnosisController = TextEditingController();
  final List<_EditablePrescriptionMedication> _medications = [
    _EditablePrescriptionMedication(),
  ];
  late ClinicalRelationship _relationship = widget.relationships.first;
  bool _scanning = false;
  bool _scanCompleted = false;
  bool _previewing = false;
  String? _scanError;
  ({List<int> bytes, String name})? _attachment;

  Future<void> _pickAttachment() async {
    const acceptedTypes = XTypeGroup(
      label: 'Medical files',
      extensions: ['pdf', 'jpg', 'jpeg', 'png'],
      mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
    );
    final selected = await openFile(acceptedTypeGroups: const [acceptedTypes]);
    if (selected == null) return;
    final bytes = await selected.readAsBytes();
    if (!mounted) return;
    final attachment = (bytes: bytes, name: selected.name);
    setState(() {
      _attachment = attachment;
      _scanning = true;
      _scanCompleted = false;
      _scanError = null;
    });
    try {
      final extracted = await widget.repository
          .extractPrescriptionsFromAttachment(attachment: attachment);
      if (!mounted || _attachment != attachment) return;
      _applyScan(extracted);
      setState(() {
        _scanning = false;
        _scanCompleted = true;
      });
    } catch (error) {
      if (!mounted || _attachment != attachment) return;
      setState(() {
        _scanning = false;
        _scanError = _friendlyError(error);
      });
    }
  }

  void _applyScan(List<PrescriptionScanDraft> scans) {
    if (scans.isEmpty) return;
    final diagnosis = scans
        .map((scan) => scan.diagnosisReason?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (diagnosis != null) _diagnosisController.text = diagnosis;
    final medications = scans
        .map(_EditablePrescriptionMedication.fromScan)
        .toList(growable: false);
    for (final medication in _medications) {
      medication.dispose();
    }
    _medications
      ..clear()
      ..addAll(medications);
  }

  Future<void> _chooseStartDate(
    _EditablePrescriptionMedication medication,
  ) async {
    final value = await showDatePicker(
      context: context,
      initialDate: medication.startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value == null || !mounted) return;
    setState(() {
      medication.startDate = DateUtils.dateOnly(value);
      if (medication.endDate != null &&
          medication.endDate!.isBefore(medication.startDate)) {
        medication.endDate = null;
      }
    });
  }

  Future<void> _chooseEndDate(
    _EditablePrescriptionMedication medication,
  ) async {
    final value = await showDatePicker(
      context: context,
      initialDate: medication.endDate ?? medication.startDate,
      firstDate: medication.startDate,
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      setState(() => medication.endDate = DateUtils.dateOnly(value));
    }
  }

  void _addMedication() {
    setState(() => _medications.add(_EditablePrescriptionMedication()));
  }

  void _removeMedication(_EditablePrescriptionMedication medication) {
    if (_medications.length == 1) return;
    setState(() => _medications.remove(medication));
    medication.dispose();
  }

  void _showPreview() {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _scanning) return;
    setState(() => _previewing = true);
  }

  _PrescriptionDraft _draft() => _PrescriptionDraft(
    relationship: _relationship,
    diagnosisReason: _diagnosisController.text.trim(),
    medications: _medications
        .map((medication) => medication.toDraft())
        .toList(growable: false),
    attachment: _attachment,
  );

  @override
  void dispose() {
    _diagnosisController.dispose();
    for (final medication in _medications) {
      medication.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x6,
      ),
      icon: const Icon(Icons.medication_outlined),
      title: Text(_previewing ? 'Confirm prescription' : 'Issue prescription'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: _previewing
            ? _buildPreview(context)
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.showRelationshipField) ...[
                      _ClinicalRelationshipField(
                        value: _relationship,
                        relationships: widget.relationships,
                        onChanged: (value) =>
                            setState(() => _relationship = value),
                      ),
                      const SizedBox(height: AppSpacing.x4),
                    ],
                    Text(
                      'Attach and scan first (optional)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      'A PDF or clear image will be scanned to prefill the editable fields below. Always verify the result.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    OutlinedButton.icon(
                      onPressed: _scanning ? null : _pickAttachment,
                      icon: _scanning
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.document_scanner_outlined,
                              size: 18,
                            ),
                      label: Text(
                        _scanning
                            ? 'Scanning attachment…'
                            : _attachment == null
                            ? 'Attach and scan file'
                            : 'Change and rescan file',
                      ),
                    ),
                    if (_attachment != null) ...[
                      const SizedBox(height: AppSpacing.x2),
                      Row(
                        children: [
                          const Icon(Icons.attachment, size: 16),
                          const SizedBox(width: AppSpacing.x2),
                          Expanded(
                            child: Text(
                              _attachment!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove attachment',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _scanning
                                ? null
                                : () => setState(() {
                                    _attachment = null;
                                    _scanCompleted = false;
                                    _scanError = null;
                                  }),
                          ),
                        ],
                      ),
                    ],
                    if (_scanCompleted)
                      Text(
                        'Scan complete. Review every autofilled value before issuing.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    if (_scanError != null)
                      Text(
                        'Scan unavailable: $_scanError You can still enter the prescription manually.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.x5),
                    TextFormField(
                      controller: _diagnosisController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        labelText: 'Why it was prescribed',
                        hintText: 'Short diagnosis or reason',
                      ),
                      validator: _requiredClinicalValue,
                    ),
                    const SizedBox(height: AppSpacing.x4),
                    Text(
                      'Medications',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      'Add a complete order for each medication. A scan can create several editable entries automatically.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    for (
                      var index = 0;
                      index < _medications.length;
                      index++
                    ) ...[
                      _buildMedicationEditor(
                        context,
                        medication: _medications[index],
                        index: index,
                      ),
                      const SizedBox(height: AppSpacing.x3),
                    ],
                    OutlinedButton.icon(
                      key: const Key('add-prescription-medication'),
                      onPressed: _addMedication,
                      icon: const Icon(Icons.add),
                      label: const Text('Add another medication'),
                    ),
                    const SizedBox(height: AppSpacing.x5),
                    Text(
                      'Prescriber',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    if (widget.prescriber == null)
                      Text(
                        'Complete your prescriber name and license number in your profile before issuing.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(widget.prescriber!.name),
                        subtitle: Text(
                          [
                            if (widget.prescriber!.specialization != null)
                              widget.prescriber!.specialization!,
                            'License ${widget.prescriber!.licenseNumber}',
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_previewing)
          TextButton(
            onPressed: () => setState(() => _previewing = false),
            child: const Text('Back to edit'),
          ),
        FilledButton(
          onPressed: _previewing
              ? () => Navigator.of(context).pop(_draft())
              : _showPreview,
          child: Text(_previewing ? 'Confirm & issue' : 'Preview prescription'),
        ),
      ],
    );
  }

  Widget _buildMedicationEditor(
    BuildContext context, {
    required _EditablePrescriptionMedication medication,
    required int index,
  }) {
    return Card(
      key: ObjectKey(medication),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Medication ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (_medications.length > 1)
                  IconButton(
                    tooltip: 'Remove medication ${index + 1}',
                    onPressed: () => _removeMedication(medication),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            TextFormField(
              controller: medication.nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Medication name'),
              validator: _requiredClinicalValue,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: medication.formStrengthController,
              decoration: const InputDecoration(
                labelText: 'Medication form and strength',
                hintText: 'Example: 500 mg tablet',
              ),
              validator: _requiredClinicalValue,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: medication.routeController,
              decoration: const InputDecoration(
                labelText: 'Route',
                hintText: 'Example: oral, topical, inhaled',
              ),
              validator: _requiredClinicalValue,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: medication.exactDoseController,
              decoration: const InputDecoration(
                labelText: 'Exact dose per intake',
                hintText: 'Example: 1 tablet or 5 mL',
              ),
              validator: _requiredClinicalValue,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: medication.frequencyController,
              decoration: const InputDecoration(
                labelText: 'Frequency',
                hintText: 'Example: Every 8 hours',
              ),
              validator: _requiredClinicalValue,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: medication.durationController,
              decoration: const InputDecoration(
                labelText: 'Duration',
                hintText: 'Example: 7 days',
              ),
              validator: _requiredClinicalValue,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: medication.quantityController,
              decoration: const InputDecoration(
                labelText: 'Total quantity to dispense',
                hintText: 'Example: 21 tablets',
              ),
              validator: _requiredClinicalValue,
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: medication.refillsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of refills',
                helperText: 'Enter 0 for no refills',
              ),
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                return parsed == null || parsed < 0 || parsed > 99
                    ? 'Enter a whole number from 0 to 99.'
                    : null;
              },
            ),
            const SizedBox(height: AppSpacing.x4),
            Wrap(
              spacing: AppSpacing.x2,
              runSpacing: AppSpacing.x2,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _chooseStartDate(medication),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    'Start: ${DateFormat.yMMMd().format(medication.startDate)}',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _chooseEndDate(medication),
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(
                    medication.endDate == null
                        ? 'Add end date'
                        : 'End: ${DateFormat.yMMMd().format(medication.endDate!)}',
                  ),
                ),
                if (medication.endDate != null)
                  IconButton(
                    tooltip: 'Clear end date for medication ${index + 1}',
                    onPressed: () => setState(() => medication.endDate = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.x3),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Take as needed (PRN)'),
              subtitle: const Text(
                'Requires a PRN reason and maximum daily dose.',
              ),
              value: medication.isPrn,
              onChanged: (value) => setState(() => medication.isPrn = value),
            ),
            if (medication.isPrn) ...[
              const SizedBox(height: AppSpacing.x2),
              TextFormField(
                controller: medication.prnReasonController,
                decoration: const InputDecoration(
                  labelText: 'PRN reason',
                  hintText: 'Example: for breakthrough pain',
                ),
                validator: _requiredClinicalValue,
              ),
              const SizedBox(height: AppSpacing.x4),
              TextFormField(
                controller: medication.maximumDailyDoseController,
                decoration: const InputDecoration(
                  labelText: 'Maximum daily dose',
                  hintText: 'Example: maximum 4 tablets in 24 hours',
                ),
                validator: _requiredClinicalValue,
              ),
            ],
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: medication.instructionsController,
              minLines: 1,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Extra instructions (optional)',
                helperText:
                    'Only add details not already covered by dose, frequency, or duration.',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final rows = <(String, String)>[
      (
        'Patient',
        _relationship.hasConsultation
            ? '${_relationship.patientLabel} — ${_relationship.consultationLabel}'
            : _relationship.patientLabel,
      ),
      ('Diagnosis / reason', _diagnosisController.text.trim()),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review every detail before issuing. After confirmation, the prescription and attachment become part of the patient record.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.x4),
        for (final row in rows) ...[
          Text(row.$1, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.x1),
          SelectableText(row.$2),
          const Divider(height: AppSpacing.x5),
        ],
        for (var index = 0; index < _medications.length; index++)
          ..._buildMedicationPreview(context, index),
        if (_attachment != null)
          ..._buildPreviewRow(context, 'Attachment', _attachment!.name),
        ..._buildPreviewRow(
          context,
          'Prescriber',
          widget.prescriber?.name ?? 'Unavailable',
        ),
        ..._buildPreviewRow(
          context,
          'License',
          widget.prescriber?.licenseNumber ?? 'Unavailable',
        ),
      ],
    );
  }

  List<Widget> _buildMedicationPreview(BuildContext context, int index) {
    final medication = _medications[index];
    return [
      Text(
        'Medication ${index + 1}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: AppSpacing.x2),
      ..._buildPreviewRow(
        context,
        'Medication',
        medication.nameController.text.trim(),
      ),
      ..._buildPreviewRow(
        context,
        'Form and strength',
        medication.formStrengthController.text.trim(),
      ),
      ..._buildPreviewRow(
        context,
        'Route',
        medication.routeController.text.trim(),
      ),
      ..._buildPreviewRow(
        context,
        'Dose per intake',
        medication.exactDoseController.text.trim(),
      ),
      ..._buildPreviewRow(
        context,
        'Frequency',
        medication.frequencyController.text.trim(),
      ),
      ..._buildPreviewRow(
        context,
        'Duration',
        medication.durationController.text.trim(),
      ),
      ..._buildPreviewRow(
        context,
        'Quantity',
        medication.quantityController.text.trim(),
      ),
      ..._buildPreviewRow(
        context,
        'Refills',
        medication.refillsController.text.trim() == '0'
            ? 'No refills'
            : medication.refillsController.text.trim(),
      ),
      ..._buildPreviewRow(
        context,
        'Start date',
        DateFormat.yMMMMd().format(medication.startDate),
      ),
      if (medication.endDate != null)
        ..._buildPreviewRow(
          context,
          'End date',
          DateFormat.yMMMMd().format(medication.endDate!),
        ),
      if (medication.isPrn)
        ..._buildPreviewRow(
          context,
          'PRN reason',
          medication.prnReasonController.text.trim(),
        ),
      if (medication.isPrn)
        ..._buildPreviewRow(
          context,
          'Maximum daily dose',
          medication.maximumDailyDoseController.text.trim(),
        ),
      if (medication.instructionsController.text.trim().isNotEmpty)
        ..._buildPreviewRow(
          context,
          'Instructions',
          medication.instructionsController.text.trim(),
        ),
    ];
  }

  List<Widget> _buildPreviewRow(
    BuildContext context,
    String label,
    String value,
  ) => [
    Text(label, style: Theme.of(context).textTheme.labelMedium),
    const SizedBox(height: AppSpacing.x1),
    SelectableText(value),
    const Divider(height: AppSpacing.x5),
  ];
}

class _EditablePrescriptionMedication {
  _EditablePrescriptionMedication({
    DateTime? startDate,
    this.endDate,
    this.isPrn = false,
  }) : startDate = DateUtils.dateOnly(startDate ?? DateTime.now());

  factory _EditablePrescriptionMedication.fromScan(PrescriptionScanDraft scan) {
    final medication = _EditablePrescriptionMedication(
      startDate: scan.startDate,
      endDate: scan.endDate,
      isPrn: scan.isPrn,
    );
    medication._fill(medication.nameController, scan.medicationName);
    medication._fill(
      medication.formStrengthController,
      scan.medicationFormStrength,
    );
    medication._fill(medication.routeController, scan.route);
    medication._fill(medication.exactDoseController, scan.exactDose);
    medication._fill(medication.frequencyController, scan.frequency);
    medication._fill(medication.durationController, scan.duration);
    medication._fill(medication.quantityController, scan.quantityToDispense);
    if (scan.refills != null) {
      medication.refillsController.text = '${scan.refills}';
    }
    medication._fill(medication.prnReasonController, scan.prnReason);
    medication._fill(
      medication.maximumDailyDoseController,
      scan.maximumDailyDose,
    );
    medication._fill(medication.instructionsController, scan.instructions);
    return medication;
  }

  final nameController = TextEditingController();
  final formStrengthController = TextEditingController();
  final routeController = TextEditingController();
  final exactDoseController = TextEditingController();
  final frequencyController = TextEditingController();
  final durationController = TextEditingController();
  final quantityController = TextEditingController();
  final refillsController = TextEditingController(text: '0');
  final prnReasonController = TextEditingController();
  final maximumDailyDoseController = TextEditingController();
  final instructionsController = TextEditingController();
  DateTime startDate;
  DateTime? endDate;
  bool isPrn;

  void _fill(TextEditingController controller, String? value) {
    if (value != null && value.trim().isNotEmpty) {
      controller.text = value.trim();
    }
  }

  _PrescriptionMedicationDraft toDraft() => _PrescriptionMedicationDraft(
    medicationName: nameController.text.trim(),
    medicationFormStrength: formStrengthController.text.trim(),
    route: routeController.text.trim(),
    exactDose: exactDoseController.text.trim(),
    frequency: frequencyController.text.trim(),
    duration: durationController.text.trim(),
    quantityToDispense: quantityController.text.trim(),
    refills: int.parse(refillsController.text.trim()),
    startDate: startDate,
    endDate: endDate,
    isPrn: isPrn,
    prnReason: prnReasonController.text.trim(),
    maximumDailyDose: maximumDailyDoseController.text.trim(),
    instructions: instructionsController.text.trim(),
  );

  void dispose() {
    nameController.dispose();
    formStrengthController.dispose();
    routeController.dispose();
    exactDoseController.dispose();
    frequencyController.dispose();
    durationController.dispose();
    quantityController.dispose();
    refillsController.dispose();
    prnReasonController.dispose();
    maximumDailyDoseController.dispose();
    instructionsController.dispose();
  }
}

class _LaboratoryRequestDraft {
  const _LaboratoryRequestDraft({
    required this.relationship,
    required this.testName,
    required this.priority,
    required this.instructions,
    this.attachment,
  });

  final ClinicalRelationship relationship;
  final String testName;
  final String priority;
  final String instructions;
  final ({List<int> bytes, String name})? attachment;
}

class _LaboratoryResultUploadDraft {
  const _LaboratoryResultUploadDraft({
    required this.relationship,
    required this.reports,
  });

  final ClinicalRelationship relationship;
  final List<_DiagnosticResultUploadItem> reports;
}

class _DiagnosticResultUploadItem {
  const _DiagnosticResultUploadItem({
    required this.category,
    required this.testProcedureName,
    required this.testProcedureNameAiGenerated,
    required this.performedOrCollectedDate,
    required this.performedOrCollectedDateText,
    required this.resultDate,
    required this.resultDateText,
    required this.facility,
    required this.requestingDoctor,
    required this.patientNameOnReport,
    required this.attachment,
    required this.procedureDetails,
    required this.resultDetails,
    required this.officialFindingsImpression,
    required this.recommendations,
    required this.technicalSummary,
    required this.patientFriendlySummary,
    required this.verificationNotes,
    required this.notes,
  });

  final String category;
  final String testProcedureName;
  final bool testProcedureNameAiGenerated;
  final DateTime? performedOrCollectedDate;
  final String? performedOrCollectedDateText;
  final DateTime? resultDate;
  final String? resultDateText;
  final String? facility;
  final String? requestingDoctor;
  final String? patientNameOnReport;
  final ({List<int> bytes, String name}) attachment;
  final String? procedureDetails;
  final String? resultDetails;
  final String? officialFindingsImpression;
  final String? recommendations;
  final String? technicalSummary;
  final String? patientFriendlySummary;
  final String? verificationNotes;
  final String? notes;
}

class _LaboratoryResultUploadDialog extends StatefulWidget {
  const _LaboratoryResultUploadDialog({
    required this.relationships,
    required this.repository,
    required this.showRelationshipField,
  });

  final List<ClinicalRelationship> relationships;
  final CareRepository repository;
  final bool showRelationshipField;

  @override
  State<_LaboratoryResultUploadDialog> createState() =>
      _LaboratoryResultUploadDialogState();
}

class _LaboratoryResultUploadDialogState
    extends State<_LaboratoryResultUploadDialog> {
  static const _maximumAttachmentBytes = 20 * 1024 * 1024;
  static const _maximumScanBytes = 2 * 1024 * 1024;
  static const _maximumAttachments = 5;
  static const _categories = <String, String>{
    'laboratory': 'Laboratory',
    'x_ray': 'X-ray',
    'ct_scan': 'CT scan',
    'mri': 'MRI',
    'ultrasound': 'Ultrasound',
    'ecg': 'ECG',
    'pathology': 'Pathology',
    'other': 'Other',
  };

  final _formKey = GlobalKey<FormState>();
  late ClinicalRelationship _relationship = widget.relationships.first;
  List<({List<int> bytes, String name})> _attachments = [];
  final List<_EditableDiagnosticReport> _reports = [];
  String? _attachmentError;
  bool _pickingAttachment = false;
  bool _scanning = false;
  bool _scanCompleted = false;
  String? _scanError;

  Future<void> _pickAttachments() async {
    const acceptedTypes = XTypeGroup(
      label: 'Diagnostic result files',
      extensions: ['pdf', 'jpg', 'jpeg', 'png'],
      mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
    );
    setState(() {
      _pickingAttachment = true;
      _attachmentError = null;
    });
    try {
      final selected = await openFiles(
        acceptedTypeGroups: const [acceptedTypes],
      );
      if (selected.isEmpty || !mounted) return;
      if (selected.length > _maximumAttachments) {
        setState(() {
          _attachmentError = 'Choose no more than 5 files at a time.';
        });
        return;
      }
      final attachments = <({List<int> bytes, String name})>[];
      for (final file in selected) {
        final length = await file.length();
        if (length <= 0 || length > _maximumAttachmentBytes) {
          if (!mounted) return;
          setState(() {
            _attachmentError = length <= 0
                ? '${file.name} is empty.'
                : '${file.name} is larger than 20 MB.';
          });
          return;
        }
        attachments.add((bytes: await file.readAsBytes(), name: file.name));
      }
      if (!mounted) return;
      _replaceReports([
        for (final attachment in attachments)
          _EditableDiagnosticReport.manual(attachment),
      ]);
      final totalBytes = attachments.fold<int>(
        0,
        (total, attachment) => total + attachment.bytes.length,
      );
      setState(() {
        _attachments = attachments;
        _attachmentError = null;
        _scanning = totalBytes <= _maximumScanBytes;
        _scanCompleted = false;
        _scanError = totalBytes > _maximumScanBytes
            ? 'The selected files exceed the 2 MB combined AI scan limit. You can still enter and upload each report manually.'
            : null;
      });
      if (totalBytes > _maximumScanBytes) return;
      try {
        final extracted = await widget.repository
            .extractDiagnosticResultsFromAttachments(attachments: attachments);
        if (!mounted || !_sameAttachments(_attachments, attachments)) return;
        final reports = <_EditableDiagnosticReport>[];
        for (var index = 0; index < extracted.length; index++) {
          final scan = extracted[index];
          final attachment = _attachmentForScan(scan, index, attachments);
          reports.add(_EditableDiagnosticReport.fromScan(attachment, scan));
        }
        if (reports.isEmpty) {
          throw StateError('No diagnostic reports were identified.');
        }
        _replaceReports(reports);
        setState(() {
          _scanning = false;
          _scanCompleted = true;
        });
      } catch (error) {
        if (!mounted || !_sameAttachments(_attachments, attachments)) return;
        setState(() {
          _scanning = false;
          _scanError = _friendlyError(error);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _attachmentError =
            'Could not read the selected file. ${_friendlyError(error)}';
      });
    } finally {
      if (mounted) setState(() => _pickingAttachment = false);
    }
  }

  void _replaceReports(List<_EditableDiagnosticReport> reports) {
    for (final report in _reports) {
      report.dispose();
    }
    _reports
      ..clear()
      ..addAll(reports);
  }

  bool _sameAttachments(
    List<({List<int> bytes, String name})> left,
    List<({List<int> bytes, String name})> right,
  ) =>
      left.length == right.length &&
      List.generate(left.length, (index) => index).every(
        (index) =>
            identical(left[index].bytes, right[index].bytes) &&
            left[index].name == right[index].name,
      );

  ({List<int> bytes, String name}) _attachmentForScan(
    DiagnosticResultScanDraft scan,
    int index,
    List<({List<int> bytes, String name})> attachments,
  ) {
    final sourceName = scan.sourceFileName?.trim().toLowerCase();
    if (sourceName != null && sourceName.isNotEmpty) {
      for (final attachment in attachments) {
        if (attachment.name.trim().toLowerCase() == sourceName) {
          return attachment;
        }
      }
    }
    return attachments[index < attachments.length
        ? index
        : attachments.length - 1];
  }

  void _removeAttachment(({List<int> bytes, String name}) attachment) {
    final retainedReports = _reports
        .where(
          (report) => !identical(report.attachment.bytes, attachment.bytes),
        )
        .toList(growable: false);
    final removedReports = _reports
        .where((report) => identical(report.attachment.bytes, attachment.bytes))
        .toList(growable: false);
    for (final report in removedReports) {
      report.dispose();
    }
    setState(() {
      _attachments = _attachments
          .where((item) => !identical(item.bytes, attachment.bytes))
          .toList(growable: false);
      _reports
        ..clear()
        ..addAll(retainedReports);
      _scanCompleted = _attachments.isNotEmpty && _scanCompleted;
      _scanError = null;
    });
  }

  void _removeReport(_EditableDiagnosticReport report) {
    final attachmentStillUsed = _reports.any(
      (item) =>
          !identical(item, report) &&
          identical(item.attachment.bytes, report.attachment.bytes),
    );
    report.dispose();
    setState(() {
      _reports.remove(report);
      if (!attachmentStillUsed) {
        _attachments = _attachments
            .where((item) => !identical(item.bytes, report.attachment.bytes))
            .toList(growable: false);
      }
      _scanCompleted = _reports.isNotEmpty && _scanCompleted;
    });
  }

  Widget _buildResultFileScanner(BuildContext context) {
    final busy = _pickingAttachment || _scanning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Result file and AI autofill',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          'Attach up to 5 PDFs or clear images. AI creates a separate editable draft for every report it finds; review every field before uploading.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.x2),
        OutlinedButton.icon(
          onPressed: busy ? null : _pickAttachments,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.document_scanner_outlined, size: 18),
          label: Text(
            _pickingAttachment
                ? 'Reading result file…'
                : _scanning
                ? 'Scanning result file…'
                : _attachments.isEmpty
                ? 'Attach and scan result files'
                : _attachments.length == 1
                ? 'Change and rescan result file'
                : 'Change files and rescan',
          ),
        ),
        if (_attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x2),
          for (final attachment in _attachments)
            Row(
              children: [
                const Icon(Icons.attachment, size: 16),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove ${attachment.name}',
                  onPressed: busy ? null : () => _removeAttachment(attachment),
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
        ],
        if (_scanCompleted) ...[
          Text(
            'Scan complete. Review every autofilled value before uploading.',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          Text(
            '${_reports.length} ${_reports.length == 1 ? 'report' : 'reports'} detected.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_scanError != null)
          Text(
            'Scan unavailable: $_scanError You can still complete the fields manually and upload the selected ${_attachments.length == 1 ? 'file' : 'files'}.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_attachmentError != null) ...[
          const SizedBox(height: AppSpacing.x1),
          Text(
            _attachmentError!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.x1),
        Text(
          'Accepted formats: PDF, JPG, or PNG (up to 5 files; 20 MB each for upload; 2 MB combined for AI scan).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _choosePerformedOrCollectedDate(
    _EditableDiagnosticReport report,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final value = await showDatePicker(
      context: context,
      initialDate: report.performedOrCollectedDate ?? today,
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (value == null || !mounted) return;
    final selected = DateUtils.dateOnly(value);
    setState(() {
      report.performedOrCollectedDate = selected;
      report.performedOrCollectedController.text = DateFormat.yMMMd().format(
        selected,
      );
      if (report.resultDate != null && report.resultDate!.isBefore(selected)) {
        report.resultDate = null;
        report.resultDateController.clear();
      }
    });
  }

  Future<void> _chooseResultDate(_EditableDiagnosticReport report) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = report.performedOrCollectedDate ?? DateTime(1900);
    final value = await showDatePicker(
      context: context,
      initialDate:
          report.resultDate ?? report.performedOrCollectedDate ?? today,
      firstDate: firstDate,
      lastDate: today,
    );
    if (value == null || !mounted) return;
    final selected = DateUtils.dateOnly(value);
    setState(() {
      report.resultDate = selected;
      report.resultDateController.text = DateFormat.yMMMd().format(selected);
    });
  }

  Widget _buildReportFields(
    BuildContext context,
    _EditableDiagnosticReport report,
    int index,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Report ${index + 1} of ${_reports.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_reports.length > 1)
                  IconButton(
                    tooltip: 'Remove report ${index + 1}',
                    onPressed: () => _removeReport(report),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            Text(
              report.attachment.name,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.x3),
            TextFormField(
              controller: report.patientNameController,
              textCapitalization: TextCapitalization.words,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Patient name shown on report (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            DropdownButtonFormField<String>(
              key: ValueKey('category-$index-${report.category}'),
              initialValue: report.category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Result category'),
              items: [
                for (final entry in _categories.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) =>
                  setState(() => report.category = value ?? 'other'),
            ),
            const SizedBox(height: AppSpacing.x4),
            TextFormField(
              controller: report.testProcedureController,
              autofocus: index == 0,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: 'Test/procedure name',
                hintText: 'Example: Complete blood count or chest CT',
                helperText: report.testProcedureNameAiGenerated
                    ? 'AI-generated suggested name — verify or edit.'
                    : null,
              ),
              onChanged: (_) {
                if (report.testProcedureNameAiGenerated) {
                  setState(() => report.testProcedureNameAiGenerated = false);
                }
              },
              validator: (value) {
                final length = value?.trim().length ?? 0;
                return length < 2 ? 'Enter at least 2 characters.' : null;
              },
            ),
            const SizedBox(height: AppSpacing.x2),
            TextFormField(
              controller: report.performedOrCollectedController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Confirmed procedure or collection date (optional)',
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              onTap: () => _choosePerformedOrCollectedDate(report),
            ),
            const SizedBox(height: AppSpacing.x2),
            TextFormField(
              controller: report.performedOrCollectedDateTextController,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Procedure/collection date as printed (optional)',
                helperText:
                    'Preserved exactly. Confirm ambiguous dates such as 01/02/25 above.',
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            TextFormField(
              controller: report.resultDateController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Confirmed result date',
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              onTap: () => _chooseResultDate(report),
            ),
            const SizedBox(height: AppSpacing.x2),
            TextFormField(
              controller: report.resultDateTextController,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Result date as printed (optional)',
                helperText:
                    'Do not reuse an unspecified date for both date fields.',
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            TextFormField(
              controller: report.facilityController,
              textCapitalization: TextCapitalization.words,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Facility (optional if not stated)',
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            TextFormField(
              controller: report.requestingDoctorController,
              textCapitalization: TextCapitalization.words,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Requesting or referring doctor (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            TextFormField(
              controller: report.procedureDetailsController,
              minLines: 2,
              maxLines: 8,
              maxLength: 30000,
              decoration: const InputDecoration(
                labelText: 'Type-specific report details (optional)',
                helperText:
                    'Examples: imaging body part/technique/comparison; pathology specimen/grade/margins/biomarkers; heart rhythm/rate/measurements.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            TextFormField(
              controller: report.resultDetailsController,
              minLines: 3,
              maxLines: 12,
              maxLength: 50000,
              decoration: const InputDecoration(
                labelText: 'All results, measurements, units, and ranges',
                helperText:
                    'Keep every readable normal and abnormal result. Do not classify values without a matching printed range.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            TextFormField(
              controller: report.officialFindingsController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 10,
              maxLength: 30000,
              decoration: const InputDecoration(
                labelText: 'Official findings/impression (optional)',
                helperText:
                    'Preserve the report author\'s wording and uncertainty.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            TextFormField(
              controller: report.recommendationsController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 6,
              maxLength: 10000,
              decoration: const InputDecoration(
                labelText: 'Report-stated recommendations (optional)',
                helperText:
                    'Do not add recommendations not stated in the report.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            TextFormField(
              controller: report.technicalSummaryController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 5,
              maxLength: 800,
              decoration: const InputDecoration(
                labelText: 'Short clinical summary',
                helperText:
                    'Up to 3 key points, with important findings first.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            TextFormField(
              controller: report.patientFriendlySummaryController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Simple patient summary',
                helperText:
                    'Main result in 1–2 short sentences; verify before saving.',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final report in _reports) {
      report.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x6,
      ),
      icon: const Icon(Icons.upload_file_outlined),
      title: const Text('Upload diagnostic result'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showRelationshipField) ...[
                _ClinicalRelationshipField(
                  value: _relationship,
                  relationships: widget.relationships,
                  onChanged: (value) => setState(() => _relationship = value),
                ),
                const SizedBox(height: AppSpacing.x4),
              ],
              _buildResultFileScanner(context),
              if (_reports.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x5),
                for (var index = 0; index < _reports.length; index++) ...[
                  _buildReportFields(context, _reports[index], index),
                  if (index != _reports.length - 1)
                    const SizedBox(height: AppSpacing.x4),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _pickingAttachment || _scanning
              ? null
              : () {
                  final valid = _formKey.currentState?.validate() ?? false;
                  if (_attachments.isEmpty || _reports.isEmpty) {
                    setState(
                      () =>
                          _attachmentError = 'Choose at least one result file.',
                    );
                  }
                  if (!valid || _attachments.isEmpty || _reports.isEmpty) {
                    return;
                  }
                  String? optionalText(TextEditingController controller) {
                    final value = controller.text.trim();
                    return value.isEmpty ? null : value;
                  }

                  Navigator.of(context).pop(
                    _LaboratoryResultUploadDraft(
                      relationship: _relationship,
                      reports: [
                        for (final report in _reports)
                          _DiagnosticResultUploadItem(
                            category: report.category,
                            testProcedureName: report
                                .testProcedureController
                                .text
                                .trim(),
                            testProcedureNameAiGenerated:
                                report.testProcedureNameAiGenerated,
                            performedOrCollectedDate:
                                report.performedOrCollectedDate,
                            performedOrCollectedDateText: optionalText(
                              report.performedOrCollectedDateTextController,
                            ),
                            resultDate: report.resultDate,
                            resultDateText: optionalText(
                              report.resultDateTextController,
                            ),
                            facility: optionalText(report.facilityController),
                            requestingDoctor: optionalText(
                              report.requestingDoctorController,
                            ),
                            patientNameOnReport: optionalText(
                              report.patientNameController,
                            ),
                            attachment: report.attachment,
                            procedureDetails: optionalText(
                              report.procedureDetailsController,
                            ),
                            resultDetails: optionalText(
                              report.resultDetailsController,
                            ),
                            officialFindingsImpression: optionalText(
                              report.officialFindingsController,
                            ),
                            recommendations: optionalText(
                              report.recommendationsController,
                            ),
                            technicalSummary: optionalText(
                              report.technicalSummaryController,
                            ),
                            patientFriendlySummary: optionalText(
                              report.patientFriendlySummaryController,
                            ),
                            verificationNotes: optionalText(
                              report.verificationNotesController,
                            ),
                            notes: optionalText(report.notesController),
                          ),
                      ],
                    ),
                  );
                },
          child: const Text('Upload diagnostic result'),
        ),
      ],
    );
  }
}

class _EditableDiagnosticReport {
  _EditableDiagnosticReport._({
    required this.attachment,
    required this.category,
    required this.testProcedureNameAiGenerated,
    required this.performedOrCollectedDate,
    required this.resultDate,
    required String? patientName,
    required String? testProcedureName,
    required String? performedOrCollectedDateText,
    required String? resultDateText,
    required String? facility,
    required String? requestingDoctor,
    required String? procedureDetails,
    required String? resultDetails,
    required String? officialFindingsImpression,
    required String? recommendations,
    required String? technicalSummary,
    required String? patientFriendlySummary,
    required String? verificationNotes,
    required String? notes,
  }) : patientNameController = TextEditingController(text: patientName),
       testProcedureController = TextEditingController(text: testProcedureName),
       performedOrCollectedController = TextEditingController(
         text: performedOrCollectedDate == null
             ? null
             : DateFormat.yMMMd().format(performedOrCollectedDate),
       ),
       performedOrCollectedDateTextController = TextEditingController(
         text: performedOrCollectedDateText,
       ),
       resultDateController = TextEditingController(
         text: resultDate == null
             ? null
             : DateFormat.yMMMd().format(resultDate),
       ),
       resultDateTextController = TextEditingController(text: resultDateText),
       facilityController = TextEditingController(text: facility),
       requestingDoctorController = TextEditingController(
         text: requestingDoctor,
       ),
       procedureDetailsController = TextEditingController(
         text: procedureDetails,
       ),
       resultDetailsController = TextEditingController(text: resultDetails),
       officialFindingsController = TextEditingController(
         text: officialFindingsImpression,
       ),
       recommendationsController = TextEditingController(text: recommendations),
       technicalSummaryController = TextEditingController(
         text: technicalSummary,
       ),
       patientFriendlySummaryController = TextEditingController(
         text: patientFriendlySummary,
       ),
       verificationNotesController = TextEditingController(
         text: verificationNotes,
       ),
       notesController = TextEditingController(text: notes);

  factory _EditableDiagnosticReport.manual(
    ({List<int> bytes, String name}) attachment,
  ) {
    final today = DateUtils.dateOnly(DateTime.now());
    return _EditableDiagnosticReport._(
      attachment: attachment,
      category: 'other',
      testProcedureNameAiGenerated: false,
      performedOrCollectedDate: null,
      resultDate: today,
      patientName: null,
      testProcedureName: null,
      performedOrCollectedDateText: null,
      resultDateText: null,
      facility: null,
      requestingDoctor: null,
      procedureDetails: null,
      resultDetails: null,
      officialFindingsImpression: null,
      recommendations: null,
      technicalSummary: null,
      patientFriendlySummary: null,
      verificationNotes: 'AI scan unavailable. Review the source manually.',
      notes: null,
    );
  }

  factory _EditableDiagnosticReport.fromScan(
    ({List<int> bytes, String name}) attachment,
    DiagnosticResultScanDraft scan,
  ) {
    final today = DateUtils.dateOnly(DateTime.now());
    final verification = <String>[
      ...?scan.verificationNotes
          ?.split(RegExp(r'\r?\n'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    ];
    void verify(String message) {
      if (!verification.any(
        (item) => item.toLowerCase() == message.toLowerCase(),
      )) {
        verification.add(message);
      }
    }

    if (scan.patientName == null) {
      verify('Patient information on the report needs verification.');
    }
    if (!_LaboratoryResultUploadDialogState._categories.containsKey(
      scan.category,
    )) {
      verify('Result category needs verification.');
    }
    if (scan.testProcedureName == null) {
      verify('Test or procedure name needs verification.');
    }
    final performed = scan.performedOrCollectedDate == null
        ? null
        : DateUtils.dateOnly(scan.performedOrCollectedDate!);
    final safePerformed = performed != null && !performed.isAfter(today)
        ? performed
        : null;
    if (performed != null && performed.isAfter(today)) {
      verify('Procedure or collection date needs verification.');
    } else if (performed == null && scan.performedOrCollectedDateText != null) {
      verify('Confirm the procedure or collection date as printed.');
    }
    final result = scan.resultDate == null
        ? null
        : DateUtils.dateOnly(scan.resultDate!);
    final safeScannedResult =
        result != null &&
            !result.isAfter(today) &&
            (safePerformed == null || !result.isBefore(safePerformed))
        ? result
        : null;
    if (result != null &&
        (result.isAfter(today) ||
            (safePerformed != null && result.isBefore(safePerformed)))) {
      verify('Result date needs verification.');
    } else if (result == null && scan.resultDateText != null) {
      verify('Confirm the result date as printed.');
    }
    return _EditableDiagnosticReport._(
      attachment: attachment,
      category:
          _LaboratoryResultUploadDialogState._categories.containsKey(
            scan.category,
          )
          ? scan.category!
          : 'other',
      testProcedureNameAiGenerated: scan.testProcedureNameAiGenerated,
      performedOrCollectedDate: safePerformed,
      resultDate: result == null ? today : safeScannedResult,
      patientName: scan.patientName,
      testProcedureName: scan.testProcedureName,
      performedOrCollectedDateText: scan.performedOrCollectedDateText,
      resultDateText: scan.resultDateText,
      facility: scan.facility,
      requestingDoctor: scan.requestingDoctor,
      procedureDetails: scan.procedureDetails,
      resultDetails: scan.resultDetails,
      officialFindingsImpression:
          scan.officialFindingsImpression ?? scan.findingsImpression,
      recommendations: scan.recommendations,
      technicalSummary: scan.technicalSummary,
      patientFriendlySummary: scan.patientFriendlySummary,
      verificationNotes: verification.isEmpty ? null : verification.join('\n'),
      notes: scan.notes,
    );
  }

  final ({List<int> bytes, String name}) attachment;
  String category;
  bool testProcedureNameAiGenerated;
  DateTime? performedOrCollectedDate;
  DateTime? resultDate;
  final TextEditingController patientNameController;
  final TextEditingController testProcedureController;
  final TextEditingController performedOrCollectedController;
  final TextEditingController performedOrCollectedDateTextController;
  final TextEditingController resultDateController;
  final TextEditingController resultDateTextController;
  final TextEditingController facilityController;
  final TextEditingController requestingDoctorController;
  final TextEditingController procedureDetailsController;
  final TextEditingController resultDetailsController;
  final TextEditingController officialFindingsController;
  final TextEditingController recommendationsController;
  final TextEditingController technicalSummaryController;
  final TextEditingController patientFriendlySummaryController;
  final TextEditingController verificationNotesController;
  final TextEditingController notesController;

  void dispose() {
    patientNameController.dispose();
    testProcedureController.dispose();
    performedOrCollectedController.dispose();
    performedOrCollectedDateTextController.dispose();
    resultDateController.dispose();
    resultDateTextController.dispose();
    facilityController.dispose();
    requestingDoctorController.dispose();
    procedureDetailsController.dispose();
    resultDetailsController.dispose();
    officialFindingsController.dispose();
    recommendationsController.dispose();
    technicalSummaryController.dispose();
    patientFriendlySummaryController.dispose();
    verificationNotesController.dispose();
    notesController.dispose();
  }
}

class _LaboratoryRequestDialog extends StatefulWidget {
  const _LaboratoryRequestDialog({required this.relationships});

  final List<ClinicalRelationship> relationships;

  @override
  State<_LaboratoryRequestDialog> createState() =>
      _LaboratoryRequestDialogState();
}

class _LaboratoryRequestDialogState extends State<_LaboratoryRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _testController = TextEditingController();
  final _instructionsController = TextEditingController();
  late ClinicalRelationship _relationship = widget.relationships.first;
  String _priority = 'routine';
  ({List<int> bytes, String name})? _attachment;

  Future<void> _pickAttachment() async {
    const acceptedTypes = XTypeGroup(
      label: 'Medical files',
      extensions: ['pdf', 'jpg', 'jpeg', 'png'],
      mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
    );
    final selected = await openFile(acceptedTypeGroups: const [acceptedTypes]);
    if (selected == null) return;
    final bytes = await selected.readAsBytes();
    if (mounted) {
      setState(() => _attachment = (bytes: bytes, name: selected.name));
    }
  }

  @override
  void dispose() {
    _testController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.science_outlined),
      title: const Text('Request laboratory test'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ClinicalRelationshipField(
                  value: _relationship,
                  relationships: widget.relationships,
                  onChanged: (value) => setState(() => _relationship = value),
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _testController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Test name',
                    hintText: 'Example: Complete blood count',
                  ),
                  validator: (value) {
                    final length = value?.trim().length ?? 0;
                    return length < 2 ? 'Enter at least 2 characters.' : null;
                  },
                ),
                const SizedBox(height: AppSpacing.x4),
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'routine', child: Text('Routine')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                    DropdownMenuItem(value: 'stat', child: Text('STAT')),
                  ],
                  onChanged: (value) =>
                      setState(() => _priority = value ?? 'routine'),
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _instructionsController,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Clinical instructions (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.x4),
                if (_attachment != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.attachment, size: 16),
                      const SizedBox(width: AppSpacing.x2),
                      Expanded(
                        child: Text(
                          _attachment!.name,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _attachment = null),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x2),
                ],
                OutlinedButton.icon(
                  onPressed: _pickAttachment,
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: Text(
                    _attachment == null ? 'Attach File' : 'Change Attachment',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _LaboratoryRequestDraft(
                relationship: _relationship,
                testName: _testController.text.trim(),
                priority: _priority,
                instructions: _instructionsController.text.trim(),
                attachment: _attachment,
              ),
            );
          },
          child: const Text('Create request'),
        ),
      ],
    );
  }
}

class _ClinicalRelationshipField extends StatelessWidget {
  const _ClinicalRelationshipField({
    required this.value,
    required this.relationships,
    required this.onChanged,
  });

  final ClinicalRelationship value;
  final List<ClinicalRelationship> relationships;
  final ValueChanged<ClinicalRelationship> onChanged;

  @override
  Widget build(BuildContext context) {
    if (relationships.length == 1) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Patient'),
        child: Text(value.patientLabel, overflow: TextOverflow.ellipsis),
      );
    }
    return DropdownButtonFormField<ClinicalRelationship>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Patient'),
      items: [
        for (final relationship in relationships)
          DropdownMenuItem(
            value: relationship,
            child: Text(
              relationship.hasConsultation
                  ? '${relationship.patientLabel} — ${relationship.consultationLabel}'
                  : relationship.patientLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (relationship) {
        if (relationship != null) onChanged(relationship);
      },
    );
  }
}

String? _requiredClinicalValue(String? value) =>
    (value?.trim().isEmpty ?? true) ? 'This clinical field is required.' : null;

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog();

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _startsController = TextEditingController(text: '09:00');
  final _endsController = TextEditingController(text: '12:00');
  final _slotController = TextEditingController(text: '30');
  int _day = 1;
  String _type = 'online';

  @override
  void dispose() {
    _startsController.dispose();
    _endsController.dispose();
    _slotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.calendar_month_outlined),
      title: const Text('Publish schedule slot'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _day,
                decoration: const InputDecoration(labelText: 'Day'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Monday')),
                  DropdownMenuItem(value: 2, child: Text('Tuesday')),
                  DropdownMenuItem(value: 3, child: Text('Wednesday')),
                  DropdownMenuItem(value: 4, child: Text('Thursday')),
                  DropdownMenuItem(value: 5, child: Text('Friday')),
                  DropdownMenuItem(value: 6, child: Text('Saturday')),
                  DropdownMenuItem(value: 0, child: Text('Sunday')),
                ],
                onChanged: (value) => setState(() => _day = value ?? 1),
              ),
              const SizedBox(height: AppSpacing.x4),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startsController,
                      decoration: const InputDecoration(
                        labelText: 'Starts (24-hour)',
                        hintText: '09:00',
                      ),
                      validator: _timeValidator,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: TextFormField(
                      controller: _endsController,
                      decoration: const InputDecoration(
                        labelText: 'Ends (24-hour)',
                        hintText: '12:00',
                      ),
                      validator: (value) {
                        final basic = _timeValidator(value);
                        if (basic != null) return basic;
                        if ((value ?? '').compareTo(_startsController.text) <=
                            0) {
                          return 'End must be later.';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x4),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Care mode'),
                items: const [
                  DropdownMenuItem(value: 'online', child: Text('Online')),
                  DropdownMenuItem(
                    value: ConsultationType.faceToFace,
                    child: Text('In person'),
                  ),
                ],
                onChanged: (value) => setState(() => _type = value ?? 'online'),
              ),
              const SizedBox(height: AppSpacing.x4),
              TextFormField(
                controller: _slotController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutes per appointment',
                ),
                validator: (value) {
                  final minutes = int.tryParse(value ?? '');
                  return minutes == null || minutes < 10 || minutes > 240
                      ? 'Enter 10 to 240 minutes.'
                      : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _ScheduleDraft(
                dayOfWeek: _day,
                startsAt: _startsController.text,
                endsAt: _endsController.text,
                consultationType: _type,
                slotMinutes: int.parse(_slotController.text),
              ),
            );
          },
          child: const Text('Publish slot'),
        ),
      ],
    );
  }

  String? _timeValidator(String? value) {
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value ?? '')) {
      return 'Use HH:mm.';
    }
    return null;
  }
}

class _EmergencyCapacityDraft {
  const _EmergencyCapacityDraft({
    required this.total,
    required this.occupied,
    required this.closedOrUnstaffed,
    required this.reserved,
    required this.currentPatients,
    this.statusOverride,
    this.overrideReason,
  });

  final int total;
  final int occupied;
  final int closedOrUnstaffed;
  final int reserved;
  final int currentPatients;
  final String? statusOverride;
  final String? overrideReason;
}

class _EmergencyCapacityDialog extends StatefulWidget {
  const _EmergencyCapacityDialog({
    required this.initialTotal,
    required this.initialOccupied,
    required this.initialClosedOrUnstaffed,
    required this.initialReserved,
    required this.initialPatientCount,
    this.initialStatusOverride,
    this.initialOverrideReason,
  });

  final int initialTotal;
  final int initialOccupied;
  final int initialClosedOrUnstaffed;
  final int initialReserved;
  final int initialPatientCount;
  final String? initialStatusOverride;
  final String? initialOverrideReason;

  @override
  State<_EmergencyCapacityDialog> createState() =>
      _EmergencyCapacityDialogState();
}

class _EmergencyCapacityDialogState extends State<_EmergencyCapacityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _totalController;
  late final TextEditingController _occupiedController;
  late final TextEditingController _closedController;
  late final TextEditingController _reservedController;
  late final TextEditingController _patientController;
  late final TextEditingController _reasonController;
  String? _statusOverride;

  @override
  void initState() {
    super.initState();
    _totalController = TextEditingController(text: '${widget.initialTotal}');
    _occupiedController = TextEditingController(
      text: '${widget.initialOccupied}',
    );
    _closedController = TextEditingController(
      text: '${widget.initialClosedOrUnstaffed}',
    );
    _reservedController = TextEditingController(
      text: '${widget.initialReserved}',
    );
    _patientController = TextEditingController(
      text: '${widget.initialPatientCount}',
    );
    _reasonController = TextEditingController(
      text: widget.initialOverrideReason ?? '',
    );
    _statusOverride = switch (widget.initialStatusOverride) {
      'limited' ||
      'full' ||
      'temporarily_closed' => widget.initialStatusOverride,
      _ => null,
    };
  }

  @override
  void dispose() {
    _totalController.dispose();
    _occupiedController.dispose();
    _closedController.dispose();
    _reservedController.dispose();
    _patientController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  int? _parsed(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  int? get _available {
    final total = _parsed(_totalController);
    final occupied = _parsed(_occupiedController);
    final closed = _parsed(_closedController);
    final reserved = _parsed(_reservedController);
    if ([total, occupied, closed, reserved].any((value) => value == null)) {
      return null;
    }
    return total! - occupied! - closed! - reserved!;
  }

  String? _wholeNumberValidator(String? value) {
    final number = int.tryParse(value?.trim() ?? '');
    return number == null || number < 0
        ? 'Enter zero or a positive whole number.'
        : null;
  }

  String? _reservedValidator(String? value) {
    final basic = _wholeNumberValidator(value);
    if (basic != null) return basic;
    final available = _available;
    return available != null && available < 0
        ? 'Occupied, unavailable, and reserved beds exceed the total.'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    final derivedStatus = available == null || available < 0
        ? 'Check capacity values'
        : available == 0
        ? 'Full'
        : () {
            final total = _parsed(_totalController) ?? 0;
            final closed = _parsed(_closedController) ?? 0;
            final staffed = total - closed;
            return staffed > 0 && available * 5 <= staffed
                ? 'Limited'
                : 'Available';
          }();
    return AlertDialog(
      icon: const Icon(Icons.emergency_outlined),
      title: const Text('Confirm emergency capacity'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter the current ER census. Available beds and the public status are calculated by the server.',
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _totalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Physical ER beds',
                    helperText: 'Configured ER treatment spaces',
                  ),
                  validator: _wholeNumberValidator,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.x3),
                TextFormField(
                  controller: _occupiedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Occupied beds',
                    helperText: 'Beds currently occupied by ER patients',
                  ),
                  validator: _wholeNumberValidator,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.x3),
                TextFormField(
                  controller: _closedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Closed or unstaffed beds',
                    helperText:
                        'Unavailable for staffing, cleaning, maintenance, or infection control',
                  ),
                  validator: _wholeNumberValidator,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.x3),
                TextFormField(
                  controller: _reservedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Reserved beds',
                    helperText:
                        'Held for arriving or clinically reserved patients',
                  ),
                  validator: _reservedValidator,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.x3),
                TextFormField(
                  controller: _patientController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Current ER patients',
                    helperText: 'Includes waiting and boarding patients',
                  ),
                  validator: _wholeNumberValidator,
                ),
                const SizedBox(height: AppSpacing.x4),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.selected,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColors.secondary),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calculate_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            available == null || available < 0
                                ? 'Available beds: Check the entered values'
                                : 'Available beds: $available · Automatic status: $derivedStatus',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x4),
                DropdownButtonFormField<String?>(
                  initialValue: _statusOverride,
                  decoration: const InputDecoration(
                    labelText: 'Operational status override',
                    helperText: 'Use only when the calculated status is unsafe',
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Automatic'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'limited',
                      child: Text('Limited'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'full',
                      child: Text('Full'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'temporarily_closed',
                      child: Text('Temporarily closed'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _statusOverride = value;
                    if (value == null) _reasonController.clear();
                  }),
                ),
                if (_statusOverride != null) ...[
                  const SizedBox(height: AppSpacing.x3),
                  TextFormField(
                    controller: _reasonController,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Override reason',
                      helperText: 'Explain the staffing or operational risk',
                    ),
                    validator: (value) {
                      if (_statusOverride == null) return null;
                      final reason = value?.trim() ?? '';
                      return reason.length < 3
                          ? 'Enter at least 3 characters.'
                          : null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false) ||
                _available == null ||
                _available! < 0) {
              return;
            }
            Navigator.of(context).pop(
              _EmergencyCapacityDraft(
                total: _parsed(_totalController)!,
                occupied: _parsed(_occupiedController)!,
                closedOrUnstaffed: _parsed(_closedController)!,
                reserved: _parsed(_reservedController)!,
                currentPatients: _parsed(_patientController)!,
                statusOverride: _statusOverride,
                overrideReason: _statusOverride == null
                    ? null
                    : _reasonController.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.publish_outlined),
          label: const Text('Publish confirmation'),
        ),
      ],
    );
  }
}

class _CapacityDialog extends StatefulWidget {
  const _CapacityDialog({
    required this.resourceLabel,
    required this.initialTotal,
    required this.initialAvailable,
  });

  final String resourceLabel;
  final int initialTotal;
  final int initialAvailable;

  @override
  State<_CapacityDialog> createState() => _CapacityDialogState();
}

class _CapacityDialogState extends State<_CapacityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _totalController;
  late final TextEditingController _availableController;

  @override
  void initState() {
    super.initState();
    _totalController = TextEditingController(text: '${widget.initialTotal}');
    _availableController = TextEditingController(
      text: '${widget.initialAvailable}',
    );
  }

  @override
  void dispose() {
    _totalController.dispose();
    _availableController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.monitor_heart_outlined),
      title: Text('Update ${widget.resourceLabel}'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _totalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total capacity'),
                validator: (value) {
                  final total = int.tryParse(value ?? '');
                  return total == null || total < 0
                      ? 'Enter zero or a positive whole number.'
                      : null;
                },
              ),
              const SizedBox(height: AppSpacing.x4),
              TextFormField(
                controller: _availableController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Available capacity',
                ),
                validator: (value) {
                  final total = int.tryParse(_totalController.text);
                  final available = int.tryParse(value ?? '');
                  if (available == null || available < 0) {
                    return 'Enter zero or a positive whole number.';
                  }
                  if (total != null && available > total) {
                    return 'Available capacity cannot exceed total capacity.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop((
              total: int.parse(_totalController.text),
              available: int.parse(_availableController.text),
            ));
          },
          child: const Text('Save capacity'),
        ),
      ],
    );
  }
}

class _MedicalDocumentTitleDialog extends StatefulWidget {
  const _MedicalDocumentTitleDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_MedicalDocumentTitleDialog> createState() =>
      _MedicalDocumentTitleDialogState();
}

class _MedicalDocumentTitleDialogState
    extends State<_MedicalDocumentTitleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.edit_document),
      title: const Text('Edit file title'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            maxLength: 180,
            decoration: const InputDecoration(labelText: 'File title'),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? 'A file title is required.'
                : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_controller.text.trim());
          },
          child: const Text('Save title'),
        ),
      ],
    );
  }
}

class _TextValueDialog extends StatefulWidget {
  const _TextValueDialog({required this.title, required this.initialValue});

  final String title;
  final String initialValue;

  @override
  State<_TextValueDialog> createState() => _TextValueDialogState();
}

class _TextValueDialogState extends State<_TextValueDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.tune_outlined),
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Setting value',
              alignLabelWithHint: true,
            ),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? 'A setting value is required.'
                : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_controller.text.trim());
          },
          child: const Text('Save setting'),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<WorkspaceMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * AppSpacing.x3) / columns;
        return Wrap(
          spacing: AppSpacing.x3,
          runSpacing: AppSpacing.x3,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: ContentPanel(
                  padding: const EdgeInsets.all(AppSpacing.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.value,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        metric.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ScheduleSummary extends StatelessWidget {
  const _ScheduleSummary({required this.items});

  final List<WorkspaceItem> items;

  @override
  Widget build(BuildContext context) {
    final active = items.where((item) => item.data['is_active'] == true).length;
    final online = items
        .where(
          (item) =>
              item.data['consultation_type']?.toString().toLowerCase() ==
              'online',
        )
        .length;
    final inPerson = items.length - online;
    final summaries = [
      (Icons.calendar_today_outlined, '${items.length}', 'Total slots'),
      (Icons.event_available_outlined, '$active', 'Open for reservation'),
      (Icons.videocam_outlined, '$online', 'Online'),
      (Icons.local_hospital_outlined, '$inPerson', 'Face-to-face'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final width = compact
            ? (constraints.maxWidth - AppSpacing.x3) / 2
            : (constraints.maxWidth - AppSpacing.x3 * 3) / 4;
        return Wrap(
          spacing: AppSpacing.x3,
          runSpacing: AppSpacing.x3,
          children: [
            for (final summary in summaries)
              SizedBox(
                width: width,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.x4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.panel),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.selected,
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                        ),
                        child: Icon(
                          summary.$1,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary.$2,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              summary.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Map<String, Object?> _connectionRequestData(WorkspaceItem item) {
  final nested = item.data['data'];
  return {
    ...item.data,
    if (nested is Map) ...Map<String, Object?>.from(nested),
  };
}

List<CareNotification> collapseNotificationThreads(
  List<CareNotification> notifications,
) {
  final newestFirst = notifications.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final groups = <String, List<CareNotification>>{};
  for (final notification in newestFirst) {
    final conversationId = notification.type == 'message'
        ? notification.data['conversation_id']?.toString().trim() ?? ''
        : '';
    final key = conversationId.isEmpty
        ? 'notification:${notification.id}'
        : 'message:$conversationId';
    groups.putIfAbsent(key, () => []).add(notification);
  }

  return groups.values
      .map((group) {
        final latest = group.first;
        if (group.length == 1) return latest;
        return CareNotification(
          id: latest.id,
          title: 'New messages',
          message:
              'You received ${group.length} messages in this conversation.',
          type: latest.type,
          isRead: group.every((notification) => notification.isRead),
          createdAt: latest.createdAt,
          actionPath: latest.actionPath,
          referenceId: latest.referenceId,
          data: {
            ...latest.data,
            'notification_ids': group
                .map((notification) => notification.id)
                .toList(growable: false),
            'message_count': group.length,
          },
        );
      })
      .toList(growable: false);
}

bool _isPatientConnectionRequest(WorkspaceItem item) =>
    item.kind == 'notifications' &&
    _connectionRequestData(item)['notification_type'] == 'access_request';

class _ConnectionRequestCard extends StatelessWidget {
  const _ConnectionRequestCard({
    required this.item,
    required this.busy,
    this.onAccept,
    this.onDecline,
  });

  final WorkspaceItem item;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final data = _connectionRequestData(item);
    var status =
        data['status']?.toString().trim().toLowerCase() ??
        (item.status == 'read' ? 'requested' : item.status) ??
        'requested';
    final requestExpiry = DateTime.tryParse(
      data['expires_at']?.toString() ?? '',
    );
    if (status == 'requested' &&
        requestExpiry != null &&
        !requestExpiry.isAfter(DateTime.now())) {
      status = 'expired';
    }
    final isPending = status == 'requested';
    final clinician = data['doctor_display_name']?.toString().trim();
    final hospital = data['hospital_name']?.toString().trim();
    final title = clinician?.isNotEmpty == true
        ? '$clinician would like to connect'
        : 'A verified clinician would like to connect';
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.primaryContainer.withValues(alpha: 0.32),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  child: const Icon(Icons.health_and_safety_outlined),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (hospital?.isNotEmpty == true) ...[
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          hospital!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x3),
            Text(
              isPending
                  ? 'Accepting lets this verified clinician view and add care information needed to support you for up to 90 days. Only accept if you recognize this request.'
                  : status == 'approved'
                  ? 'You accepted this request. The clinician can now support your care through CareNavigator PH.'
                  : status == 'expired'
                  ? 'This request expired before a decision was made. The clinician was not connected to your account.'
                  : 'You declined this request. The clinician was not connected to your account.',
            ),
            if (isPending && (onAccept != null || onDecline != null)) ...[
              const SizedBox(height: AppSpacing.x4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stackButtons = constraints.maxWidth < 340;
                  final decline = OutlinedButton(
                    onPressed: busy ? null : onDecline,
                    child: const Text('Decline'),
                  );
                  final accept = FilledButton.icon(
                    onPressed: busy ? null : onAccept,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(busy ? 'Saving…' : 'Accept request'),
                  );
                  if (stackButtons) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        accept,
                        const SizedBox(height: AppSpacing.x2),
                        decline,
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      decline,
                      const SizedBox(width: AppSpacing.x2),
                      accept,
                    ],
                  );
                },
              ),
            ] else if (!isPending) ...[
              const SizedBox(height: AppSpacing.x3),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: Icon(
                    status == 'approved'
                        ? Icons.check_circle_outline
                        : status == 'expired'
                        ? Icons.schedule_outlined
                        : Icons.block_outlined,
                    size: 18,
                  ),
                  label: Text(
                    status == 'approved'
                        ? 'Accepted'
                        : status == 'expired'
                        ? 'Expired'
                        : 'Declined',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminRecordDetailsDialog extends StatelessWidget {
  const _AdminRecordDetailsDialog({required this.item, required this.role});

  final WorkspaceItem item;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String)>[
      ('Record ID', item.id),
      for (final entry in item.data.entries)
        if (entry.key != 'id')
          if (_detailValue(entry.value, entry.key) case final value?)
            (_detailLabel(entry.key), value),
    ];
    return AlertDialog(
      icon: Icon(_iconFor(item.kind)),
      title: Text(item.title.isEmpty ? 'Record details' : item.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: SingleChildScrollView(
          child: item.kind == 'consultations'
              ? _LiveRecordDetails(item: item, role: role)
              : Wrap(
                  spacing: AppSpacing.x4,
                  runSpacing: AppSpacing.x4,
                  children: [
                    for (final entry in entries)
                      SizedBox(
                        width: 340,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.$1,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: AppSpacing.x1),
                            SelectableText(entry.$2),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _LiveRecordDetails extends StatelessWidget {
  const _LiveRecordDetails({required this.item, this.role, this.topActions});

  final WorkspaceItem item;
  final UserRole? role;
  final Widget? topActions;

  @override
  Widget build(BuildContext context) {
    if (item.kind == 'consultations') {
      return _ConsultationDetails(item: item, role: role);
    }
    if (item.kind == 'prescriptions') {
      return _GroupedPrescriptionDetailView(
        item: item,
        topActions: topActions,
      );
    }
    final rawCheckups = item.data['checkup_history'];
    final checkups = rawCheckups is List
        ? rawCheckups
              .whereType<Map>()
              .map((record) => Map<String, Object?>.from(record))
              .toList(growable: false)
        : const <Map<String, Object?>>[];
    final rawPrescriptions = item.data['prescription_history'];
    final prescriptions = rawPrescriptions is List
        ? rawPrescriptions
              .whereType<Map>()
              .map((record) => Map<String, Object?>.from(record))
              .toList(growable: false)
        : const <Map<String, Object?>>[];
    final rawDiagnosticResults = item.data['diagnostic_result_history'];
    final diagnosticResults = rawDiagnosticResults is List
        ? rawDiagnosticResults
              .whereType<Map>()
              .map((record) => Map<String, Object?>.from(record))
              .toList(growable: false)
        : const <Map<String, Object?>>[];
    final showCheckupHistory =
        role == UserRole.doctor && item.kind == 'doctor_patient_assignments';
    final rawPatientContext = item.data['patient_context'];
    final patientContext = rawPatientContext is Map
        ? Map<String, Object?>.from(rawPatientContext)
        : null;
    final patientContextUnavailable = item.data['patient_context_unavailable']
        ?.toString();
    final entries = item.kind == 'medical_documents'
        ? _medicalDocumentDetailEntries(item.data)
        : _isPatientConnectionRequest(item)
        ? <(String, String)>[]
        : <(String, String)>[
            for (final key in _detailKeys(item.kind))
              if (!(item.kind == 'prescriptions' &&
                  key == 'dosage' &&
                  _detailValue(item.data['exact_dose'], 'exact_dose') != null))
                if (_detailValue(item.data[key], key) case final value?)
                  (_detailLabel(key), value),
          ];
    if (entries.isEmpty && topActions == null && !showCheckupHistory) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topActions != null) ...[
          topActions!,
          const SizedBox(height: AppSpacing.x6),
        ],
        if (role == UserRole.doctor && patientContext != null) ...[
          _AuthorizedPatientContext(contextData: patientContext),
          const SizedBox(height: AppSpacing.x4),
        ] else if (role == UserRole.doctor &&
            patientContextUnavailable?.isNotEmpty == true) ...[
          _PatientContextUnavailable(
            message: patientContextUnavailable!,
            assignmentHistoryAvailable: showCheckupHistory,
          ),
          const SizedBox(height: AppSpacing.x4),
        ],
        if (entries.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: AppSpacing.x4),
            padding: const EdgeInsets.all(AppSpacing.x4),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fieldWidth = constraints.maxWidth >= 720
                    ? (constraints.maxWidth - AppSpacing.x4) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: AppSpacing.x4,
                  runSpacing: AppSpacing.x4,
                  children: [
                    for (final entry in entries)
                      SizedBox(
                        width: fieldWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.$1,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: AppSpacing.x1),
                            SelectableText(entry.$2),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        if (showCheckupHistory) ...[
          const SizedBox(height: AppSpacing.x2),
          _PatientCheckupHistory(records: checkups),
          const SizedBox(height: AppSpacing.x6),
          _PatientClinicalHistorySection(
            title: 'Prescription History',
            description:
                'A chronological record of prescriptions issued for this patient.',
            emptyMessage: 'No prescriptions recorded yet.',
            records: prescriptions,
            prescription: true,
          ),
          const SizedBox(height: AppSpacing.x6),
          _PatientClinicalHistorySection(
            title: 'Diagnostic Result History',
            description:
                'Laboratory and diagnostic results available through this care relationship.',
            emptyMessage: 'No diagnostic results recorded yet.',
            records: diagnosticResults,
          ),
        ],
      ],
    );
  }
}

class _AuthorizedPatientContext extends StatelessWidget {
  const _AuthorizedPatientContext({required this.contextData});

  final Map<String, Object?> contextData;

  @override
  Widget build(BuildContext context) {
    const categoryLabels = <String, String>{
      'medical_records': 'Medical records',
      'diagnoses': 'Diagnoses',
      'prescriptions': 'Prescriptions',
      'laboratory_requests': 'Laboratory requests',
      'laboratory_results': 'Diagnostic results',
      'medical_documents': 'Medical documents',
      'treatment_plans': 'Treatment plans',
    };
    final categories =
        <({String key, String label, List<Map<String, Object?>> rows})>[
          for (final entry in categoryLabels.entries)
            if (contextData[entry.key] case final List<dynamic> rows)
              (
                key: entry.key,
                label: entry.value,
                rows: rows
                    .whereType<Map>()
                    .map((row) => Map<String, Object?>.from(row))
                    .toList(growable: false),
              ),
        ];
    final allergies = contextData['allergies_medications'];
    final allergyData = allergies is Map
        ? Map<String, Object?>.from(allergies)
        : null;
    final demographics = contextData['demographics'];
    final demographicData = demographics is Map
        ? Map<String, Object?>.from(demographics)
        : null;

    return Material(
      color: AppColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_shared_outlined),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    'Authorized patient context',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Only categories authorized for this active consultation are queried. External records keep their source and are read-only.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (demographicData != null) ...[
              const SizedBox(height: AppSpacing.x3),
              _ConsultationFieldGrid(
                fields: [
                  if (_firstText(demographicData, const ['first_name'])
                      case final firstName?)
                    _ConsultationField(
                      'Patient',
                      '$firstName ${_firstText(demographicData, const ['last_name']) ?? ''}'
                          .trim(),
                    ),
                  if (_detailValue(
                        demographicData['patient_number'],
                        'patient_number',
                      )
                      case final value?)
                    _ConsultationField('Patient number', value),
                  if (_detailValue(demographicData['birth_date'], 'birth_date')
                      case final value?)
                    _ConsultationField('Birth date', value),
                  if (_detailValue(demographicData['sex'], 'sex')
                      case final value?)
                    _ConsultationField('Sex', value),
                  if (_detailValue(
                        demographicData['mobile_number'],
                        'mobile_number',
                      )
                      case final value?)
                    _ConsultationField('Registered phone', value),
                  if (_detailValue(demographicData['address'], 'address')
                      case final value?)
                    _ConsultationField('Address', value),
                ],
              ),
            ],
            if (allergyData != null) ...[
              const SizedBox(height: AppSpacing.x3),
              _ConsultationFieldGrid(
                fields: [
                  _ConsultationField(
                    'Allergies',
                    _detailValue(allergyData['allergies'], 'allergies') ??
                        'None recorded',
                  ),
                  _ConsultationField(
                    'Current medications',
                    _detailValue(
                          allergyData['current_medications'],
                          'current_medications',
                        ) ??
                        'None recorded',
                  ),
                ],
              ),
            ],
            for (final category in categories)
              if (category.rows.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x3),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(category.label),
                  subtitle: Text(
                    '${category.rows.length} authorized record${category.rows.length == 1 ? '' : 's'}',
                  ),
                  children: [
                    for (final record in category.rows)
                      _AuthorizedPatientContextRecord(
                        category: category.key,
                        categoryLabel: category.label,
                        record: record,
                      ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _AuthorizedPatientContextRecord extends ConsumerStatefulWidget {
  const _AuthorizedPatientContextRecord({
    required this.category,
    required this.categoryLabel,
    required this.record,
  });

  final String category;
  final String categoryLabel;
  final Map<String, Object?> record;

  @override
  ConsumerState<_AuthorizedPatientContextRecord> createState() =>
      _AuthorizedPatientContextRecordState();
}

class _AuthorizedPatientContextRecordState
    extends ConsumerState<_AuthorizedPatientContextRecord> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    final rawRecord = widget.record['record'];
    final clinicalRecord = rawRecord is Map
        ? Map<String, Object?>.from(rawRecord)
        : const <String, Object?>{};
    if (widget.category != 'medical_documents') {
      await showRootDialog<void>(
        builder: (context) => _AuthorizedClinicalRecordDialog(
          categoryLabel: widget.categoryLabel,
          record: widget.record,
        ),
      );
      return;
    }

    final documentId = clinicalRecord['id']?.toString() ?? '';
    if (documentId.isEmpty) {
      showRootMessage('This medical document is missing its secure file link.');
      return;
    }
    setState(() => _opening = true);
    try {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final url = await repository.createSignedFileUrl(documentId);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('The secure medical document could not be opened.');
      }
    } catch (error) {
      showRootMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawRecord = widget.record['record'];
    final clinicalRecord = rawRecord is Map
        ? Map<String, Object?>.from(rawRecord)
        : const <String, Object?>{};
    final title =
        _firstText(clinicalRecord, const [
          'title',
          'diagnosis',
          'medication_name',
          'test_name',
          'plan',
          'record_type',
        ]) ??
        'Clinical record';
    final source =
        _firstText(widget.record, const ['originating_hospital']) ??
        'Source hospital unavailable';
    final author =
        _firstText(widget.record, const ['authoring_doctor']) ??
        'Author unavailable';
    final recordDate =
        _detailValue(widget.record['record_date'], 'record_date') ??
        'Date unavailable';
    final recordStatus =
        _detailValue(widget.record['record_status'], 'record_status') ??
        'Status unavailable';
    final isExternal = widget.record['external_read_only'] == true;
    final isDocument = widget.category == 'medical_documents';
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.x2),
      child: ListTile(
        onTap: _opening ? null : _open,
        leading: Icon(
          isExternal ? Icons.lock_outline : Icons.description_outlined,
        ),
        title: Text(title),
        subtitle: Text(
          '$source | $author | $recordDate | $recordStatus${isExternal ? ' | External read-only' : ''}',
        ),
        trailing: _opening
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: _open,
                icon: Icon(
                  isDocument ? Icons.open_in_new : Icons.visibility_outlined,
                  size: 18,
                ),
                label: Text(isDocument ? 'Open file' : 'View'),
              ),
        isThreeLine: true,
      ),
    );
  }
}

class _AuthorizedClinicalRecordDialog extends StatelessWidget {
  const _AuthorizedClinicalRecordDialog({
    required this.categoryLabel,
    required this.record,
  });

  final String categoryLabel;
  final Map<String, Object?> record;

  @override
  Widget build(BuildContext context) {
    final rawRecord = record['record'];
    final clinicalRecord = rawRecord is Map
        ? Map<String, Object?>.from(rawRecord)
        : const <String, Object?>{};
    final title =
        _firstText(clinicalRecord, const [
          'title',
          'diagnosis',
          'medication_name',
          'test_name',
          'plan',
          'record_type',
        ]) ??
        categoryLabel;
    final preferredKeys = _detailKeys(
      categoryLabel == 'Medical records'
          ? 'medical_records'
          : categoryLabel == 'Prescriptions'
          ? 'prescriptions'
          : categoryLabel == 'Laboratory requests'
          ? 'laboratory_requests'
          : categoryLabel == 'Diagnostic results'
          ? 'laboratory_results'
          : '',
    );
    const hiddenKeys = {
      'id',
      'patient_id',
      'doctor_id',
      'hospital_id',
      'consultation_id',
      'uploaded_by',
      'author_doctor_id',
      'storage_bucket',
      'storage_path',
      'checksum',
    };
    final keys = preferredKeys.isNotEmpty
        ? preferredKeys
        : clinicalRecord.keys
              .where((key) => !hiddenKeys.contains(key))
              .toList(growable: false);
    final fields = <_ConsultationField>[
      if (_firstText(record, const ['originating_hospital']) case final value?)
        _ConsultationField('Source facility', value),
      if (_firstText(record, const ['authoring_doctor']) case final value?)
        _ConsultationField('Author', value),
      if (_detailValue(record['record_date'], 'record_date') case final value?)
        _ConsultationField('Record date', value),
      if (_detailValue(record['record_status'], 'record_status')
          case final value?)
        _ConsultationField('Status', value),
      for (final key in keys)
        if (_detailValue(clinicalRecord[key], key) case final value?)
          _ConsultationField(_detailLabel(key), value),
    ];

    return AlertDialog(
      icon: const Icon(Icons.description_outlined),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                categoryLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (record['external_read_only'] == true) ...[
                const SizedBox(height: AppSpacing.x2),
                const Text(
                  'This record comes from another facility and is available read-only.',
                ),
              ],
              const SizedBox(height: AppSpacing.x4),
              if (fields.isEmpty)
                const Text('No additional record details are available.')
              else
                for (var index = 0; index < fields.length; index++) ...[
                  Text(
                    fields[index].label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  SelectableText(fields[index].value),
                  if (index != fields.length - 1)
                    const SizedBox(height: AppSpacing.x3),
                ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PatientContextUnavailable extends StatelessWidget {
  const _PatientContextUnavailable({
    required this.message,
    this.assignmentHistoryAvailable = false,
  });

  final String message;
  final bool assignmentHistoryAvailable;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.x4),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(AppRadius.panel),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: Text(
            assignmentHistoryAvailable
                ? 'Consultation-specific patient context is unavailable. $message Checkup, prescription, and diagnostic result histories authorized by this assignment remain available below.'
                : 'Patient context is unavailable because no active authorized care relationship covers it. $message',
          ),
        ),
      ],
    ),
  );
}

class _PatientCheckupHistory extends StatelessWidget {
  const _PatientCheckupHistory({required this.records});

  final List<Map<String, Object?>> records;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Checkup History', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.x1),
      Text(
        'A chronological record of this patient\'s saved checkups.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.x3),
      if (records.isEmpty)
        Container(
          padding: const EdgeInsets.all(AppSpacing.x4),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: const Text('No checkups recorded yet.'),
        )
      else
        for (var index = 0; index < records.length; index++) ...[
          _CheckupHistoryEntry(record: records[index]),
          if (index != records.length - 1)
            const SizedBox(height: AppSpacing.x2),
        ],
    ],
  );
}

class _CheckupHistoryEntry extends StatelessWidget {
  const _CheckupHistoryEntry({required this.record});

  final Map<String, Object?> record;

  @override
  Widget build(BuildContext context) {
    final title =
        _firstText(record, const ['title', 'reason_for_visit']) ??
        'Patient checkup';
    final recordedAt =
        _detailValue(record['vitals_recorded_at'], 'vitals_recorded_at') ??
        _detailValue(record['created_at'], 'created_at') ??
        _detailValue(record['record_date'], 'record_date') ??
        'Date not recorded';
    final doctor =
        _firstText(record, const ['doctor_display_name']) ?? 'Care team';
    final hospital = _firstText(record, const [
      'originating_hospital',
      'hospital_name',
      'facility',
    ]);
    final details = <(String, String)>[
      if (hospital != null && hospital.isNotEmpty)
        ('Originating Facility / Hospital', hospital),
      for (final key in _detailKeys('medical_records'))
        if (!{'title', 'created_at', 'originating_hospital', 'hospital_name'}.contains(key))
          if (_detailValue(record[key], key) case final value?)
            (_detailLabel(key), value),
    ];

    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: Text(title),
        subtitle: Text(
          [
            recordedAt,
            doctor,
            if (hospital != null && hospital.isNotEmpty) hospital,
          ].join(' • '),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.x4,
          0,
          AppSpacing.x4,
          AppSpacing.x4,
        ),
        children: [
          const Divider(),
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = constraints.maxWidth >= 720
                  ? (constraints.maxWidth - AppSpacing.x4) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.x4,
                runSpacing: AppSpacing.x3,
                children: [
                  for (final detail in details)
                    SizedBox(
                      width: fieldWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.$1,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: AppSpacing.x1),
                          SelectableText(detail.$2),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PatientClinicalHistorySection extends StatelessWidget {
  const _PatientClinicalHistorySection({
    required this.title,
    required this.description,
    required this.emptyMessage,
    required this.records,
    this.prescription = false,
  });

  final String title;
  final String description;
  final String emptyMessage;
  final List<Map<String, Object?>> records;
  final bool prescription;

  @override
  Widget build(BuildContext context) {
    final isPrescription = prescription;
    final prescriptionGroups =
        isPrescription ? _groupPrescriptions(records) : null;
    final isEmpty = isPrescription
        ? prescriptionGroups!.isEmpty
        : records.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.x1),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.x3),
        if (isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.x4),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Text(emptyMessage),
          )
        else if (isPrescription)
          for (var index = 0; index < prescriptionGroups!.length; index++) ...[
            if (prescriptionGroups[index].medications.isEmpty &&
                prescriptionGroups[index].attachment != null)
              _PatientClinicalHistoryEntry(
                record: prescriptionGroups[index].attachment!,
                prescription: true,
              )
            else
              _PatientGroupedPrescriptionCard(
                group: prescriptionGroups[index],
              ),
            if (index != prescriptionGroups.length - 1)
              const SizedBox(height: AppSpacing.x2),
          ]
        else
          for (var index = 0; index < records.length; index++) ...[
            _PatientClinicalHistoryEntry(
              record: records[index],
              prescription: false,
            ),
            if (index != records.length - 1)
              const SizedBox(height: AppSpacing.x2),
          ],
      ],
    );
  }
}

class _PrescriptionGroup {
  const _PrescriptionGroup({
    required this.id,
    required this.date,
    required this.formattedDate,
    required this.recordedAtText,
    required this.doctor,
    required this.hospital,
    required this.diagnosisReason,
    required this.medications,
    this.attachment,
  });

  final String id;
  final DateTime date;
  final String formattedDate;
  final String recordedAtText;
  final String? doctor;
  final String? hospital;
  final String? diagnosisReason;
  final List<Map<String, Object?>> medications;
  final Map<String, Object?>? attachment;
}

DateTime _clinicalHistoryDate(Map<String, Object?> record) {
  for (final key in const [
    'electronically_signed_at',
    'created_at',
    'start_date',
    'result_date',
    'uploaded_at',
  ]) {
    final value = record[key];
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return DateTime(1970);
}

List<_PrescriptionGroup> _groupPrescriptions(
  List<Map<String, Object?>> records,
) {
  if (records.isEmpty) return const [];

  final medicationRows = <Map<String, Object?>>[];
  final documentRows = <Map<String, Object?>>[];

  for (final record in records) {
    if (record['history_source'] == 'medical_documents' ||
        record['document_type'] == 'prescription') {
      documentRows.add(record);
    } else {
      medicationRows.add(record);
    }
  }

  medicationRows.sort(
    (left, right) =>
        _clinicalHistoryDate(right).compareTo(_clinicalHistoryDate(left)),
  );

  final clusters = <List<Map<String, Object?>>>[];
  for (final med in medicationRows) {
    final medTime = _clinicalHistoryDate(med);
    final patientId = med['patient_id']?.toString() ?? '';
    final doctorId = med['doctor_id']?.toString() ??
        med['prescriber_name']?.toString() ??
        med['doctor_display_name']?.toString() ??
        '';
    final consultationId = med['consultation_id']?.toString() ?? '';

    List<Map<String, Object?>>? targetCluster;
    for (final cluster in clusters) {
      final leader = cluster.first;
      final leaderTime = _clinicalHistoryDate(leader);
      final leaderPatientId = leader['patient_id']?.toString() ?? '';
      final leaderDoctorId = leader['doctor_id']?.toString() ??
          leader['prescriber_name']?.toString() ??
          leader['doctor_display_name']?.toString() ??
          '';
      final leaderConsultationId = leader['consultation_id']?.toString() ?? '';

      final samePatient = patientId.isEmpty ||
          leaderPatientId.isEmpty ||
          patientId == leaderPatientId;
      final sameDoctor = doctorId.isEmpty ||
          leaderDoctorId.isEmpty ||
          doctorId == leaderDoctorId;
      final sameConsultation = consultationId.isNotEmpty &&
          consultationId == leaderConsultationId;
      final timeDifference = (medTime.difference(leaderTime).inSeconds).abs();

      if (samePatient && sameDoctor && (sameConsultation || timeDifference <= 300)) {
        targetCluster = cluster;
        break;
      }
    }

    if (targetCluster != null) {
      targetCluster.add(med);
    } else {
      clusters.add([med]);
    }
  }

  final availableDocs = List<Map<String, Object?>>.from(documentRows);
  final groups = <_PrescriptionGroup>[];

  for (final cluster in clusters) {
    final leader = cluster.first;
    final leaderTime = _clinicalHistoryDate(leader);
    final leaderPatientId = leader['patient_id']?.toString() ?? '';
    final leaderDoctorId = leader['doctor_id']?.toString() ?? '';

    Map<String, Object?>? matchedDoc;
    for (var i = 0; i < availableDocs.length; i++) {
      final doc = availableDocs[i];
      final docTime = _clinicalHistoryDate(doc);
      final docPatientId = doc['patient_id']?.toString() ?? '';
      final docDoctorId = doc['author_doctor_id']?.toString() ??
          doc['doctor_id']?.toString() ??
          '';

      final samePatient = leaderPatientId.isEmpty ||
          docPatientId.isEmpty ||
          leaderPatientId == docPatientId;
      final sameDoctor = leaderDoctorId.isEmpty ||
          docDoctorId.isEmpty ||
          leaderDoctorId == docDoctorId;
      final timeDiff = (docTime.difference(leaderTime).inSeconds).abs();

      if (samePatient && sameDoctor && timeDiff <= 300) {
        matchedDoc = doc;
        availableDocs.removeAt(i);
        break;
      }
    }

    final doctor = _firstText(
      leader,
      const ['prescriber_name', 'doctor_display_name'],
    );
    final hospital = _firstText(leader, const [
      'originating_hospital',
      'hospital_name',
      'facility',
    ]);
    final diagnosis = _firstText(
      leader,
      const ['diagnosis_reason', 'diagnosis'],
    );
    final recordedAtText = _detailValue(
          leader['electronically_signed_at'],
          'electronically_signed_at',
        ) ??
        _detailValue(leader['created_at'], 'created_at') ??
        _detailValue(leader['start_date'], 'start_date') ??
        'Date not recorded';
    final formattedDate = leaderTime.year > 1970
        ? DateFormat('MMM d, y').format(leaderTime.toLocal())
        : recordedAtText;

    groups.add(
      _PrescriptionGroup(
        id: leader['id']?.toString() ?? '',
        date: leaderTime,
        formattedDate: formattedDate,
        recordedAtText: recordedAtText,
        doctor: doctor,
        hospital: hospital,
        diagnosisReason: diagnosis,
        medications: cluster,
        attachment: matchedDoc,
      ),
    );
  }

  for (final doc in availableDocs) {
    final docTime = _clinicalHistoryDate(doc);
    final doctor = _firstText(
      doc,
      const ['requesting_doctor', 'doctor_display_name', 'authoring_doctor'],
    );
    final hospital = _firstText(doc, const [
      'originating_hospital',
      'hospital_name',
      'facility',
    ]);
    final recordedAtText = _detailValue(doc['result_date'], 'result_date') ??
        _detailValue(doc['uploaded_at'], 'uploaded_at') ??
        _detailValue(doc['created_at'], 'created_at') ??
        'Date not recorded';
    final formattedDate = docTime.year > 1970
        ? DateFormat('MMM d, y').format(docTime.toLocal())
        : recordedAtText;

    groups.add(
      _PrescriptionGroup(
        id: doc['id']?.toString() ?? '',
        date: docTime,
        formattedDate: formattedDate,
        recordedAtText: recordedAtText,
        doctor: doctor,
        hospital: hospital,
        diagnosisReason: null,
        medications: const [],
        attachment: doc,
      ),
    );
  }

  groups.sort((a, b) => b.date.compareTo(a.date));
  return groups;
}

class _PatientGroupedPrescriptionCard extends ConsumerStatefulWidget {
  const _PatientGroupedPrescriptionCard({required this.group});

  final _PrescriptionGroup group;

  @override
  ConsumerState<_PatientGroupedPrescriptionCard> createState() =>
      _PatientGroupedPrescriptionCardState();
}

class _PatientGroupedPrescriptionCardState
    extends ConsumerState<_PatientGroupedPrescriptionCard> {
  bool _opening = false;

  Future<void> _openFile(String documentId) async {
    if (_opening || documentId.isEmpty) return;
    setState(() => _opening = true);
    try {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final url = await repository.createSignedFileUrl(documentId);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('The secure clinical file could not be opened.');
      }
    } catch (error) {
      showRootMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final medCount = group.medications.length;
    final isStandaloneDoc = group.medications.isEmpty && group.attachment != null;

    final subtitleParts = [
      group.recordedAtText,
      if (group.doctor != null && group.doctor!.isNotEmpty) group.doctor!,
      if (group.hospital != null &&
          group.hospital!.isNotEmpty &&
          (group.doctor == null || !group.doctor!.contains(group.hospital!)))
        group.hospital!,
    ];

    if (isStandaloneDoc) {
      return Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: ExpansionTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(
            group.attachment!['title']?.toString() ?? 'Prescription Attachment',
          ),
          subtitle: Text(subtitleParts.join(' • ')),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x2,
            AppSpacing.x4,
            AppSpacing.x4,
          ),
          children: [
            const Divider(),
            if (group.attachment!['id'] != null)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _opening
                      ? null
                      : () => _openFile(group.attachment!['id'].toString()),
                  icon: _opening
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('Open secure file'),
                ),
              ),
          ],
        ),
      );
    }

    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(
          Icons.medication_outlined,
          color: AppColors.primary,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Prescription — ${group.formattedDate}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x2,
                vertical: AppSpacing.x1 / 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.selected,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Text(
                '$medCount medication${medCount == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
        subtitle: Text(subtitleParts.join(' • ')),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.x4,
          AppSpacing.x1,
          AppSpacing.x4,
          AppSpacing.x4,
        ),
        children: [
          const Divider(),
          if (group.diagnosisReason != null &&
              group.diagnosisReason!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.x2),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Text(
                'Indication / Diagnosis: ${group.diagnosisReason}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
          ],
          for (var index = 0; index < group.medications.length; index++) ...[
            _buildMedicationRow(context, group.medications[index], index + 1),
            if (index != group.medications.length - 1)
              const SizedBox(height: AppSpacing.x2),
          ],
          if (group.attachment != null && group.attachment!['id'] != null) ...[
            const SizedBox(height: AppSpacing.x3),
            const Divider(),
            const SizedBox(height: AppSpacing.x1),
            Row(
              children: [
                const Icon(Icons.attachment, size: 18),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    group.attachment!['title']?.toString() ??
                        group.attachment!['file_name']?.toString() ??
                        'Prescription Attachment',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _opening
                      ? null
                      : () => _openFile(group.attachment!['id'].toString()),
                  icon: _opening
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_open_outlined, size: 16),
                  label: const Text('Open scan file'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicationRow(
    BuildContext context,
    Map<String, Object?> med,
    int number,
  ) {
    final name = med['medication_name']?.toString() ?? 'Medication';
    final formStrength = med['medication_form_strength']?.toString();
    final dose =
        med['exact_dose']?.toString() ?? med['dosage']?.toString() ?? '';
    final frequency = med['frequency']?.toString() ?? '';
    final duration = med['duration']?.toString();
    final quantity = med['quantity_to_dispense']?.toString();
    final refills = med['refills'];
    final instructions = med['instructions']?.toString();
    final isPrn = med['is_prn'] == true;
    final prnReason = med['prn_reason']?.toString();

    final parts = [
      if (dose.isNotEmpty) dose,
      if (frequency.isNotEmpty) frequency,
      if (duration != null && duration.isNotEmpty) duration,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$number. ',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
              ),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (formStrength != null && formStrength.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.x1),
                      Flexible(
                        child: Text(
                          '— $formStrength',
                          style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (quantity != null && quantity.isNotEmpty)
                Text(
                  '# $quantity',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
            ],
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x1),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                'Sig: ${parts.join(' — ')}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
              ),
            ),
          ],
          if (isPrn) ...[
            const SizedBox(height: AppSpacing.x1 / 2),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                'Take as needed (PRN)${prnReason != null ? ': $prnReason' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          ],
          if (instructions != null &&
              instructions.isNotEmpty &&
              instructions != frequency &&
              instructions != parts.join(' — ')) ...[
            const SizedBox(height: AppSpacing.x1 / 2),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                'Instructions: $instructions',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (refills != null && refills != 0) ...[
            const SizedBox(height: AppSpacing.x1 / 2),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                'Refills: $refills',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupedPrescriptionDetailView extends ConsumerStatefulWidget {
  const _GroupedPrescriptionDetailView({required this.item, this.topActions});

  final WorkspaceItem item;
  final Widget? topActions;

  @override
  ConsumerState<_GroupedPrescriptionDetailView> createState() =>
      _GroupedPrescriptionDetailViewState();
}

class _GroupedPrescriptionDetailViewState
    extends ConsumerState<_GroupedPrescriptionDetailView> {
  bool _opening = false;

  Future<void> _openFile(String documentId) async {
    if (_opening || documentId.isEmpty) return;
    setState(() => _opening = true);
    try {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final url = await repository.createSignedFileUrl(documentId);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('The secure clinical file could not be opened.');
      }
    } catch (error) {
      showRootMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final rawMeds = item.data['grouped_medications'];
    final medications = rawMeds is List
        ? rawMeds
            .whereType<Map>()
            .map((m) => Map<String, Object?>.from(m))
            .toList(growable: false)
        : [item.data];
    final prescriberName = _firstText(
      item.data,
      const ['prescriber_name', 'doctor_display_name'],
    );
    final prescriberLicense =
        item.data['prescriber_license_number']?.toString();
    final prescriberSpecialization =
        item.data['prescriber_specialization']?.toString();
    final hospital = _firstText(
      item.data,
      const ['originating_hospital', 'hospital_name', 'facility'],
    );
    final diagnosis = _firstText(
      item.data,
      const ['diagnosis_reason', 'diagnosis'],
    );
    final rawAttachment = item.data['attachment_document'];
    final attachment = rawAttachment is Map
        ? Map<String, Object?>.from(rawAttachment)
        : null;
    final attachmentId = attachment?['id']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.topActions != null) ...[
          widget.topActions!,
          const SizedBox(height: AppSpacing.x6),
        ],
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: AppSpacing.x4),
          padding: const EdgeInsets.all(AppSpacing.x4),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.badge_outlined, size: 20),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Text(
                      prescriberName ?? 'Licensed Prescriber',
                      style:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ),
                ],
              ),
              if ((prescriberLicense != null &&
                      prescriberLicense.isNotEmpty) ||
                  (prescriberSpecialization != null &&
                      prescriberSpecialization.isNotEmpty)) ...[
                const SizedBox(height: AppSpacing.x1),
                Text(
                  [
                    if (prescriberSpecialization != null &&
                        prescriberSpecialization.isNotEmpty)
                      prescriberSpecialization,
                    if (prescriberLicense != null &&
                        prescriberLicense.isNotEmpty)
                      'License $prescriberLicense',
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (hospital != null && hospital.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x1),
                Text(
                  hospital,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
              if (diagnosis != null && diagnosis.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.x3),
                const Divider(),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  'Diagnosis / Indication: $diagnosis',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ],
          ),
        ),
        Text(
          'Medications (${medications.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.x2),
        for (var index = 0; index < medications.length; index++) ...[
          _buildMedicationCard(context, medications[index], index + 1),
          const SizedBox(height: AppSpacing.x3),
        ],
        if (attachmentId != null && attachmentId.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x2),
          Container(
            padding: const EdgeInsets.all(AppSpacing.x3),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              children: [
                const Icon(Icons.attachment, size: 20),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    attachment?['title']?.toString() ??
                        attachment?['file_name']?.toString() ??
                        'Prescription Attachment',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _opening ? null : () => _openFile(attachmentId),
                  icon: _opening
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_open_outlined, size: 16),
                  label: const Text('Open file'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMedicationCard(
    BuildContext context,
    Map<String, Object?> med,
    int number,
  ) {
    final name = med['medication_name']?.toString() ?? 'Medication';
    final formStrength = med['medication_form_strength']?.toString();
    final dose =
        med['exact_dose']?.toString() ?? med['dosage']?.toString() ?? '';
    final route = med['route']?.toString();
    final frequency = med['frequency']?.toString() ?? '';
    final duration = med['duration']?.toString();
    final quantity = med['quantity_to_dispense']?.toString();
    final refills = med['refills'];
    final instructions = med['instructions']?.toString();
    final startDate = med['start_date']?.toString();
    final isPrn = med['is_prn'] == true;
    final prnReason = med['prn_reason']?.toString();

    final details = <(String, String)>[
      if (formStrength != null && formStrength.isNotEmpty)
        ('Form and strength', formStrength),
      if (route != null && route.isNotEmpty) ('Route', route),
      if (dose.isNotEmpty) ('Exact dose', dose),
      if (frequency.isNotEmpty) ('Frequency', frequency),
      if (duration != null && duration.isNotEmpty) ('Duration', duration),
      if (quantity != null && quantity.isNotEmpty)
        ('Quantity to dispense', quantity),
      if (refills != null) ('Refills', refills.toString()),
      if (startDate != null && startDate.isNotEmpty) ('Start date', startDate),
      if (isPrn) ('PRN (as needed)', prnReason ?? 'Yes'),
      if (instructions != null && instructions.isNotEmpty)
        ('Instructions', instructions),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '$number. ',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                ),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (quantity != null && quantity.isNotEmpty)
                  Text(
                    '# $quantity',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            Wrap(
              spacing: AppSpacing.x4,
              runSpacing: AppSpacing.x3,
              children: [
                for (final detail in details)
                  SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.$1,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: AppSpacing.x1 / 2),
                        SelectableText(detail.$2),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientClinicalHistoryEntry extends ConsumerStatefulWidget {
  const _PatientClinicalHistoryEntry({
    required this.record,
    required this.prescription,
  });

  final Map<String, Object?> record;
  final bool prescription;

  @override
  ConsumerState<_PatientClinicalHistoryEntry> createState() =>
      _PatientClinicalHistoryEntryState();
}

class _PatientClinicalHistoryEntryState
    extends ConsumerState<_PatientClinicalHistoryEntry> {
  bool _opening = false;

  Future<void> _openFile() async {
    final documentId = widget.record['id']?.toString() ?? '';
    if (_opening || documentId.isEmpty) return;
    setState(() => _opening = true);
    try {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final url = await repository.createSignedFileUrl(documentId);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('The secure clinical file could not be opened.');
      }
    } catch (error) {
      showRootMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final source = record['history_source']?.toString() ?? '';
    final isFile = source == 'medical_documents';
    final title = widget.prescription
        ? _firstText(record, const ['medication_name', 'title']) ??
              'Prescription'
        : _firstText(record, const [
                'test_procedure_name',
                'test_name',
                'title',
              ]) ??
              'Diagnostic result';
    final recordedAt = widget.prescription
        ? _detailValue(
                record['electronically_signed_at'],
                'electronically_signed_at',
              ) ??
              _detailValue(record['created_at'], 'created_at') ??
              'Date not recorded'
        : _detailValue(record['result_date'], 'result_date') ??
              _detailValue(record['uploaded_at'], 'uploaded_at') ??
              _detailValue(record['created_at'], 'created_at') ??
              'Date not recorded';
    final author = widget.prescription
        ? _firstText(record, const ['prescriber_name', 'doctor_display_name'])
        : _firstText(record, const [
            'requesting_doctor',
            'doctor_display_name',
            'authoring_doctor',
          ]);
    final hospital = _firstText(record, const [
      'originating_hospital',
      'hospital_name',
      'facility',
    ]);
    final keys = widget.prescription
        ? source == 'prescriptions'
              ? _detailKeys('prescriptions')
              : _detailKeys('medical_documents')
        : source == 'laboratory_results'
        ? _detailKeys('laboratory_results')
        : const [
            'result_category',
            'test_procedure_name',
            'performed_or_collected_date',
            'result_date',
            'facility',
            'requesting_doctor',
            'patient_name_on_report',
            'procedure_details',
            'test_procedure_name_ai_generated',
            'performed_or_collected_date_text',
            'result_date_text',
            'result_details',
            'official_findings_impression',
            'report_recommendations',
            'technical_summary',
            'patient_friendly_summary',
            'verification_notes',
            'findings_impression',
            'notes',
            'ai_analysis_status',
            'ai_summary',
            'ai_analysis_error',
            'created_at',
          ];
    final details = isFile
        ? [
            if (hospital != null &&
                hospital.isNotEmpty &&
                record['facility'] == null)
              ('Originating Facility / Hospital', hospital),
            ..._medicalDocumentDetailEntries(record),
          ]
        : <(String, String)>[
            if (hospital != null &&
                hospital.isNotEmpty &&
                !keys.contains('facility') &&
                record['facility'] == null)
              ('Originating Facility / Hospital', hospital),
            for (final key in keys)
              if (key != 'originating_hospital')
                if (_detailValue(record[key], key) case final value?)
                  (_detailLabel(key), value),
          ];

    final subtitleParts = [
      recordedAt,
      if (author != null && author.isNotEmpty) author,
      if (hospital != null &&
          hospital.isNotEmpty &&
          (author == null || !author.contains(hospital)))
        hospital,
    ];

    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: ExpansionTile(
        leading: Icon(
          widget.prescription
              ? Icons.medication_outlined
              : Icons.biotech_outlined,
        ),
        title: Text(title),
        subtitle: Text(subtitleParts.join(' • ')),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.x4,
          AppSpacing.x2,
          AppSpacing.x4,
          AppSpacing.x4,
        ),
        children: [
          const Divider(),
          if (isFile) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _opening ? null : _openFile,
                icon: _opening
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_new, size: 18),
                label: Text(_opening ? 'Opening...' : 'Open secure file'),
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = constraints.maxWidth >= 720
                  ? (constraints.maxWidth - AppSpacing.x4) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.x4,
                runSpacing: AppSpacing.x3,
                children: [
                  for (final detail in details)
                    SizedBox(
                      width: fieldWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.$1,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: AppSpacing.x1),
                          SelectableText(detail.$2),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AppointmentDetailPageHeader extends StatelessWidget {
  const _AppointmentDetailPageHeader({
    required this.consultationCount,
    required this.onBack,
  });

  final int consultationCount;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Appointment Details',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.x4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to list'),
            ),
            Text(
              _consultationCountLabel(consultationCount),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ],
    ),
  );
}

class _ConsultationDetails extends StatelessWidget {
  const _ConsultationDetails({required this.item, this.role});

  final WorkspaceItem item;
  final UserRole? role;

  @override
  Widget build(BuildContext context) {
    final data = item.data;
    final rawPatientContext = data['patient_context'];
    final patientContext = rawPatientContext is Map
        ? Map<String, Object?>.from(rawPatientContext)
        : null;
    final patientContextUnavailable = data['patient_context_unavailable']
        ?.toString();
    final facility =
        _firstText(data, const ['hospital_name', 'facility_name']) ??
        'Not listed';
    final doctorName =
        _firstText(data, const ['doctor_display_name', 'doctor_name']) ??
        'Not assigned';
    final overview = <_ConsultationField>[
      _ConsultationField('Facility', facility),
      if (_firstText(data, const ['department_name']) case final value?)
        _ConsultationField('Department', value),
      if (_firstText(data, const ['hospital_location']) case final value?)
        _ConsultationField('Location', value),
      _ConsultationField(
        'Type',
        _consultationTypeLabel(data['consultation_type']),
      ),
    ];
    final clinical = <_ConsultationField>[
      if (_firstText(data, const ['doctor_notes', 'consultation_summary'])
          case final value?)
        _ConsultationField('Clinical Notes', value),
      if (_firstText(data, const ['confirmed_diagnosis']) case final value?)
        _ConsultationField('Diagnosis / Assessment', value),
      if (_firstText(data, const [
            'follow_up_instructions',
            'follow_up',
            'treatment_plan',
          ])
          case final value?)
        _ConsultationField('Follow-up', value),
    ];
    final health = <_ConsultationField>[
      if (_firstText(data, const ['current_symptoms']) case final value?)
        _ConsultationField('Symptoms', value),
      _ConsultationField(
        'Medical conditions',
        _firstText(data, const ['known_medical_conditions']) ?? 'None recorded',
      ),
      _ConsultationField(
        'Allergies',
        _firstText(data, const ['allergies']) ?? 'None recorded',
      ),
      _ConsultationField(
        'Current medications',
        _firstText(data, const ['current_medications']) ?? 'None recorded',
      ),
      if (_consultationVitals(data) case final value?)
        _ConsultationField('Vitals', value),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: AppSpacing.x6),
          Text('Appointment', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.x4),
          if (facility != 'Not listed') ...[
            HospitalImage(
              imageUrl: _firstText(data, const ['hospital_image_url']),
              height: MediaQuery.sizeOf(context).width < 600 ? 150 : 220,
              semanticLabel: '$facility exterior',
            ),
            const SizedBox(height: AppSpacing.x4),
          ],
          _DoctorIdentity(
            name: doctorName,
            imageUrl: _firstText(data, const ['doctor_profile_image_url']),
          ),
          const SizedBox(height: AppSpacing.x4),
          _ConsultationFieldGrid(fields: overview),
          const SizedBox(height: AppSpacing.x4),
          Text(
            'Reason for visit',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.x1),
          SelectableText(
            _firstText(data, const ['chief_complaint']) ?? 'Not provided',
          ),
          if (role == UserRole.doctor && patientContext != null) ...[
            const Divider(height: AppSpacing.x8),
            _AuthorizedPatientContext(contextData: patientContext),
          ] else if (role == UserRole.doctor &&
              patientContextUnavailable?.isNotEmpty == true) ...[
            const Divider(height: AppSpacing.x8),
            _PatientContextUnavailable(message: patientContextUnavailable!),
          ],
          const Divider(height: AppSpacing.x8),
          Text(
            'Clinical Summary',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.x3),
          if (clinical.isEmpty)
            const _ClinicalSummaryEmptyState()
          else
            _ConsultationFieldGrid(fields: clinical),
          const Divider(height: AppSpacing.x8),
          _ConsultationSection(title: 'Health Information', fields: health),
          if (role == UserRole.patient || role == UserRole.doctor) ...[
            const Divider(height: AppSpacing.x8),
            Text(
              'Related Care',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.x2),
            _ConsultationRelatedLink(
              label: 'Prescriptions',
              actionLabel: 'View',
              onPressed: () =>
                  context.go('${role!.homeLocation}/prescriptions'),
            ),
            const Divider(height: 1),
            _ConsultationRelatedLink(
              label: role == UserRole.patient ? 'Diagnostics' : 'Laboratory',
              actionLabel: 'View',
              onPressed: () => context.go(
                '${role!.homeLocation}/${role == UserRole.patient ? 'labs' : 'laboratory'}',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DoctorIdentity extends StatelessWidget {
  const _DoctorIdentity({required this.name, this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    final fallback = Container(
      color: AppColors.selected,
      alignment: Alignment.center,
      child: const Icon(
        Icons.person_outline,
        color: AppColors.primary,
        size: 32,
      ),
    );
    return Row(
      children: [
        ClipOval(
          child: SizedBox.square(
            dimension: 68,
            child: url == null || url.isEmpty
                ? fallback
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    semanticLabel: '$name profile photo',
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Doctor', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: AppSpacing.x1),
              Text(name, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConsultationSection extends StatelessWidget {
  const _ConsultationSection({required this.title, required this.fields});

  final String title;
  final List<_ConsultationField> fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.x3),
        _ConsultationFieldGrid(fields: fields),
      ],
    );
  }
}

class _ConsultationFieldGrid extends StatelessWidget {
  const _ConsultationFieldGrid({required this.fields});

  final List<_ConsultationField> fields;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldWidth = constraints.maxWidth >= 720
            ? (constraints.maxWidth - AppSpacing.x4) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.x4,
          runSpacing: AppSpacing.x4,
          children: [
            for (final field in fields)
              SizedBox(
                width: fieldWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    SelectableText(field.value),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ConsultationField {
  const _ConsultationField(this.label, this.value);

  final String label;
  final String value;
}

class _ConsultationRelatedLink extends StatelessWidget {
  const _ConsultationRelatedLink({
    required this.label,
    required this.actionLabel,
    required this.onPressed,
  });

  final String label;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(actionLabel, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: AppSpacing.x1),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ClinicalSummaryEmptyState extends StatelessWidget {
  const _ClinicalSummaryEmptyState();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.x4),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: Row(
      children: [
        const Icon(Icons.notes_outlined, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: Text(
            'Not available yet',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

class _ConsultationRecordRow extends StatelessWidget {
  const _ConsultationRecordRow({
    required this.item,
    required this.busy,
    this.onOpen,
    this.trailing,
  });

  final WorkspaceItem item;
  final bool busy;
  final VoidCallback? onOpen;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final status = item.status;
    final statusTag = status != null && status.isNotEmpty
        ? StatusTag(
            label: _statusLabel(status),
            icon: _statusIcon(status),
            color: _statusColor(status),
            height: 48,
          )
        : null;
    final rowAction = trailing != null
        ? busy
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : trailing!
        : onOpen != null
        ? const Icon(Icons.chevron_right)
        : null;
    return Semantics(
      button: onOpen != null,
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep the summary readable when status and action controls would
            // otherwise leave it only a few pixels wide on small screens.
            final compact = constraints.maxWidth < 680;
            final summary = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const Icon(
                    Icons.medical_information_outlined,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _consultationTitle(item.title),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        _consultationSummary(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!compact && statusTag != null) ...[
                  const SizedBox(width: AppSpacing.x3),
                  statusTag,
                ],
                if (!compact && rowAction != null) ...[
                  const SizedBox(width: AppSpacing.x2),
                  rowAction,
                ],
              ],
            );
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summary,
                        if (statusTag != null || rowAction != null) ...[
                          const SizedBox(height: AppSpacing.x2),
                          Padding(
                            padding: const EdgeInsets.only(left: 50),
                            child: Wrap(
                              spacing: AppSpacing.x2,
                              runSpacing: AppSpacing.x2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [?statusTag, ?rowAction],
                            ),
                          ),
                        ],
                      ],
                    )
                  : summary,
            );
          },
        ),
      ),
    );
  }
}

List<String> _detailKeys(String kind) => switch (kind) {
  'consultations' => const [
    'consultation_type',
    'appointment_date',
    'status',
    'patient_name',
    'first_name',
    'last_name',
    'birth_date',
    'sex',
    'mobile_number',
    'email',
    'address',
    'chief_complaint',
    'current_symptoms',
    'known_medical_conditions',
    'allergies',
    'current_medications',
    'height_cm',
    'weight_kg',
    'bmi',
    'blood_pressure_systolic',
    'blood_pressure_diastolic',
    'body_temperature_c',
    'heart_rate_bpm',
    'respiratory_rate_bpm',
    'oxygen_saturation_percent',
    'vitals_recorded_at',
    'confirmed_diagnosis',
    'treatment_plan',
    'relevant_medical_history',
    'previous_surgeries',
    'smoking_status',
    'alcohol_use',
    'pregnancy_status',
    'doctor_notes',
    'consultation_summary',
    'rejection_reason',
  ],
  'guest_consultation_requests' => const [
    'reference_number',
    'first_name',
    'last_name',
    'birth_date',
    'sex',
    'mobile_number',
    'email',
    'address',
    'symptoms',
    'symptom_duration',
    'consultation_reason',
    'preferred_consultation_type',
    'preferred_schedule',
    'request_status',
    'identity_review_status',
    'rejection_reason',
  ],
  'online_consultation_requests' => const [
    'reference_number',
    'profile_first_name',
    'profile_last_name',
    'phone_number_snapshot',
    'medical_concern',
    'symptom_duration',
    'preferred_schedule',
    'proposed_schedule',
    'confirmed_schedule',
    'consultation_channel',
    'request_status',
    'additional_information_request',
    'rejection_reason',
    'cancellation_reason',
  ],
  'notifications' => const [
    'notification_type',
    'title',
    'message',
    'is_read',
    'created_at',
  ],
  'prescriptions' => const [
    'originating_hospital',
    'hospital_name',
    'diagnosis_reason',
    'medication_name',
    'medication_form_strength',
    'route',
    'exact_dose',
    'dosage',
    'frequency',
    'duration',
    'quantity_to_dispense',
    'refills',
    'start_date',
    'end_date',
    'is_prn',
    'prn_reason',
    'maximum_daily_dose',
    'instructions',
    'prescriber_name',
    'prescriber_specialization',
    'prescriber_license_number',
    'electronically_signed_at',
    'created_at',
  ],
  'laboratory_results' => const [
    'originating_hospital',
    'hospital_name',
    'facility',
    'test_name',
    'verification_status',
    'ai_summary',
    'professional_interpretation',
    'rejection_reason',
    'uploaded_at',
    'reviewed_at',
  ],
  'laboratory_requests' => const [
    'originating_hospital',
    'hospital_name',
    'test_name',
    'priority',
    'status',
    'instructions',
    'requested_at',
    'due_at',
    'completed_at',
  ],
  'medical_documents' => const [
    'originating_hospital',
    'hospital_name',
    'facility',
    'title',
    'document_type',
    'ai_analysis_status',
    'ai_summary',
    'ai_analysis_error',
    'ai_analyzed_at',
    'mime_type',
    'size_bytes',
    'created_at',
  ],
  'medical_records' => const [
    'originating_hospital',
    'hospital_name',
    'title',
    'record_type',
    'description',
    'doctor_display_name',
    'reason_for_visit',
    'confirmed_diagnosis',
    'treatment_plan',
    'current_symptoms',
    'known_medical_conditions',
    'allergies',
    'current_medications',
    'relevant_medical_history',
    'previous_surgeries',
    'smoking_status',
    'alcohol_use',
    'pregnancy_status',
    'height_cm',
    'weight_kg',
    'bmi',
    'blood_pressure_systolic',
    'blood_pressure_diastolic',
    'body_temperature_c',
    'heart_rate_bpm',
    'respiratory_rate_bpm',
    'oxygen_saturation_percent',
    'vitals_recorded_at',
    'doctor_notes',
    'record_date',
    'created_at',
  ],
  'doctor_schedules' => const [
    'day_of_week',
    'starts_at',
    'ends_at',
    'consultation_type',
    'slot_minutes',
    'is_active',
  ],
  'doctor_patient_assignments' => const [
    'patient_name',
    'patient_number',
    'birth_date',
    'sex',
    'mobile_number',
    'email',
    'address',
    'blood_type',
    'allergies',
    'existing_conditions',
    'identity_verification_status',
    'profile_status',
    'latest_vitals_summary',
    'latest_height_cm',
    'latest_weight_kg',
    'latest_bmi',
    'latest_blood_pressure_systolic',
    'latest_blood_pressure_diastolic',
    'latest_body_temperature_c',
    'latest_heart_rate_bpm',
    'latest_respiratory_rate_bpm',
    'latest_oxygen_saturation_percent',
    'latest_vitals_recorded_at',
    'latest_recorded_by',
    'assignment_type',
    'notes',
    'assigned_at',
    'ended_at',
  ],
  'patients' => const [
    'patient_number',
    'blood_type',
    'emergency_contact',
    'allergies',
    'existing_conditions',
    'identity_verification_status',
    'profile_status',
  ],
  'doctors' => const [
    'display_name',
    'specialization',
    'license_number',
    'license_verification_status',
    'availability_status',
    'record_status',
  ],
  'hospital_beds' => const [
    'bed_type',
    'total_beds',
    'occupied_beds',
    'available_beds',
    'last_updated',
  ],
  'hospital_rooms' => const [
    'room_type',
    'total_rooms',
    'occupied_rooms',
    'available_rooms',
    'status',
    'last_updated',
  ],
  'emergency_room_status' => const [
    'status',
    'maximum_capacity',
    'occupied_beds',
    'closed_or_unstaffed_beds',
    'reserved_beds',
    'available_beds',
    'current_patient_count',
    'status_override',
    'override_reason',
    'capacity_source',
    'last_updated',
  ],
  'hospital_services' => const [
    'service_name',
    'description',
    'department_name',
    'availability_status',
    'delivery_modes',
    'created_at',
    'updated_at',
  ],
  'hospital_departments' => const [
    'department_name',
    'description',
    'availability_status',
    'created_at',
    'updated_at',
  ],
  'hospital_facility_status' => const [
    'facility_type',
    'status',
    'available_units',
    'notes',
    'last_updated',
  ],
  'hospitals' => const [
    'hospital_name',
    'classification_name',
    'verification_status',
    'operating_status',
    'address',
    'city',
    'province',
    'latitude',
    'longitude',
    'contact_number',
    'emergency_contact_number',
    'email',
    'description',
    'operating_hours',
    'image_url',
    'verification_notes',
    'verification_decided_at',
    'created_at',
    'updated_at',
  ],
  'users' => const [
    'first_name',
    'last_name',
    'email',
    'mobile_number',
    'birth_date',
    'sex',
    'address',
    'role_name',
    'hospital_name',
    'account_status',
    'status_reason',
    'display_name',
    'specialization',
    'license_number',
    'license_verification_status',
    'department_name',
    'availability_status',
    'consultation_fee',
    'biography',
    'last_login_at',
    'created_at',
    'updated_at',
  ],
  'role_permissions' => const [
    'role_name',
    'permission',
    'is_allowed',
    'created_at',
    'updated_at',
  ],
  'system_settings' => const ['key', 'value', 'description', 'updated_at'],
  'security_logs' => const [
    'event_type',
    'severity',
    'success',
    'details',
    'created_at',
  ],
  'audit_logs' => const [
    'action',
    'module',
    'entity_type',
    'entity_id',
    'description',
    'old_values',
    'new_values',
    'created_at',
  ],
  'maintenance_windows' => const [
    'title',
    'message',
    'starts_at',
    'ends_at',
    'is_active',
  ],
  _ => const <String>[],
};

String _detailLabel(String key) => switch (key) {
  'originating_hospital' => 'Originating Facility / Hospital',
  'chief_complaint' => 'Reason for Visit',
  'appointment_date' => 'Date & Time',
  'consultation_type' => 'Consultation Type',
  'doctor_display_name' => 'Doctor',
  'hospital_name' => 'Facility',
  'doctor_notes' => 'Clinical Notes',
  'confirmed_diagnosis' => 'Diagnosis / Assessment',
  'diagnosis_reason' => 'Diagnosis / Reason for Medication',
  'medication_form_strength' => 'Medication Form and Strength',
  'exact_dose' => 'Dose per Intake',
  'quantity_to_dispense' => 'Quantity to Dispense',
  'is_prn' => 'As Needed (PRN)',
  'prn_reason' => 'PRN Reason',
  'maximum_daily_dose' => 'Maximum Daily Dose',
  'prescriber_license_number' => 'Prescriber License Number',
  'electronically_signed_at' => 'Electronically Signed',
  'treatment_plan' => 'Follow-up',
  'ai_summary' => 'AI Summary',
  'ai_analysis_status' => 'AI Summary Status',
  'ai_analysis_error' => 'AI Summary Note',
  'ai_analyzed_at' => 'AI Summary Generated',
  'result_category' => 'Diagnostic Type',
  'test_procedure_name' => 'Test or Procedure',
  'performed_or_collected_date' => 'Performed or Collected',
  'result_date' => 'Result Issued',
  'patient_name_on_report' => 'Patient Name on Report',
  'procedure_details' => 'Type-specific Report Details',
  'test_procedure_name_ai_generated' => 'Procedure Name AI-generated',
  'performed_or_collected_date_text' => 'Procedure/Collection Date as Printed',
  'result_date_text' => 'Result Date as Printed',
  'result_details' => 'All Results and Measurements',
  'official_findings_impression' => 'Official Findings / Impression',
  'report_recommendations' => 'Report-stated Recommendations',
  'technical_summary' => 'Technical Summary',
  'patient_friendly_summary' => 'Patient-friendly Summary',
  'verification_notes' => 'Needs Verification',
  'findings_impression' => 'Findings and Impression',
  _ =>
    key
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' '),
};

String? _detailValue(Object? raw, [String? key]) {
  if (raw == null) return null;
  if (raw is bool) return raw ? 'Yes' : 'No';
  if (raw is Iterable) {
    final value = raw.map((entry) => entry.toString()).join(', ').trim();
    return value.isEmpty ? null : value;
  }
  final value = raw.toString().trim();
  if (value.isEmpty) return null;
  final date = DateTime.tryParse(value);
  if (key == 'consultation_type') {
    return _consultationTypeLabel(value);
  }
  if ({
    'status',
    'request_status',
    'verification_status',
    'identity_review_status',
    'license_verification_status',
    'account_status',
    'profile_status',
    'availability_status',
    'record_status',
    'record_type',
    'document_type',
    'notification_type',
    'assignment_type',
    'priority',
    'severity',
    'event_type',
  }.contains(key)) {
    return _humanizeEnum(value);
  }
  if (date == null || !_isDateField(key)) return value;
  if ({
    'birth_date',
    'record_date',
    'start_date',
    'end_date',
    'result_date',
    'performed_or_collected_date',
  }.contains(key)) {
    return DateFormat('MMMM d, y').format(date.toLocal());
  }
  return DateFormat('MMMM d, y · h:mm a').format(date.toLocal());
}

List<(String, String)> _medicalDocumentDetailEntries(
  Map<String, Object?> data,
) {
  final documentType = data['document_type']?.toString() ?? '';
  final rawExtracted = data['ai_extracted_data'];
  final extracted = rawExtracted is Map
      ? Map<String, Object?>.from(rawExtracted)
      : const <String, Object?>{};
  String? value(Map<String, Object?> source, String key) =>
      _detailValue(source[key], key);
  final entries = <(String, String)>[];

  void add(String label, String? fieldValue) {
    if (fieldValue != null) entries.add((label, fieldValue));
  }

  if (documentType == 'prescription') {
    add('Patient', value(extracted, 'patient_name'));
    add('Prescription date', value(extracted, 'document_date'));
    add('Prescriber', value(extracted, 'provider_name'));
    add('Medication and directions', value(extracted, 'medications'));
    add('Instructions', value(extracted, 'instructions'));
    add('Important note', value(extracted, 'limitations'));
    add('Summary', value(data, 'ai_summary'));
    add('Summary generated', value(data, 'ai_analyzed_at'));
    return entries;
  }

  if (documentType == 'diagnostic_result' || documentType == 'lab_result') {
    for (final key in const [
      'result_category',
      'test_procedure_name',
      'performed_or_collected_date',
      'result_date',
      'facility',
      'requesting_doctor',
      'patient_name_on_report',
      'procedure_details',
      'test_procedure_name_ai_generated',
      'performed_or_collected_date_text',
      'result_date_text',
      'result_details',
      'official_findings_impression',
      'report_recommendations',
      'technical_summary',
      'patient_friendly_summary',
      'verification_notes',
      'findings_impression',
      'notes',
    ]) {
      add(_detailLabel(key), value(data, key));
    }
    add('Reported findings', value(extracted, 'test_results'));
    add('Important note', value(extracted, 'limitations'));
    add('Summary', value(data, 'ai_summary'));
    add('Summary generated', value(data, 'ai_analyzed_at'));
    return entries;
  }

  for (final key in _detailKeys('medical_documents')) {
    if (key == 'ai_analysis_status' && data[key] == 'completed') continue;
    add(_detailLabel(key), value(data, key));
  }
  return entries;
}

String _consultationCountLabel(int count) =>
    '$count ${count == 1 ? 'consultation' : 'consultations'}';

String _consultationTitle(String title) {
  final value = title.trim();
  if (value.isEmpty) return 'Consultation';
  return value
      .split(RegExp(r'\s+'))
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String _consultationSummary(WorkspaceItem item) {
  final type = _firstText(item.data, const ['consultation_type']);
  final date =
      _formatConsultationDate(item.data['appointment_date']) ??
      (item.timestamp == null
          ? null
          : DateFormat('MMMM d, y · h:mm a').format(item.timestamp!.toLocal()));
  final parts = <String>[if (type != null) _consultationTypeLabel(type), ?date];
  return parts.isEmpty ? 'Consultation details unavailable' : parts.join(' · ');
}

String _consultationTypeLabel(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return 'Not provided';
  return switch (value.toLowerCase()) {
    'face_to_face' || 'in_person' || 'in-person' => 'Face-to-face',
    'online' || 'teleconsultation' || 'telemedicine' => 'Online',
    _ => _humanizeEnum(value),
  };
}

String? _formatConsultationDate(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  final date = DateTime.tryParse(value);
  return date == null
      ? null
      : DateFormat('MMMM d, y · h:mm a').format(date.toLocal());
}

String? _firstText(Map<String, Object?> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    if (value is Iterable) {
      final entries = value
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty && entry != 'null')
          .toList(growable: false);
      if (entries.isNotEmpty) return entries.join(', ');
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty && text != 'null' && text != '[]' && text != '{}') {
      return text;
    }
  }
  return null;
}

bool _isPastConsultation(WorkspaceItem item) {
  final status = item.status?.toLowerCase().trim() ?? '';
  return {
    'completed',
    'cancelled',
    'canceled',
    'rejected',
    'no_show',
    'no show',
    'patient_unreachable',
    'patient unreachable',
    'face_to_face_recommended',
    'face to face recommended',
  }.contains(status);
}

DateTime _consultationSortDate(WorkspaceItem item) =>
    DateTime.tryParse(item.data['appointment_date']?.toString() ?? '') ??
    item.timestamp ??
    DateTime.fromMillisecondsSinceEpoch(0);

int _compareUpcomingConsultations(WorkspaceItem a, WorkspaceItem b) =>
    _consultationSortDate(a).compareTo(_consultationSortDate(b));

int _comparePastConsultations(WorkspaceItem a, WorkspaceItem b) =>
    _consultationSortDate(b).compareTo(_consultationSortDate(a));

String? _consultationVitals(Map<String, Object?> data) {
  final values = <String>[
    if (data['blood_pressure_systolic'] != null &&
        data['blood_pressure_diastolic'] != null)
      'BP ${data['blood_pressure_systolic']}/${data['blood_pressure_diastolic']} mmHg',
    if (data['heart_rate_bpm'] != null) 'Pulse ${data['heart_rate_bpm']} bpm',
    if (data['oxygen_saturation_percent'] != null)
      'SpO₂ ${data['oxygen_saturation_percent']}%',
    if (data['body_temperature_c'] != null)
      'Temp ${data['body_temperature_c']} °C',
    if (data['bmi'] != null) 'BMI ${data['bmi']}',
  ];
  return values.isEmpty ? null : values.join(' · ');
}

bool _isDateField(String? key) =>
    key == 'birth_date' ||
    key == 'record_date' ||
    key == 'appointment_date' ||
    key == 'created_at' ||
    key == 'updated_at' ||
    key == 'last_updated' ||
    key == 'requested_at' ||
    key == 'uploaded_at' ||
    key == 'reviewed_at' ||
    key == 'ai_analyzed_at' ||
    key == 'electronically_signed_at' ||
    key == 'result_date' ||
    key == 'performed_or_collected_date' ||
    key == 'assigned_at' ||
    key == 'ended_at' ||
    key == 'vitals_recorded_at' ||
    key == 'last_login_at' ||
    key == 'verification_decided_at' ||
    key == 'preferred_schedule' ||
    key == 'scheduled_for' ||
    key == 'otp_verified_at' ||
    key == 'consent_at' ||
    key == 'starts_at' ||
    key == 'ends_at' ||
    key == 'due_at' ||
    key == 'completed_at';

String _humanizeEnum(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

class _LiveRecordRow extends StatelessWidget {
  const _LiveRecordRow({
    required this.item,
    required this.busy,
    this.onOpen,
    this.trailing,
  });

  final WorkspaceItem item;
  final bool busy;
  final VoidCallback? onOpen;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (item.kind == 'consultations') {
      return _ConsultationRecordRow(
        item: item,
        busy: busy,
        onOpen: onOpen,
        trailing: trailing,
      );
    }
    if (item.kind == 'doctor_schedules') {
      return _ScheduleRecordRow(item: item, busy: busy, trailing: trailing);
    }
    final status = item.status;
    final statusTag = status != null && status.isNotEmpty
        ? StatusTag(
            label: _statusLabel(status),
            icon: _statusIcon(status),
            color: _statusColor(status),
            height: 48,
          )
        : null;
    final rowAction = trailing != null
        ? busy
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : trailing!
        : item.kind == 'prescriptions' && onOpen != null
        ? TextButton(
            onPressed: busy ? null : onOpen,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined, size: 18),
                SizedBox(width: AppSpacing.x1),
                Text('View details'),
              ],
            ),
          )
        : onOpen != null
        ? const Icon(Icons.chevron_right)
        : null;
    return Semantics(
      button: onOpen != null,
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            final summary = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: item.isUnread
                        ? AppColors.selected
                        : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(
                    _iconFor(item.kind),
                    size: 20,
                    color: item.isUnread
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title.isEmpty ? 'Untitled record' : item.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (item.subtitle.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          item.subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (item.timestamp != null) ...[
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          DateFormat(
                            'MMM d, y · h:mm a',
                          ).format(item.timestamp!.toLocal()),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!compact && statusTag != null) ...[
                  const SizedBox(width: AppSpacing.x3),
                  statusTag,
                ],
                if (!compact && rowAction != null) ...[
                  const SizedBox(width: AppSpacing.x2),
                  rowAction,
                ],
              ],
            );
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summary,
                        if (statusTag != null || rowAction != null) ...[
                          const SizedBox(height: AppSpacing.x2),
                          Padding(
                            padding: const EdgeInsets.only(left: 50),
                            child: Wrap(
                              spacing: AppSpacing.x2,
                              runSpacing: AppSpacing.x2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [?statusTag, ?rowAction],
                            ),
                          ),
                        ],
                      ],
                    )
                  : summary,
            );
          },
        ),
      ),
    );
  }
}

class _ScheduleRecordRow extends StatelessWidget {
  const _ScheduleRecordRow({
    required this.item,
    required this.busy,
    this.trailing,
    this.showDay = true,
  });

  final WorkspaceItem item;
  final bool busy;
  final Widget? trailing;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final active = item.data['is_active'] == true;
    final reservedCount =
        int.tryParse(
          item.data['reserved_consultation_count']?.toString() ?? '',
        ) ??
        0;
    final consultationType = _humanizeEnum(
      item.data['consultation_type']?.toString() ??
          item.subtitle.split(' · ').last,
    );
    final startsAt = item.data['starts_at']?.toString() ?? '';
    final endsAt = item.data['ends_at']?.toString() ?? '';
    final time = startsAt.isNotEmpty && endsAt.isNotEmpty
        ? '$startsAt – $endsAt'
        : item.subtitle;
    final stateLabel = reservedCount > 0
        ? 'Reserved'
        : active
        ? 'Open'
        : 'Hidden';
    final stateColor = reservedCount > 0
        ? AppColors.information
        : active
        ? AppColors.success
        : AppColors.textMuted;
    final action = busy
        ? const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : trailing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final details = Row(
          children: [
            Icon(
              consultationType.toLowerCase().contains('online')
                  ? Icons.videocam_outlined
                  : Icons.local_hospital_outlined,
              size: 17,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.x1),
            Flexible(
              child: Text(
                consultationType,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
        final status = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: stateColor.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: stateColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                stateLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: stateColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDay) ...[
                          _ScheduleDayTile(day: item.title),
                          const SizedBox(width: AppSpacing.x3),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                time,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.x1),
                              details,
                            ],
                          ),
                        ),
                        status,
                      ],
                    ),
                    if (action != null) ...[
                      const SizedBox(height: AppSpacing.x2),
                      Padding(
                        padding: EdgeInsets.only(left: showDay ? 54 : 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: action,
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    if (showDay) ...[
                      _ScheduleDayTile(day: item.title),
                      const SizedBox(width: AppSpacing.x4),
                      Expanded(
                        flex: 2,
                        child: Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                    Expanded(
                      flex: 2,
                      child: Text(
                        time,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Expanded(flex: 2, child: details),
                    status,
                    if (action != null) ...[
                      const SizedBox(width: AppSpacing.x3),
                      action,
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _ScheduleWeekView extends StatelessWidget {
  const _ScheduleWeekView({
    required this.items,
    required this.busyItems,
    required this.actionsFor,
  });

  static const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  final List<WorkspaceItem> items;
  final Set<String> busyItems;
  final Widget? Function(WorkspaceItem item) actionsFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var dayIndex = 0; dayIndex < days.length; dayIndex++) ...[
          _ScheduleDayGroup(
            day: days[dayIndex],
            items: _itemsForDay(days[dayIndex]),
            busyItems: busyItems,
            actionsFor: actionsFor,
          ),
          if (dayIndex != days.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }

  List<WorkspaceItem> _itemsForDay(String day) {
    final matches = items
        .where(
          (item) =>
              item.title.trim().toLowerCase().startsWith(day.toLowerCase()),
        )
        .toList(growable: false);
    matches.sort(
      (left, right) => (left.data['starts_at']?.toString() ?? '').compareTo(
        right.data['starts_at']?.toString() ?? '',
      ),
    );
    return matches;
  }
}

class _ScheduleDayGroup extends StatelessWidget {
  const _ScheduleDayGroup({
    required this.day,
    required this.items,
    required this.busyItems,
    required this.actionsFor,
  });

  final String day;
  final List<WorkspaceItem> items;
  final Set<String> busyItems;
  final Widget? Function(WorkspaceItem item) actionsFor;

  @override
  Widget build(BuildContext context) {
    final hasSlots = items.isNotEmpty;
    final availableCount = items
        .where((item) => item.data['is_active'] == true)
        .length;
    final hasAvailability = availableCount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ScheduleDayTile(day: day),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      hasAvailability
                          ? '$availableCount ${availableCount == 1 ? 'time slot' : 'time slots'} open for reservation'
                          : hasSlots
                          ? 'No time slots open for reservation'
                          : 'No available time slots',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: hasAvailability
                            ? AppColors.success
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                hasAvailability
                    ? Icons.check_circle_outline
                    : Icons.remove_circle_outline,
                color: hasAvailability ? AppColors.success : AppColors.disabled,
                size: 21,
              ),
            ],
          ),
          if (hasSlots) ...[
            const SizedBox(height: AppSpacing.x2),
            Padding(
              padding: const EdgeInsets.only(left: 54),
              child: Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _ScheduleRecordRow(
                      item: items[index],
                      busy: busyItems.contains(items[index].id),
                      trailing: actionsFor(items[index]),
                      showDay: false,
                    ),
                    if (index != items.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleDayTile extends StatelessWidget {
  const _ScheduleDayTile({required this.day});

  final String day;

  @override
  Widget build(BuildContext context) {
    final shortDay = day.length >= 3 ? day.substring(0, 3).toUpperCase() : day;
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.selected,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(
        shortDay,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class _LiveLoadingState extends StatelessWidget {
  const _LiveLoadingState();

  @override
  Widget build(BuildContext context) => const DataState(
    icon: Icons.sync,
    title: 'Loading your workspace',
    message: 'Retrieving your current care information.',
    action: SizedBox.square(
      dimension: 28,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    ),
  );
}

class _LiveErrorState extends StatelessWidget {
  const _LiveErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DataState(
    icon: Icons.cloud_off_outlined,
    title: 'Workspace unavailable',
    message: message,
    action: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Try again'),
    ),
  );
}

IconData _iconFor(String kind) => switch (kind) {
  'consultations' => Icons.medical_information_outlined,
  'guest_consultation_requests' => Icons.person_add_alt_outlined,
  'online_consultation_requests' => Icons.fact_check_outlined,
  'notifications' => Icons.notifications_outlined,
  'prescriptions' => Icons.medication_outlined,
  'laboratory_results' || 'laboratory_requests' => Icons.science_outlined,
  'medical_documents' || 'medical_records' => Icons.folder_copy_outlined,
  'chat_conversations' => Icons.chat_bubble_outline,
  'doctor_schedules' => Icons.calendar_month_outlined,
  'doctor_patient_assignments' || 'patients' => Icons.people_outline,
  'doctors' || 'users' => Icons.badge_outlined,
  'hospital_beds' => Icons.bed_outlined,
  'hospital_rooms' => Icons.meeting_room_outlined,
  'emergency_room_status' => Icons.emergency_outlined,
  'hospitals' => Icons.local_hospital_outlined,
  'security_logs' => Icons.security_outlined,
  'audit_logs' => Icons.manage_search_outlined,
  'maintenance_windows' => Icons.build_outlined,
  _ => Icons.description_outlined,
};

Color _statusColor(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('reject') ||
      normalized.contains('fail') ||
      normalized.contains('suspend') ||
      normalized.contains('closed') ||
      normalized.contains('full')) {
    return AppColors.destructive;
  }
  if (normalized.contains('pending') ||
      normalized.contains('limited') ||
      normalized.contains('unread')) {
    return AppColors.warning;
  }
  if (normalized.contains('active') ||
      normalized.contains('verified') ||
      normalized.contains('available') ||
      normalized.contains('complete') ||
      normalized.contains('allowed')) {
    return AppColors.success;
  }
  return AppColors.information;
}

IconData _statusIcon(String status) {
  final color = _statusColor(status);
  if (color == AppColors.destructive) return Icons.error_outline;
  if (color == AppColors.warning) return Icons.schedule_outlined;
  if (color == AppColors.success) return Icons.check_circle_outline;
  return Icons.info_outline;
}

String _statusLabel(String value) => _humanizeEnum(value);

String _friendlyError(Object error) {
  return userFacingRepositoryError(error);
}

int _intValue(dynamic value) =>
    value is int ? value : int.tryParse('$value') ?? 0;
