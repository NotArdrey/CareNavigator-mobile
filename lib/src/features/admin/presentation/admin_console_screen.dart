import 'dart:convert';

import 'package:care_navigator_ph/src/models/user_profile.dart';
import 'package:care_navigator_ph/src/providers/app_providers.dart';
import 'package:care_navigator_ph/src/repositories/admin_repository.dart';
import 'package:care_navigator_ph/src/routing/role_routes.dart';
import 'package:care_navigator_ph/src/theme/app_theme.dart';
import 'package:care_navigator_ph/src/widgets/admin_desktop_only_screen.dart';
import 'package:care_navigator_ph/src/widgets/async_value_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminConsoleScreen extends ConsumerWidget {
  const AdminConsoleScreen({super.key});

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
      return _AccessMessage(
        title: 'Administrator sign-in required',
        action: () => context.go('/login?redirect=/admin'),
      );
    }
    return AsyncValuePanel<UserProfile?>(
      value: ref.watch(currentProfileProvider),
      onRetry: () => ref.invalidate(currentProfileProvider),
      data: (profile) {
        if (profile == null ||
            profile.accountStatus != 'active' ||
            !{'super_admin', 'hospital_admin'}.contains(profile.role)) {
          return const _AccessMessage(title: 'Administrator access required');
        }
        if (!desktopPortalAvailable) {
          return const AdminDesktopOnlyScreen(signOut: true);
        }
        final body = profile.role == 'super_admin'
            ? const _SuperAdminPanel()
            : profile.hospitalId == null
            ? const _AccessMessage(
                title: 'No hospital is assigned to this administrator.',
              )
            : _HospitalAdminPanel(hospitalId: profile.hospitalId!);
        return _AdminFrame(profile: profile, child: body);
      },
    );
  }
}

class _AdminFrame extends StatelessWidget {
  const _AdminFrame({required this.profile, required this.child});

  final UserProfile profile;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to dashboard',
                  onPressed: () => context.go('/dashboard'),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Administration',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('${profile.displayName} · ${profile.roleLabel}'),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/admin/operations'),
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Reports & operations'),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _SuperAdminPanel extends ConsumerStatefulWidget {
  const _SuperAdminPanel();

  @override
  ConsumerState<_SuperAdminPanel> createState() => _SuperAdminPanelState();
}

class _SuperAdminPanelState extends ConsumerState<_SuperAdminPanel> {
  bool _loading = true;
  Object? _error;
  List<JsonMap> _hospitals = const [];
  List<JsonMap> _classifications = const [];
  List<JsonMap> _admins = const [];
  List<JsonMap> _serviceCategories = const [];
  List<JsonMap> _doctors = const [];
  String _doctorQuery = '';
  String _doctorAvailability = 'all';
  String _doctorAccountStatus = 'all';
  String _doctorHospital = 'all';

