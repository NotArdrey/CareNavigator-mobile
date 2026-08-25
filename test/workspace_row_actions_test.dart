import 'package:care_navigator_ph/src/features/workspaces/live_workspace_view.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/admin_repository.dart';
import 'package:care_navigator_ph/src/repositories/care_repository.dart';
import 'package:care_navigator_ph/src/repositories/profile_repository.dart';
import 'package:care_navigator_ph/src/repositories/workspace_repository.dart';
import 'package:care_navigator_ph/src/routing/root_overlay.dart';
import 'package:care_navigator_ph/src/widgets/data_display/content_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('message notifications collapse once per conversation', () {
    final grouped = collapseNotificationThreads([
      CareNotification(
        id: 'message-notification-1',
        title: 'New message',
        message: 'You received a consultation message',
        type: 'message',
        isRead: true,
        createdAt: DateTime(2026, 8, 23, 23, 8),
        data: const {'conversation_id': 'conversation-a'},
      ),
      CareNotification(
        id: 'message-notification-2',
        title: 'New message',
        message: 'You received a consultation message',
        type: 'message',
        isRead: false,
        createdAt: DateTime(2026, 8, 23, 23, 23),
        data: const {'conversation_id': 'conversation-a'},
      ),
      CareNotification(
        id: 'message-notification-3',
        title: 'New message',
        message: 'You received a consultation message',
        type: 'message',
        isRead: false,
        createdAt: DateTime(2026, 8, 23, 23, 14),
        data: const {'conversation_id': 'conversation-b'},
      ),
      CareNotification(
        id: 'status-notification',
        title: 'Hospital status update',
        message: 'Availability changed',
        type: 'hospital_status',
        isRead: false,
        createdAt: DateTime(2026, 8, 23, 22),
      ),
    ]);

    expect(grouped, hasLength(3));
    final conversationA = grouped.firstWhere(
      (notification) =>
          notification.data['conversation_id'] == 'conversation-a',
    );
    expect(conversationA.title, 'New messages');
    expect(conversationA.isRead, isFalse);
    expect(conversationA.createdAt, DateTime(2026, 8, 23, 23, 23));
    expect(conversationA.data['notification_ids'], [
      'message-notification-2',
      'message-notification-1',
    ]);
  });

  testWidgets('doctor patient action opens the checkup form', (tester) async {
    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'patients',
      item: const WorkspaceItem(
        id: 'assignment-id',
        kind: 'doctor_patient_assignments',
        title: 'Maria Santos',
        subtitle: 'Assigned patient',
        data: {'patient_id': 'patient-id'},
      ),
    );

    await _openAndCancel(
      tester,
      find.widgetWithText(FilledButton, 'Follow-up checkup'),
      'Follow-up patient checkup',
    );
  });

  testWidgets(
    'follow-up checkup puts attachments and AI auto-fill before fields',
    (tester) async {
      await _pumpItem(
        tester,
        role: UserRole.doctor,
        section: 'patients',
        item: const WorkspaceItem(
          id: 'assignment-id',
          kind: 'doctor_patient_assignments',
          title: 'Maria Santos',
          subtitle: 'Assigned patient',
          data: {
            'patient_id': 'patient-id',
            'checkup_history': [
              {
                'title': 'Previous follow-up',
                'record_type': 'checkup',
                'created_at': '2026-08-20T09:00:00Z',
              },
            ],
          },
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Follow-up checkup'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Checkup History'), findsOneWidget);
      expect(find.text('Previous follow-up'), findsOneWidget);
      expect(find.text('Attach Files'), findsOneWidget);
      expect(find.text('Scan & Auto-fill'), findsOneWidget);
      expect(find.text('Attachments and AI auto-fill'), findsOneWidget);
      expect(find.textContaining('PDF, Word, JPG, or PNG'), findsOneWidget);
      await _cancelDialog(tester);
    },
  );

  testWidgets('doctor patient detail exposes aligned clinical quick actions', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'patients',
      itemId: 'assignment-id',
      careRepository: _AssignmentOnlyCareRepository(),
      item: const WorkspaceItem(
        id: 'assignment-id',
        kind: 'doctor_patient_assignments',
        title: 'Maria Santos',
        subtitle: 'Assigned patient',
        data: {
          'patient_id': 'patient-id',
          'conversation_id': 'conversation-id',
          'patient_name': 'Maria Santos',
        },
      ),
    );

    expect(find.text('Reserve Appointment'), findsNothing);
    expect(find.text('Request Laboratory Test'), findsNothing);
    expect(find.text('Follow-up checkup'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Message Patient'),
          )
          .onPressed,
      isNotNull,
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(FilledButton, 'Add Record'),
      'Follow-up patient checkup',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Issue Prescription'));
    await tester.pumpAndSettle();
    expect(find.text('Issue prescription'), findsOneWidget);
    expect(find.text('Patient'), findsNothing);
    expect(find.text('Apply my electronic signature'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, 'Upload diagnostic result'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Upload diagnostic result'), findsWidgets);
    expect(find.text('Patient'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();

    final actionLabels = [
      'Message Patient',
      'Add Record',
      'Issue Prescription',
      'Upload diagnostic result',
    ];
    final actionSizes = [
      for (final label in actionLabels)
        tester.getSize(find.widgetWithText(FilledButton, label)),
    ];
    expect(actionSizes.map((size) => size.width).toSet(), hasLength(1));
    expect(actionSizes.map((size) => size.height).toSet(), {48.0});
  });

  testWidgets('message patient opens the linked conversation', (tester) async {
    final repository = _RecordingCareRepository();
    final router = await _pumpMessagePatientRoute(
      tester,
      careRepository: repository,
      item: const WorkspaceItem(
        id: 'assignment-id',
        kind: 'doctor_patient_assignments',
        title: 'Maria Santos',
        subtitle: 'Assigned patient',
        data: {
          'patient_id': 'patient-id',
          'conversation_id': 'conversation-id',
          'patient_name': 'Maria Santos',
        },
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Message Patient'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/doctor/messages/conversation-id');
    expect(repository.ensuredPatientId, isNull);
    expect(repository.sentConversationId, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'message patient creates and opens a persistent conversation when needed',
    (tester) async {
      final repository = _RecordingCareRepository();
      final router = await _pumpMessagePatientRoute(
        tester,
        careRepository: repository,
        item: const WorkspaceItem(
          id: 'assignment-id',
          kind: 'doctor_patient_assignments',
          title: 'Maria Santos',
          subtitle: 'Assigned patient',
          data: {'patient_id': 'patient-id'},
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Message Patient'));
      await tester.pumpAndSettle();

      expect(repository.ensuredPatientId, 'patient-id');
      expect(
        router.state.uri.path,
        '/doctor/messages/persistent-conversation-id',
      );
      expect(repository.sentConversationId, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('messenger conversation keeps send and back actions connected', (
    tester,
  ) async {
    final repository = _RecordingCareRepository(
      messages: [
        CareMessage(
          id: 'message-1',
          conversationId: 'conversation-id',
          senderId: 'patient-auth-id',
          message: 'Good morning, Doctor.',
          sentAt: DateTime(2026, 8, 23, 8, 30),
        ),
        CareMessage(
          id: 'message-2',
          conversationId: 'conversation-id',
          senderId: 'doctor-auth-id',
          message: 'How are you feeling today?',
          sentAt: DateTime(2026, 8, 23, 8, 32),
          readAt: DateTime(2026, 8, 23, 8, 33),
        ),
      ],
    );
    final router = await _pumpConversationRoute(tester, repository);

    expect(find.text('Maria Santos'), findsWidgets);
    expect(find.textContaining('Secure conversation'), findsOneWidget);
    expect(find.text('Good morning, Doctor.'), findsOneWidget);
    expect(find.text('How are you feeling today?'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('How are you feeling today?')).dy,
      greaterThan(tester.getTopLeft(find.text('Good morning, Doctor.')).dy),
    );
    expect(find.textContaining('Seen'), findsOneWidget);
    expect(repository.readConversationId, 'conversation-id');

    final sendButton = find.widgetWithIcon(IconButton, Icons.send_rounded);
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('message-composer')),
      'I am feeling better today.',
    );
    await tester.pump();
    expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);

    await tester.tap(sendButton);
    await tester.pumpAndSettle();
    expect(repository.sentConversationId, 'conversation-id');
    expect(repository.sentMessage, 'I am feeling better today.');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('message-composer')))
          .controller
          ?.text,
      isEmpty,
    );

    await tester.tap(find.byTooltip('Back to conversations'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/doctor/messages');
  });

  testWidgets('messenger inbox search, clear, row, and compose actions work', (
    tester,
  ) async {
    final router = await _pumpMessagesInboxRoute(tester);

    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Jose Dela Cruz'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('conversation-search')),
      'Maria',
    );
    await tester.pump();
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Jose Dela Cruz'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Jose Dela Cruz'), findsOneWidget);

    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/doctor/messages/conversation-1');

    router.go('/doctor/messages');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Start a conversation'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/doctor/patients');
  });

  testWidgets('messenger conversation remains usable on a phone viewport', (
    tester,
  ) async {
    final repository = _RecordingCareRepository();
    await _pumpConversationRoute(
      tester,
      repository,
      viewport: const Size(390, 844),
    );

    expect(find.text('Maria Santos'), findsWidgets);
    expect(find.byKey(const Key('message-composer')), findsOneWidget);
    expect(find.byTooltip('Add attachment'), findsOneWidget);
    expect(find.byTooltip('Send message'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doctor patient detail shows complete checkup history', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'patients',
      itemId: 'assignment-id',
      item: const WorkspaceItem(
        id: 'assignment-id',
        kind: 'doctor_patient_assignments',
        title: 'Maria Santos',
        subtitle: 'Assigned patient',
        data: {
          'patient_id': 'patient-id',
          'checkup_history': [
            {
              'title': 'Blood pressure follow-up',
              'record_type': 'checkup',
              'doctor_display_name': 'Dr. Ana Reyes',
              'created_at': '2026-08-20T09:00:00Z',
              'blood_pressure_systolic': 128,
              'blood_pressure_diastolic': 82,
            },
            {
              'title': 'Initial checkup',
              'record_type': 'checkup',
              'doctor_display_name': 'Dr. Ana Reyes',
              'created_at': '2026-07-18T09:00:00Z',
              'doctor_notes': 'Baseline assessment',
            },
          ],
        },
      ),
    );

    expect(find.text('Checkup History'), findsOneWidget);
    expect(find.text('Blood pressure follow-up'), findsOneWidget);
    expect(find.text('Initial checkup'), findsOneWidget);
  });

  testWidgets(
    'doctor patient detail shows prescription and diagnostic histories without a consultation',
    (tester) async {
      await _pumpItem(
        tester,
        role: UserRole.doctor,
        section: 'patients',
        itemId: 'assignment-id',
        item: const WorkspaceItem(
          id: 'assignment-id',
          kind: 'doctor_patient_assignments',
          title: 'Maria Santos',
          subtitle: 'Assigned patient',
          data: {
            'patient_id': 'patient-id',
            'patient_context_unavailable':
                'No active consultation is linked to this assignment.',
            'prescription_history': [
              {
                'id': 'prescription-id',
                'history_source': 'prescriptions',
                'medication_name': 'Amoxicillin',
                'exact_dose': '500 mg',
                'frequency': 'Every 8 hours',
                'prescriber_name': 'Dr. Ana Reyes',
                'electronically_signed_at': '2026-08-22T09:00:00Z',
              },
            ],
            'diagnostic_result_history': [
              {
                'id': 'document-id',
                'history_source': 'medical_documents',
                'document_type': 'diagnostic_result',
                'title': 'Chest X-ray result',
                'test_procedure_name': 'Chest X-ray',
                'result_category': 'x_ray',
                'result_date': '2026-08-21',
                'facility': 'Care Hospital',
                'requesting_doctor': 'Dr. Ana Reyes',
              },
            ],
          },
        ),
      );

      expect(find.text('Prescription History'), findsOneWidget);
      expect(find.text('Amoxicillin'), findsOneWidget);
      expect(find.text('Diagnostic Result History'), findsOneWidget);
      expect(find.text('Chest X-ray'), findsOneWidget);
      expect(
        find.textContaining(
          'histories authorized by this assignment remain available below',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Chest X-ray'));
      await tester.tap(find.text('Chest X-ray'));
      await tester.pumpAndSettle();
      expect(find.text('Open secure file'), findsOneWidget);
      expect(find.text('Care Hospital'), findsOneWidget);
    },
  );

  testWidgets(
    'doctor patient detail labels originating hospitals on checkup and clinical history entries',
    (tester) async {
      await _pumpItem(
        tester,
        role: UserRole.doctor,
        section: 'patients',
        itemId: 'assignment-id',
        item: const WorkspaceItem(
          id: 'assignment-id',
          kind: 'doctor_patient_assignments',
          title: 'Neil Ardrey Laza',
          subtitle: 'Assigned patient',
          data: {
            'patient_id': 'patient-id',
            'checkup_history': [
              {
                'title': 'General Checkup',
                'record_type': 'checkup',
                'doctor_display_name': 'Dr. Maria Santos',
                'originating_hospital': 'CareNavigator Regional Hospital (Demo)',
                'created_at': '2026-08-20T09:00:00Z',
              },
            ],
            'prescription_history': [
              {
                'id': 'prescription-id',
                'history_source': 'prescriptions',
                'medication_name': 'Paracetamol 500mg',
                'prescriber_name': 'Dr. Maria Santos',
                'originating_hospital': 'CareNavigator Regional Hospital (Demo)',
                'created_at': '2026-08-20T09:00:00Z',
              },
            ],
            'diagnostic_result_history': [
              {
                'id': 'doc-id',
                'history_source': 'medical_documents',
                'document_type': 'diagnostic_result',
                'test_procedure_name': 'CT Scan Chest',
                'requesting_doctor': 'Dr. Maria Santos',
                'originating_hospital': 'CareNavigator Regional Hospital (Demo)',
                'result_date': '2026-08-21',
              },
            ],
          },
        ),
      );

      expect(find.text('General Checkup'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('CT Scan Chest'), findsOneWidget);
      expect(find.textContaining('CareNavigator Regional Hospital (Demo)'), findsWidgets);

      await tester.ensureVisible(find.text('General Checkup'));
      await tester.tap(find.text('General Checkup'));
      await tester.pumpAndSettle();
      expect(find.text('Originating Facility / Hospital'), findsOneWidget);
    },
  );

  testWidgets('prescription history file shows extracted medication details', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'patients',
      itemId: 'assignment-id',
      item: const WorkspaceItem(
        id: 'assignment-id',
        kind: 'doctor_patient_assignments',
        title: 'Maria Santos',
        subtitle: 'Assigned patient',
        data: {
          'patient_id': 'patient-id',
          'prescription_history': [
            {
              'id': 'prescription-document-id',
              'history_source': 'medical_documents',
              'document_type': 'prescription',
              'title': 'Prescription Attachment',
              'created_at': '2026-08-23T14:26:00Z',
              'ai_summary': 'Paracetamol was prescribed for fever or pain.',
              'ai_extracted_data': {
                'patient_name': 'Maria Test Santos',
                'document_date': '21 August 2026',
                'provider_name': 'Dr. Andrea Reyes',
                'medications': [
                  'Paracetamol 500 mg tablet, take 1 every 6 hours, maximum 4 tablets in 24 hours',
                ],
                'instructions': ['Do not combine with other paracetamol.'],
              },
            },
          ],
        },
      ),
    );

    await tester.ensureVisible(find.text('Prescription Attachment'));
    await tester.tap(find.text('Prescription Attachment'));
    await tester.pumpAndSettle();

    expect(find.text('Medication and directions'), findsOneWidget);
    expect(find.textContaining('maximum 4 tablets'), findsOneWidget);
    expect(find.text('Dr. Andrea Reyes'), findsOneWidget);
    expect(find.text('Open secure file'), findsOneWidget);
    expect(find.text('AI Summary Status'), findsNothing);
  });

  testWidgets('doctor detail labels authorized external patient context', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'consultations',
      itemId: 'consultation-id',
      item: const WorkspaceItem(
        id: 'consultation-id',
        kind: 'consultations',
        title: 'Maria Santos',
        subtitle: 'Scheduled consultation',
        data: {
          'patient_context': {
            'demographics': {
              'first_name': 'Maria',
              'last_name': 'Santos',
              'patient_number': 'PT-1001',
              'mobile_number': '+63 917 000 0000',
            },
            'allergies_medications': {
              'allergies': ['Penicillin'],
              'current_medications': ['Metformin'],
            },
            'medical_records': [
              {
                'originating_hospital': 'Hospital A',
                'authoring_doctor': 'Dr. Ana Reyes',
                'record_date': '2026-08-20T09:00:00Z',
                'record_status': 'final',
                'external_read_only': true,
                'record': {
                  'title': 'Previous assessment',
                  'record_type': 'consultation_note',
                  'description': 'Blood pressure is improving.',
                },
              },
            ],
            'medical_documents': [
              {
                'originating_hospital': 'Hospital A',
                'authoring_doctor': 'Dr. Ana Reyes',
                'record_date': '2026-08-20T09:00:00Z',
                'record_status': 'final',
                'external_read_only': true,
                'record': {
                  'id': 'document-id',
                  'title': 'Checkup Attachment',
                  'document_type': 'checkup_attachment',
                },
              },
            ],
          },
        },
      ),
    );

    expect(find.text('Authorized patient context'), findsOneWidget);
    expect(find.text('Maria Santos'), findsWidgets);
    expect(find.text('PT-1001'), findsOneWidget);
    await tester.tap(find.text('Medical records'));
    await tester.pumpAndSettle();
    expect(find.textContaining('External read-only'), findsOneWidget);
    expect(find.textContaining('Hospital A'), findsOneWidget);
    expect(find.textContaining('Dr. Ana Reyes'), findsOneWidget);
    expect(find.textContaining('Final'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'View'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Previous assessment'), findsWidgets);
    expect(find.text('Blood pressure is improving.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Medical documents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medical documents'));
    await tester.pumpAndSettle();
    expect(find.text('Checkup Attachment'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open file'), findsOneWidget);
  });

  testWidgets('hospital admin can submit doctor department reassignment', (
    tester,
  ) async {
    final repository = _DepartmentAdminRepository();
    await _pumpItem(
      tester,
      role: UserRole.hospitalAdministrator,
      section: 'staff',
      adminRepository: repository,
      item: const WorkspaceItem(
        id: 'doctor-user-id',
        kind: 'users',
        title: 'Dr. Ana Reyes',
        subtitle: 'Doctor',
        data: {
          'display_name': 'Dr. Ana Reyes',
          'department_id': 'department-one',
        },
      ),
    );

    final editAction = find.widgetWithText(OutlinedButton, 'Edit');
    await tester.ensureVisible(editAction);
    await tester.tap(editAction);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change department'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Change doctor department'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Cardiology').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(FilledButton, 'Save department'));
    await tester.pumpAndSettle();

    expect(repository.updatedUserId, 'doctor-user-id');
    expect(repository.updatedDepartmentId, 'department-two');
  });

  testWidgets('admin workspace can load records beyond the first page', (
    tester,
  ) async {
    const request = (
      role: UserRole.superAdministrator,
      section: 'hospitals',
      itemId: null,
    );
    final repository = _PagedWorkspaceRepository();
    final container = ProviderContainer(
      overrides: [
        workspaceSnapshotProvider(request).overrideWith(
          (ref) async => WorkspaceSnapshot(
            title: 'Hospitals',
            description: 'Platform hospitals.',
            items: repository.items.take(2).toList(growable: false),
            hasMore: true,
            loadedAt: DateTime(2026, 8, 15),
          ),
        ),
        workspaceRepositoryProvider.overrideWithValue(repository),
        adminRepositoryProvider.overrideWithValue(_NoopAdminRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: LiveWorkspaceView(
              role: UserRole.superAdministrator,
              section: 'hospitals',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Load more'));
    await tester.pumpAndSettle();

    expect(find.text('Hospital Three'), findsOneWidget);
    expect(repository.requestedLimit, 102);
  });

  testWidgets('schedule publish and delete controls open confirmations', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'schedule',
      item: const WorkspaceItem(
        id: 'schedule-id',
        kind: 'doctor_schedules',
        title: 'Monday morning',
        subtitle: 'Online',
        data: {'is_active': false, 'reserved_consultation_count': 0},
      ),
    );

    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Publish'),
      'Publish schedule slot?',
    );
    await _openAndCancel(
      tester,
      find.byTooltip('Delete availability'),
      'Delete availability?',
    );
  });

  testWidgets('capacity edit control opens the persisted-value form', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.hospitalAdministrator,
      section: 'capacity',
      item: const WorkspaceItem(
        id: 'bed-id',
        kind: 'hospital_beds',
        title: 'Ward beds',
        subtitle: '8 available',
        data: {'total_beds': 12, 'available_beds': 8},
      ),
    );

    await _openAndCancel(
      tester,
      find.widgetWithText(OutlinedButton, 'Edit'),
      'Update Ward beds',
    );
  });

  testWidgets('admin table view action opens record details in a modal', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.hospitalAdministrator,
      section: 'services',
      adminRepository: _DepartmentAdminRepository(),
      item: const WorkspaceItem(
        id: 'service-view-id',
        kind: 'hospital_services',
        title: 'Cardiology',
        subtitle: 'Available',
        data: {
          'service_name': 'Cardiology',
          'description': 'Heart and vascular care',
        },
      ),
    );

    expect(
      find.byKey(const ValueKey('view-record-service-view-id')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'View'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Record ID'), findsOneWidget);
    expect(find.text('service-view-id'), findsOneWidget);
    expect(find.text('Heart and vascular care'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('immutable admin records remain explicit view only', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.superAdministrator,
      section: 'security',
      item: const WorkspaceItem(
        id: 'security-event-id',
        kind: 'security_events',
        title: 'Failed sign-in',
        subtitle: 'Recorded security event',
      ),
    );

    expect(find.widgetWithText(OutlinedButton, 'View'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Delete'), findsNothing);
  });

  testWidgets('facility availability exposes connected add edit and delete', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.hospitalAdministrator,
      section: 'availability',
      item: const WorkspaceItem(
        id: 'facility-id',
        kind: 'hospital_facility_status',
        title: 'Intensive care unit',
        subtitle: '4 units available',
        status: 'available',
        data: {
          'facility_type': 'icu',
          'status': 'available',
          'available_units': 4,
          'notes': 'Staffed continuously',
        },
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add facility status'));
    await tester.pumpAndSettle();
    expect(find.text('Add facility status'), findsWidgets);
    expect(find.text('Operating room'), findsOneWidget);
    await _cancelDialog(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit facility'), findsOneWidget);
    expect(find.text('Staffed continuously'), findsOneWidget);
    await _cancelDialog(tester);

    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Delete'),
      'Delete Intensive care unit?',
    );
  });

  testWidgets('ER capacity confirmation shows the server-derived preview', (
    tester,
  ) async {
    final repository = _RecordingAdminRepository();
    await _pumpItem(
      tester,
      role: UserRole.hospitalAdministrator,
      section: 'emergency-room',
      adminRepository: repository,
      item: const WorkspaceItem(
        id: 'er-status-id',
        kind: 'emergency_room_status',
        title: 'Emergency room',
        subtitle: '9 beds available',
        status: 'available',
        data: {
          'maximum_capacity': 29,
          'available_beds': 9,
          'occupied_beds': 17,
          'closed_or_unstaffed_beds': 2,
          'reserved_beds': 1,
          'current_patient_count': 13,
        },
      ),
    );

    final statusControl = find.byType(StatusTag);
    final viewControl = find.byKey(const ValueKey('view-record-er-status-id'));
    final editControl = find.byKey(const ValueKey('edit-record-er-status-id'));
    expect(statusControl, findsOneWidget);
    expect(
      tester.getSize(statusControl).height,
      tester.getSize(viewControl).height,
    );
    expect(
      tester.getSize(statusControl).height,
      tester.getSize(editControl).height,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm emergency capacity'), findsOneWidget);
    expect(
      find.text('Available beds: 9 · Automatic status: Available'),
      findsOneWidget,
    );
    expect(find.text('Publish confirmation'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Publish confirmation'));
    await tester.pumpAndSettle();

    expect(repository.recordId, 'er-status-id');
    expect(repository.totalCapacity, 29);
    expect(repository.occupiedCapacity, 17);
    expect(repository.closedOrUnstaffedCapacity, 2);
    expect(repository.reservedCapacity, 1);
    expect(repository.currentPatientCount, 13);
    expect(repository.statusOverride, isNull);
    expect(repository.overrideReason, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text(
        'Emergency capacity confirmed. The public timestamp has been refreshed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('laboratory cancellation control opens the audit-safe warning', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'laboratory',
      item: const WorkspaceItem(
        id: 'lab-id',
        kind: 'laboratory_requests',
        title: 'Complete blood count',
        subtitle: 'Routine',
        status: 'requested',
      ),
    );

    await _openAndCancel(
      tester,
      find.byTooltip('Cancel laboratory request'),
      'Cancel Complete blood count?',
    );
  });

  testWidgets('patient can manage a lab file they uploaded', (tester) async {
    await _pumpItem(
      tester,
      role: UserRole.patient,
      section: 'labs',
      item: const WorkspaceItem(
        id: 'patient-lab-file-id',
        kind: 'medical_documents',
        title: 'CBC result.pdf',
        subtitle: 'Lab result',
        data: {'is_current_user_upload': true},
      ),
    );

    expect(find.widgetWithText(TextButton, 'Download'), findsOneWidget);
    await _openAndCancel(
      tester,
      find.byTooltip('Edit file title'),
      'Edit file title',
    );
    await _openAndCancel(
      tester,
      find.byTooltip('Delete file'),
      'Delete CBC result.pdf?',
    );
  });

  testWidgets('patient cannot edit or delete a doctor-uploaded file', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.patient,
      section: 'prescriptions',
      item: const WorkspaceItem(
        id: 'doctor-prescription-file-id',
        kind: 'medical_documents',
        title: 'Doctor prescription.pdf',
        subtitle: 'Prescription',
        data: {'is_current_user_upload': false},
      ),
    );

    expect(find.widgetWithText(TextButton, 'Download'), findsOneWidget);
    expect(find.byTooltip('Edit file title'), findsNothing);
    expect(find.byTooltip('Delete file'), findsNothing);
  });

  testWidgets(
    'patient prescription list uses readable actions without an AI completed badge',
    (tester) async {
      await _pumpItem(
        tester,
        role: UserRole.patient,
        section: 'prescriptions',
        item: const WorkspaceItem(
          id: 'paracetamol-id',
          kind: 'prescriptions',
          title: 'Paracetamol',
          subtitle: 'Take 1 tablet | every 6 hours | 8 days',
        ),
      );

      final viewDetails = find.ancestor(
        of: find.text('View details'),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      expect(viewDetails, findsOneWidget);
      expect(
        tester.widget<ButtonStyleButton>(viewDetails).onPressed,
        isNotNull,
      );
      expect(find.text('Completed'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );

  testWidgets('patient prescription attachment shows extracted directions', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.patient,
      section: 'prescriptions',
      itemId: 'prescription-document-id',
      item: const WorkspaceItem(
        id: 'prescription-document-id',
        kind: 'medical_documents',
        title: 'Prescription Attachment',
        subtitle: 'Prescription',
        data: {
          'document_type': 'prescription',
          'ai_analysis_status': 'completed',
          'ai_summary': 'Paracetamol was prescribed for fever or pain.',
          'ai_extracted_data': {
            'patient_name': 'Maria Test Santos',
            'document_date': '21 August 2026',
            'provider_name': 'Dr. Andrea Reyes',
            'medications': [
              'Paracetamol 500 mg tablet, oral, take 1 tablet every 6 hours as needed, maximum 4 tablets in 24 hours, dispense 12 tablets, no refills',
            ],
            'instructions': [
              'Do not combine with other products containing paracetamol.',
            ],
            'limitations': ['Fictional sample; not valid for dispensing.'],
          },
        },
      ),
    );

    expect(find.text('Medication and directions'), findsOneWidget);
    expect(
      find.textContaining('maximum 4 tablets in 24 hours'),
      findsOneWidget,
    );
    expect(find.text('Prescriber'), findsOneWidget);
    expect(find.text('Dr. Andrea Reyes'), findsOneWidget);
    expect(find.text('Important note'), findsOneWidget);
    expect(find.text('AI Summary Status'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Download'), findsOneWidget);
  });

  testWidgets('patient can read a doctor-uploaded document AI summary', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.patient,
      section: 'labs',
      itemId: 'doctor-lab-file-id',
      item: const WorkspaceItem(
        id: 'doctor-lab-file-id',
        kind: 'medical_documents',
        title: 'CBC result.jpg',
        subtitle: 'Lab result · Groq summary',
        status: 'completed',
        data: {
          'document_type': 'lab_result',
          'ai_analysis_status': 'completed',
          'ai_summary':
              'The document lists hemoglobin at 13.5 g/dL and marks no result as abnormal.',
          'is_current_user_upload': false,
        },
      ),
    );

    expect(find.text('Summary'), findsOneWidget);
    expect(
      find.text(
        'The document lists hemoglobin at 13.5 g/dL and marks no result as abnormal.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Download'), findsOneWidget);
  });

  testWidgets('patient file actions pass the selected document id', (
    tester,
  ) async {
    final repository = _RecordingCareRepository();
    await _pumpItem(
      tester,
      role: UserRole.patient,
      section: 'labs',
      careRepository: repository,
      item: const WorkspaceItem(
        id: 'selected-document-id',
        kind: 'medical_documents',
        title: 'Original title',
        subtitle: 'Lab result',
        data: {'is_current_user_upload': true},
      ),
    );

    await tester.tap(find.byTooltip('Edit file title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'Updated title');
    await tester.tap(find.widgetWithText(FilledButton, 'Save title'));
    await tester.pumpAndSettle();
    expect(repository.renamedFileId, 'selected-document-id');
    expect(repository.renamedTitle, 'Updated title');

    await tester.tap(find.byTooltip('Delete file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete file'));
    await tester.pumpAndSettle();
    expect(repository.deletedFileId, 'selected-document-id');
  });

  testWidgets('managed service status and delete controls open confirmations', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.hospitalAdministrator,
      section: 'services',
      adminRepository: _DepartmentAdminRepository(),
      item: const WorkspaceItem(
        id: 'service-id',
        kind: 'hospital_services',
        title: 'Cardiology',
        subtitle: 'Available',
        status: 'available',
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit service'), findsOneWidget);
    expect(find.text('Availability'), findsOneWidget);
    await _cancelDialog(tester);

    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Delete'),
      'Delete Cardiology?',
    );
  });

  testWidgets('account status menu reaches its protected confirmation', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.superAdministrator,
      section: 'accounts',
      item: const WorkspaceItem(
        id: 'user-id',
        kind: 'users',
        title: 'Test User',
        subtitle: 'Doctor',
        status: 'active',
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set status to Suspended').last);
    await tester.pumpAndSettle();
    expect(find.text('Change account status?'), findsOneWidget);
    await _cancelDialog(tester);
  });

  testWidgets('permission and setting controls open governance dialogs', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.superAdministrator,
      section: 'permissions',
      item: const WorkspaceItem(
        id: 'permission-id',
        kind: 'role_permissions',
        title: 'Manage users',
        subtitle: 'Allowed',
        data: {'is_allowed': true},
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deny permission'));
    await tester.pumpAndSettle();
    expect(find.text('Deny permission?'), findsOneWidget);
    await _cancelDialog(tester);

    await _pumpItem(
      tester,
      role: UserRole.superAdministrator,
      section: 'settings',
      item: const WorkspaceItem(
        id: 'support_email',
        kind: 'system_settings',
        title: 'Support email',
        subtitle: 'support@example.test',
        data: {'value': 'support@example.test'},
      ),
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(OutlinedButton, 'Edit'),
      'Edit Support email',
    );
  });

  testWidgets('maintenance activate and delete controls open confirmations', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.superAdministrator,
      section: 'maintenance',
      item: const WorkspaceItem(
        id: 'maintenance-id',
        kind: 'maintenance_windows',
        title: 'Database maintenance',
        subtitle: 'Tomorrow',
        data: {'is_active': false},
      ),
    );

    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Activate'),
      'Activate maintenance window?',
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Delete'),
      'Delete Database maintenance?',
    );
  });

  testWidgets('hospital approval controls open approve and reject reviews', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.superAdministrator,
      section: 'approvals',
      item: const WorkspaceItem(
        id: 'hospital-id',
        kind: 'hospitals',
        title: 'New Hospital',
        subtitle: 'Pending verification',
        status: 'pending_verification',
      ),
    );

    await _openAndCancel(
      tester,
      find.widgetWithText(FilledButton, 'Approve'),
      'Approve hospital?',
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Reject'),
      'Reject hospital application',
    );
  });

  testWidgets('consultation lifecycle controls open protected actions', (
    tester,
  ) async {
    final appointment = DateTime.now().add(const Duration(days: 1));
    await _pumpItem(
      tester,
      role: UserRole.patient,
      section: 'consultations',
      item: WorkspaceItem(
        id: 'consultation-id',
        kind: 'consultations',
        title: 'Dr. Reyes',
        subtitle: 'In person',
        status: 'scheduled',
        data: {'appointment_date': appointment.toIso8601String()},
      ),
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(OutlinedButton, 'Cancel'),
      'Cancel consultation?',
    );

    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'consultations',
      item: WorkspaceItem(
        id: 'consultation-id',
        kind: 'consultations',
        title: 'Maria Santos',
        subtitle: 'In person',
        status: 'pending',
        data: {'appointment_date': appointment.toIso8601String()},
      ),
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(FilledButton, 'Approve'),
      'Approve consultation?',
    );

    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'consultations',
      item: WorkspaceItem(
        id: 'consultation-id',
        kind: 'consultations',
        title: 'Maria Santos',
        subtitle: 'In person',
        status: 'in_progress',
        data: {
          'appointment_date': appointment.toIso8601String(),
          'patient_name': 'Maria Santos',
        },
      ),
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(FilledButton, 'Complete'),
      'Complete consultation',
    );
  });

  testWidgets('laboratory review controls open analysis and review dialogs', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'results-review',
      item: const WorkspaceItem(
        id: 'result-id',
        kind: 'laboratory_results',
        title: 'Blood panel',
        subtitle: 'Uploaded',
        status: 'uploaded',
      ),
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(FilledButton, 'Analyze'),
      'Run preliminary analysis?',
    );

    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'results-review',
      item: const WorkspaceItem(
        id: 'result-id',
        kind: 'laboratory_results',
        title: 'Blood panel',
        subtitle: 'Awaiting review',
        status: 'pending_doctor_review',
      ),
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(FilledButton, 'Confirm'),
      'Confirm medical result',
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Reject'),
      'Reject preliminary result',
    );
  });

  testWidgets('guest request controls open approve and reject reviews', (
    tester,
  ) async {
    await _pumpItem(
      tester,
      role: UserRole.doctor,
      section: 'requests',
      item: WorkspaceItem(
        id: 'request-id',
        kind: 'guest_consultation_requests',
        title: 'Guest patient',
        subtitle: 'Pending review',
        status: 'pending_doctor_review',
        data: {
          'assigned_doctor_id': 'doctor-id',
          'preferred_schedule': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
        },
      ),
    );

    await _openAndCancel(
      tester,
      find.widgetWithText(FilledButton, 'Approve'),
      'Approve guest consultation?',
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Reject'),
      'Reject guest consultation',
    );
  });

  testWidgets('reviewed online requests expose role-scoped decisions', (
    tester,
  ) async {
    final preferred = DateTime.now().add(const Duration(days: 2));
    await _pumpItem(
      tester,
      role: UserRole.patient,
      section: 'appointments',
      item: WorkspaceItem(
        id: 'online-request-id',
        kind: 'online_consultation_requests',
        title: 'ONL-20260823-000001',
        subtitle: 'Persistent cough',
        status: 'submitted',
        data: {'preferred_schedule': preferred.toIso8601String()},
      ),
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Cancel request'),
      'Cancel online consultation request',
    );

    await _pumpItem(
      tester,
      role: UserRole.hospitalAdministrator,
      section: 'appointments',
      item: WorkspaceItem(
        id: 'online-request-id',
        kind: 'online_consultation_requests',
        title: 'ONL-20260823-000001',
        subtitle: 'Persistent cough',
        status: 'submitted',
        data: {
          'hospital_id': 'hospital-id',
          'requested_department_id': 'department-id',
          'preferred_schedule': preferred.toIso8601String(),
        },
      ),
    );
    await _openAndCancel(
      tester,
      find.widgetWithText(TextButton, 'Reject'),
      'Reject online consultation request',
    );
  });

  testWidgets('patient can understand and accept a clinician connection', (
    tester,
  ) async {
    final repository = _RecordingCareRepository();
    await _pumpItem(
      tester,
      role: UserRole.patient,
      section: 'notifications',
      itemId: 'notification-id',
      careRepository: repository,
      viewport: const Size(532, 1152),
      item: const WorkspaceItem(
        id: 'notification-id',
        kind: 'notifications',
        title: 'Care connection request',
        subtitle: 'Review this request.',
        status: 'unread',
        isUnread: true,
        data: {
          'notification_type': 'access_request',
          'reference_id': 'request-id',
          'data': {
            'connection_request_id': 'request-id',
            'doctor_display_name': 'Dr. Ana Reyes',
            'hospital_name': 'Makati Medical Center',
            'status': 'requested',
          },
        },
      ),
    );

    expect(find.text('Connection request'), findsOneWidget);
    expect(find.text('Dr. Ana Reyes would like to connect'), findsOneWidget);
    expect(find.text('Makati Medical Center'), findsOneWidget);
    expect(find.text('Notification Type'), findsNothing);
    expect(find.text('Is Read'), findsNothing);
    expect(find.text('Accept request'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept request'));
    await tester.pumpAndSettle();
    expect(find.text('Accept this connection?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Accept request').last);
    await tester.pumpAndSettle();

    expect(repository.connectionRequestId, 'request-id');
    expect(repository.connectionApproved, isTrue);
  });
}

Future<GoRouter> _pumpMessagePatientRoute(
  WidgetTester tester, {
  required CareRepository careRepository,
  required WorkspaceItem item,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const request = (
    role: UserRole.doctor,
    section: 'patients',
    itemId: 'assignment-id',
  );
  final container = ProviderContainer(
    overrides: [
      workspaceSnapshotProvider(request).overrideWith(
        (ref) async => WorkspaceSnapshot(
          title: 'Patient details',
          description: 'Runtime message-navigation verification.',
          items: [item],
          loadedAt: DateTime(2026, 8, 23),
        ),
      ),
      careRepositoryProvider.overrideWithValue(careRepository),
      adminRepositoryProvider.overrideWithValue(_NoopAdminRepository()),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/doctor/patients/assignment-id',
    routes: [
      GoRoute(
        path: '/doctor/patients/:itemId',
        builder: (context, state) => const Scaffold(
          body: LiveWorkspaceView(
            role: UserRole.doctor,
            section: 'patients',
            itemId: 'assignment-id',
          ),
        ),
      ),
      GoRoute(
        path: '/doctor/messages/:conversationId',
        builder: (context, state) => Scaffold(
          body: Text('Conversation ${state.pathParameters['conversationId']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<GoRouter> _pumpConversationRoute(
  WidgetTester tester,
  _RecordingCareRepository repository, {
  Size viewport = const Size(900, 760),
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const request = (
    role: UserRole.doctor,
    section: 'messages',
    itemId: 'conversation-id',
  );
  final container = ProviderContainer(
    overrides: [
      workspaceSnapshotProvider(request).overrideWith(
        (ref) async => WorkspaceSnapshot(
          title: 'Conversation',
          description: 'Secure care conversation.',
          items: const [
            WorkspaceItem(
              id: 'conversation-id',
              kind: 'chat_conversations',
              title: 'Maria Santos',
              subtitle: 'Good morning, Doctor.',
              data: {'participant_role': 'Patient'},
            ),
          ],
          loadedAt: DateTime(2026, 8, 23),
        ),
      ),
      careRepositoryProvider.overrideWithValue(repository),
      careProfileProvider.overrideWith(
        (ref) async => const CareProfile(
          userId: 'doctor-auth-id',
          firstName: 'Ana',
          lastName: 'Reyes',
          email: 'doctor@example.com',
          mobileNumber: null,
          birthDate: null,
          sex: null,
          address: null,
          preferences: NotificationPreferences(),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/doctor/messages/conversation-id',
    routes: [
      GoRoute(
        path: '/doctor/messages',
        builder: (context, state) =>
            const Scaffold(body: Text('Conversations')),
        routes: [
          GoRoute(
            path: ':conversationId',
            builder: (context, state) => const Scaffold(
              body: LiveWorkspaceView(
                role: UserRole.doctor,
                section: 'messages',
                itemId: 'conversation-id',
              ),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<GoRouter> _pumpMessagesInboxRoute(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.physicalSize = const Size(900, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const request = (role: UserRole.doctor, section: 'messages', itemId: null);
  final container = ProviderContainer(
    overrides: [
      workspaceSnapshotProvider(request).overrideWith(
        (ref) async => WorkspaceSnapshot(
          title: 'Messages',
          description: 'Care conversations.',
          items: [
            WorkspaceItem(
              id: 'conversation-1',
              kind: 'chat_conversations',
              title: 'Maria Santos',
              subtitle: 'You: Please continue your medication.',
              timestamp: DateTime(2026, 8, 23, 9, 15),
            ),
            WorkspaceItem(
              id: 'conversation-2',
              kind: 'chat_conversations',
              title: 'Jose Dela Cruz',
              subtitle: 'Thank you, Doctor.',
              timestamp: DateTime(2026, 8, 22, 16, 30),
              isUnread: true,
              data: {'unread_count': 2},
            ),
          ],
          loadedAt: DateTime(2026, 8, 23),
        ),
      ),
      careRepositoryProvider.overrideWithValue(_NoopCareRepository()),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/doctor/messages',
    routes: [
      GoRoute(
        path: '/doctor/messages',
        builder: (context, state) => const Scaffold(
          body: LiveWorkspaceView(role: UserRole.doctor, section: 'messages'),
        ),
        routes: [
          GoRoute(
            path: ':conversationId',
            builder: (context, state) => Scaffold(
              body: Text(
                'Conversation ${state.pathParameters['conversationId']}',
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/doctor/patients',
        builder: (context, state) => const Scaffold(body: Text('Patients')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _pumpItem(
  WidgetTester tester, {
  required UserRole role,
  required String section,
  required WorkspaceItem item,
  String? itemId,
  AdminRepository? adminRepository,
  CareRepository? careRepository,
  Size viewport = const Size(1440, 1000),
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final request = (role: role, section: section, itemId: itemId);
  final container = ProviderContainer(
    overrides: [
      workspaceSnapshotProvider(request).overrideWith(
        (ref) async => WorkspaceSnapshot(
          title: 'Action coverage',
          description: 'Runtime row-action verification.',
          items: [item],
          loadedAt: DateTime(2026, 8, 15),
        ),
      ),
      careRepositoryProvider.overrideWithValue(
        careRepository ?? _NoopCareRepository(),
      ),
      adminRepositoryProvider.overrideWithValue(
        adminRepository ?? _NoopAdminRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: Scaffold(
          body: LiveWorkspaceView(role: role, section: section, itemId: itemId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAndCancel(
  WidgetTester tester,
  Finder action,
  String expectedTitle,
) async {
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text(expectedTitle), findsWidgets);
  expect(tester.takeException(), isNull);
  await _cancelDialog(tester);
}

Future<void> _cancelDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

class _NoopCareRepository implements CareRepository {
  @override
  Future<List<ClinicalRelationship>> listClinicalRelationships() async =>
      const [
        ClinicalRelationship(
          patientId: 'patient-id',
          patientLabel: 'Maria Santos',
          consultationId: 'consultation-id',
          consultationLabel: 'Follow-up consultation',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AssignmentOnlyCareRepository extends _NoopCareRepository {
  @override
  Future<List<ClinicalRelationship>> listClinicalRelationships() async =>
      const [
        ClinicalRelationship(
          patientId: 'patient-id',
          patientLabel: 'Maria Santos',
          consultationId: '',
          consultationLabel: 'Assigned care relationship',
          assignmentId: 'assignment-id',
        ),
      ];
}

class _RecordingCareRepository extends _NoopCareRepository {
  _RecordingCareRepository({this.messages = const []});

  final List<CareMessage> messages;
  String? renamedFileId;
  String? renamedTitle;
  String? deletedFileId;
  String? sentConversationId;
  String? sentMessage;
  String? connectionRequestId;
  bool? connectionApproved;
  String? ensuredPatientId;
  String? readConversationId;

  @override
  Stream<List<CareMessage>> watchMessages(String conversationId) =>
      Stream.value(messages);

  @override
  Future<void> markConversationRead(String conversationId) async {
    readConversationId = conversationId;
  }

  @override
  Future<String> ensurePatientConversation(String patientId) async {
    ensuredPatientId = patientId;
    return 'persistent-conversation-id';
  }

  @override
  Future<void> decidePatientConnectionRequest({
    required String requestId,
    required bool approve,
  }) async {
    connectionRequestId = requestId;
    connectionApproved = approve;
  }

  @override
  Future<void> renameOwnMedicalFile({
    required String fileId,
    required String title,
  }) async {
    renamedFileId = fileId;
    renamedTitle = title;
  }

  @override
  Future<void> deleteOwnMedicalFile({required String fileId}) async {
    deletedFileId = fileId;
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String body,
    ({List<int> bytes, String name})? attachment,
  }) async {
    sentConversationId = conversationId;
    sentMessage = body;
  }
}

class _NoopAdminRepository implements AdminRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAdminRepository extends _NoopAdminRepository {
  String? recordId;
  int? totalCapacity;
  int? occupiedCapacity;
  int? closedOrUnstaffedCapacity;
  int? reservedCapacity;
  int? currentPatientCount;
  String? statusOverride;
  String? overrideReason;

  @override
  Future<void> updateEmergencyCapacity({
    required String recordId,
    required int totalCapacity,
    required int occupiedCapacity,
    required int closedOrUnstaffedCapacity,
    required int reservedCapacity,
    required int currentPatientCount,
    String? statusOverride,
    String? overrideReason,
  }) async {
    this.recordId = recordId;
    this.totalCapacity = totalCapacity;
    this.occupiedCapacity = occupiedCapacity;
    this.closedOrUnstaffedCapacity = closedOrUnstaffedCapacity;
    this.reservedCapacity = reservedCapacity;
    this.currentPatientCount = currentPatientCount;
    this.statusOverride = statusOverride;
    this.overrideReason = overrideReason;
  }
}

class _DepartmentAdminRepository implements AdminRepository {
  String? updatedUserId;
  String? updatedDepartmentId;

  @override
  Future<HospitalAdminContext> loadHospitalAdminContext() async =>
      const HospitalAdminContext(
        hospitalId: 'hospital-id',
        departments: [
          HospitalDepartmentOption(
            id: 'department-one',
            name: 'Internal Medicine',
          ),
          HospitalDepartmentOption(id: 'department-two', name: 'Cardiology'),
        ],
      );

  @override
  Future<void> updateDoctorDepartment({
    required String userId,
    required String departmentId,
  }) async {
    updatedUserId = userId;
    updatedDepartmentId = departmentId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PagedWorkspaceRepository implements WorkspaceRepository {
  int? requestedLimit;

  final items = const [
    WorkspaceItem(
      id: 'hospital-one',
      kind: 'hospitals',
      title: 'Hospital One',
      subtitle: 'Verified hospital',
    ),
    WorkspaceItem(
      id: 'hospital-two',
      kind: 'hospitals',
      title: 'Hospital Two',
      subtitle: 'Verified hospital',
    ),
    WorkspaceItem(
      id: 'hospital-three',
      kind: 'hospitals',
      title: 'Hospital Three',
      subtitle: 'Verified hospital',
    ),
  ];

  @override
  Future<WorkspaceSnapshot> load({
    required UserRole role,
    String? section,
    String? itemId,
    int limit = 100,
  }) async {
    requestedLimit = limit;
    return WorkspaceSnapshot(
      title: 'Hospitals',
      description: 'Platform hospitals.',
      items: items,
      loadedAt: DateTime.now(),
    );
  }
}
