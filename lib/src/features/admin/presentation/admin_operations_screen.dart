import 'dart:convert';

import 'package:care_navigator_ph/src/models/user_profile.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/routing/role_routes.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/admin_desktop_only_screen.dart';
import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:care_navigator_ph/src/widgets/app_page_header.dart';
import 'package:care_navigator_ph/src/widgets/app_states.dart';
import 'package:care_navigator_ph/src/widgets/async_value_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

typedef JsonMap = Map<String, dynamic>;

class AdminOperationsScreen extends ConsumerWidget {
  const AdminOperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktopPortalAvailable = isDesktopAdminPortalAvailable(
      isWeb: kIsWeb,
      logicalWidth: MediaQuery.sizeOf(context).width,
    );
    ref.watch(authStateProvider);
    if (ref.read(supabaseClientProvider).auth.currentSession == null) {
      if (!desktopPortalAvailable) {
        return const AdminDesktopOnlyScreen();
      }
      return _AccessCard(
        onSignIn: () => context.go('/login?redirect=/admin/operations'),
      );
    }
    return AsyncValuePanel<UserProfile?>(
      value: ref.watch(currentProfileProvider),
      onRetry: () => ref.invalidate(currentProfileProvider),
      data: (profile) {
        if (profile == null ||
            profile.accountStatus != 'active' ||
            !{'super_admin', 'hospital_admin'}.contains(profile.role)) {
          return const _AccessCard();
        }
        if (!desktopPortalAvailable) {
          return AdminDesktopOnlyScreen(
            signOut: shouldSignOutBlockedAdministrator(isWeb: kIsWeb),
          );
        }
        return _OperationsBody(profile: profile);
      },
    );
  }
}