  AdminRepository get _repository => ref.read(adminRepositoryProvider);

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
      final result = await Future.wait([
        _repository.listHospitals(),
        _repository.listClassifications(),
        _repository.listHospitalAdmins(),
        _repository.listServiceCategories(),
        _listAllDoctors(),
      ]);
      if (!mounted) return;
      setState(() {
        _hospitals = result[0];
        _classifications = result[1];
        _admins = result[2];
        _serviceCategories = result[3];
        _doctors = result[4];
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

  Future<List<JsonMap>> _listAllDoctors() async {
    final rows = await ref
        .read(supabaseClientProvider)
        .from('doctors')
        .select(
          'id, hospital_id, department_id, display_name, specialization, '
          'license_number, availability_status, created_at, '
          'hospitals(hospital_name), hospital_departments(department_name), '
          'users!doctors_user_id_fkey(account_status)',
        )
        .order('display_name');
    return rows.map(JsonMap.from).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorPanel(error: _error!, onRetry: _load);
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const Material(
            color: Colors.white,
            child: TabBar(
              tabs: [
                Tab(icon: Icon(Icons.domain_rounded), text: 'Hospitals'),
                Tab(
                  icon: Icon(Icons.manage_accounts_rounded),
                  text: 'Administrators',
                ),
                Tab(
                  icon: Icon(Icons.category_outlined),
                  text: 'Service categories',
                ),
                Tab(
                  icon: Icon(Icons.medical_services_outlined),
                  text: 'Doctors',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _hospitalList(),
                _administratorList(),
                _serviceCategoryList(),
                _doctorList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hospitalList() => _ListCanvas(
    title: 'Hospital directory management',
    subtitle: '${_hospitals.length} registered hospitals',
    action: FilledButton.icon(
      onPressed: _addHospital,
      icon: const Icon(Icons.add),
      label: const Text('Add hospital'),
    ),
    children: _hospitals.isEmpty
        ? const [
            _EmptyCard(
              message: 'No hospitals yet. Add the first hospital to begin.',
            ),
          ]
        : _hospitals.map(_hospitalCard).toList(growable: false),
  );

  Widget _hospitalCard(JsonMap hospital) {
    final classification = _relationValue(
      hospital['hospital_classifications'],
      'classification_name',
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.mint,
              foregroundColor: AppColors.teal,
              child: Icon(Icons.local_hospital_rounded),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hospital['hospital_name'].toString(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [classification, hospital['city'], hospital['province']]
                        .where(
                          (value) =>
                              value != null && value.toString().isNotEmpty,
                        )
                        .join(' · '),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 7,
                    children: [
                      _StatusChip(
                        value: hospital['verification_status'].toString(),
                      ),
                      _StatusChip(
                        value: hospital['operating_status'].toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Hospital actions',
              onSelected: (action) => _hospitalAction(action, hospital),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit hospital'),
                ),
                if (hospital['verification_status'] != 'verified')
                  const PopupMenuItem(
                    value: 'approve',
                    child: Text('Approve hospital'),
                  ),
                PopupMenuItem(
                  value: hospital['operating_status'] == 'closed'
                      ? 'open'
                      : 'close',
                  child: Text(
                    hospital['operating_status'] == 'closed'
                        ? 'Reopen hospital'
                        : 'Close hospital',
                  ),
                ),
                const PopupMenuItem(
                  value: 'admin',
                  child: Text('Add administrator'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete hospital'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _administratorList() => _ListCanvas(
    title: 'Hospital administrators',
    subtitle: '${_admins.length} administrator accounts',
    children: _admins.isEmpty
        ? const [_EmptyCard(message: 'No hospital administrator accounts yet.')]
        : _admins
              .map((admin) {
                final hospital =
                    _relationValue(admin['hospitals'], 'hospital_name') ??
                    'Unassigned';
                final name =
                    '${admin['first_name'] ?? ''} ${admin['last_name'] ?? ''}'
                        .trim();
                final active = admin['account_status'] == 'active';
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    leading: const CircleAvatar(
                      child: Icon(Icons.admin_panel_settings_outlined),
                    ),
                    title: Text(
                      name.isEmpty ? admin['email'].toString() : name,
                    ),
                    subtitle: Text('${admin['email']} · $hospital'),
                    trailing: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusChip(value: admin['account_status'].toString()),
                        PopupMenuButton<String>(
                          tooltip: 'Account actions',
                          onSelected: (status) =>
                              _changeUserStatus(admin, status),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: active ? 'inactive' : 'active',
                              child: Text(active ? 'Deactivate' : 'Activate'),
                            ),
                            const PopupMenuItem(
                              value: 'suspended',
                              child: Text('Suspend'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              })
              .toList(growable: false),
  );

  Widget _doctorList() {
    final query = _doctorQuery.trim().toLowerCase();
    final doctors = _doctors
        .where((doctor) {
          final hospital =
              _relationValue(doctor['hospitals'], 'hospital_name') ?? '';
          final department =
              _relationValue(
                doctor['hospital_departments'],
                'department_name',
              ) ??
              '';
          final account =
              _relationValue(doctor['users'], 'account_status') ?? 'unknown';
          if (_doctorAvailability != 'all' &&
              doctor['availability_status']?.toString() !=
                  _doctorAvailability) {
            return false;
          }
          if (_doctorAccountStatus != 'all' &&
              account != _doctorAccountStatus) {
            return false;
          }
          if (_doctorHospital != 'all' &&
              doctor['hospital_id']?.toString() != _doctorHospital) {
            return false;
          }
          return query.isEmpty ||
              '${doctor['display_name'] ?? ''} ${doctor['specialization'] ?? ''} ${doctor['license_number'] ?? ''} $hospital $department'
                  .toLowerCase()
                  .contains(query);
        })
        .toList(growable: false);

    return _ListCanvas(
      title: 'All doctors',
      subtitle:
          '${doctors.length} of ${_doctors.length} doctor accounts - directory and account metadata only',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search doctors',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => setState(() => _doctorQuery = value),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _doctorHospital,
                    decoration: const InputDecoration(labelText: 'Hospital'),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All hospitals'),
                      ),
                      ..._hospitals.map(
                        (hospital) => DropdownMenuItem(
                          value: hospital['id'].toString(),
                          child: Text(hospital['hospital_name'].toString()),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _doctorHospital = value ?? 'all'),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: _enumField(
                    'Availability',
                    _doctorAvailability,
                    const ['all', 'available', 'limited', 'unavailable'],
                    (value) => setState(() => _doctorAvailability = value),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: _enumField(
                    'Account status',
                    _doctorAccountStatus,
                    const ['all', 'pending', 'active', 'inactive', 'suspended'],
                    (value) => setState(() => _doctorAccountStatus = value),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_doctors.isEmpty)
          const _EmptyCard(message: 'No doctor accounts are registered.')
        else if (doctors.isEmpty)
          const _EmptyCard(message: 'No doctors match the selected filters.')
        else
          ...doctors.map((doctor) {
            final hospital =
                _relationValue(doctor['hospitals'], 'hospital_name') ??
                'Unknown hospital';
            final department =
                _relationValue(
                  doctor['hospital_departments'],
                  'department_name',
                ) ??
                'No department';
            final account =
                _relationValue(doctor['users'], 'account_status') ?? 'unknown';
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                leading: const CircleAvatar(
                  backgroundColor: AppColors.mint,
                  foregroundColor: AppColors.teal,
                  child: Icon(Icons.medical_services_outlined),
                ),
                title: Text(doctor['display_name']?.toString() ?? 'Doctor'),
                subtitle: Text(
                  '$hospital - $department / ${doctor['specialization'] ?? 'General practice'}\n'
                  'License: ${doctor['license_number'] ?? 'Not recorded'} - Created ${_shortDate(doctor['created_at'])}',
                ),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusChip(value: account),
                    _StatusChip(
                      value:
                          doctor['availability_status']?.toString() ??
                          'unknown',
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _serviceCategoryList() => _ListCanvas(
    title: 'Platform taxonomies',
    subtitle:
        'Manage the shared hospital classification and healthcare service category lists.',
    children: [
      _SectionCard(
        title: 'Hospital classifications',
        action: FilledButton.icon(
          onPressed: () => _editClassification(),
          icon: const Icon(Icons.add),
          label: const Text('Add classification'),
        ),
        children: _classifications.isEmpty
            ? const [
                _EmptyCard(
                  message: 'No hospital classifications are available.',
                ),
              ]
            : _classifications
                  .map(
                    (classification) => ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.mint,
                        child: Icon(Icons.account_tree_outlined),
                      ),
                      title: Text(
                        classification['classification_name'].toString(),
                      ),
                      subtitle: Text(
                        classification['description']?.toString() ?? '',
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Classification actions',
                        onSelected: (action) =>
                            _classificationAction(action, classification),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
      ),
      _SectionCard(
        title: 'Healthcare service categories',
        action: FilledButton.icon(
          onPressed: () => _editServiceCategory(),
          icon: const Icon(Icons.add),
          label: const Text('Add category'),
        ),
        children: _serviceCategories.isEmpty
            ? const [
                _EmptyCard(message: 'No service categories are available.'),
              ]
            : _serviceCategories
                  .map(
                    (category) => ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.mint,
                        child: Icon(Icons.category_outlined),
                      ),
                      title: Text(category['category_name'].toString()),
                      subtitle: Text(category['description']?.toString() ?? ''),
                      trailing: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatusChip(
                            value: category['is_active'] == true
                                ? 'active'
                                : 'inactive',
                          ),
                          PopupMenuButton<String>(
                            onSelected: (action) =>
                                _serviceCategoryAction(action, category),
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text('Toggle active status'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
      ),
    ],
  );

  Future<void> _editClassification([JsonMap? initial]) async {
    final values = await _showClassificationDialog(context, initial: initial);
    if (values == null) return;
    await _run(
      () => _repository.saveClassification(
        id: initial?['id']?.toString(),
        values: values,
      ),
    );
  }

  Future<void> _classificationAction(
    String action,
    JsonMap classification,
  ) async {
    switch (action) {
      case 'edit':
        await _editClassification(classification);
      case 'delete':
        if (await _confirm(
          context,
          'Delete ${classification['classification_name']}?',
          'This succeeds only when no hospital currently uses the classification.',
          destructive: true,
        )) {
          await _run(
            () => _repository.deleteClassification(
              classification['id'].toString(),
            ),
          );
        }
    }
  }

  Future<void> _editServiceCategory([JsonMap? initial]) async {
    final values = await _showServiceCategoryDialog(context, initial: initial);
    if (values == null) return;
    await _run(
      () => _repository.saveServiceCategory(
        id: initial?['id']?.toString(),
        values: values,
      ),
    );
  }

  Future<void> _serviceCategoryAction(String action, JsonMap category) async {
    switch (action) {
      case 'edit':
        await _editServiceCategory(category);
      case 'toggle':
        await _run(
          () => _repository.saveServiceCategory(
            id: category['id'].toString(),
            values: {'is_active': category['is_active'] != true},
          ),
        );
      case 'delete':
        if (await _confirm(
          context,
          'Delete ${category['category_name']}?',
          'Hospital services will remain available but become uncategorized.',
          destructive: true,
        )) {
          await _run(
            () => _repository.deleteRecord(
              'healthcare_service_categories',
              category['id'].toString(),
            ),
          );
        }
    }
  }

  Future<void> _addHospital() async {
    final values = await _showHospitalDialog(context, _classifications);
    if (values != null) await _run(() => _repository.createHospital(values));
  }

  Future<void> _hospitalAction(String action, JsonMap hospital) async {
    final id = hospital['id'].toString();
    switch (action) {
      case 'edit':
        final values = await _showHospitalDialog(
          context,
          _classifications,
          initial: hospital,
        );
        if (values != null) {
          await _run(() => _repository.updateHospital(id, values));
        }
      case 'approve':
        await _run(
          () => _repository.updateHospital(id, {
            'verification_status': 'verified',
          }),
        );
      case 'open':
        await _run(
          () => _repository.updateHospital(id, {'operating_status': 'open'}),
        );
      case 'close':
        if (await _confirm(
          context,
          'Close this hospital?',
          'It will disappear from the open public directory.',
        )) {
          await _run(
            () =>
                _repository.updateHospital(id, {'operating_status': 'closed'}),
          );
        }
      case 'admin':
        final account = await _showAccountDialog(
          context,
          title: 'Create hospital administrator',
        );
        if (account != null) {
          await _run(
            () => _repository.createHospitalAdmin(
              hospitalId: id,
              email: account['email'],
              password: account['password'],
              firstName: account['first_name'],
              lastName: account['last_name'],
            ),
          );
        }
      case 'delete':
        if (await _confirm(
          context,
          'Delete ${hospital['hospital_name']}?',
          'Departments, services, availability, and related hospital data will also be deleted. This cannot be undone.',
          destructive: true,
        )) {
          await _run(() => _repository.deleteHospital(id));
        }
    }
  }

  Future<void> _changeUserStatus(JsonMap admin, String status) async {
    if (status != 'active' &&
        !await _confirm(
          context,
          'Mark this account $status?',
          'The administrator will lose sign-in access.',
        )) {
      return;
    }
    await _run(
      () => _repository.updateUserStatus(admin['id'].toString(), status),
    );
  }

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Changes saved.')));
      await _load();
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }
}

class _HospitalAdminPanel extends ConsumerStatefulWidget {
  const _HospitalAdminPanel({required this.hospitalId});

  final String hospitalId;

  @override
  ConsumerState<_HospitalAdminPanel> createState() =>
      _HospitalAdminPanelState();
}

class _HospitalAdminPanelState extends ConsumerState<_HospitalAdminPanel> {
  bool _loading = true;
  Object? _error;
  List<JsonMap> _departments = const [];
  List<JsonMap> _services = const [];
  List<JsonMap> _rooms = const [];
  List<JsonMap> _beds = const [];
  List<JsonMap> _facilities = const [];
  List<JsonMap> _doctors = const [];
  List<JsonMap> _serviceCategories = const [];
  List<JsonMap> _classifications = const [];
  JsonMap? _hospital;
  JsonMap? _emergency;
  String _serviceQuery = '';
  String _serviceAvailability = 'all';
  String? _serviceCategoryId;

  AdminRepository get _repository => ref.read(adminRepositoryProvider);

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
      final result = await Future.wait<dynamic>([
        _repository.listDepartments(widget.hospitalId),
        _repository.listServices(widget.hospitalId),
        _repository.listRooms(widget.hospitalId),
        _repository.listBeds(widget.hospitalId),
        _repository.getEmergencyStatus(widget.hospitalId),
        _repository.listFacilities(widget.hospitalId),
        _repository.listDoctors(widget.hospitalId),
        _repository.listServiceCategories(),
        _repository.listClassifications(),
        _repository.getHospital(widget.hospitalId),
      ]);
      if (!mounted) return;
      setState(() {
        _departments = result[0];
        _services = result[1];
        _rooms = result[2];
        _beds = result[3];
        _emergency = result[4];
        _facilities = result[5];
        _doctors = result[6];
        _serviceCategories = result[7];
        _classifications = result[8];
        _hospital = result[9];
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorPanel(error: _error!, onRetry: _load);
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.local_hospital_outlined),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _hospital?['hospital_name']?.toString() ??
                          'Assigned hospital',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _editHospitalProfile,
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: const Text('Edit hospital profile'),
                  ),
                ],
              ),
            ),
          ),
          const Material(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(
                  icon: Icon(Icons.medical_services_outlined),
                  text: 'Departments & services',
                ),
                Tab(icon: Icon(Icons.bed_outlined), text: 'Live availability'),
                Tab(icon: Icon(Icons.badge_outlined), text: 'Doctors'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [_careCatalog(), _availability(), _doctorList()],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editHospitalProfile() async {
    final current = _hospital;
    if (current == null) return;
    final values = await _showHospitalDialog(
      context,
      _classifications,
      initial: current,
      canSetVerification: false,
    );
    if (values == null) return;
    await _run(() => _repository.updateHospital(widget.hospitalId, values));
  }

  Widget _careCatalog() {
    final normalized = _serviceQuery.trim().toLowerCase();
    final visibleServices = _services
        .where((service) {
          final categoryId = service['category_id']?.toString();
          final haystack = [
            service['service_name'],
            service['service_code'],
            service['description'],
            ...(service['tags'] as List? ?? const []),
          ].join(' ').toLowerCase();
          return (normalized.isEmpty || haystack.contains(normalized)) &&
              (_serviceAvailability == 'all' ||
                  service['availability_status'] == _serviceAvailability) &&
              (_serviceCategoryId == null || categoryId == _serviceCategoryId);
        })
        .toList(growable: false);

    return _ListCanvas(
      title: 'Care catalog',
      subtitle:
          '${_departments.length} departments · ${_services.length} services',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _editDepartment(),
            icon: const Icon(Icons.add),
            label: const Text('Department'),
          ),
          FilledButton.icon(
            onPressed: () => _editService(),
            icon: const Icon(Icons.add),
            label: const Text('Service offering'),
          ),
        ],
      ),
      children: [
        _SectionCard(
          title: 'Departments',
          children: _departments
              .map(
                (item) => _editableTile(
                  icon: Icons.account_tree_outlined,
                  title: item['department_name'].toString(),
                  subtitle: item['description']?.toString() ?? '',
                  status: item['availability_status'].toString(),
                  onEdit: () => _editDepartment(item),
                  onDelete: () => _delete(
                    'hospital_departments',
                    item,
                    item['department_name'].toString(),
                  ),
                ),
              )
              .toList(growable: false),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 310,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search service, code, or tag',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _serviceQuery = value),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: _serviceAvailability,
                    decoration: const InputDecoration(
                      labelText: 'Availability',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(
                        value: 'available',
                        child: Text('Available'),
                      ),
                      DropdownMenuItem(
                        value: 'limited',
                        child: Text('Limited'),
                      ),
                      DropdownMenuItem(
                        value: 'unavailable',
                        child: Text('Unavailable'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _serviceAvailability = value ?? 'all'),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _serviceCategoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All categories'),
                      ),
                      ..._serviceCategories.map(
                        (category) => DropdownMenuItem<String?>(
                          value: category['id'].toString(),
                          child: Text(category['category_name'].toString()),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _serviceCategoryId = value),
                  ),
                ),
              ],
            ),
          ),
        ),
        _SectionCard(
          title: 'Service offerings (${visibleServices.length})',
          children: visibleServices
              .map((item) => _serviceTile(item))
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _serviceTile(JsonMap item) {
    final department =
        _relationValue(item['hospital_departments'], 'department_name') ??
        'No department';
    final category = _relationValue(
      item['healthcare_service_categories'],
      'category_name',
    );
    final modes = (item['delivery_modes'] as List? ?? const [])
        .map((value) => _pretty(value.toString()))
        .join(', ');
    final assignments = item['hospital_service_doctors'] as List? ?? const [];
    final fee = _feeLabel(item['fee_min'], item['fee_max']);
    return _editableTile(
      icon: Icons.health_and_safety_outlined,
      title: item['service_name'].toString(),
      subtitle: <String?>[
        category,
        department,
        modes.isEmpty ? null : modes,
        fee,
        '${assignments.length} assigned doctor${assignments.length == 1 ? '' : 's'}',
      ].whereType<String>().join(' · '),
      status: item['availability_status'].toString(),
      onEdit: () => _editService(item),
      onDelete: () =>
          _delete('hospital_services', item, item['service_name'].toString()),
    );
  }

  Widget _availability() => _ListCanvas(
    title: 'Live hospital availability',
    subtitle: 'Keep counts accurate for patients choosing where to go.',
    action: FilledButton.icon(
      onPressed: _editEmergency,
      icon: const Icon(Icons.emergency_outlined),
      label: const Text('Update ER'),
    ),
    children: [
      _EmergencyCard(value: _emergency, onEdit: _editEmergency),
      _SectionCard(
        title: 'Rooms',
        action: IconButton(
          tooltip: 'Add room type',
          onPressed: () => _editInventory('room'),
          icon: const Icon(Icons.add_circle_outline),
        ),
        children: _rooms
            .map(
              (item) => _editableTile(
                icon: Icons.meeting_room_outlined,
                title: item['room_type'].toString(),
                subtitle:
                    '${item['available_rooms']} available · ${item['occupied_rooms']} occupied · ${item['total_rooms']} total',
                status: item['status'].toString(),
                onEdit: () => _editInventory('room', item),
                onDelete: () => _delete(
                  'hospital_rooms',
                  item,
                  item['room_type'].toString(),
                ),
              ),
            )
            .toList(growable: false),
      ),
      _SectionCard(
        title: 'Beds',
        action: IconButton(
          tooltip: 'Add bed type',
          onPressed: () => _editInventory('bed'),
          icon: const Icon(Icons.add_circle_outline),
        ),
        children: _beds
            .map(
              (item) => _editableTile(
                icon: Icons.bed_outlined,
                title: item['bed_type'].toString(),
                subtitle:
                    '${item['available_beds']} available · ${item['occupied_beds']} occupied · ${item['total_beds']} total',
                onEdit: () => _editInventory('bed', item),
                onDelete: () =>
                    _delete('hospital_beds', item, item['bed_type'].toString()),
              ),
            )
            .toList(growable: false),
      ),
      _SectionCard(
        title: 'Facilities',
        action: IconButton(
          tooltip: 'Add facility',
          onPressed: () => _editFacility(),
          icon: const Icon(Icons.add_circle_outline),
        ),
        children: _facilities
            .map(
              (item) => _editableTile(
                icon: Icons.precision_manufacturing_outlined,
                title: _pretty(item['facility_type'].toString()),
                subtitle:
                    '${item['available_units'] ?? '—'} available units${(item['notes'] ?? '').toString().isEmpty ? '' : ' · ${item['notes']}'}',
                status: item['status'].toString(),
                onEdit: () => _editFacility(item),
                onDelete: () => _delete(
                  'hospital_facility_status',
                  item,
                  _pretty(item['facility_type'].toString()),
                ),
              ),
            )
            .toList(growable: false),
      ),
    ],
  );

  Widget _doctorList() => _ListCanvas(
    title: 'Doctor accounts',
    subtitle: '${_doctors.length} doctors assigned to this hospital',
    action: FilledButton.icon(
      onPressed: _createDoctor,
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Add doctor'),
    ),
    children: _doctors.isEmpty
        ? const [_EmptyCard(message: 'No doctor accounts have been created.')]
        : _doctors
              .map((doctor) {
                final department = _relationValue(
                  doctor['hospital_departments'],
                  'department_name',
                );
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.mint,
                      child: Icon(Icons.medical_information_outlined),
                    ),
                    title: Text(doctor['display_name'].toString()),
                    subtitle: Text(
                      '${doctor['specialization']} · ${department ?? 'No department'}\nLicense ${doctor['license_number']}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Doctor actions',
                      onSelected: (action) => _doctorAction(action, doctor),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'schedule',
                          child: Text('Manage schedule'),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'available',
                          child: Text('Mark available'),
                        ),
                        PopupMenuItem(
                          value: 'limited',
                          child: Text('Mark limited'),
                        ),
                        PopupMenuItem(
                          value: 'unavailable',
                          child: Text('Mark unavailable'),
                        ),
                      ],
                      child: _StatusChip(
                        value: doctor['availability_status'].toString(),
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
  );

  Widget _editableTile({
    required IconData icon,
    required String title,
    required String subtitle,
    String? status,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) => ListTile(
    leading: Icon(icon, color: AppColors.blue),
    title: Text(title),
    subtitle: subtitle.isEmpty ? null : Text(subtitle),
    trailing: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (status != null) _StatusChip(value: status),
        PopupMenuButton<String>(
          onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    ),
  );

  Future<void> _editDepartment([JsonMap? initial]) async {
    final values = await _showCatalogDialog(
      context,
      kind: 'Department',
      initial: initial,
    );
    if (values == null) return;
    await _run(
      () => _repository.saveDepartment(
        id: initial?['id']?.toString(),
        values: {...values, 'hospital_id': widget.hospitalId},
      ),
    );
  }

  Future<void> _editService([JsonMap? initial]) async {
    final values = await _showServiceDialog(
      context,
      initial: initial,
      departments: _departments,
      categories: _serviceCategories,
      doctors: _doctors,
    );
    if (values == null) return;
    final doctorIds = (values.remove('doctor_ids') as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final primaryDoctorId = values.remove('primary_doctor_id')?.toString();
    await _run(
      () => _repository.saveService(
        id: initial?['id']?.toString(),
        values: {...values, 'hospital_id': widget.hospitalId},
        doctorIds: doctorIds,
        primaryDoctorId: primaryDoctorId,
      ),
    );
  }

  Future<void> _editInventory(String kind, [JsonMap? initial]) async {
    final values = await _showInventoryDialog(
      context,
      kind: kind,
      initial: initial,
      departments: _departments,
    );
    if (values == null) return;
    final data = {
      ...values,
      'hospital_id': widget.hospitalId,
      'last_updated': DateTime.now().toUtc().toIso8601String(),
    };
    await _run(
      () => kind == 'room'
          ? _repository.saveRoom(id: initial?['id']?.toString(), values: data)
          : _repository.saveBed(id: initial?['id']?.toString(), values: data),
    );
  }

  Future<void> _editEmergency() async {
    final values = await _showEmergencyDialog(context, initial: _emergency);
    if (values == null) return;
    await _run(
      () => _repository.saveEmergencyStatus({
        ...values,
        'hospital_id': widget.hospitalId,
        'last_updated': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> _editFacility([JsonMap? initial]) async {
    final values = await _showFacilityDialog(context, initial: initial);
    if (values == null) return;
    await _run(
      () => _repository.saveFacility(
        id: initial?['id']?.toString(),
        values: {
          ...values,
          'hospital_id': widget.hospitalId,
          'last_updated': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );
  }

  Future<void> _createDoctor() async {
    final values = await _showDoctorDialog(context, departments: _departments);
    if (values == null) return;
    await _run(
      () => _repository.createDoctor(
        hospitalId: widget.hospitalId,
        email: values['email'],
        password: values['password'],
        firstName: values['first_name'],
        lastName: values['last_name'],
        specialization: values['specialization'],
        licenseNumber: values['license_number'],
        departmentId: values['department_id'],
        consultationFee: values['consultation_fee'],
        biography: values['biography'],
      ),
    );
  }

  Future<void> _doctorAction(String action, JsonMap doctor) async {
    if (action == 'schedule') {
      await showDialog<void>(
        context: context,
        builder: (context) =>
            _DoctorSchedulesDialog(repository: _repository, doctor: doctor),
      );
      return;
    }
    await _run(
      () => _repository.updateDoctorStatus(doctor['id'].toString(), action),
    );
  }

  Future<void> _delete(String table, JsonMap item, String label) async {
    if (await _confirm(
      context,
      'Delete $label?',
      'This cannot be undone.',
      destructive: true,
    )) {
      await _run(() => _repository.deleteRecord(table, item['id'].toString()));
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Changes saved.')));
      await _load();
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }
}

class _ListCanvas extends StatelessWidget {
  const _ListCanvas({
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 34,
      vertical: 24,
    ),
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
          action ?? const SizedBox.shrink(),
        ],
      ),
      const SizedBox(height: 18),
      ...children.expand((child) => [child, const SizedBox(height: 12)]),
    ],
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: Theme.of(context).textTheme.titleLarge),
            trailing: action,
          ),
          if (children.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Nothing has been added yet.'),
            )
          else
            ...children,
        ],
      ),
    ),
  );
}

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.value, required this.onEdit});
  final JsonMap? value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFFE8E6),
        foregroundColor: AppColors.danger,
        child: Icon(Icons.emergency_rounded),
      ),
      title: const Text('Emergency room'),
      subtitle: value == null
          ? const Text('No live status has been published.')
          : Text(
              '${value!['available_beds']} beds available · ${value!['current_patient_count']} of ${value!['maximum_capacity']} patients',
            ),
      trailing: value == null
          ? TextButton(onPressed: onEdit, child: const Text('Set status'))
          : _StatusChip(value: value!['status'].toString()),
      onTap: onEdit,
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final positive = {
      'active',
      'available',
      'verified',
      'open',
    }.contains(value);
    final warning = {'pending', 'limited'}.contains(value);
    final color = positive
        ? AppColors.teal
        : warning
        ? const Color(0xFF9A6700)
        : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _pretty(value),
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
  const _EmptyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Center(child: Text(message, textAlign: TextAlign.center)),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44),
          const SizedBox(height: 10),
          Text(_cleanError(error), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _AccessMessage extends StatelessWidget {
  const _AccessMessage({required this.title, this.action});
  final String title;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 44),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: 18),
                FilledButton(onPressed: action, child: const Text('Sign in')),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

Future<JsonMap?> _showHospitalDialog(
  BuildContext context,
  List<JsonMap> classifications, {
  JsonMap? initial,
  bool canSetVerification = true,
}) {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(
    text: initial?['hospital_name']?.toString(),
  );
  final address = TextEditingController(text: initial?['address']?.toString());
  final city = TextEditingController(text: initial?['city']?.toString());
  final province = TextEditingController(
    text: initial?['province']?.toString(),
  );
  final contact = TextEditingController(
    text: initial?['contact_number']?.toString(),
  );
  final emergency = TextEditingController(
    text: initial?['emergency_contact_number']?.toString(),
  );
  final email = TextEditingController(text: initial?['email']?.toString());
  final description = TextEditingController(
    text: initial?['description']?.toString(),
  );
  final latitude = TextEditingController(
    text: initial?['latitude']?.toString(),
  );
  final longitude = TextEditingController(
    text: initial?['longitude']?.toString(),
  );
  final operatingHours = TextEditingController(
    text: const JsonEncoder.withIndent(
      '  ',
    ).convert(initial?['operating_hours'] ?? const <String, dynamic>{}),
  );
  String? classificationId = initial?['classification_id']?.toString();
  var operatingStatus = initial?['operating_status']?.toString() ?? 'open';
  var verificationStatus =
      initial?['verification_status']?.toString() ?? 'pending';

  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initial == null ? 'Add hospital' : 'Edit hospital'),
        content: SizedBox(
          width: 620,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _requiredField(name, 'Hospital name'),
                  const SizedBox(height: 11),
                  DropdownButtonFormField<String>(
                    initialValue: classificationId,
                    decoration: const InputDecoration(
                      labelText: 'Classification',
                    ),
                    items: classifications
                        .map(
                          (item) => DropdownMenuItem(
                            value: item['id'].toString(),
                            child: Text(item['classification_name'].toString()),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) =>
                        setState(() => classificationId = value),
                  ),
                  const SizedBox(height: 11),
                  _requiredField(address, 'Full address'),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(child: _field(city, 'City')),
                      const SizedBox(width: 10),
                      Expanded(child: _field(province, 'Province')),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                          validator: (value) => _coordinateError(
                            value,
                            minimum: -90,
                            maximum: 90,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                          validator: (value) => _coordinateError(
                            value,
                            minimum: -180,
                            maximum: 180,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(child: _field(contact, 'Contact number')),
                      const SizedBox(width: 10),
                      Expanded(child: _field(emergency, 'Emergency contact')),
                    ],
                  ),
                  const SizedBox(height: 11),
                  _field(
                    email,
                    'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 11),
                  _field(description, 'Description', maxLines: 3),
                  const SizedBox(height: 11),
                  TextFormField(
                    controller: operatingHours,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Operating hours (JSON object)',
                      helperText:
                          'Example: {"monday":{"enabled":true,"open":"08:00","close":"17:00"}}',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      try {
                        return jsonDecode(value ?? '{}') is Map
                            ? null
                            : 'Operating hours must be a JSON object.';
                      } on FormatException {
                        return 'Enter valid JSON operating hours.';
                      }
                    },
                  ),
                  const SizedBox(height: 11),
                  if (canSetVerification)
                    Row(
                      children: [
                        Expanded(
                          child: _enumField(
                            'Operating status',
                            operatingStatus,
                            const [
                              'open',
                              'limited',
                              'temporarily_closed',
                              'closed',
                            ],
                            (value) => setState(() => operatingStatus = value),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _enumField(
                            'Verification',
                            verificationStatus,
                            const ['pending', 'verified', 'rejected'],
                            (value) =>
                                setState(() => verificationStatus = value),
                          ),
                        ),
                      ],
                    )
                  else
                    _enumField(
                      'Operating status',
                      operatingStatus,
                      const ['open', 'limited', 'temporarily_closed', 'closed'],
                      (value) => setState(() => operatingStatus = value),
                    ),
                ],
              ),
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
              if (!formKey.currentState!.validate()) return;
              if (latitude.text.trim().isEmpty !=
                  longitude.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Provide both latitude and longitude, or leave both blank.',
                    ),
                  ),
                );
                return;
              }
              final values = <String, dynamic>{
                'hospital_name': name.text.trim(),
                'classification_id': classificationId,
                'address': address.text.trim(),
                'city': _nullIfEmpty(city.text),
                'province': _nullIfEmpty(province.text),
                'contact_number': _nullIfEmpty(contact.text),
                'emergency_contact_number': _nullIfEmpty(emergency.text),
                'email': _nullIfEmpty(email.text),
                'description': description.text.trim(),
                'latitude': double.tryParse(latitude.text.trim()),
                'longitude': double.tryParse(longitude.text.trim()),
                'operating_hours': jsonDecode(operatingHours.text),
                'operating_status': operatingStatus,
                if (canSetVerification)
                  'verification_status': verificationStatus,
              };
              Navigator.pop(context, values);
            },
            child: const Text('Save hospital'),
          ),
        ],
      ),
    ),
  );
}

String? _coordinateError(
  String? value, {
  required double minimum,
  required double maximum,
}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final number = double.tryParse(text);
  if (number == null || number < minimum || number > maximum) {
    return 'Use a value from $minimum to $maximum.';
  }
  return null;
}

Future<JsonMap?> _showAccountDialog(
  BuildContext context, {
  required String title,
}) {
  final formKey = GlobalKey<FormState>();
  final first = TextEditingController();
  final last = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  var hidden = true;
  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _requiredField(first, 'First name')),
                    const SizedBox(width: 10),
                    Expanded(child: _requiredField(last, 'Last name')),
                  ],
                ),
                const SizedBox(height: 11),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: _emailValidator,
                ),
                const SizedBox(height: 11),
                TextFormField(
                  controller: password,
                  obscureText: hidden,
                  decoration: InputDecoration(
                    labelText: 'Temporary password',
                    helperText: 'At least 12 characters',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => hidden = !hidden),
                      icon: Icon(
                        hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => (value?.length ?? 0) < 12
                      ? 'Use at least 12 characters.'
                      : null,
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
              if (!formKey.currentState!.validate()) return;
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
}

Future<JsonMap?> _showCatalogDialog(
  BuildContext context, {
  required String kind,
  JsonMap? initial,
  List<JsonMap> departments = const [],
}) {
  final isService = kind == 'Service';
  final formKey = GlobalKey<FormState>();
  final nameKey = isService ? 'service_name' : 'department_name';
  final name = TextEditingController(text: initial?[nameKey]?.toString());
  final description = TextEditingController(
    text: initial?['description']?.toString(),
  );
  var status = initial?['availability_status']?.toString() ?? 'available';
  String? departmentId = initial?['department_id']?.toString();
  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          '${initial == null ? 'Add' : 'Edit'} ${kind.toLowerCase()}',
        ),
        content: SizedBox(
          width: 500,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _requiredField(name, '$kind name'),
                if (isService) ...[
                  const SizedBox(height: 11),
                  DropdownButtonFormField<String?>(
                    initialValue: departmentId,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No department'),
                      ),
                      ...departments.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item['id'].toString(),
                          child: Text(item['department_name'].toString()),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => departmentId = value),
                  ),
                ],
                const SizedBox(height: 11),
                _field(description, 'Description', maxLines: 3),
                const SizedBox(height: 11),
                _enumField('Availability', status, const [
                  'available',
                  'limited',
                  'unavailable',
                ], (value) => setState(() => status = value)),
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
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, {
                nameKey: name.text.trim(),
                'description': description.text.trim(),
                'availability_status': status,
                if (isService) 'department_id': departmentId,
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<JsonMap?> _showClassificationDialog(
  BuildContext context, {
  JsonMap? initial,
}) async {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(
    text: initial?['classification_name']?.toString(),
  );
  final description = TextEditingController(
    text: initial?['description']?.toString(),
  );
  final result = await showDialog<JsonMap>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${initial == null ? 'Add' : 'Edit'} classification'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Classification name *',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Classification name is required.'
                    : null,
              ),
              const SizedBox(height: 11),
              TextFormField(
                controller: description,
                minLines: 2,
                maxLines: 5,
                maxLength: 600,
                decoration: const InputDecoration(labelText: 'Description'),
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
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'classification_name': name.text.trim(),
              'description': description.text.trim(),
            });
          },
          child: Text(initial == null ? 'Add classification' : 'Save'),
        ),
      ],
    ),
  );
  name.dispose();
  description.dispose();
  return result;
}

