import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:typed_data';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/auth/user_role.dart';
import '../../models/clinical_checkup.dart';
import '../../models/consultation_type.dart';
import '../../models/hospitals/hospital_models.dart';
import '../../providers/core_providers.dart';
import '../../providers/hospital_directory_provider.dart';
import '../../repositories/admin_repository.dart';
import '../../repositories/care_repository.dart';
import '../../repositories/consultation_repository.dart';
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
  });

  final UserRole role;
  final String? section;
  final String? itemId;
  final bool isTab;
  final bool showDetailHeader;

  @override
  ConsumerState<LiveWorkspaceView> createState() => _LiveWorkspaceViewState();
}

class _LiveWorkspaceViewState extends ConsumerState<LiveWorkspaceView> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _query = '';
  final Set<String> _busyItems = {};

  WorkspaceRequest get _request =>
      (role: widget.role, section: _dataSection, itemId: widget.itemId);

  String? get _dataSection =>
      widget.role == UserRole.patient && widget.section == 'medical-records'
      ? 'records'
      : widget.section;

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
        data: (items) => _buildSnapshot(
          WorkspaceSnapshot(
            title: 'Notifications',
            description: 'Live account and care updates for your account.',
            metrics: [
              WorkspaceMetric(
                label: 'Unread',
                value: '${items.where((item) => !item.isRead).length}',
              ),
            ],
            items: items
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
                    },
                  ),
                )
                .toList(growable: false),
            loadedAt: DateTime.now(),
          ),
        ),
      );
    }
    final snapshot = ref.watch(workspaceSnapshotProvider(_request));
    return snapshot.when(
      loading: () => const _LiveLoadingState(),
      error: (error, _) => _LiveErrorState(
        message: _friendlyError(error),
        onRetry: () => ref.invalidate(workspaceSnapshotProvider(_request)),
      ),
      data: widget.section == 'messages' && widget.itemId == null
          ? _buildMessagesInbox
          : _buildSnapshot,
    );
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
        maxWidth: 920,
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
                IconButton(
                  tooltip: 'Search conversations',
                  onPressed: _searchFocusNode.requestFocus,
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: 'Start a conversation',
                  onPressed: _startConversation,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x5),
            TextField(
              key: const Key('conversation-search'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                prefixIcon: const Icon(Icons.search),
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
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.panel),
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
                          const Divider(height: 1, indent: 80),
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
                title: isPatientConsultationsPage
                    ? 'Consultations'
                    : snapshot.title,
                description: isPatientConsultationsPage
                    ? 'View your past and upcoming consultations.'
                    : snapshot.description,
                actions: [
                  if (_patientUploadCategory != null && widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('medical-file-upload')
                          ? null
                          : _uploadContextualMedicalFile,
                      icon: _busyItems.contains('medical-file-upload')
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryForeground,
                              ),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(_patientUploadButtonLabel!),
                    ),
                  if (isPatientConsultationView && widget.itemId == null)
                    FilledButton.icon(
                      onPressed: _busyItems.contains('consultation-book')
                          ? null
                          : _bookConsultation,
                      icon: const Icon(Icons.event_available_outlined),
                      label: const Text('Book consultation'),
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
                      onPressed: () =>
                          ref.invalidate(workspaceSnapshotProvider(_request)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.x3),
            if (!isPatientConsultationView && snapshot.metrics.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x5),
              _MetricGrid(metrics: snapshot.metrics),
            ],
            const SizedBox(height: AppSpacing.x5),
            ContentPanel(
              title: isPatientConsultationView
                  ? null
                  : widget.itemId == null
                  ? 'Current records'
                  : 'Record detail',
              subtitle: isPatientConsultationView || snapshot.loadedAt == null
                  ? null
                  : 'Updated ${DateFormat('MMM d, y · h:mm a').format(snapshot.loadedAt!.toLocal())}',
              action: snapshot.items.length > 5 && widget.itemId == null
                  ? SizedBox(
                      width: 260,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: isPatientConsultationView
                              ? 'Search consultations'
                              : 'Search visible records',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                      ),
                    )
                  : null,
              child: items.isEmpty
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
                        for (var index = 0; index < items.length; index++) ...[
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
                              topActions: _buildPatientQuickActions(
                                items[index],
                              ),
                            ),
                          if (index != items.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
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
        Wrap(
          spacing: AppSpacing.x2,
          runSpacing: AppSpacing.x2,
          children: [
            FilledButton.icon(
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _bookAppointment(item),
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: const Text('Book Appointment'),
            ),
            FilledButton.icon(
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _messagePatient(item),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Message Patient'),
            ),
            FilledButton.icon(
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _recordPatientCheckup(item),
              icon: const Icon(Icons.folder_shared_outlined, size: 18),
              label: const Text('Add Record'),
            ),
            FilledButton.icon(
              onPressed: _busyItems.contains('prescription-create')
                  ? null
                  : _createPrescription,
              icon: const Icon(Icons.medication_outlined, size: 18),
              label: const Text('Issue Prescription'),
            ),
            FilledButton.icon(
              onPressed: _busyItems.contains('laboratory-request-create')
                  ? null
                  : _createLaboratoryRequest,
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('Request Laboratory Test'),
            ),
          ],
        ),
      ],
    );
  }

  bool _canOpen(WorkspaceItem item) =>
      widget.section != null && widget.itemId == null && item.id != 'record';

  void _open(WorkspaceItem item) {
    final section = widget.section;
    if (section == null) return;
    context.go('${widget.role.homeLocation}/$section/${item.id}');
  }

  Widget? _actionsFor(WorkspaceItem item) {
    if (item.kind == 'notifications' && item.isUnread) {
      return TextButton(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _markNotificationRead(item),
        child: const Text('Mark read'),
      );
    }
    if (item.kind == 'medical_documents') {
      return TextButton.icon(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _downloadFile(item),
        icon: const Icon(Icons.download_outlined, size: 18),
        label: const Text('Download'),
      );
    }
    if (item.kind == 'consultations') {
      return _consultationActions(item);
    }
    if (widget.role == UserRole.doctor &&
        widget.section == 'patients' &&
        item.kind == 'doctor_patient_assignments') {
      return FilledButton.icon(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _recordPatientCheckup(item),
        icon: const Icon(Icons.monitor_heart_outlined, size: 18),
        label: const Text('Record checkup'),
      );
    }
    if (item.kind == 'guest_consultation_requests' &&
        {'otp_verified', 'pending_doctor_review'}.contains(item.status)) {
      final assignedDoctor = item.data['assigned_doctor_id']?.toString();
      final canApprove =
          widget.role == UserRole.doctor ||
          (assignedDoctor != null && assignedDoctor.isNotEmpty);
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
            message: canApprove
                ? 'Approve and schedule request'
                : 'Assign a doctor before approval',
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
    if (item.kind == 'users' &&
        {'accounts', 'staff'}.contains(widget.section)) {
      return PopupMenuButton<String>(
        tooltip: 'Change account status',
        enabled: !_busyItems.contains(item.id),
        onSelected: (status) => _updateAccountStatus(item, status),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'active', child: Text('Mark active')),
          PopupMenuItem(value: 'inactive', child: Text('Mark inactive')),
          PopupMenuItem(value: 'suspended', child: Text('Suspend account')),
        ],
      );
    }
    if (item.kind == 'doctor_schedules') {
      final active = item.data['is_active'] == true;
      final bookedCount =
          int.tryParse(
            item.data['booked_consultation_count']?.toString() ?? '',
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
          if (bookedCount == 0)
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
                  '$bookedCount appointment${bookedCount == 1 ? '' : 's'} use this availability; deletion is protected.',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Booked'),
              ),
            ),
        ],
      );
    }
    if ({'hospital_beds', 'hospital_rooms'}.contains(item.kind)) {
      return TextButton.icon(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _editCapacity(item),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit'),
      );
    }
    if (widget.role == UserRole.doctor &&
        {
          'prescriptions',
          'laboratory_results',
          'medical_records',
          'laboratory_requests',
        }.contains(item.kind)) {
      return IconButton(
        tooltip: 'Delete record',
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _deleteCareRecord(item),
        icon: const Icon(Icons.delete_outline),
      );
    }
    if ({
      'hospital_services',
      'hospital_departments',
      'hospital_facility_status',
      'emergency_room_status',
    }.contains(item.kind)) {
      final statuses = item.kind == 'emergency_room_status'
          ? const ['available', 'limited', 'full', 'temporarily_closed']
          : const ['available', 'limited', 'unavailable'];
      final statusMenu = PopupMenuButton<String>(
        tooltip: 'Update availability',
        enabled: !_busyItems.contains(item.id),
        onSelected: (status) => _updateOperationalStatus(item, status),
        itemBuilder: (context) => [
          for (final status in statuses)
            PopupMenuItem(value: status, child: Text(_statusLabel(status))),
        ],
      );
      if ({'hospital_services', 'hospital_departments'}.contains(item.kind)) {
        return Wrap(
          spacing: AppSpacing.x1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            statusMenu,
            IconButton(
              tooltip: 'Delete record',
              onPressed: _busyItems.contains(item.id)
                  ? null
                  : () => _deleteManagedRecord(item),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        );
      }
      return statusMenu;
    }
    if (item.kind == 'role_permissions') {
      final allowed = item.data['is_allowed'] == true;
      return TextButton(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _updatePermission(item, !allowed),
        child: Text(allowed ? 'Deny' : 'Allow'),
      );
    }
    if (item.kind == 'system_settings') {
      return TextButton.icon(
        onPressed: _busyItems.contains(item.id)
            ? null
            : () => _editSystemSetting(item),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit'),
      );
    }
    if (item.kind == 'maintenance_windows') {
      final active = item.data['is_active'] == true;
      return Wrap(
        spacing: AppSpacing.x1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _setMaintenanceActive(item, !active),
            child: Text(active ? 'Deactivate' : 'Activate'),
          ),
          IconButton(
            tooltip: 'Delete maintenance window',
            onPressed: _busyItems.contains(item.id)
                ? null
                : () => _deleteManagedRecord(item),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
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
      await repository.markNotificationRead(item.id);
      ref.invalidate(careNotificationsProvider);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Notification marked as read.');
    },
  );

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

  String? get _patientUploadCategory => widget.role != UserRole.patient
      ? null
      : switch (widget.section) {
          'labs' => 'lab_result',
          'prescriptions' => 'prescription',
          _ => null,
        };

  String? get _patientUploadButtonLabel => switch (_patientUploadCategory) {
    'lab_result' => 'Upload Lab Result',
    'prescription' => 'Upload Prescription',
    _ => null,
  };

  Future<void> _uploadContextualMedicalFile() async {
    final category = _patientUploadCategory;
    final buttonLabel = _patientUploadButtonLabel;
    if (category == null || buttonLabel == null) return;
    const acceptedTypes = XTypeGroup(
      label: 'Medical files',
      extensions: ['pdf', 'jpg', 'jpeg', 'png'],
      mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
    );
    final selected = await openFile(acceptedTypeGroups: const [acceptedTypes]);
    if (selected == null) return;
    final confirmed = await confirmRootAction(
      title: '$buttonLabel?',
      message:
          '“${selected.name}” will be stored securely and visible only to you and your care team.',
      confirmLabel: 'Upload securely',
    );
    if (!confirmed) return;
    await _runItemAction('medical-file-upload', () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final patientId = await repository.currentPatientId();
      final bytes = await selected.readAsBytes();
      await repository.uploadMedicalFile(
        patientId: patientId,
        fileName: selected.name,
        title: selected.name,
        documentType: category,
        bytes: bytes,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage(
        category == 'lab_result'
            ? 'Lab result uploaded securely.'
            : 'Prescription uploaded securely.',
      );
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

  Future<void> _createPrescription() => _runItemAction(
    'prescription-create',
    () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final relationships = await repository.listClinicalRelationships();
      if (relationships.isEmpty) {
        throw StateError(
          'No assigned patient consultation is available for prescribing.',
        );
      }
      final draft = await showRootDialog<_PrescriptionDraft>(
        barrierDismissible: false,
        builder: (context) => _PrescriptionDialog(relationships: relationships),
      );
      if (draft == null) return;
      await repository.createPrescription(
        relationship: draft.relationship,
        medicationName: draft.medicationName,
        dosage: draft.dosage,
        frequency: draft.frequency,
        duration: draft.duration,
        instructions: draft.instructions,
        attachment: draft.attachment,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Prescription issued to the selected patient.');
    },
  );

  Future<void> _createLaboratoryRequest() => _runItemAction(
    'laboratory-request-create',
    () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      final relationships = await repository.listClinicalRelationships();
      if (relationships.isEmpty) {
        throw StateError(
          'No assigned patient consultation is available for a laboratory request.',
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

  Future<void> _bookConsultation() => _runItemAction(
    'consultation-book',
    () async {
      await ref.read(hospitalDirectoryProvider.notifier).refresh();
      final directory = ref.read(hospitalDirectoryProvider);
      if (directory.errorMessage != null) {
        throw StateError(directory.errorMessage!);
      }
      final clinicians = <DoctorDirectoryEntry>[
        for (final hospital in directory.entries)
          for (final doctor in hospital.doctors)
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
          'No clinician with published availability is available for booking.',
        );
      }
      final draft = await showRootDialog<_BookingDraft>(
        barrierDismissible: false,
        builder: (context) => _BookingDialog(clinicians: clinicians),
      );
      if (draft == null) return;
      final appointmentDate = await requestRootDateTime(
        initial: draft.clinician.doctor.nextAvailableAt,
      );
      if (appointmentDate == null) return;
      final repository = ref.read(consultationRepositoryProvider);
      if (repository == null) {
        throw StateError('Consultation service is unavailable.');
      }
      await repository.bookConsultation(
        doctorId: draft.clinician.doctor.id,
        hospitalId: draft.clinician.hospitalId,
        consultationType: draft.consultationType,
        appointmentDate: appointmentDate,
        chiefComplaint: draft.chiefComplaint,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Consultation request booked and pending approval.');
    },
  );

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
    final selected = await requestRootDateTime(
      initial:
          current?.toLocal() ?? DateTime.now().add(const Duration(days: 1)),
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
      final draft =
          await showRootDialog<
            ({
              ClinicalCheckupDraft checkup,
              ({List<int> bytes, String name})? attachment,
            })
          >(
            barrierDismissible: false,
            builder: (context) => _PatientCheckupDialog(patient: item.data),
          );
      if (draft == null) return;
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.recordPatientCheckup(
        patientId: patientId,
        checkup: draft.checkup,
        attachment: draft.attachment,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Patient checkup recorded.');
    });
  }

  Future<void> _bookAppointment(WorkspaceItem item) async {
    await _runItemAction(item.id, () async {
      final patientId = item.data['patient_id']?.toString() ?? '';
      if (patientId.isEmpty) {
        throw StateError('The selected patient is missing a clinical link.');
      }
      final draft =
          await showRootDialog<
            ({
              DateTime date,
              String type,
              String complaint,
              ({List<int> bytes, String name})? attachment,
            })
          >(
            barrierDismissible: false,
            builder: (context) => _BookAppointmentDialog(patient: item.data),
          );
      if (draft == null) return;
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.bookAppointment(
        patientId: patientId,
        appointmentDate: draft.date,
        consultationType: draft.type,
        chiefComplaint: draft.complaint,
        attachment: draft.attachment,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Appointment booked.');
    });
  }

  Future<void> _messagePatient(WorkspaceItem item) async {
    await _runItemAction(item.id, () async {
      final patientId = item.data['patient_id']?.toString() ?? '';
      final conversationId = item.data['conversation_id']?.toString();
      if (patientId.isEmpty ||
          conversationId == null ||
          conversationId.isEmpty) {
        showRootMessage('Patient has not set up a messaging conversation yet.');
        return;
      }
      final draft =
          await showRootDialog<
            ({String message, ({List<int> bytes, String name})? attachment})
          >(
            barrierDismissible: false,
            builder: (context) => _MessagePatientDialog(patient: item.data),
          );
      if (draft == null) return;
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.sendMessage(
        conversationId: conversationId,
        body: draft.message,
        patientId: patientId,
        attachment: draft.attachment,
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Message sent.');
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
    await _runItemAction(item.id, () async {
      final repository = ref.read(consultationRepositoryProvider);
      if (repository == null) {
        throw StateError('Consultation service is unavailable.');
      }
      await repository.reviewGuestRequest(
        requestId: item.id,
        decision: approve ? 'approved' : 'rejected',
        doctorId: widget.role == UserRole.hospitalAdministrator
            ? item.data['assigned_doctor_id']?.toString()
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

  Future<void> _updateOperationalStatus(
    WorkspaceItem item,
    String status,
  ) async {
    final confirmed = await confirmRootAction(
      title: 'Update operational status?',
      message:
          'This publishes ${_statusLabel(status)} for ${item.title} and may notify affected users.',
      confirmLabel: 'Update status',
      destructive: {
        'unavailable',
        'full',
        'temporarily_closed',
      }.contains(status),
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) throw StateError('Admin service is unavailable.');
      await repository.updateOperationalRecord(
        table: item.kind,
        recordId: item.id,
        changes: {
          item.kind == 'hospital_services' ||
                      item.kind == 'hospital_departments'
                  ? 'availability_status'
                  : 'status':
              status,
        },
      );
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Operational status updated.');
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
      showRootMessage('${item.title} capacity updated.');
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
      final draft = await showRootDialog<_DoctorAccountDraft>(
        barrierDismissible: false,
        builder: (context) => _DoctorAccountDialog(context: adminContext),
      );
      if (draft == null) return;
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
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Doctor account created for the assigned hospital.');
    },
  );

  Future<void> _createPatientAccount() => _runItemAction(
    'patient-account-create',
    () async {
      final draft = await showRootDialog<_PatientAccountDraft>(
        barrierDismissible: false,
        builder: (context) => const _PatientAccountDialog(),
      );
      if (draft == null) return;
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');

      if (draft.isExistingAccount) {
        await repository.linkExistingPatient(draft.email);
        ref.invalidate(workspaceSnapshotProvider(_request));
        showRootMessage(
          'Existing patient successfully linked to your account.',
        );
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
      if ({'hospital_services', 'hospital_departments'}.contains(item.kind)) {
        await ref.read(hospitalDirectoryProvider.notifier).refresh();
      }
      showRootMessage('Managed record deleted.');
    });
  }

  Future<void> _deleteCareRecord(WorkspaceItem item) async {
    final confirmed = await confirmRootAction(
      title: 'Delete ${item.title}?',
      message: 'This permanently removes the selected care record.',
      confirmLabel: 'Delete record',
      destructive: true,
    );
    if (!confirmed) return;
    await _runItemAction(item.id, () async {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.deleteCareRecord(table: item.kind, recordId: item.id);
      ref.invalidate(workspaceSnapshotProvider(_request));
      showRootMessage('Care record deleted.');
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Row(
            children: [
              _ConversationAvatar(name: item.title),
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
                    style: Theme.of(context).textTheme.bodySmall,
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
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.secondary,
      foregroundColor: AppColors.primary,
      child: Text(
        initials.isEmpty ? 'C' : initials,
        style: TextStyle(fontSize: size * .34, fontWeight: FontWeight.w700),
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
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
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
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final repository = ref.read(careRepositoryProvider);
      if (repository == null) throw StateError('Care service is unavailable.');
      await repository.sendMessage(
        conversationId: widget.conversationId,
        body: body,
      );
      _messageController.clear();
      _refreshConversationSnapshots();
    } catch (error) {
      showRootMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
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
    final identity = ref.watch(appIdentityProvider);
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
      color: AppColors.surface,
      child: Column(
        children: [
          Material(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Container(
                constraints: const BoxConstraints(minHeight: 68),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x2,
                  vertical: AppSpacing.x2,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to conversations',
                      onPressed: () =>
                          context.go('${widget.role.homeLocation}/messages'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    _ConversationAvatar(name: participantName, size: 42),
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
                          Text(
                            subtitle,
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
          ),
          Expanded(
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
              data: (items) => items.isEmpty
                  ? const Center(
                      child: DataState(
                        icon: Icons.forum_outlined,
                        title: 'No messages yet',
                        message: 'Send a message to start the conversation.',
                      ),
                    )
                  : ListView.separated(
                      key: const Key('conversation-message-list'),
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.x4,
                        AppSpacing.x6,
                        AppSpacing.x4,
                        AppSpacing.x6,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.x3),
                      itemBuilder: (context, index) {
                        final message = items[items.length - index - 1];
                        return _LiveMessageBubble(
                          message: message,
                          mine: message.senderId == identity.userId,
                        );
                      },
                    ),
            ),
          ),
          Material(
            color: AppColors.surface,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Add attachment',
                      onPressed: () => showRootMessage(
                        'Attachments can be added from the related care record.',
                      ),
                      icon: const Icon(Icons.add),
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
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.surfaceMuted,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.x4,
                            vertical: AppSpacing.x3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x2),
                    IconButton.filled(
                      tooltip: 'Send message',
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryForeground,
                              ),
                            )
                          : const Icon(Icons.send),
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

class _LiveMessageBubble extends StatelessWidget {
  const _LiveMessageBubble({required this.message, required this.mine});

  final CareMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${mine ? 'Your' : 'Care team'} message, ${message.message ?? 'Attachment'}',
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: AppSpacing.x3,
            ),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.panel),
              border: mine ? null : Border.all(color: AppColors.border),
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
                const SizedBox(height: AppSpacing.x1),
                Text(
                  DateFormat('MMM d · h:mm a').format(message.sentAt.toLocal()),
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
  final bool isExistingAccount;
}

enum _PatientRegistrationMode { newAccount, existingAccount }

class _PatientAccountDialog extends StatefulWidget {
  const _PatientAccountDialog();

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
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  DateTime? _birthDate;
  String? _sex;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
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
                      label: Text('New account'),
                      icon: Icon(Icons.person_add_alt_outlined),
                    ),
                    ButtonSegment(
                      value: _PatientRegistrationMode.existingAccount,
                      label: Text('Existing patient'),
                      icon: Icon(Icons.search),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (set) =>
                      setState(() => _mode = set.first),
                  showSelectedIcon: false,
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
                    'Search for a patient who already has a CareNavigator account.',
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Patient email address',
                      prefixIcon: Icon(Icons.email_outlined),
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
              final email = _emailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                showRootMessage('Please enter a valid email address.');
                return;
              }
              Navigator.of(context).pop(
                _PatientAccountDraft(email: email, isExistingAccount: true),
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
          child: const Text('Register patient'),
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
                if (widget.context.departments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x4),
                  DropdownButtonFormField<String?>(
                    initialValue: _departmentId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Department (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        child: Text('No department selected'),
                      ),
                      for (final department in widget.context.departments)
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
  });

  final String name;
  final String description;
  final String? departmentId;
}

class _NamedRecordDialog extends StatefulWidget {
  const _NamedRecordDialog({
    required this.title,
    required this.nameLabel,
    required this.confirmLabel,
    this.departments = const [],
  });

  final String title;
  final String nameLabel;
  final String confirmLabel;
  final List<HospitalDepartmentOption> departments;

  @override
  State<_NamedRecordDialog> createState() => _NamedRecordDialogState();
}

class _NamedRecordDialogState extends State<_NamedRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _departmentId;

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
            ),
          );
        },
        child: Text(widget.confirmLabel),
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
  const _MaintenanceCopyDialog();

  @override
  State<_MaintenanceCopyDialog> createState() => _MaintenanceCopyDialogState();
}

class _MaintenanceCopyDialogState extends State<_MaintenanceCopyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.build_outlined),
    title: const Text('Schedule maintenance'),
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
        child: const Text('Choose schedule'),
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
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.instructions,
    this.attachment,
  });

  final ClinicalRelationship relationship;
  final String medicationName;
  final String dosage;
  final String frequency;
  final String duration;
  final String instructions;
  final ({List<int> bytes, String name})? attachment;
}

class _BookingDraft {
  const _BookingDraft({
    required this.clinician,
    required this.consultationType,
    required this.chiefComplaint,
  });

  final DoctorDirectoryEntry clinician;
  final String consultationType;
  final String chiefComplaint;
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
  const _PatientCheckupDialog({required this.patient});

  final Map<String, Object?> patient;

  @override
  State<_PatientCheckupDialog> createState() => _PatientCheckupDialogState();
}

class _PatientCheckupDialogState extends State<_PatientCheckupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = _CheckupFormControllers();
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
    _controllers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.monitor_heart_outlined),
    title: const Text('Record patient checkup'),
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
                title: 'Optional measurements and medical information',
                subtitle:
                    'Record only what is clinically needed. This creates a new history entry and does not change patient identity details.',
              ),
              const SizedBox(height: AppSpacing.x3),
              _ClinicalCheckupFields(
                controllers: _controllers,
                showReasonForVisit: true,
                onChanged: () => setState(() {}),
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
          ).pop((checkup: checkup, attachment: _attachment));
        },
        child: const Text('Save checkup'),
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
    this.onChanged,
  });

  final _CheckupFormControllers controllers;
  final bool showReasonForVisit;
  final bool reasonReadOnly;
  final bool showDoctorNotes;
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
  const _CheckupWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
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

class _BookingDialog extends StatefulWidget {
  const _BookingDialog({required this.clinicians});

  final List<DoctorDirectoryEntry> clinicians;

  @override
  State<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<_BookingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _complaintController = TextEditingController();
  late DoctorDirectoryEntry _clinician = widget.clinicians.first;
  late String _consultationType =
      _clinician.doctor.publishedConsultationTypes.first;

  @override
  void dispose() {
    _complaintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = _clinician.doctor.publishedConsultationTypes;
    return AlertDialog(
      icon: const Icon(Icons.event_available_outlined),
      title: const Text('Book consultation'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<DoctorDirectoryEntry>(
                  initialValue: _clinician,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Clinician'),
                  items: [
                    for (final entry in widget.clinicians)
                      DropdownMenuItem(
                        value: entry,
                        child: Text(
                          '${entry.doctor.displayLabel} — ${entry.doctor.specialtyLabel}, ${entry.hospitalName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _clinician = value;
                      _consultationType =
                          value.doctor.publishedConsultationTypes.first;
                    });
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
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _consultationType = value);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.x4),
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
                  validator: (value) => (value?.trim().length ?? 0) < 5
                      ? 'Describe the concern in at least 5 characters.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  'Next, choose a date and time. The server will accept only an unoccupied slot inside this clinician’s published schedule.',
                  style: Theme.of(context).textTheme.bodySmall,
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
              _BookingDraft(
                clinician: _clinician,
                consultationType: _consultationType,
                chiefComplaint: _complaintController.text.trim(),
              ),
            );
          },
          child: const Text('Choose schedule'),
        ),
      ],
    );
  }
}

class _PrescriptionDialog extends StatefulWidget {
  const _PrescriptionDialog({required this.relationships});

  final List<ClinicalRelationship> relationships;

  @override
  State<_PrescriptionDialog> createState() => _PrescriptionDialogState();
}

class _PrescriptionDialogState extends State<_PrescriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _medicationController = TextEditingController();
  final _dosageController = TextEditingController();
  final _frequencyController = TextEditingController();
  final _durationController = TextEditingController();
  final _instructionsController = TextEditingController();
  late ClinicalRelationship _relationship = widget.relationships.first;
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
    _medicationController.dispose();
    _dosageController.dispose();
    _frequencyController.dispose();
    _durationController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.medication_outlined),
      title: const Text('Issue prescription'),
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
                  controller: _medicationController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Medication name',
                  ),
                  validator: _requiredClinicalValue,
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _dosageController,
                  decoration: const InputDecoration(
                    labelText: 'Dosage',
                    hintText: 'Example: 500 mg',
                  ),
                  validator: _requiredClinicalValue,
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _frequencyController,
                  decoration: const InputDecoration(
                    labelText: 'Frequency',
                    hintText: 'Example: Every 8 hours',
                  ),
                  validator: _requiredClinicalValue,
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _durationController,
                  decoration: const InputDecoration(
                    labelText: 'Duration',
                    hintText: 'Example: 7 days',
                  ),
                  validator: _requiredClinicalValue,
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _instructionsController,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Instructions (optional)',
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
              _PrescriptionDraft(
                relationship: _relationship,
                medicationName: _medicationController.text.trim(),
                dosage: _dosageController.text.trim(),
                frequency: _frequencyController.text.trim(),
                duration: _durationController.text.trim(),
                instructions: _instructionsController.text.trim(),
                attachment: _attachment,
              ),
            );
          },
          child: const Text('Issue prescription'),
        ),
      ],
    );
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
    return DropdownButtonFormField<ClinicalRelationship>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Patient consultation'),
      items: [
        for (final relationship in relationships)
          DropdownMenuItem(
            value: relationship,
            child: Text(
              '${relationship.patientLabel} — ${relationship.consultationLabel}',
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
    final entries = <(String, String)>[
      for (final key in _detailKeys(item.kind))
        if (_detailValue(item.data[key], key) case final value?)
          (_detailLabel(key), value),
    ];
    if (entries.isEmpty && topActions == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topActions != null) ...[
          topActions!,
          const SizedBox(height: AppSpacing.x6),
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
      ],
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
    final facility =
        _firstText(data, const ['hospital_name', 'facility_name']) ??
        'Not listed';
    final doctorName =
        _firstText(data, const ['doctor_display_name', 'doctor_name']) ??
        'Not assigned';
    final overview = <_ConsultationField>[
      _ConsultationField('Facility', facility),
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
              label: role == UserRole.patient ? 'Lab Results' : 'Laboratory',
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
    'preferred_schedule',
    'request_status',
    'identity_review_status',
    'rejection_reason',
  ],
  'notifications' => const [
    'notification_type',
    'title',
    'message',
    'is_read',
    'created_at',
  ],
  'prescriptions' => const [
    'medication_name',
    'dosage',
    'frequency',
    'duration',
    'instructions',
    'created_at',
  ],
  'laboratory_results' => const [
    'test_name',
    'verification_status',
    'ai_summary',
    'professional_interpretation',
    'rejection_reason',
    'uploaded_at',
    'reviewed_at',
  ],
  'laboratory_requests' => const [
    'test_name',
    'priority',
    'status',
    'instructions',
    'requested_at',
    'due_at',
    'completed_at',
  ],
  'medical_documents' => const [
    'title',
    'document_type',
    'mime_type',
    'size_bytes',
    'created_at',
  ],
  'medical_records' => const [
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
    'current_patient_count',
    'available_beds',
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
  'chief_complaint' => 'Reason for Visit',
  'appointment_date' => 'Date & Time',
  'consultation_type' => 'Consultation Type',
  'doctor_display_name' => 'Doctor',
  'hospital_name' => 'Facility',
  'doctor_notes' => 'Clinical Notes',
  'confirmed_diagnosis' => 'Diagnosis / Assessment',
  'treatment_plan' => 'Follow-up',
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
  if (key == 'birth_date' || key == 'record_date') {
    return DateFormat('MMMM d, y').format(date.toLocal());
  }
  return DateFormat('MMMM d, y · h:mm a').format(date.toLocal());
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
    final status = item.status;
    return Semantics(
      button: onOpen != null,
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
          child: Row(
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
              if (status != null && status.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.x3),
                StatusTag(
                  label: _statusLabel(status),
                  icon: _statusIcon(status),
                  color: _statusColor(status),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.x3),
                if (busy)
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  trailing!,
              ] else if (onOpen != null) ...[
                const SizedBox(width: AppSpacing.x2),
                const Icon(Icons.chevron_right),
              ],
            ],
          ),
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

class _BookAppointmentDialog extends StatefulWidget {
  const _BookAppointmentDialog({required this.patient});

  final Map<String, Object?> patient;

  @override
  State<_BookAppointmentDialog> createState() => _BookAppointmentDialogState();
}

class _BookAppointmentDialogState extends State<_BookAppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _complaintController = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  String _type = 'online';
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
    _complaintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.calendar_month_outlined),
      title: const Text('Book appointment'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Consultation type',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'online',
                      child: Text('Online consultation'),
                    ),
                    DropdownMenuItem(
                      value: ConsultationType.faceToFace,
                      child: Text('In-person visit'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _type = value ?? 'online'),
                ),
                const SizedBox(height: AppSpacing.x4),
                TextFormField(
                  controller: _complaintController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Chief complaint',
                  ),
                  validator: _requiredClinicalValue,
                ),
                const SizedBox(height: AppSpacing.x4),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_date),
                    );
                    if (time == null || !mounted) return;
                    setState(() {
                      _date = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Appointment date',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      DateFormat.yMMMd().add_jm().format(_date),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
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
            Navigator.of(context).pop((
              date: _date,
              type: _type,
              complaint: _complaintController.text.trim(),
              attachment: _attachment,
            ));
          },
          child: const Text('Book'),
        ),
      ],
    );
  }
}

class _MessagePatientDialog extends StatefulWidget {
  const _MessagePatientDialog({required this.patient});

  final Map<String, Object?> patient;

  @override
  State<_MessagePatientDialog> createState() => _MessagePatientDialogState();
}

class _MessagePatientDialogState extends State<_MessagePatientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
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
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.chat_bubble_outline),
      title: const Text('Message patient'),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _messageController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Message body',
                    alignLabelWithHint: true,
                  ),
                  validator: _requiredClinicalValue,
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
            Navigator.of(context).pop((
              message: _messageController.text.trim(),
              attachment: _attachment,
            ));
          },
          child: const Text('Send'),
        ),
      ],
    );
  }
}