class _OperationsBody extends ConsumerStatefulWidget {
  const _OperationsBody({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_OperationsBody> createState() => _OperationsBodyState();
}

class _OperationsBodyState extends ConsumerState<_OperationsBody> {
  bool _loading = true;
  int _selectedModule = 0;
  Object? _error;
  JsonMap _analytics = const {};
  List<JsonMap> _announcements = const [];
  List<JsonMap> _audit = const [];
  List<JsonMap> _settings = const [];
  List<JsonMap> _aiConfigurations = const [];
  List<JsonMap> _rolePermissions = const [];
  List<JsonMap> _maintenanceWindows = const [];
  List<JsonMap> _securityLogs = const [];
  List<JsonMap> _roles = const [];
  List<JsonMap> _hospitalPatients = const [];
  List<JsonMap> _hospitalConsultations = const [];
  final Set<String> _busyActions = {};

  bool get _isSuper => widget.profile.role == 'super_admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (mounted && showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final client = ref.read(supabaseClientProvider);
      final results = await Future.wait<dynamic>([
        client.rpc(_isSuper ? 'platform_analytics' : 'hospital_analytics'),
        client
            .from('hospital_announcements')
            .select(
              'id, hospital_id, title, message, is_global, published_at, expires_at, created_at, hospitals(hospital_name)',
            )
            .order('published_at', ascending: false)
            .limit(100),
        client
            .from('audit_logs')
            .select(
              'id, action, module, record_id, metadata, ip_address, created_at, users(first_name, last_name), hospitals(hospital_name)',
            )
            .order('created_at', ascending: false)
            .limit(150),
        if (_isSuper)
          client
              .from('system_settings')
              .select('key, value, description, is_public, updated_at')
              .order('key')
        else
          Future<List<JsonMap>>.value(const []),
        if (_isSuper)
          client
              .from('ai_configurations')
              .select(
                'id, configuration_key, purpose, provider, model_name, prompt_template, configuration, is_active, created_at, updated_at',
              )
              .order('configuration_key')
        else
          Future<List<JsonMap>>.value(const []),
        if (_isSuper)
          client
              .from('role_permissions')
              .select(
                'id, role_id, permission, is_allowed, created_at, updated_at, roles(id, role_name)',
              )
              .order('role_id')
              .order('permission')
        else
          Future<List<JsonMap>>.value(const []),
        if (_isSuper)
          client
              .from('maintenance_windows')
              .select(
                'id, title, message, starts_at, ends_at, is_active, created_at, updated_at',
              )
              .order('starts_at', ascending: false)
        else
          Future<List<JsonMap>>.value(const []),
        if (_isSuper)
          client
              .from('security_logs')
              .select(
                'id, actor_auth_user_id, event_type, severity, success, ip_address, user_agent, metadata, created_at',
              )
              .order('created_at', ascending: false)
              .limit(200)
        else
          Future<List<JsonMap>>.value(const []),
        if (_isSuper)
          client.from('roles').select('id, role_name').order('id')
        else
          Future<List<JsonMap>>.value(const []),
        if (!_isSuper && widget.profile.hospitalId != null)
          client
              .from('patients')
              .select(
                'id, patient_number, identity_verification_status, account_activation_status, profile_status, converted_from_guest, created_at, users(first_name, last_name)',
              )
              .eq('primary_hospital_id', widget.profile.hospitalId!)
              .order('created_at', ascending: false)
              .limit(300)
        else
          Future<List<JsonMap>>.value(const []),
        if (!_isSuper && widget.profile.hospitalId != null)
          client
              .from('consultations')
              .select(
                'id, appointment_date, consultation_type, status, created_at, patients(patient_number, users(first_name, last_name)), guest_consultation_requests(reference_number, full_name), doctors(display_name, specialization)',
              )
              .eq('hospital_id', widget.profile.hospitalId!)
              .order('appointment_date', ascending: false)
              .limit(300)
        else
          Future<List<JsonMap>>.value(const []),
      ]);
      if (!mounted) return;
      final analyticsValue = results[0];
      setState(() {
        _analytics = analyticsValue is JsonMap
            ? analyticsValue
            : analyticsValue is List &&
                  analyticsValue.isNotEmpty &&
                  analyticsValue.first is JsonMap
            ? analyticsValue.first as JsonMap
            : const {};
        _announcements = (results[1] as List).whereType<JsonMap>().toList();
        _audit = (results[2] as List).whereType<JsonMap>().toList();
        _settings = (results[3] as List).whereType<JsonMap>().toList();
        _aiConfigurations = (results[4] as List).whereType<JsonMap>().toList();
        _rolePermissions = (results[5] as List).whereType<JsonMap>().toList();
        _maintenanceWindows = (results[6] as List)
            .whereType<JsonMap>()
            .toList();
        _securityLogs = (results[7] as List).whereType<JsonMap>().toList();
        _roles = (results[8] as List).whereType<JsonMap>().toList();
        _hospitalPatients = (results[9] as List).whereType<JsonMap>().toList();
        _hospitalConsultations = (results[10] as List)
            .whereType<JsonMap>()
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!showLoading) rethrow;
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveAnnouncement([JsonMap? initial]) async {
    final values = await _announcementDialog(context, initial);
    if (values == null) return;
    try {
      final client = ref.read(supabaseClientProvider);
      final payload = <String, dynamic>{
        ...values,
        'is_global': _isSuper,
        'hospital_id': _isSuper ? null : widget.profile.hospitalId,
        'created_by': widget.profile.id,
      };
      if (initial == null) {
        await client.from('hospital_announcements').insert(payload);
      } else {
        payload.remove('created_by');
        await client
            .from('hospital_announcements')
            .update(payload)
            .eq('id', initial['id']);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              initial == null
                  ? 'Announcement published.'
                  : 'Announcement updated.',
            ),
          ),
        );
      }
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteAnnouncement(JsonMap item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text('“${item['title']}” will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(supabaseClientProvider)
          .from('hospital_announcements')
          .delete()
          .eq('id', item['id']);
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editSetting(JsonMap item) async {
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(item['value']),
    );
    final value = await showDialog<dynamic>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${item['key']}'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 14,
            decoration: const InputDecoration(labelText: 'JSON value'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                Navigator.pop(context, jsonDecode(controller.text));
              } on FormatException {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter valid JSON.')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await ref
          .read(supabaseClientProvider)
          .from('system_settings')
          .update({'value': value, 'updated_by': widget.profile.id})
          .eq('key', item['key']);
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  bool _isBusy(String key) => _busyActions.contains(key);

  Future<void> _mutate({
    required String key,
    required Future<void> Function() operation,
    required String successMessage,
  }) async {
    if (_isBusy(key)) return;
    setState(() => _busyActions.add(key));
    try {
      await operation();
      await _load(showLoading: false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busyActions.remove(key));
    }
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _saveAiConfiguration([JsonMap? initial]) async {
    final values = await _aiConfigurationDialog(context, initial);
    if (values == null) return;
    final key = 'ai:${initial?['id'] ?? 'new'}';
    await _mutate(
      key: key,
      operation: () async {
        final payload = {...values, 'updated_by': widget.profile.id};
        final query = ref
            .read(supabaseClientProvider)
            .from('ai_configurations');
        if (initial == null) {
          await query.insert(payload);
        } else {
          await query.update(payload).eq('id', initial['id']);
        }
      },
      successMessage: initial == null
          ? 'AI configuration created.'
          : 'AI configuration updated.',
    );
  }

  Future<void> _deleteAiConfiguration(JsonMap item) async {
    if (!await _confirmDelete(
      title: 'Delete AI configuration?',
      message:
          'The configuration "${item['configuration_key']}" will be removed permanently.',
    )) {
      return;
    }
    await _mutate(
      key: 'ai:${item['id']}',
      operation: () async {
        await ref
            .read(supabaseClientProvider)
            .from('ai_configurations')
            .delete()
            .eq('id', item['id']);
      },
      successMessage: 'AI configuration deleted.',
    );
  }

  Future<void> _saveRolePermission([JsonMap? initial]) async {
    final values = await _rolePermissionDialog(context, _roles, initial);
    if (values == null) return;
    final key = 'permission:${initial?['id'] ?? 'new'}';
    await _mutate(
      key: key,
      operation: () async {
        final query = ref.read(supabaseClientProvider).from('role_permissions');
        if (initial == null) {
          await query.insert(values);
        } else {
          await query.update(values).eq('id', initial['id']);
        }
      },
      successMessage: initial == null
          ? 'Role permission created.'
          : 'Role permission updated.',
    );
  }

  Future<void> _deleteRolePermission(JsonMap item) async {
    if (!await _confirmDelete(
      title: 'Delete role permission?',
      message:
          'The permission "${item['permission']}" will be removed from ${_relation(item['roles'], 'role_name')}.',
    )) {
      return;
    }
    await _mutate(
      key: 'permission:${item['id']}',
      operation: () async {
        await ref
            .read(supabaseClientProvider)
            .from('role_permissions')
            .delete()
            .eq('id', item['id']);
      },
      successMessage: 'Role permission deleted.',
    );
  }

  Future<void> _saveMaintenanceWindow([JsonMap? initial]) async {
    final values = await _maintenanceWindowDialog(context, initial);
    if (values == null) return;
    final key = 'maintenance:${initial?['id'] ?? 'new'}';
    await _mutate(
      key: key,
      operation: () async {
        final query = ref
            .read(supabaseClientProvider)
            .from('maintenance_windows');
        if (initial == null) {
          await query.insert({...values, 'created_by': widget.profile.id});
        } else {
          await query.update(values).eq('id', initial['id']);
        }
      },
      successMessage: initial == null
          ? 'Maintenance window scheduled.'
          : 'Maintenance window updated.',
    );
  }

  Future<void> _deleteMaintenanceWindow(JsonMap item) async {
    if (!await _confirmDelete(
      title: 'Delete maintenance window?',
      message: '"${item['title']}" will be removed permanently.',
    )) {
      return;
    }
    await _mutate(
      key: 'maintenance:${item['id']}',
      operation: () async {
        await ref
            .read(supabaseClientProvider)
            .from('maintenance_windows')
            .delete()
            .eq('id', item['id']);
      },
      successMessage: 'Maintenance window deleted.',
    );
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
      return const AppLoadingState(label: 'Loading operations');
    }
    if (_error != null) {
      return AppStatePanel(
        kind: AppStateKind.error,
        icon: AppIcons.cloudOffRounded,
        title: 'Unable to load operations',
        message: _error.toString(),
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(AppIcons.refreshRounded),
          label: const Text('Try again'),
        ),
      );
    }
    final tabs = <Tab>[
      const Tab(icon: Icon(AppIcons.analyticsOutlined), text: 'Reports'),
      const Tab(icon: Icon(AppIcons.campaignOutlined), text: 'Announcements'),
      const Tab(icon: Icon(AppIcons.policyOutlined), text: 'Audit'),
      if (!_isSuper)
        const Tab(icon: Icon(AppIcons.peopleOutlineRounded), text: 'Patients'),
      if (!_isSuper)
        const Tab(
          icon: Icon(AppIcons.calendarMonthOutlined),
          text: 'Appointments',
        ),
      if (_isSuper)
        const Tab(icon: Icon(AppIcons.tuneRounded), text: 'Settings'),
      if (_isSuper)
        const Tab(icon: Icon(AppIcons.psychologyOutlined), text: 'AI controls'),
      if (_isSuper)
        const Tab(icon: Icon(AppIcons.keyOutlined), text: 'Permissions'),
      if (_isSuper)
        const Tab(icon: Icon(AppIcons.buildOutlined), text: 'Maintenance'),
      if (_isSuper)
        const Tab(icon: Icon(AppIcons.securityOutlined), text: 'Security'),
    ];
    final destinations = tabs
        .map(
          (tab) => AppModuleDestination(
            label: tab.text ?? 'Module',
            icon: (tab.icon as Icon?)?.icon ?? AppIcons.settingsOutlined,
          ),
        )
        .toList(growable: false);
    final bodies = <Widget>[
      _AnalyticsPanel(values: _analytics),
      _AnnouncementPanel(
        items: _announcements,
        onAdd: () => _saveAnnouncement(),
        onEdit: _saveAnnouncement,
        onDelete: _deleteAnnouncement,
      ),
      _AuditPanel(items: _audit),
      if (!_isSuper) _HospitalPatientsPanel(items: _hospitalPatients),
      if (!_isSuper) _HospitalConsultationsPanel(items: _hospitalConsultations),
      if (_isSuper) _SettingsPanel(items: _settings, onEdit: _editSetting),
      if (_isSuper)
        _AiConfigurationsPanel(
          items: _aiConfigurations,
          isBusy: (item) => _isBusy('ai:${item['id']}'),
          isCreating: _isBusy('ai:new'),
          onAdd: () => _saveAiConfiguration(),
          onEdit: _saveAiConfiguration,
          onDelete: _deleteAiConfiguration,
        ),
      if (_isSuper)
        _RolePermissionsPanel(
          items: _rolePermissions,
          isBusy: (item) => _isBusy('permission:${item['id']}'),
          isCreating: _isBusy('permission:new'),
          onAdd: () => _saveRolePermission(),
          onEdit: _saveRolePermission,
          onDelete: _deleteRolePermission,
        ),
      if (_isSuper)
        _MaintenancePanel(
          items: _maintenanceWindows,
          isBusy: (item) => _isBusy('maintenance:${item['id']}'),
          isCreating: _isBusy('maintenance:new'),
          onAdd: () => _saveMaintenanceWindow(),
          onEdit: _saveMaintenanceWindow,
          onDelete: _deleteMaintenanceWindow,
        ),
      if (_isSuper) _SecurityLogsPanel(items: _securityLogs),
    ];
    if (_selectedModule >= bodies.length) _selectedModule = 0;
    return SafeArea(
      child: Column(
        children: [
          AppPageHeader(
            eyebrow: 'AUDITED OPERATIONS CENTER',
            title: _isSuper
                ? 'Platform operating picture'
                : 'Hospital operating picture',
            subtitle:
                '${widget.profile.displayName} · ${widget.profile.roleLabel}',
            icon: AppIcons.monitorHeartRounded,
            onBack: () => context.go('/admin'),
            backTooltip: 'Back to administration',
            actions: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () => context.go('/notifications'),
                icon: const Icon(AppIcons.notificationsOutlined),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const Icon(AppIcons.refreshRounded),
              ),
            ],
          ),
          Expanded(
            child: AppModuleLayout(
              eyebrow: _isSuper ? 'PLATFORM OPERATIONS' : 'HOSPITAL OPERATIONS',
              title: _isSuper
                  ? 'Control, evidence, and resilience'
                  : 'Activity, patients, and capacity',
              summary:
                  '${_announcements.length} announcements · ${_audit.length} audit events',
              destinations: destinations,
              selectedIndex: _selectedModule,
              onSelected: (value) => setState(() => _selectedModule = value),
              child: bodies[_selectedModule],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsPanel extends StatelessWidget {
  const _AnalyticsPanel({required this.values});
  final JsonMap values;

  @override
  Widget build(BuildContext context) {
    final metrics = _flatten(values);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Current performance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        const Text('Counts are scoped by your role and hospital assignment.'),
        const SizedBox(height: 18),
        if (metrics.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text('No report data is available yet.'),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: metrics.entries
                  .map(
                    (entry) => SizedBox(
                      width: constraints.maxWidth >= 900
                          ? (constraints.maxWidth - 24) / 3
                          : constraints.maxWidth >= 560
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_label(entry.key)),
                              const SizedBox(height: 8),
                              Text(
                                _metricValue(entry.key, entry.value),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(color: AppColors.blue),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _AnnouncementPanel extends StatelessWidget {
  const _AnnouncementPanel({
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });
  final List<JsonMap> items;
  final VoidCallback onAdd;
  final ValueChanged<JsonMap> onEdit;
  final ValueChanged<JsonMap> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(AppIcons.addRounded),
          label: const Text('New announcement'),
        ),
      ),
      const SizedBox(height: 14),
      if (items.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Text('No announcements have been published.'),
          ),
        )
      else
        for (final item in items)
          Card(
            child: ListTile(
              title: Text(item['title']?.toString() ?? 'Announcement'),
              subtitle: Text(
                '${item['message'] ?? ''}\n${item['is_global'] == true ? 'Global' : _relation(item['hospitals'], 'hospital_name')} · ${_dateTime(item['published_at'])}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (value) =>
                    value == 'edit' ? onEdit(item) : onDelete(item),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ),
    ],
  );
}

class _AuditPanel extends StatelessWidget {
  const _AuditPanel({required this.items});
  final List<JsonMap> items;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('No authorized audit events are available.'))
      : ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              child: ExpansionTile(
                leading: const Icon(AppIcons.historyRounded),
                title: Text(
                  '${_label(item['action']?.toString() ?? '')} · ${_label(item['module']?.toString() ?? '')}',
                ),
                subtitle: Text(
                  '${_dateTime(item['created_at'])} · ${_relation(item['users'], 'first_name')} ${_relation(item['users'], 'last_name')}',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(item['metadata'] ?? const {}),
                    ),
                  ),
                ],
              ),
            );
          },
        );
}

class _HospitalPatientsPanel extends StatefulWidget {
  const _HospitalPatientsPanel({required this.items});

  final List<JsonMap> items;

  @override
  State<_HospitalPatientsPanel> createState() => _HospitalPatientsPanelState();
}

class _HospitalPatientsPanelState extends State<_HospitalPatientsPanel> {
  String _activationStatus = 'all';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final statuses =
        widget.items
            .map((item) => item['account_activation_status']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (_activationStatus != 'all' && !statuses.contains(_activationStatus)) {
      _activationStatus = 'all';
    }
    final query = _search.trim().toLowerCase();
    final filtered = widget.items.where((item) {
      if (_activationStatus != 'all' &&
          item['account_activation_status']?.toString() != _activationStatus) {
        return false;
      }
      if (query.isEmpty) return true;
      return '${_patientDisplayName(item)} ${item['patient_number'] ?? ''}'
          .toLowerCase()
          .contains(query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Hospital patients',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'Operational identity and account status only. Clinical information is not shown here.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Find patient',
                  prefixIcon: Icon(AppIcons.searchRounded),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: _activationStatus,
                decoration: const InputDecoration(
                  labelText: 'Activation status',
                ),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All')),
                  ...statuses.map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(_label(status)),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _activationStatus = value ?? 'all'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text('No patients are registered with this hospital.'),
            ),
          )
        else if (filtered.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text('No patients match the selected filters.'),
            ),
          )
        else
          for (final item in filtered)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(_initials(_patientDisplayName(item))),
                ),
                title: Text(_patientDisplayName(item)),
                subtitle: Text(
                  'Patient number: ${item['patient_number'] ?? 'Pending'}\n'
                  'Identity: ${_label(item['identity_verification_status']?.toString() ?? 'unknown')} - '
                  'Account: ${_label(item['account_activation_status']?.toString() ?? 'unknown')}\n'
                  'Profile: ${_label(item['profile_status']?.toString() ?? 'unknown')} - '
                  '${item['converted_from_guest'] == true ? 'Converted guest' : 'Registered patient'} - '
                  'Added ${_dateTime(item['created_at'])}',
                ),
                isThreeLine: true,
              ),
            ),
      ],
    );
  }
}