Future<JsonMap?> _showServiceCategoryDialog(
  BuildContext context, {
  JsonMap? initial,
}) {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(
    text: initial?['category_name']?.toString(),
  );
  final description = TextEditingController(
    text: initial?['description']?.toString(),
  );
  final icon = TextEditingController(text: initial?['icon_name']?.toString());
  final order = TextEditingController(
    text: initial?['display_order']?.toString() ?? '0',
  );
  var active = initial?['is_active'] as bool? ?? true;
  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('${initial == null ? 'Add' : 'Edit'} service category'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _requiredField(name, 'Category name'),
                const SizedBox(height: 11),
                _field(description, 'Description', maxLines: 3),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(child: _field(icon, 'Icon name (optional)')),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField(order, 'Display order')),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active and available to hospitals'),
                  value: active,
                  onChanged: (value) => setState(() => active = value),
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
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, {
                'category_name': name.text.trim(),
                'description': description.text.trim(),
                'icon_name': _nullIfEmpty(icon.text),
                'display_order': int.parse(order.text),
                'is_active': active,
              });
            },
            child: const Text('Save category'),
          ),
        ],
      ),
    ),
  );
}

Future<JsonMap?> _showServiceDialog(
  BuildContext context, {
  JsonMap? initial,
  required List<JsonMap> departments,
  required List<JsonMap> categories,
  required List<JsonMap> doctors,
}) {
  const days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(
    text: initial?['service_name']?.toString(),
  );
  final code = TextEditingController(
    text: initial?['service_code']?.toString(),
  );
  final description = TextEditingController(
    text: initial?['description']?.toString(),
  );
  final feeMin = TextEditingController(text: initial?['fee_min']?.toString());
  final feeMax = TextEditingController(text: initial?['fee_max']?.toString());
  final feeNotes = TextEditingController(
    text: initial?['fee_notes']?.toString(),
  );
  final contact = TextEditingController(
    text: initial?['contact_number']?.toString(),
  );
  final bookingUrl = TextEditingController(
    text: initial?['booking_url']?.toString(),
  );
  final preparation = TextEditingController(
    text: initial?['preparation_instructions']?.toString(),
  );
  final tags = TextEditingController(
    text: (initial?['tags'] as List? ?? const []).join(', '),
  );
  String? departmentId = initial?['department_id']?.toString();
  String? categoryId = initial?['category_id']?.toString();
  var status = initial?['availability_status']?.toString() ?? 'available';
  var appointmentRequired = initial?['appointment_required'] as bool? ?? false;
  var acceptsWalkIns = initial?['accepts_walk_ins'] as bool? ?? true;
  final deliveryModes = (initial?['delivery_modes'] as List? ?? ['in_person'])
      .map((value) => value.toString())
      .toSet();
  final rawHours = initial?['operating_hours'];
  final hours = <String, JsonMap>{};
  for (final day in days) {
    final rawDay = rawHours is Map ? rawHours[day] : null;
    final dayData = rawDay is Map ? JsonMap.from(rawDay) : <String, dynamic>{};
    hours[day] = {
      'enabled': dayData['enabled'] == true,
      'open': dayData['open']?.toString() ?? '08:00',
      'close': dayData['close']?.toString() ?? '17:00',
    };
  }
  final assignments = initial?['hospital_service_doctors'] as List? ?? const [];
  final selectedDoctors = assignments
      .whereType<Map>()
      .map((item) => item['doctor_id'].toString())
      .toSet();
  String? primaryDoctorId;
  for (final assignment in assignments.whereType<Map>()) {
    if (assignment['is_primary'] == true) {
      primaryDoctorId = assignment['doctor_id'].toString();
      break;
    }
  }

  return showDialog<JsonMap>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          '${initial == null ? 'Add' : 'Edit'} hospital service offering',
        ),
        content: SizedBox(
          width: 760,
          child: Form(
            key: formKey,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 690),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: _requiredField(name, 'Service name'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: code,
                            decoration: const InputDecoration(
                              labelText: 'Internal code',
                              hintText: 'CARDIO-OPD',
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) return null;
                              return RegExp(
                                    r'^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$',
                                  ).hasMatch(text)
                                  ? null
                                  : 'Use letters, numbers, ., _, or -.';
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: categoryId,
                            decoration: const InputDecoration(
                              labelText: 'Category (optional)',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Custom / uncategorized'),
                              ),
                              ...categories.map(
                                (item) => DropdownMenuItem<String?>(
                                  value: item['id'].toString(),
                                  child: Text(item['category_name'].toString()),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => categoryId = value),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: departmentId,
                            decoration: const InputDecoration(
                              labelText: 'Department (optional)',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('No department'),
                              ),
                              ...departments.map(
                                (item) => DropdownMenuItem<String?>(
                                  value: item['id'].toString(),
                                  child: Text(
                                    item['department_name'].toString(),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => departmentId = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    _field(description, 'Public description', maxLines: 3),
                    const SizedBox(height: 16),
                    Text(
                      'How the service is offered',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          const {
                                'in_person': 'In person',
                                'online': 'Online',
                                'home_service': 'Home service',
                                'emergency': 'Emergency',
                              }.entries
                              .map(
                                (entry) => FilterChip(
                                  label: Text(entry.value),
                                  selected: deliveryModes.contains(entry.key),
                                  onSelected: (selected) => setState(() {
                                    if (selected) {
                                      deliveryModes.add(entry.key);
                                    } else if (deliveryModes.length > 1) {
                                      deliveryModes.remove(entry.key);
                                    }
                                  }),
                                ),
                              )
                              .toList(growable: false),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Appointment required'),
                      value: appointmentRequired,
                      onChanged: (value) =>
                          setState(() => appointmentRequired = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accepts walk-ins'),
                      value: acceptsWalkIns,
                      onChanged: (value) =>
                          setState(() => acceptsWalkIns = value),
                    ),
                    const Divider(height: 26),
                    Text(
                      'Availability and pricing',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _enumField(
                            'Current availability',
                            status,
                            const ['available', 'limited', 'unavailable'],
                            (value) => setState(() => status = value),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _moneyField(feeMin, 'Minimum fee')),
                        const SizedBox(width: 10),
                        Expanded(child: _moneyField(feeMax, 'Maximum fee')),
                      ],
                    ),
                    const SizedBox(height: 11),
                    _field(feeNotes, 'Fee notes', maxLines: 2),
                    const Divider(height: 26),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Weekly operating hours'),
                      subtitle: const Text(
                        'Set only the days this service operates.',
                      ),
                      children: days
                          .map((day) {
                            final dayHours = hours[day]!;
                            final enabled = dayHours['enabled'] == true;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 138,
                                    child: CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: Text(_pretty(day)),
                                      value: enabled,
                                      onChanged: (value) => setState(
                                        () =>
                                            dayHours['enabled'] = value == true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      enabled: enabled,
                                      initialValue: dayHours['open'].toString(),
                                      decoration: const InputDecoration(
                                        labelText: 'Opens',
                                        hintText: '08:00',
                                      ),
                                      onChanged: (value) =>
                                          dayHours['open'] = value,
                                      validator: (value) => enabled
                                          ? _timeValidator(value)
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      enabled: enabled,
                                      initialValue: dayHours['close']
                                          .toString(),
                                      decoration: const InputDecoration(
                                        labelText: 'Closes',
                                        hintText: '17:00',
                                      ),
                                      onChanged: (value) =>
                                          dayHours['close'] = value,
                                      validator: (value) => enabled
                                          ? _timeValidator(value)
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                    const Divider(height: 26),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Assign doctors'),
                      subtitle: Text('${selectedDoctors.length} selected'),
                      children: [
                        if (doctors.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Create doctor accounts before assigning them.',
                            ),
                          )
                        else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: doctors
                                  .map((doctor) {
                                    final id = doctor['id'].toString();
                                    return FilterChip(
                                      label: Text(
                                        doctor['display_name'].toString(),
                                      ),
                                      selected: selectedDoctors.contains(id),
                                      onSelected: (selected) => setState(() {
                                        if (selected) {
                                          selectedDoctors.add(id);
                                        } else {
                                          selectedDoctors.remove(id);
                                          if (primaryDoctorId == id) {
                                            primaryDoctorId = null;
                                          }
                                        }
                                      }),
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                          ),
                        if (selectedDoctors.isNotEmpty) ...[
                          const SizedBox(height: 11),
                          DropdownButtonFormField<String?>(
                            initialValue: primaryDoctorId,
                            decoration: const InputDecoration(
                              labelText: 'Primary doctor (optional)',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('No primary doctor'),
                              ),
                              ...doctors
                                  .where(
                                    (doctor) => selectedDoctors.contains(
                                      doctor['id'].toString(),
                                    ),
                                  )
                                  .map(
                                    (doctor) => DropdownMenuItem<String?>(
                                      value: doctor['id'].toString(),
                                      child: Text(
                                        doctor['display_name'].toString(),
                                      ),
                                    ),
                                  ),
                            ],
                            onChanged: (value) =>
                                setState(() => primaryDoctorId = value),
                          ),
                        ],
                      ],
                    ),
                    const Divider(height: 26),
                    Text(
                      'Patient instructions and contact',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _field(contact, 'Service contact number'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: bookingUrl,
                            decoration: const InputDecoration(
                              labelText: 'Booking URL',
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) return null;
                              final uri = Uri.tryParse(text);
                              return uri != null &&
                                      {'http', 'https'}.contains(uri.scheme)
                                  ? null
                                  : 'Use a complete http(s) URL.';
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    _field(
                      preparation,
                      'Preparation instructions',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 11),
                    _field(tags, 'Search tags, separated by commas'),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final minimum = double.tryParse(feeMin.text.trim());
              final maximum = double.tryParse(feeMax.text.trim());
              if (minimum != null && maximum != null && maximum < minimum) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Maximum fee cannot be below minimum fee.'),
                  ),
                );
                return;
              }
              for (final day in days) {
                final dayHours = hours[day]!;
                if (dayHours['enabled'] == true &&
                    dayHours['open'].toString().compareTo(
                          dayHours['close'].toString(),
                        ) >=
                        0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${_pretty(day)} closing time must be later than opening time.',
                      ),
                    ),
                  );
                  return;
                }
              }
              final tagValues = _csv(tags.text);
              if (tagValues.length > 20) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Use no more than 20 service tags.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'department_id': departmentId,
                'category_id': categoryId,
                'service_name': name.text.trim(),
                'service_code': _nullIfEmpty(code.text),
                'description': description.text.trim(),
                'availability_status': status,
                'operating_hours': hours,
                'delivery_modes': deliveryModes.toList(growable: false),
                'appointment_required': appointmentRequired,
                'accepts_walk_ins': acceptsWalkIns,
                'fee_min': minimum,
                'fee_max': maximum,
                'fee_notes': _nullIfEmpty(feeNotes.text),
                'contact_number': _nullIfEmpty(contact.text),
                'booking_url': _nullIfEmpty(bookingUrl.text),
                'preparation_instructions': _nullIfEmpty(preparation.text),
                'tags': tagValues,
                'doctor_ids': selectedDoctors.toList(growable: false),
                'primary_doctor_id': primaryDoctorId,
              });
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save offering'),
          ),
        ],
      ),
    ),
  );
}

