import 'dart:typed_data';

import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/admin_repository.dart';
import 'package:care_navigator_ph/src/repositories/care_repository.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:care_navigator_ph/src/routing/root_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

void main() {
  const relationship = ClinicalRelationship(
    patientId: 'patient-id',
    patientLabel: 'Maria Santos',
    consultationId: 'consultation-id',
    consultationLabel: 'Follow-up · scheduled',
  );
  final careRepository = _DialogCareRepository(relationship);
  final adminRepository = _DialogAdminRepository();

  final cases = <_PrimaryActionCase>[
    const _PrimaryActionCase(
      role: UserRole.doctor,
      section: 'schedule',
      button: 'Add slot',
      dialogTitle: 'Publish schedule slot',
    ),
    const _PrimaryActionCase(
      role: UserRole.doctor,
      section: 'patients',
      button: 'Register patient',
      dialogTitle: 'Register patient',
    ),
    const _PrimaryActionCase(
      role: UserRole.doctor,
      section: 'prescriptions',
      button: 'Issue prescription',
      dialogTitle: 'Issue prescription',
    ),
    const _PrimaryActionCase(
      role: UserRole.doctor,
      section: 'laboratory',
      button: 'Request test',
      dialogTitle: 'Request laboratory test',
    ),
    const _PrimaryActionCase(
      role: UserRole.doctor,
      section: 'results-review',
      button: 'Upload diagnostic result',
      dialogTitle: 'Upload diagnostic result',
    ),
    const _PrimaryActionCase(
      role: UserRole.hospitalAdministrator,
      section: 'availability',
      button: 'Add facility status',
      dialogTitle: 'Add facility status',
    ),
    const _PrimaryActionCase(
      role: UserRole.hospitalAdministrator,
      section: 'beds',
      button: 'Add bed type',
      dialogTitle: 'Add bed type',
    ),
    const _PrimaryActionCase(
      role: UserRole.hospitalAdministrator,
      section: 'rooms',
      button: 'Add room type',
      dialogTitle: 'Add room type',
    ),
    const _PrimaryActionCase(
      role: UserRole.hospitalAdministrator,
      section: 'emergency-room',
      button: 'Add ER capacity',
      dialogTitle: 'Confirm emergency capacity',
    ),
    const _PrimaryActionCase(
      role: UserRole.hospitalAdministrator,
      section: 'staff',
      button: 'Add doctor',
      dialogTitle: 'Create doctor account',
    ),
    const _PrimaryActionCase(
      role: UserRole.hospitalAdministrator,
      section: 'services',
      button: 'Add service',
      dialogTitle: 'Add service',
    ),
    const _PrimaryActionCase(
      role: UserRole.hospitalAdministrator,
      section: 'departments',
      button: 'Add department',
      dialogTitle: 'Add department',
    ),
    const _PrimaryActionCase(
      role: UserRole.superAdministrator,
      section: 'hospitals',
      button: 'Add hospital',
      dialogTitle: 'Add hospital',
    ),
    const _PrimaryActionCase(
      role: UserRole.superAdministrator,
      section: 'permissions',
      button: 'Add permission',
      dialogTitle: 'Add permission',
    ),
    const _PrimaryActionCase(
      role: UserRole.superAdministrator,
      section: 'settings',
      button: 'Add setting',
      dialogTitle: 'Add setting',
    ),
    const _PrimaryActionCase(
      role: UserRole.superAdministrator,
      section: 'maintenance',
      button: 'Schedule maintenance',
      dialogTitle: 'Schedule maintenance',
    ),
  ];

  for (final actionCase in cases) {
    testWidgets('${actionCase.button} opens its operational dialog', (
      tester,
    ) async {
      final request = (
        role: actionCase.role,
        section: actionCase.section,
        itemId: null as String?,
      );
      final container = ProviderContainer(
        overrides: [
          workspaceSnapshotProvider(request).overrideWith(
            (ref) async => WorkspaceSnapshot(
              title: actionCase.dialogTitle,
              description: 'Operational action test.',
              items: const [],
              loadedAt: DateTime(2026, 8, 15),
            ),
          ),
          careRepositoryProvider.overrideWithValue(careRepository),
          adminRepositoryProvider.overrideWithValue(adminRepository),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            home: Scaffold(
              body: LiveWorkspaceView(
                role: actionCase.role,
                section: actionCase.section,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, actionCase.button));
      await tester.pumpAndSettle();
      expect(find.text(actionCase.dialogTitle), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  testWidgets('prescription flow scans first and exposes a reviewable order', (
    tester,
  ) async {
    const request = (
      role: UserRole.doctor,
      section: 'prescriptions',
      itemId: null as String?,
    );
    final container = ProviderContainer(
      overrides: [
        workspaceSnapshotProvider(request).overrideWith(
          (ref) async => WorkspaceSnapshot(
            title: 'Prescriptions',
            description: 'Structured prescription test.',
            items: const [],
            loadedAt: DateTime(2026, 8, 23),
          ),
        ),
        careRepositoryProvider.overrideWithValue(careRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(
            body: LiveWorkspaceView(
              role: UserRole.doctor,
              section: 'prescriptions',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Issue prescription'));
    await tester.pumpAndSettle();

    expect(find.text('Attach and scan first (optional)'), findsOneWidget);
    expect(find.text('Attach and scan file'), findsOneWidget);
    expect(find.text('Diagnosis or reason for medication'), findsOneWidget);
    expect(find.text('Medication form and strength'), findsOneWidget);
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Exact dose per intake'), findsOneWidget);
    expect(find.text('Total quantity to dispense'), findsOneWidget);
    expect(find.text('Number of refills'), findsOneWidget);
    expect(find.text('Take as needed (PRN)'), findsOneWidget);
    expect(find.text('Dr. Test Prescriber'), findsOneWidget);
    expect(find.text('Apply my electronic signature'), findsOneWidget);
    expect(find.text('Preview prescription'), findsOneWidget);

    Finder field(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(field('Diagnosis or reason for medication'), 'Pain');
    await tester.enterText(field('Medication name'), 'Paracetamol');
    await tester.enterText(
      field('Medication form and strength'),
      '500 mg tablet',
    );
    await tester.enterText(field('Route'), 'Oral');
    await tester.enterText(field('Exact dose per intake'), '1 tablet');
    await tester.enterText(field('Frequency'), 'Every 6 hours');
    await tester.enterText(field('Duration'), '3 days');
    await tester.enterText(field('Total quantity to dispense'), '12 tablets');
    final signature = find.widgetWithText(
      CheckboxListTile,
      'Apply my electronic signature',
    );
    await tester.ensureVisible(signature);
    await tester.tap(signature);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Preview prescription'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm prescription'), findsOneWidget);
    expect(find.text('No refills'), findsOneWidget);
    expect(find.text('Confirm & issue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prescription dialog remains usable on a short mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const request = (
      role: UserRole.doctor,
      section: 'prescriptions',
      itemId: null as String?,
    );
    final container = ProviderContainer(
      overrides: [
        workspaceSnapshotProvider(request).overrideWith(
          (ref) async => WorkspaceSnapshot(
            title: 'Prescriptions',
            description: 'Mobile dialog test.',
            items: const [],
            loadedAt: DateTime(2026, 8, 23),
          ),
        ),
        careRepositoryProvider.overrideWithValue(careRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(
            body: LiveWorkspaceView(
              role: UserRole.doctor,
              section: 'prescriptions',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Issue prescription'));
    await tester.pumpAndSettle();

    expect(find.text('Issue prescription'), findsWidgets);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostic result scan prefills and submits editable fields', (
    tester,
  ) async {
    final repository = _DialogCareRepository(relationship);
    final previousSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _FakeFileSelector();
    addTearDown(() => FileSelectorPlatform.instance = previousSelector);
    const request = (
      role: UserRole.doctor,
      section: 'results-review',
      itemId: null as String?,
    );
    final container = ProviderContainer(
      overrides: [
        workspaceSnapshotProvider(request).overrideWith(
          (ref) async => WorkspaceSnapshot(
            title: 'Results Review',
            description: 'Lab upload test.',
            items: const [],
            loadedAt: DateTime(2026, 8, 23),
          ),
        ),
        careRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(
            body: LiveWorkspaceView(
              role: UserRole.doctor,
              section: 'results-review',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Upload diagnostic result').last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Result category'), findsOneWidget);
    expect(find.text('Result file and AI autofill'), findsOneWidget);
    final scanFile = find.widgetWithText(
      OutlinedButton,
      'Attach and scan result file',
    );
    await tester.ensureVisible(scanFile);
    await tester.tap(scanFile);
    await tester.pumpAndSettle();

    expect(find.text('Change and rescan result file'), findsOneWidget);
    expect(
      find.text(
        'Scan complete. Review every autofilled value before uploading.',
      ),
      findsOneWidget,
    );
    expect(find.text('CT scan'), findsOneWidget);
    expect(find.text('CT scan of chest without contrast'), findsOneWidget);
    expect(find.text('Care Navigator Medical Center'), findsOneWidget);
    expect(find.text('Dr. Juan Dela Cruz'), findsOneWidget);
    expect(find.text('No acute findings.'), findsOneWidget);
    expect(find.text('Uploaded from the facility portal.'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Upload diagnostic result').last,
    );
    await tester.pumpAndSettle();

    expect(repository.uploadedPatientId, relationship.patientId);
    expect(repository.uploadedReferenceId, relationship.consultationId);
    expect(repository.uploadedDocumentType, 'diagnostic_result');
    expect(repository.uploadedFileName, 'lab-result.pdf');
    expect(repository.uploadedTitle, 'CT scan of chest without contrast');
    expect(repository.uploadedDiagnosticResult?.category, 'ct_scan');
    expect(
      repository.uploadedDiagnosticResult?.testProcedureName,
      'CT scan of chest without contrast',
    );
    expect(
      repository.uploadedDiagnosticResult?.facility,
      'Care Navigator Medical Center',
    );
    expect(
      repository.uploadedDiagnosticResult?.requestingDoctor,
      'Dr. Juan Dela Cruz',
    );
    expect(
      repository.uploadedDiagnosticResult?.findingsImpression,
      'No acute findings.',
    );
    expect(
      repository.uploadedDiagnosticResult?.notes,
      'Uploaded from the facility portal.',
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing patient mode searches the global identity directory', (
    tester,
  ) async {
    final searchableRepository = _DialogCareRepository(
      relationship,
      searchResults: const [
        ExistingPatientMatch(
          patientId: 'patient-maria-1',
          displayName: 'Maria Santos',
          email: 'maria.one@example.com',
        ),
        ExistingPatientMatch(
          patientId: 'patient-maria-2',
          displayName: 'Maria Santos',
          email: 'maria.two@example.com',
        ),
      ],
    );
    const request = (
      role: UserRole.doctor,
      section: 'patients',
      itemId: null as String?,
    );
    final container = ProviderContainer(
      overrides: [
        workspaceSnapshotProvider(request).overrideWith(
          (ref) async => WorkspaceSnapshot(
            title: 'Patients',
            description: 'Patient search test.',
            items: const [],
            loadedAt: DateTime(2026, 8, 23),
          ),
        ),
        careRepositoryProvider.overrideWithValue(searchableRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(
            body: LiveWorkspaceView(role: UserRole.doctor, section: 'patients'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Register patient'));
    await tester.pumpAndSettle();
    expect(find.text('Existing patient'), findsOneWidget);

    await tester.tap(find.text('Existing patient'));
    await tester.pumpAndSettle();
    expect(find.text('Patient name or email address'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Patient name or email address'),
      'Maria Santos',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(searchableRepository.lastSearchQuery, 'Maria Santos');
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Maria Santos'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('maria.one@example.com'), findsOneWidget);
    expect(find.text('maria.two@example.com'), findsOneWidget);

    final secondPatient = find.ancestor(
      of: find.text('maria.two@example.com'),
      matching: find.byType(ListTile),
    );
    await tester.ensureVisible(secondPatient);
    await tester.tap(secondPatient);
    final sendRequest = find.widgetWithText(FilledButton, 'Send request');
    await tester.ensureVisible(sendRequest);
    await tester.tap(sendRequest);
    await tester.pumpAndSettle();
    expect(searchableRepository.linkedPatientId, 'patient-maria-2');
  });
}

class _PrimaryActionCase {
  const _PrimaryActionCase({
    required this.role,
    required this.section,
    required this.button,
    required this.dialogTitle,
  });

  final UserRole role;
  final String section;
  final String button;
  final String dialogTitle;
}

class _DialogCareRepository implements CareRepository {
  _DialogCareRepository(this.relationship, {this.searchResults = const []});

  final ClinicalRelationship relationship;
  final List<ExistingPatientMatch> searchResults;
  String? lastSearchQuery;
  String? linkedPatientId;
  String? uploadedPatientId;
  String? uploadedReferenceId;
  String? uploadedDocumentType;
  String? uploadedFileName;
  String? uploadedTitle;
  DiagnosticResultDetails? uploadedDiagnosticResult;

  @override
  Future<List<ClinicalRelationship>> listClinicalRelationships() async => [
    relationship,
  ];

  @override
  Future<PrescriberDetails> currentPrescriberDetails() async =>
      const PrescriberDetails(
        name: 'Dr. Test Prescriber',
        licenseNumber: 'PRC-12345',
        specialization: 'Internal Medicine',
      );

  @override
  Future<DiagnosticResultScanDraft> extractDiagnosticResultFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  }) async => DiagnosticResultScanDraft(
    category: 'ct_scan',
    testProcedureName: 'CT scan of chest without contrast',
    performedOrCollectedDate: DateTime(2026, 8, 20),
    resultDate: DateTime(2026, 8, 21),
    facility: 'Care Navigator Medical Center',
    requestingDoctor: 'Dr. Juan Dela Cruz',
    findingsImpression: 'No acute findings.',
    notes: 'Uploaded from the facility portal.',
  );

  @override
  Future<List<ExistingPatientMatch>> searchExistingPatients(
    String query,
  ) async {
    lastSearchQuery = query;
    return searchResults;
  }

  @override
  Future<void> linkExistingPatient(String patientId) async {
    linkedPatientId = patientId;
  }

  @override
  Future<void> uploadMedicalFile({
    required String patientId,
    required String fileName,
    required String title,
    required String documentType,
    required List<int> bytes,
    String? referenceId,
    String? referenceType,
    DiagnosticResultDetails? diagnosticResult,
  }) async {
    uploadedPatientId = patientId;
    uploadedReferenceId = referenceId;
    uploadedDocumentType = documentType;
    uploadedFileName = fileName;
    uploadedTitle = title;
    uploadedDiagnosticResult = diagnosticResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFileSelector extends FileSelectorPlatform {
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile.fromData(
    Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37]),
    path: 'lab-result.pdf',
    name: 'lab-result.pdf',
    mimeType: 'application/pdf',
  );
}

class _DialogAdminRepository implements AdminRepository {
  @override
  Future<HospitalAdminContext> loadHospitalAdminContext() async =>
      const HospitalAdminContext(
        hospitalId: 'hospital-id',
        departments: [
          HospitalDepartmentOption(
            id: 'department-id',
            name: 'Internal Medicine',
          ),
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