class _HospitalConsultationsPanel extends StatefulWidget {
  const _HospitalConsultationsPanel({required this.items});

  final List<JsonMap> items;

  @override
  State<_HospitalConsultationsPanel> createState() =>
      _HospitalConsultationsPanelState();
}

class _HospitalConsultationsPanelState
    extends State<_HospitalConsultationsPanel> {
  String _status = 'all';
  String _dateRange = 'all';

  @override
  Widget build(BuildContext context) {
    final statuses =
        widget.items
            .map((item) => item['status']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (_status != 'all' && !statuses.contains(_status)) _status = 'all';
    final now = DateTime.now();
    final filtered = widget.items.where((item) {
      if (_status != 'all' && item['status']?.toString() != _status) {
        return false;
      }
      final schedule = DateTime.tryParse(
        item['appointment_date']?.toString() ?? '',
      )?.toLocal();
      if (_dateRange == 'upcoming' &&
          (schedule == null || schedule.isBefore(now))) {
        return false;
      }
      if (_dateRange == 'past' &&
          (schedule == null || !schedule.isBefore(now))) {
        return false;
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Consultations and appointments',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'Hospital-scoped scheduling and assignment data. Clinical complaints and notes are excluded.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All')),
                  ...statuses.map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(_label(status)),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value ?? 'all'),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: _dateRange,
                decoration: const InputDecoration(labelText: 'Schedule'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All dates')),
                  DropdownMenuItem(value: 'upcoming', child: Text('Upcoming')),
                  DropdownMenuItem(value: 'past', child: Text('Past')),
                ],
                onChanged: (value) =>
                    setState(() => _dateRange = value ?? 'all'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text('No consultations are scheduled for this hospital.'),
            ),
          )
        else if (filtered.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text('No appointments match the selected filters.'),
            ),
          )
        else
          for (final item in filtered)
            Card(
              child: ListTile(
                leading: Icon(
                  item['consultation_type']?.toString() == 'online'
                      ? AppIcons.videocamOutlined
                      : AppIcons.localHospitalOutlined,
                  color: AppColors.blue,
                ),
                title: Text(_consultationPatientName(item)),
                subtitle: Text(
                  '${_dateTime(item['appointment_date'])} - '
                  '${_label(item['consultation_type']?.toString() ?? 'consultation')}\n'
                  'Doctor: ${_consultationDoctorName(item)}\n'
                  'Reference: ${_consultationReference(item)}',
                ),
                isThreeLine: true,
                trailing: Chip(
                  label: Text(_label(item['status']?.toString() ?? 'unknown')),
                ),
              ),
            ),
      ],
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.items, required this.onEdit});
  final List<JsonMap> items;
  final ValueChanged<JsonMap> onEdit;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('No platform settings are configured.'))
      : ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              child: ListTile(
                title: Text(item['key']?.toString() ?? ''),
                subtitle: Text(
                  '${item['description'] ?? ''}\n${jsonEncode(item['value'])}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Edit setting',
                  onPressed: () => onEdit(item),
                  icon: const Icon(AppIcons.editRounded),
                ),
              ),
            );
          },
        );
}