Future<JsonMap?> _showInventoryDialog(
  BuildContext context, {
  required String kind,
  JsonMap? initial,
  required List<JsonMap> departments,
}) {
  final room = kind == 'room';
  final formKey = GlobalKey<FormState>();
  final typeKey = room ? 'room_type' : 'bed_type';
  final totalKey = room ? 'total_rooms' : 'total_beds';
  final availableKey = room ? 'available_rooms' : 'available_beds';
  final occupiedKey = room ? 'occupied_rooms' : 'occupied_beds';
  final type = TextEditingController(text: initial?[typeKey]?.toString());
  final total = TextEditingController(
    text: initial?[totalKey]?.toString() ?? '0',
  );
  final available = TextEditingController(
    text: initial?[availableKey]?.toString() ?? '0',
  );
  final occupied = TextEditingController(
    text: initial?[occupiedKey]?.toString() ?? '0',
  );
  String? departmentId = initial?['department_id']?.toString();
  var status = initial?['status']?.toString() ?? 'available';
  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('${initial == null ? 'Add' : 'Edit'} $kind availability'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _requiredField(type, '${_pretty(kind)} type'),
                if (!room) ...[
                  const SizedBox(height: 11),
                  DropdownButtonFormField<String?>(
                    initialValue: departmentId,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No department'),
                      ),
                      ...departments.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item['id'].toString(),
                          child: Text(item['department_name'].toString()),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => departmentId = value),
                  ),
                ],
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(child: _numberField(total, 'Total')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(available, 'Available')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(occupied, 'Occupied')),
                  ],
                ),
                if (room) ...[
                  const SizedBox(height: 11),
                  _enumField('Status', status, const [
                    'available',
                    'limited',
                    'unavailable',
                  ], (value) => setState(() => status = value)),
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
              if (!formKey.currentState!.validate()) return;
              final totalValue = int.parse(total.text);
              final availableValue = int.parse(available.text);
              final occupiedValue = int.parse(occupied.text);
              if (availableValue + occupiedValue > totalValue) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Available plus occupied cannot exceed total.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                typeKey: type.text.trim(),
                totalKey: totalValue,
                availableKey: availableValue,
                occupiedKey: occupiedValue,
                if (room) 'status': status else 'department_id': departmentId,
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<JsonMap?> _showEmergencyDialog(
  BuildContext context, {
  JsonMap? initial,
}) {
  final formKey = GlobalKey<FormState>();
  final beds = TextEditingController(
    text: initial?['available_beds']?.toString() ?? '0',
  );
  final patients = TextEditingController(
    text: initial?['current_patient_count']?.toString() ?? '0',
  );
  final capacity = TextEditingController(
    text: initial?['maximum_capacity']?.toString() ?? '0',
  );
  var status = initial?['status']?.toString() ?? 'available';
  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Update emergency room'),
        content: SizedBox(
          width: 500,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _enumField('ER status', status, const [
                  'available',
                  'limited',
                  'full',
                  'temporarily_closed',
                ], (value) => setState(() => status = value)),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(child: _numberField(beds, 'Available beds')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(patients, 'Current patients')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(capacity, 'Capacity')),
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
              if (!formKey.currentState!.validate()) return;
              final patientCount = int.parse(patients.text);
              final maximum = int.parse(capacity.text);
              if (maximum > 0 && patientCount > maximum) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Current patients cannot exceed capacity.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'status': status,
                'available_beds': int.parse(beds.text),
                'current_patient_count': patientCount,
                'maximum_capacity': maximum,
              });
            },
            child: const Text('Publish status'),
          ),
        ],
      ),
    ),
  );
}

