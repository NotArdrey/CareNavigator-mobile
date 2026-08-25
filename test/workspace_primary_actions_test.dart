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
    expect(find.text('Medication 1'), findsOneWidget);
    expect(find.text('Add another medication'), findsOneWidget);
    expect(find.text('Dr. Test Prescriber'), findsOneWidget);
    expect(find.text('Apply my electronic signature'), findsNothing);
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
    await tester.tap(find.widgetWithText(FilledButton, 'Preview prescription'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm prescription'), findsOneWidget);
    expect(find.text('No refills'), findsOneWidget);
    expect(find.text('Confirm & issue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prescription scan prefills every detected medication', (
    tester,
  ) async {
    final repository = _DialogCareRepository(
      relationship,
      prescriptionScans: const [
        PrescriptionScanDraft(
          diagnosisReason: 'Upper respiratory infection',
          medicationName: 'Amoxicillin',
          medicationFormStrength: '500 mg capsule',
          route: 'Oral',
          exactDose: '1 capsule',
          frequency: 'Every 8 hours',
          duration: '7 days',
          quantityToDispense: '21 capsules',
          refills: 0,
        ),
        PrescriptionScanDraft(
          diagnosisReason: 'Upper respiratory infection',
          medicationName: 'Paracetamol',
          medicationFormStrength: '500 mg tablet',
          route: 'Oral',
          exactDose: '1 tablet',
          frequency: 'Every 6 hours as needed',
          duration: '3 days',
          quantityToDispense: '12 tablets',
          refills: 0,
          isPrn: true,
          prnReason: 'Fever',
          maximumDailyDose: '4 tablets in 24 hours',
        ),
      ],
    );
    final previousSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _FakeFileSelector();
    addTearDown(() => FileSelectorPlatform.instance = previousSelector);
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
            description: 'Multiple medication scan test.',
            items: const [],
            loadedAt: DateTime(2026, 8, 26),
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
              section: 'prescriptions',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Issue prescription'));
    await tester.pumpAndSettle();
    final scanButton = find.widgetWithText(
      OutlinedButton,
      'Attach and scan file',
    );
    await tester.ensureVisible(scanButton);
    await tester.tap(scanButton);
    await tester.pumpAndSettle();

    expect(find.text('Medication 1'), findsOneWidget);
    expect(find.text('Medication 2'), findsOneWidget);
    expect(find.text('Medication name'), findsNWidgets(2));
    expect(find.text('Take as needed (PRN)'), findsNWidgets(2));
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('Paracetamol'), findsOneWidget);
    expect(find.text('PRN reason'), findsOneWidget);
    expect(find.text('Fever'), findsOneWidget);
    expect(
      find.text('Scan complete. Review every autofilled value before issuing.'),
      findsOneWidget,
    );
    final previewButton = find.widgetWithText(
      FilledButton,
      'Preview prescription',
    );
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();
    expect(find.text('Confirm prescription'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm & issue'));
    await tester.pumpAndSettle();
    expect(repository.createdMedicationNames, ['Amoxicillin', 'Paracetamol']);
    expect(repository.createdPrescriptionAttachments, [
      'prescription.pdf',
      null,
    ]);
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
    expect(find.text('Result category'), findsNothing);
    expect(find.text('Result file and AI autofill'), findsOneWidget);
    final scanFile = find.widgetWithText(
      OutlinedButton,
      'Attach and scan result files',
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
    expect(find.text('Result category'), findsOneWidget);
    expect(find.text('CT scan'), findsOneWidget);
    expect(find.text('CT scan of chest without contrast'), findsOneWidget);
    expect(find.text('Care Navigator Medical Center'), findsOneWidget);
    expect(find.text('Dr. Juan Dela Cruz'), findsOneWidget);
    expect(find.text('No acute findings.'), findsOneWidget);
    expect(find.text('Technical summary'), findsOneWidget);
    expect(find.text('Patient-friendly summary'), findsOneWidget);
    expect(find.text('Uploaded from the facility portal.'), findsNothing);
    expect(find.text('Needs verification (optional)'), findsNothing);
    expect(find.text('Other report notes (optional)'), findsNothing);
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

  testWidgets('diagnostic upload keeps multiple reports separately editable', (
    tester,
  ) async {
    final repository = _DialogCareRepository(
      relationship,
      diagnosticScans: [
        const DiagnosticResultScanDraft(
          sourceFileName: 'cbc.pdf',
          patientName: 'Maria Santos',
          category: 'laboratory',
          testProcedureName: 'Complete Blood Count',
          resultDetails: 'WBC | 6.2 | 10^9/L | 4-11 | within_range',
          technicalSummary: 'WBC is within the report-stated range.',
          patientFriendlySummary:
              'Your WBC is within the range printed on this report.',
        ),
        const DiagnosticResultScanDraft(
          sourceFileName: 'chest-xray.png',
          patientName: 'Maria Santos',
          category: 'x_ray',
          testProcedureName: 'Chest X-ray',
          officialFindingsImpression: 'No focal airspace opacity.',
          technicalSummary: 'No acute report-stated abnormality.',
          patientFriendlySummary:
              'The report does not describe an acute abnormality.',
        ),
      ],
    );
    final previousSelector = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _FakeFileSelector(
      files: [_testXFile('cbc.pdf'), _testXFile('chest-xray.png', png: true)],
    );
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
            description: 'Multiple result upload test.',
            items: const [],
            loadedAt: DateTime(2026, 8, 25),
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
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Attach and scan result files'),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 reports detected.'), findsOneWidget);
    expect(find.text('Report 1 of 2'), findsOneWidget);
    expect(find.text('Report 2 of 2'), findsOneWidget);
    expect(find.text('Complete Blood Count'), findsOneWidget);
    expect(find.text('Chest X-ray'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Upload diagnostic result').last,
    );
    await tester.pumpAndSettle();
    expect(repository.uploadedTitles, ['Complete Blood Count', 'Chest X-ray']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'diagnostic upload omits identity warning and dates undated results',
    (tester) async {
      final repository = _DialogCareRepository(
        relationship,
        diagnosticScans: const [
          DiagnosticResultScanDraft(
            sourceFileName: 'result.pdf',
            patientName: 'Ana Reyes',
            category: 'laboratory',
            testProcedureName: 'Complete Blood Count',
          ),
        ],
      );
      final previousSelector = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _FakeFileSelector(
        files: [_testXFile('result.pdf')],
      );
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
              description: 'Patient match test.',
              items: const [],
              loadedAt: DateTime(2026, 8, 25),
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
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Attach and scan result files'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Patient mismatch'), findsNothing);
      expect(
        find.textContaining('Patient identity needs verification'),
        findsNothing,
      );
      expect(find.text('Confirmed result date'), findsOneWidget);
      expect(find.text('Needs verification (optional)'), findsNothing);
      expect(find.text('Other report notes (optional)'), findsNothing);

      final uploadDay = DateUtils.dateOnly(DateTime.now());
      await tester.tap(
        find.widgetWithText(FilledButton, 'Upload diagnostic result').last,
      );
      await tester.pumpAndSettle();
      expect(repository.uploadedTitles, ['Complete Blood Count']);
      expect(repository.uploadedDiagnosticResult?.resultDate, uploadDay);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
  _DialogCareRepository(
    this.relationship, {
    this.searchResults = const [],
    this.diagnosticScans,
    this.prescriptionScans,
  });

  final ClinicalRelationship relationship;
  final List<ExistingPatientMatch> searchResults;
  final List<DiagnosticResultScanDraft>? diagnosticScans;
  final List<PrescriptionScanDraft>? prescriptionScans;
  String? lastSearchQuery;
  String? linkedPatientId;
  String? uploadedPatientId;
  String? uploadedReferenceId;
  String? uploadedDocumentType;
  String? uploadedFileName;
  String? uploadedTitle;
  DiagnosticResultDetails? uploadedDiagnosticResult;
  final List<String> uploadedTitles = [];
  final List<String> createdMedicationNames = [];
  final List<String?> createdPrescriptionAttachments = [];

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
  Future<PrescriptionScanDraft> extractPrescriptionFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  }) async =>
      (await extractPrescriptionsFromAttachment(attachment: attachment)).first;

  @override
  Future<List<PrescriptionScanDraft>> extractPrescriptionsFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  }) async =>
      prescriptionScans ??
      const [
        PrescriptionScanDraft(
          diagnosisReason: 'Pain',
          medicationName: 'Paracetamol',
          medicationFormStrength: '500 mg tablet',
          route: 'Oral',
          exactDose: '1 tablet',
          frequency: 'Every 6 hours',
          duration: '3 days',
          quantityToDispense: '12 tablets',
          refills: 0,
        ),
      ];

  @override
  Future<void> createPrescription({
    required ClinicalRelationship relationship,
    required String medicationName,
    required String dosage,
    required String frequency,
    required String duration,
    String? diagnosisReason,
    String? medicationFormStrength,
    String? route,
    String? exactDose,
    String? quantityToDispense,
    int refills = 0,
    DateTime? startDate,
    DateTime? endDate,
    bool isPrn = false,
    String? prnReason,
    String? maximumDailyDose,
    String? instructions,
    ({List<int> bytes, String name})? attachment,
  }) async {
    createdMedicationNames.add(medicationName);
    createdPrescriptionAttachments.add(attachment?.name);
  }

  @override
  Future<DiagnosticResultScanDraft> extractDiagnosticResultFromAttachment({
    required ({List<int> bytes, String name}) attachment,
  }) async => (await extractDiagnosticResultsFromAttachments(
    attachments: [attachment],
  )).single;

  @override
  Future<List<DiagnosticResultScanDraft>>
  extractDiagnosticResultsFromAttachments({
    required List<({List<int> bytes, String name})> attachments,
  }) async =>
      diagnosticScans ??
      [
        DiagnosticResultScanDraft(
          sourceFileName: attachments.first.name,
          patientName: 'Maria Santos',
          category: 'ct_scan',
          testProcedureName: 'CT scan of chest without contrast',
          performedOrCollectedDate: DateTime(2026, 8, 20),
          resultDate: DateTime(2026, 8, 21),
          facility: 'Care Navigator Medical Center',
          requestingDoctor: 'Dr. Juan Dela Cruz',
          findingsImpression: 'No acute findings.',
          notes: 'Uploaded from the facility portal.',
        ),
      ];

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
    uploadedTitles.add(title);
    uploadedDiagnosticResult = diagnosticResult;
  }

  @override
  Future<void> sendPrescriptionNotificationEmail({
    required ClinicalRelationship relationship,
    required List<PrescriptionNotificationMedication> medications,
    String? diagnosisReason,
  }) async {}

  @override
  Future<void> sendDailyMedicationReminderEmail({
    String? patientId,
    String slot = 'all',
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFileSelector extends FileSelectorPlatform {
  _FakeFileSelector({this.files});

  final List<XFile>? files;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => (files ?? [_testXFile('prescription.pdf')]).firstOrNull;

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => files ?? [_testXFile('lab-result.pdf')];
}

XFile _testXFile(String name, {bool png = false}) => XFile.fromData(
  Uint8List.fromList(
    png
        ? const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        : const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37],
  ),
  path: name,
  name: name,
  mimeType: png ? 'image/png' : 'application/pdf',
);

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