class _AiConfigurationsPanel extends StatelessWidget {
  const _AiConfigurationsPanel({
    required this.items,
    required this.isBusy,
    required this.isCreating,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<JsonMap> items;
  final bool Function(JsonMap) isBusy;
  final bool isCreating;
  final VoidCallback onAdd;
  final ValueChanged<JsonMap> onEdit;
  final ValueChanged<JsonMap> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _CrudHeader(
        title: 'AI configurations',
        description:
            'Control provider, model, prompt, and non-secret generation options.',
        buttonLabel: 'New configuration',
        isCreating: isCreating,
        onAdd: onAdd,
      ),
      const SizedBox(height: 14),
      if (items.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Text('No AI configurations are defined.'),
          ),
        )
      else
        for (final item in items)
          Card(
            child: ExpansionTile(
              leading: Icon(
                item['is_active'] == true
                    ? AppIcons.smartToyRounded
                    : AppIcons.pauseCircleOutlineRounded,
                color: item['is_active'] == true ? AppColors.blue : null,
              ),
              title: Text(item['configuration_key']?.toString() ?? ''),
              subtitle: Text(
                '${item['provider']} / ${item['model_name']} - ${item['is_active'] == true ? 'Active' : 'Inactive'}',
              ),
              trailing: _CrudMenu(
                busy: isBusy(item),
                onEdit: () => onEdit(item),
                onDelete: () => onDelete(item),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      '${item['purpose'] ?? ''}\n\nPrompt template\n${item['prompt_template'] ?? 'Not set'}\n\nConfiguration\n${const JsonEncoder.withIndent('  ').convert(item['configuration'] ?? const {})}',
                    ),
                  ),
                ),
              ],
            ),
          ),
    ],
  );
}