Future<JsonMap?> _showFacilityDialog(BuildContext context, {JsonMap? initial}) {
  final formKey = GlobalKey<FormState>();
  final units = TextEditingController(
    text: initial?['available_units']?.toString() ?? '0',
  );
  final notes = TextEditingController(text: initial?['notes']?.toString());
  var type = initial?['facility_type']?.toString() ?? 'icu';
  var status = initial?['status']?.toString() ?? 'available';
  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('${initial == null ? 'Add' : 'Edit'} facility'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _enumField('Facility', type, const [
                  'icu',
                  'operating_room',
                  'ambulance',
                  'laboratory',
                  'pharmacy',
                ], (value) => setState(() => type = value)),
                const SizedBox(height: 11),
                _enumField('Status', status, const [
                  'available',
                  'limited',
                  'unavailable',
                ], (value) => setState(() => status = value)),
                const SizedBox(height: 11),
                _numberField(units, 'Available units'),
                const SizedBox(height: 11),
                _field(notes, 'Notes', maxLines: 2),
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
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, {
                'facility_type': type,
                'status': status,
                'available_units': int.parse(units.text),
                'notes': _nullIfEmpty(notes.text),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<JsonMap?> _showDoctorDialog(
  BuildContext context, {
  required List<JsonMap> departments,
}) async {
  final account = await _showAccountDialog(
    context,
    title: 'Create doctor account',
  );
  if (account == null || !context.mounted) return null;
  final formKey = GlobalKey<FormState>();
  final specialization = TextEditingController();
  final license = TextEditingController();
  final fee = TextEditingController();
  final biography = TextEditingController();
  String? departmentId;
  final details = await showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Doctor professional details'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _requiredField(specialization, 'Specialization'),
                const SizedBox(height: 11),
                _requiredField(license, 'PRC license number'),
                const SizedBox(height: 11),
                DropdownButtonFormField<String?>(
                  initialValue: departmentId,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No department'),
                    ),
                    ...departments.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item['id'].toString(),
                        child: Text(item['department_name'].toString()),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => departmentId = value),
                ),
                const SizedBox(height: 11),
                TextFormField(
                  controller: fee,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Consultation fee (optional)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final parsed = double.tryParse(value);
                    return parsed == null || parsed < 0
                        ? 'Enter a valid amount.'
                        : null;
                  },
                ),
                const SizedBox(height: 11),
                _field(biography, 'Biography', maxLines: 3),
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
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, {
                'specialization': specialization.text.trim(),
                'license_number': license.text.trim(),
                'department_id': departmentId,
                'consultation_fee': double.tryParse(fee.text.trim()),
                'biography': _nullIfEmpty(biography.text),
              });
            },
            child: const Text('Create doctor'),
          ),
        ],
      ),
    ),
  );
  return details == null ? null : {...account, ...details};
}