class _RolePermissionsPanel extends StatelessWidget {
  const _RolePermissionsPanel({
    required this.items,
    required this.isBusy,
    required this.isCreating,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<JsonMap> items;
  final bool Function(JsonMap) isBusy;
  final bool isCreating;
  final VoidCallback onAdd;
  final ValueChanged<JsonMap> onEdit;
  final ValueChanged<JsonMap> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _CrudHeader(
        title: 'Role permissions',
        description:
            'Define explicit capability flags for each application role.',
        buttonLabel: 'New permission',
        isCreating: isCreating,
        onAdd: onAdd,
      ),
      const SizedBox(height: 14),
      if (items.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Text('No role permissions are defined.'),
          ),
        )
      else
        for (final item in items)
          Card(
            child: ListTile(
              leading: Icon(
                item['is_allowed'] == true
                    ? AppIcons.checkCircleOutlineRounded
                    : AppIcons.blockRounded,
                color: item['is_allowed'] == true
                    ? Colors.green
                    : AppColors.danger,
              ),
              title: Text(item['permission']?.toString() ?? ''),
              subtitle: Text(
                '${_label(_relation(item['roles'], 'role_name'))} - ${item['is_allowed'] == true ? 'Allowed' : 'Denied'}',
              ),
              trailing: _CrudMenu(
                busy: isBusy(item),
                onEdit: () => onEdit(item),
                onDelete: () => onDelete(item),
              ),
            ),
          ),
    ],
  );
}

class _MaintenancePanel extends StatelessWidget {
  const _MaintenancePanel({
    required this.items,
    required this.isBusy,
    required this.isCreating,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<JsonMap> items;
  final bool Function(JsonMap) isBusy;
  final bool isCreating;
  final VoidCallback onAdd;
  final ValueChanged<JsonMap> onEdit;
  final ValueChanged<JsonMap> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _CrudHeader(
        title: 'Maintenance windows',
        description:
            'Schedule the notices shown during planned platform maintenance.',
        buttonLabel: 'Schedule maintenance',
        isCreating: isCreating,
        onAdd: onAdd,
      ),
      const SizedBox(height: 14),
      if (items.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Text('No maintenance windows are scheduled.'),
          ),
        )
      else
        for (final item in items)
          Card(
            child: ListTile(
              leading: Icon(
                item['is_active'] == true
                    ? AppIcons.buildCircleOutlined
                    : AppIcons.hideSourceRounded,
                color: item['is_active'] == true ? Colors.orange : null,
              ),
              title: Text(item['title']?.toString() ?? ''),
              subtitle: Text(
                '${item['message'] ?? ''}\n${_dateTime(item['starts_at'])} to ${_dateTime(item['ends_at'])} - ${item['is_active'] == true ? 'Enabled' : 'Disabled'}',
              ),
              isThreeLine: true,
              trailing: _CrudMenu(
                busy: isBusy(item),
                onEdit: () => onEdit(item),
                onDelete: () => onDelete(item),
              ),
            ),
          ),
    ],
  );
}

class _SecurityLogsPanel extends StatelessWidget {
  const _SecurityLogsPanel({required this.items});

  final List<JsonMap> items;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('No security events are available.'))
      : ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final severity = item['severity']?.toString() ?? 'info';
            return Card(
              child: ExpansionTile(
                leading: Icon(
                  severity == 'critical'
                      ? AppIcons.gppBadOutlined
                      : severity == 'warning'
                      ? AppIcons.warningAmberRounded
                      : AppIcons.shieldOutlined,
                  color: severity == 'critical'
                      ? AppColors.danger
                      : severity == 'warning'
                      ? Colors.orange
                      : AppColors.blue,
                ),
                title: Text(_label(item['event_type']?.toString() ?? 'event')),
                subtitle: Text(
                  '${_label(severity)} - ${item['success'] == true ? 'Succeeded' : 'Failed'} - ${_dateTime(item['created_at'])}',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        'Actor: ${item['actor_auth_user_id'] ?? 'System'}\nIP address: ${item['ip_address'] ?? 'Unknown'}\nUser agent: ${item['user_agent'] ?? 'Unknown'}\n\n${const JsonEncoder.withIndent('  ').convert(item['metadata'] ?? const {})}',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
}

class _CrudHeader extends StatelessWidget {
  const _CrudHeader({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.isCreating,
    required this.onAdd,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final bool isCreating;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 16,
    runSpacing: 12,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(description),
          ],
        ),
      ),
      FilledButton.icon(
        onPressed: isCreating ? null : onAdd,
        icon: isCreating
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(AppIcons.addRounded),
        label: Text(isCreating ? 'Saving...' : buttonLabel),
      ),
    ],
  );
}