class _DoctorSchedulesDialog extends StatefulWidget {
  const _DoctorSchedulesDialog({
    required this.repository,
    required this.doctor,
  });

  final AdminRepository repository;
  final JsonMap doctor;

  @override
  State<_DoctorSchedulesDialog> createState() => _DoctorSchedulesDialogState();
}

class _DoctorSchedulesDialogState extends State<_DoctorSchedulesDialog> {
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  List<JsonMap> _schedules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schedules = await widget.repository.listDoctorSchedules(
        widget.doctor['id'].toString(),
      );
      if (!mounted) return;
      setState(() {
        _schedules = schedules;
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.doctor['display_name']} · Consultation schedule'),
    content: SizedBox(
      width: 690,
      height: 480,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorPanel(error: _error!, onRetry: _load)
          : _schedules.isEmpty
          ? const _EmptyCard(
              message: 'No consultation hours have been published.',
            )
          : ListView.separated(
              itemCount: _schedules.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final schedule = _schedules[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: schedule['is_active'] == true
                        ? AppColors.mint
                        : const Color(0xFFFFE8E6),
                    child: const Icon(Icons.schedule_outlined),
                  ),
                  title: Text(
                    '${_dayName(schedule['day_of_week'])} · ${_shortTime(schedule['starts_at'])}–${_shortTime(schedule['ends_at'])}',
                  ),
                  subtitle: Text(
                    '${_pretty(schedule['consultation_type'].toString())} · ${schedule['slot_minutes']} minute slots · ${schedule['is_active'] == true ? 'Active' : 'Inactive'}',
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Edit schedule',
                        onPressed: _saving
                            ? null
                            : () => _editSchedule(schedule),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete schedule',
                        onPressed: _saving
                            ? null
                            : () => _deleteSchedule(schedule),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : () => _editSchedule(),
        icon: const Icon(Icons.add),
        label: const Text('Add hours'),
      ),
    ],
  );

  Future<void> _editSchedule([JsonMap? initial]) async {
    final values = await _showScheduleDialog(context, initial: initial);
    if (values == null) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveDoctorSchedule(
        id: initial?['id']?.toString(),
        values: {...values, 'doctor_id': widget.doctor['id'].toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Schedule saved.')));
      await _load();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSchedule(JsonMap schedule) async {
    final confirmed = await _confirm(
      context,
      'Delete this consultation schedule?',
      '${_dayName(schedule['day_of_week'])}, ${_shortTime(schedule['starts_at'])}–${_shortTime(schedule['ends_at'])}',
      destructive: true,
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      await widget.repository.deleteRecord(
        'doctor_schedules',
        schedule['id'].toString(),
      );
      await _load();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

Future<JsonMap?> _showScheduleDialog(BuildContext context, {JsonMap? initial}) {
  final formKey = GlobalKey<FormState>();
  var day = _toInt(initial?['day_of_week'], fallback: 1);
  final startsAt = TextEditingController(
    text: _shortTime(initial?['starts_at'] ?? '09:00'),
  );
  final endsAt = TextEditingController(
    text: _shortTime(initial?['ends_at'] ?? '17:00'),
  );
  final slotMinutes = TextEditingController(
    text: initial?['slot_minutes']?.toString() ?? '30',
  );
  var consultationType = initial?['consultation_type']?.toString() ?? 'online';
  var active = initial?['is_active'] as bool? ?? true;
  return showDialog<JsonMap>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('${initial == null ? 'Add' : 'Edit'} consultation hours'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: day,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: List.generate(
                    7,
                    (index) => DropdownMenuItem(
                      value: index,
                      child: Text(_dayName(index)),
                    ),
                  ),
                  onChanged: (value) => setState(() => day = value ?? 1),
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: startsAt,
                        decoration: const InputDecoration(
                          labelText: 'Starts',
                          hintText: '09:00',
                        ),
                        validator: _timeValidator,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: endsAt,
                        decoration: const InputDecoration(
                          labelText: 'Ends',
                          hintText: '17:00',
                        ),
                        validator: _timeValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: _enumField(
                        'Consultation type',
                        consultationType,
                        const [
                          'face_to_face',
                          'online',
                          'emergency',
                          'guest_online',
                        ],
                        (value) => setState(() => consultationType = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: slotMinutes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Slot minutes',
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value ?? '');
                          return parsed == null || parsed < 10 || parsed > 240
                              ? 'Use 10–240.'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Published and active'),
                  value: active,
                  onChanged: (value) => setState(() => active = value),
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
              if (!formKey.currentState!.validate()) return;
              if (startsAt.text.compareTo(endsAt.text) >= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('End time must be later than start time.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'day_of_week': day,
                'starts_at': startsAt.text.trim(),
                'ends_at': endsAt.text.trim(),
                'consultation_type': consultationType,
                'slot_minutes': int.parse(slotMinutes.text),
                'is_active': active,
              });
            },
            child: const Text('Save schedule'),
          ),
        ],
      ),
    ),
  );
}

TextFormField _requiredField(TextEditingController controller, String label) =>
    TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          value == null || value.trim().isEmpty ? '$label is required.' : null,
    );

TextFormField _field(
  TextEditingController controller,
  String label, {
  int maxLines = 1,
  TextInputType? keyboardType,
}) => TextFormField(
  controller: controller,
  maxLines: maxLines,
  keyboardType: keyboardType,
  decoration: InputDecoration(labelText: label),
);

TextFormField _numberField(TextEditingController controller, String label) =>
    TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final parsed = int.tryParse(value ?? '');
        return parsed == null || parsed < 0 ? 'Use 0 or more.' : null;
      },
    );