class _CrudMenu extends StatelessWidget {
  const _CrudMenu({
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => busy
      ? const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      : PopupMenuButton<String>(
          tooltip: 'Manage item',
          onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        );
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({this.onSignIn});
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.lockOutlineRounded, size: 42),
            const SizedBox(height: 10),
            const Text('Administrator access required.'),
            if (onSignIn != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onSignIn, child: const Text('Sign in')),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<JsonMap?> _announcementDialog(
  BuildContext context, [
  JsonMap? initial,
]) async {
  final title = TextEditingController(
    text: initial?['title']?.toString() ?? '',
  );
  final message = TextEditingController(
    text: initial?['message']?.toString() ?? '',
  );
  DateTime? expires = DateTime.tryParse(
    initial?['expires_at']?.toString() ?? '',
  );
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(initial == null ? 'New announcement' : 'Edit announcement'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                maxLength: 180,
                decoration: const InputDecoration(labelText: 'Title *'),
              ),
              TextField(
                controller: message,
                minLines: 3,
                maxLines: 7,
                maxLength: 3000,
                decoration: const InputDecoration(labelText: 'Message *'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  expires == null
                      ? 'No expiry'
                      : 'Expires ${DateFormat.yMMMd().add_jm().format(expires!.toLocal())}',
                ),
                trailing: Wrap(
                  children: [
                    if (expires != null)
                      IconButton(
                        tooltip: 'Remove expiry',
                        onPressed: () => setDialogState(() => expires = null),
                        icon: const Icon(AppIcons.clearRounded),
                      ),
                    IconButton(
                      tooltip: 'Choose expiry',
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          initialDate:
                              expires ??
                              DateTime.now().add(const Duration(days: 7)),
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(
                            expires ?? DateTime.now(),
                          ),
                        );
                        if (time != null) {
                          setDialogState(
                            () => expires = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            ),
                          );
                        }
                      },
                      icon: const Icon(AppIcons.eventRounded),
                    ),
                  ],
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
              if (title.text.trim().isEmpty || message.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Title and message are required.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'title': title.text.trim(),
                'message': message.text.trim(),
                'published_at': DateTime.now().toUtc().toIso8601String(),
                'expires_at': expires?.toUtc().toIso8601String(),
              });
            },
            child: const Text('Publish'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  message.dispose();
  return result;
}

Future<JsonMap?> _aiConfigurationDialog(
  BuildContext context, [
  JsonMap? initial,
]) async {
  final configurationKey = TextEditingController(
    text: initial?['configuration_key']?.toString() ?? '',
  );
  final purpose = TextEditingController(
    text: initial?['purpose']?.toString() ?? '',
  );
  final provider = TextEditingController(
    text: initial?['provider']?.toString() ?? 'groq',
  );
  final model = TextEditingController(
    text: initial?['model_name']?.toString() ?? '',
  );
  final prompt = TextEditingController(
    text: initial?['prompt_template']?.toString() ?? '',
  );
  final configuration = TextEditingController(
    text: const JsonEncoder.withIndent(
      '  ',
    ).convert(initial?['configuration'] ?? const <String, dynamic>{}),
  );
  var isActive = initial?['is_active'] != false;
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          initial == null ? 'New AI configuration' : 'Edit AI configuration',
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: configurationKey,
                  enabled: initial == null,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Configuration key *',
                    helperText: 'Use a stable name such as symptom_analysis.',
                  ),
                ),
                TextField(
                  controller: purpose,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Purpose *'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: provider,
                        decoration: const InputDecoration(
                          labelText: 'Provider *',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: model,
                        decoration: const InputDecoration(
                          labelText: 'Model name *',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prompt,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Prompt template',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: configuration,
                  minLines: 4,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Configuration JSON object *',
                    helperText:
                        'Generation options only. Never store API keys or secrets here.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: isActive,
                  onChanged: (value) => setDialogState(() => isActive = value),
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
              if ([
                configurationKey.text,
                purpose.text,
                provider.text,
                model.text,
              ].any((value) => value.trim().isEmpty)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Complete all required fields.'),
                  ),
                );
                return;
              }
              try {
                final decoded = jsonDecode(configuration.text);
                if (decoded is! Map) {
                  throw const FormatException('JSON must be an object.');
                }
                Navigator.pop(context, {
                  'configuration_key': configurationKey.text.trim(),
                  'purpose': purpose.text.trim(),
                  'provider': provider.text.trim(),
                  'model_name': model.text.trim(),
                  'prompt_template': prompt.text.trim().isEmpty
                      ? null
                      : prompt.text.trim(),
                  'configuration': Map<String, dynamic>.from(decoded),
                  'is_active': isActive,
                });
              } on FormatException {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Configuration must be a valid JSON object.'),
                  ),
                );
              }
            },
            child: Text(initial == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    ),
  );
  configurationKey.dispose();
  purpose.dispose();
  provider.dispose();
  model.dispose();
  prompt.dispose();
  configuration.dispose();
  return result;
}

Future<JsonMap?> _rolePermissionDialog(
  BuildContext context,
  List<JsonMap> roles, [
  JsonMap? initial,
]) async {
  int? roleId = initial?['role_id'] as int?;
  roleId ??= roles.isEmpty ? null : roles.first['id'] as int?;
  final permission = TextEditingController(
    text: initial?['permission']?.toString() ?? '',
  );
  var isAllowed = initial?['is_allowed'] != false;
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          initial == null ? 'New role permission' : 'Edit role permission',
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: roleId,
                decoration: const InputDecoration(labelText: 'Role *'),
                items: roles
                    .map(
                      (role) => DropdownMenuItem<int>(
                        value: role['id'] as int,
                        child: Text(_label(role['role_name'].toString())),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => roleId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: permission,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Permission *',
                  helperText: 'Use a stable capability name.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allowed'),
                subtitle: const Text(
                  'Turn off to record an explicit denial for this role.',
                ),
                value: isAllowed,
                onChanged: (value) => setDialogState(() => isAllowed = value),
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
            onPressed: roleId == null
                ? null
                : () {
                    if (permission.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Permission is required.'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(context, {
                      'role_id': roleId,
                      'permission': permission.text.trim(),
                      'is_allowed': isAllowed,
                    });
                  },
            child: Text(initial == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    ),
  );
  permission.dispose();
  return result;
}

Future<JsonMap?> _maintenanceWindowDialog(
  BuildContext context, [
  JsonMap? initial,
]) async {
  final title = TextEditingController(
    text: initial?['title']?.toString() ?? '',
  );
  final message = TextEditingController(
    text: initial?['message']?.toString() ?? '',
  );
  var startsAt =
      DateTime.tryParse(initial?['starts_at']?.toString() ?? '')?.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
  var endsAt =
      DateTime.tryParse(initial?['ends_at']?.toString() ?? '')?.toLocal() ??
      startsAt.add(const Duration(hours: 1));
  var isActive = initial?['is_active'] != false;
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          initial == null ? 'Schedule maintenance' : 'Edit maintenance window',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 180,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                TextField(
                  controller: message,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'User-facing message *',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Starts'),
                  subtitle: Text(DateFormat.yMMMd().add_jm().format(startsAt)),
                  trailing: IconButton(
                    tooltip: 'Choose start date and time',
                    onPressed: () async {
                      final value = await _pickDateTime(context, startsAt);
                      if (value != null) {
                        setDialogState(() {
                          startsAt = value;
                          if (!endsAt.isAfter(startsAt)) {
                            endsAt = startsAt.add(const Duration(hours: 1));
                          }
                        });
                      }
                    },
                    icon: const Icon(AppIcons.eventRounded),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ends'),
                  subtitle: Text(DateFormat.yMMMd().add_jm().format(endsAt)),
                  trailing: IconButton(
                    tooltip: 'Choose end date and time',
                    onPressed: () async {
                      final value = await _pickDateTime(context, endsAt);
                      if (value != null) {
                        setDialogState(() => endsAt = value);
                      }
                    },
                    icon: const Icon(AppIcons.eventRounded),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enabled'),
                  subtitle: const Text(
                    'The notice is visible only while this window is active.',
                  ),
                  value: isActive,
                  onChanged: (value) => setDialogState(() => isActive = value),
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
              if (title.text.trim().isEmpty || message.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Title and message are required.'),
                  ),
                );
                return;
              }
              if (!endsAt.isAfter(startsAt)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('End time must be after the start time.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'title': title.text.trim(),
                'message': message.text.trim(),
                'starts_at': startsAt.toUtc().toIso8601String(),
                'ends_at': endsAt.toUtc().toIso8601String(),
                'is_active': isActive,
              });
            },
            child: Text(initial == null ? 'Schedule' : 'Save'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  message.dispose();
  return result;
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    initialDate: initial,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

JsonMap? _asRelation(dynamic value) {
  final relation = value is List ? (value.isEmpty ? null : value.first) : value;
  return relation is Map ? Map<String, dynamic>.from(relation) : null;
}

String _patientDisplayName(JsonMap patient) {
  final user = _asRelation(patient['users']);
  final name = '${user?['first_name'] ?? ''} ${user?['last_name'] ?? ''}'
      .trim();
  if (name.isNotEmpty) return name;
  final number = patient['patient_number']?.toString();
  return number == null || number.isEmpty ? 'Patient' : 'Patient $number';
}

String _consultationPatientName(JsonMap consultation) {
  final patient = _asRelation(consultation['patients']);
  if (patient != null) return _patientDisplayName(patient);
  final guest = _asRelation(consultation['guest_consultation_requests']);
  final name = guest?['full_name']?.toString().trim() ?? '';
  return name.isEmpty ? 'Guest patient' : name;
}

String _consultationDoctorName(JsonMap consultation) {
  final doctor = _asRelation(consultation['doctors']);
  final name = doctor?['display_name']?.toString().trim() ?? '';
  final specialization = doctor?['specialization']?.toString().trim() ?? '';
  if (name.isEmpty) return 'Unassigned';
  return specialization.isEmpty ? name : '$name ($specialization)';
}

String _consultationReference(JsonMap consultation) {
  final guest = _asRelation(consultation['guest_consultation_requests']);
  final guestReference = guest?['reference_number']?.toString().trim() ?? '';
  if (guestReference.isNotEmpty) return guestReference;
  final patient = _asRelation(consultation['patients']);
  return patient?['patient_number']?.toString() ?? 'Pending';
}

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .toList();
  if (words.isEmpty) return 'P';
  return words.map((word) => word[0].toUpperCase()).join();
}

Map<String, dynamic> _flatten(JsonMap value, [String prefix = '']) {
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = prefix.isEmpty ? entry.key : '${prefix}_${entry.key}';
    if (entry.value is Map) {
      result.addAll(
        _flatten(Map<String, dynamic>.from(entry.value as Map), key),
      );
    } else if (entry.value is num ||
        entry.value is String ||
        entry.value is bool) {
      result[key] = entry.value;
    }
  }
  return result;
}

String _label(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _metricValue(String key, dynamic value) {
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is String &&
      (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value) ||
          key.endsWith('_at') ||
          key.endsWith('_time') ||
          key.contains('timestamp'))) {
    final date = DateTime.tryParse(value);
    if (date != null) {
      return DateFormat.yMMMd().add_jm().format(date.toLocal());
    }
  }
  return value.toString();
}

String _relation(dynamic value, String key) {
  final relation = value is List ? (value.isEmpty ? null : value.first) : value;
  return relation is Map ? relation[key]?.toString() ?? '' : '';
}

String _dateTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? 'Unknown time'
      : DateFormat.yMMMd().add_jm().format(date.toLocal());
}