TextFormField _moneyField(TextEditingController controller, String label) =>
    TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, prefixText: '₱ '),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return null;
        final parsed = double.tryParse(text);
        return parsed == null || parsed < 0 ? 'Enter a valid amount.' : null;
      },
    );

DropdownButtonFormField<String> _enumField(
  String label,
  String value,
  List<String> values,
  ValueChanged<String> onChanged,
) => DropdownButtonFormField<String>(
  initialValue: value,
  decoration: InputDecoration(labelText: label),
  items: values
      .map((item) => DropdownMenuItem(value: item, child: Text(_pretty(item))))
      .toList(growable: false),
  onChanged: (newValue) {
    if (newValue != null) onChanged(newValue);
  },
);

String? _emailValidator(String? value) {
  final email = value?.trim() ?? '';
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
      ? null
      : 'Enter a valid email address.';
}

String? _timeValidator(String? value) {
  final text = value?.trim() ?? '';
  return RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(text)
      ? null
      : 'Use 24-hour HH:mm.';
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message, {
  bool destructive = false,
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
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(destructive ? 'Delete' : 'Confirm'),
          ),
        ],
      ),
    ) ??
    false;

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(_cleanError(error))));
}

String _cleanError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

String? _relationValue(dynamic relation, String key) {
  if (relation is Map) return relation[key]?.toString();
  if (relation is List && relation.isNotEmpty && relation.first is Map) {
    return (relation.first as Map)[key]?.toString();
  }
  return null;
}

String _pretty(String value) => value
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');

List<String> _csv(String value) => value
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList(growable: false);

String? _feeLabel(dynamic minimum, dynamic maximum) {
  final min = double.tryParse(minimum?.toString() ?? '');
  final max = double.tryParse(maximum?.toString() ?? '');
  if (min == null && max == null) return null;
  if (min != null && max != null && min != max) {
    return '₱${_amount(min)}–₱${_amount(max)}';
  }
  return '₱${_amount(min ?? max!)}';
}

String _amount(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

int _toInt(dynamic value, {int fallback = 0}) =>
    int.tryParse(value?.toString() ?? '') ?? fallback;

String _dayName(dynamic value) {
  const days = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];
  final index = _toInt(value);
  return index >= 0 && index < days.length ? days[index] : 'Unknown day';
}

String _shortTime(dynamic value) {
  final text = value?.toString() ?? '';
  return text.length >= 5 ? text.substring(0, 5) : text;
}

String _shortDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'unknown date';
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String? _nullIfEmpty(String value) =>
    value.trim().isEmpty ? null : value.trim();
