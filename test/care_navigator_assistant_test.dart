import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/models/hospitals/hospital_models.dart';
import 'package:care_navigator_ph/src/providers/care_assistant_provider.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/providers/hospital_directory_provider.dart';
import 'package:care_navigator_ph/src/repositories/care_assistant_repository.dart';
import 'package:care_navigator_ph/src/repositories/care_assistant_history_repository.dart';
import 'package:care_navigator_ph/src/repositories/public_settings_repository.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:care_navigator_ph/src/services/emergency_location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer createContainer({
    bool authenticated = true,
    CareAssistantRepository? repository,
    CareAssistantHistoryRepository? historyRepository,
    EmergencyLocationService? emergencyLocationService,
    List<HospitalDirectoryEntry> hospitals = const [],
    AppIdentity identity = const AppIdentity(
      role: UserRole.patient,
      status: AccountStatus.active,
      userId: 'test-user-id',
      displayName: 'Test User',
    ),
  }) => ProviderContainer(
    overrides: [
      publicConfigProvider.overrideWithValue(
        const PublicConfig(
          supabaseUrl: '',
          supabasePublishableKey: '',
          appBaseUrl: '',
        ),
      ),
      publicAppSettingsProvider.overrideWith(
        (ref) async => const PublicAppSettings(
          emergencyNumber: '911',
          emergencyRegion: 'the Philippines',
        ),
      ),
      if (repository != null)
        careAssistantRepositoryProvider.overrideWithValue(repository),
      if (historyRepository != null)
        careAssistantHistoryRepositoryProvider.overrideWithValue(
          historyRepository,
        ),
      if (emergencyLocationService != null)
        emergencyLocationServiceProvider.overrideWithValue(
          emergencyLocationService,
        ),
      if (hospitals.isNotEmpty)
        hospitalDirectoryProvider.overrideWith(
          () => _TestHospitalDirectoryController(hospitals),
        ),
      if (authenticated)
        appIdentityProvider.overrideWith(
          () => _TestAuthenticatedIdentityController(identity),
        ),
    ],
  );

  Future<void> pumpDirectory(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );
    container.read(appRouterProvider).go('/hospitals');
    await tester.pumpAndSettle();
  }

  testWidgets(
    'care assistant reports service failure without local recommendations',
    (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDirectory(tester, container);

      await tester.tap(find.text('Care assistant'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('care-assistant-attach-image')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField).last,
        'I have a persistent headache.',
      );
      await tester.tap(find.widgetWithIcon(IconButton, Icons.send_outlined));
      await tester.pumpAndSettle();

      final assistant = container.read(careAssistantProvider);
      expect(assistant.status, CareAssistantStatus.error);
      expect(assistant.recommendedHospitalIds, isEmpty);
    },
  );

  testWidgets('emergency wording remains actionable without backend data', (
    tester,
  ) async {
    final container = createContainer(
      emergencyLocationService: const _StaticEmergencyLocationService(
        EmergencyLocation(latitude: 14.6760, longitude: 120.5360),
      ),
      hospitals: const [
        HospitalDirectoryEntry(
          id: 'nearby-er',
          name: 'Nearby ER',
          city: 'Balanga City',
          province: 'Bataan',
          careLevel: 'ER',
          services: ['Emergency Room'],
          departments: ['Emergency Medicine'],
          doctors: [],
          isAvailable: true,
          availableBeds: null,
          totalBeds: null,
          latitude: 14.6762,
          longitude: 120.5364,
          emergencyContactNumber: '0998 123 4567',
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpDirectory(tester, container);

    await tester.tap(find.text('Care assistant'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'I have crushing chest pain spreading to my left arm and I am sweating.',
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send_outlined));
    await tester.pumpAndSettle();

    expect(
      container.read(careAssistantProvider).status,
      CareAssistantStatus.emergency,
    );
    final emergencyReply = container
        .read(careAssistantProvider)
        .messages
        .last
        .text;
    expect(emergencyReply, contains('Immediate first aid'));
    expect(emergencyReply, contains('What to avoid'));
    expect(emergencyReply, contains('not a diagnosis'));
    expect(emergencyReply, startsWith('Call 911 now.'));
    expect(emergencyReply, contains('Do not drive yourself'));
    expect(emergencyReply, isNot(contains('?')));
    expect(find.text('Call 911'), findsOneWidget);
    expect(find.text('Find and call an emergency hospital'), findsOneWidget);
    expect(find.text('Nearest emergency hospitals'), findsOneWidget);
    expect(find.text('Nearby ER'), findsWidgets);
    expect(find.textContaining('0998 123 4567'), findsWidgets);
    expect(find.byTooltip('Show Nearby ER on map'), findsOneWidget);
  });

  test(
    'pediatric paracetamol intake is deterministic and questions come first',
    () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final controller = container.read(careAssistantProvider.notifier);

      await controller.submit(
        'My child has a fever. How much paracetamol should I give?',
      );
      final state = container.read(careAssistantProvider);
      final reply = state.messages.last.text;

      expect(state.intent, CareAssistantIntent.medical);
      expect(state.status, CareAssistantStatus.idle);
      expect(
        reply,
        startsWith('I can help check the appropriate paracetamol dose'),
      );
      expect(reply, contains("1. Child's age in months or years"));
      expect(reply, contains('2. Weight in kilograms'));
      expect(reply, contains('3. Current temperature and how it was measured'));
      expect(reply, contains('120 mg/5 mL or 250 mg/5 mL'));
      expect(reply, contains('5. Amount and time of the last dose'));
      expect(reply, contains('6. Any other medicines already given'));
      expect(reply, contains('Do not give another dose'));
      expect(reply, contains('clinician-approved pediatric dosing rule'));
      expect(reply, contains('under 3 months old'));
      expect(reply, isNot(contains('sponge')));
    },
  );

  test(
    'a fever temperature reply uses context and bypasses repeated intake',
    () async {
      final repository = _FeverFollowUpRepository();
      final container = createContainer(repository: repository);
      addTearDown(container.dispose);
      final controller = container.read(careAssistantProvider.notifier);

      await controller.submit('I have a very bad fever.');
      expect(
        container.read(careAssistantProvider).status,
        CareAssistantStatus.followUp,
      );

      await controller.submit('45 celcius');
      final state = container.read(careAssistantProvider);

      expect(
        repository.calls,
        1,
        reason:
            'The deterministic safety gate should handle the dangerous reading immediately.',
      );
      expect(state.status, CareAssistantStatus.emergency);
      expect(state.messages.last.text, contains('45°C'));
      expect(state.messages.last.text, contains('Immediate first aid'));
      expect(
        state.messages.last.text,
        isNot(contains('little more information')),
      );
    },
  );

  test(
    'young infant fever gives urgent action without waiting for backend',
    () async {
      final repository = _FeverFollowUpRepository();
      final container = createContainer(repository: repository);
      addTearDown(container.dispose);
      final controller = container.read(careAssistantProvider.notifier);

      await controller.submit('My baby is 2 months old and has a fever.');
      await controller.submit('38°C');
      final state = container.read(careAssistantProvider);

      expect(repository.calls, 1);
      expect(state.urgency, CareAssistantUrgency.urgent);
      expect(state.messages.last.text, startsWith('A baby under 3 months old'));
      expect(
        state.messages.last.text,
        contains('urgent medical assessment now'),
      );
      expect(state.messages.last.text, contains('even without other symptoms'));
    },
  );

  testWidgets('non-medical input never opens emergency actions', (
    tester,
  ) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpDirectory(tester, container);

    await tester.tap(find.text('Care assistant'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'help me with javascript',
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send_outlined));
    await tester.pumpAndSettle();

    final assistant = container.read(careAssistantProvider);
    expect(assistant.intent, CareAssistantIntent.nonMedical);
    expect(assistant.urgency, CareAssistantUrgency.routine);
    expect(assistant.showEmergencyActions, isFalse);
    expect(find.text('Emergency actions'), findsNothing);
    final messageScroll = find.descendant(
      of: find.byKey(const Key('care-assistant-messages')),
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(messageScroll).position.pixels,
      0,
      reason: 'New replies must not force the conversation to the bottom.',
    );
    await tester.drag(
      find.byKey(const Key('care-assistant-messages')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('I can help with symptoms'), findsOneWidget);
  });

  test('new chat preserves and restores complete conversation state', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final controller = container.read(careAssistantProvider.notifier);

    await controller.submit('help me with javascript');
    final first = container.read(careAssistantProvider);
    final firstId = first.conversationId;
    expect(first.conversationTitle, 'Help Me With Javascript');
    expect(first.messages, hasLength(3));

    controller.newChat();
    final newConversation = container.read(careAssistantProvider);
    expect(newConversation.conversationId, isNot(firstId));
    expect(newConversation.messages, hasLength(1));
    expect(newConversation.conversations.first.id, firstId);

    await controller.submit('tell me a joke');
    final second = container.read(careAssistantProvider);
    expect(second.conversationTitle, 'Tell Me A Joke');
    expect(second.conversations.first.id, second.conversationId);
    expect(second.conversations, hasLength(2));

    controller.selectConversation(firstId);
    final restored = container.read(careAssistantProvider);
    expect(restored.conversationId, firstId);
    expect(restored.conversationTitle, 'Help Me With Javascript');
    expect(
      restored.messages.any(
        (message) => message.text == 'help me with javascript',
      ),
      isTrue,
    );
    expect(restored.intent, CareAssistantIntent.nonMedical);

    controller.renameConversation(firstId, 'My Care Search');
    expect(
      container.read(careAssistantProvider).conversationTitle,
      'My Care Search',
    );
    controller.togglePinConversation(firstId);
    final pinned = container.read(careAssistantProvider);
    expect(pinned.conversationPinned, isTrue);
    expect(pinned.conversations.first.isPinned, isTrue);

    controller.newChat();
    final blankId = container.read(careAssistantProvider).conversationId;
    controller.renameConversation(blankId, 'My Custom Title');
    await controller.submit('help me with javascript');
    expect(
      container.read(careAssistantProvider).conversationTitle,
      'My Custom Title',
      reason: 'Automatic naming must not overwrite a user-edited title.',
    );
  });

  test(
    'signed-in conversation history reloads per account and can be deleted',
    () async {
      final history = _MemoryCareAssistantHistoryRepository();
      final firstContainer = createContainer(historyRepository: history);
      final firstController = firstContainer.read(
        careAssistantProvider.notifier,
      );
      await _drainAsyncWork();

      await firstController.submit('help me with javascript');
      await _drainAsyncWork();
      final conversationId = firstContainer
          .read(careAssistantProvider)
          .conversationId;
      expect(history.recordsFor('test-user-id').single.id, conversationId);
      firstContainer.dispose();

      final reloadedContainer = createContainer(historyRepository: history);
      addTearDown(reloadedContainer.dispose);
      reloadedContainer.read(careAssistantProvider);
      await _drainAsyncWork();
      final reloaded = reloadedContainer.read(careAssistantProvider);
      expect(reloaded.conversationId, conversationId);
      expect(
        reloaded.messages.any(
          (message) => message.text == 'help me with javascript',
        ),
        isTrue,
      );

      const secondAccount = AppIdentity(
        role: UserRole.patient,
        status: AccountStatus.active,
        userId: 'different-user-id',
        displayName: 'Different User',
      );
      final secondContainer = createContainer(
        historyRepository: history,
        identity: secondAccount,
      );
      addTearDown(secondContainer.dispose);
      secondContainer.read(careAssistantProvider);
      await _drainAsyncWork();
      expect(
        secondContainer.read(careAssistantProvider).conversations,
        isEmpty,
      );
      expect(history.loadedUserIds, contains('different-user-id'));
      expect(history.recordsFor('test-user-id'), isNotEmpty);

      await reloadedContainer
          .read(careAssistantProvider.notifier)
          .deleteConversation(conversationId);
      expect(history.recordsFor('test-user-id'), isEmpty);
      expect(
        reloadedContainer.read(careAssistantProvider).conversationId,
        isNot(conversationId),
      );
    },
  );

  test(
    'multiple image-only submission is queued with medical context',
    () async {
      final container = createContainer();
      addTearDown(container.dispose);
      const image = CareAssistantImage(
        bytes: [0xff, 0xd8, 0xff, 0xd9],
        mimeType: 'image/jpeg',
        name: 'injury.jpg',
      );
      const secondImage = CareAssistantImage(
        bytes: [0x89, 0x50, 0x4e, 0x47],
        mimeType: 'image/png',
        name: 'rash.png',
      );

      await container
          .read(careAssistantProvider.notifier)
          .submit('', images: const [image, secondImage]);

      final state = container.read(careAssistantProvider);
      final userMessage = state.messages.firstWhere(
        (message) => message.role == CareAssistantChatMessageRole.user,
      );
      expect(userMessage.images, const [image, secondImage]);
      expect(userMessage.text, contains('medical concern'));
    },
  );

  testWidgets(
    'care assistant FAB is visible and opens for unauthenticated users',
    (tester) async {
      final guestContainer = createContainer(authenticated: false);
      addTearDown(guestContainer.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDirectory(tester, guestContainer);

      expect(find.text('Care assistant'), findsOneWidget);
      await tester.tap(find.text('Care assistant'));
      await tester.pumpAndSettle();
      expect(find.text('CareNavigator assistant'), findsOneWidget);
      expect(
        find.byKey(const Key('care-assistant-attach-image')),
        findsOneWidget,
      );
    },
  );

  testWidgets('care assistant FAB is visible on the guest mobile home', (
    tester,
  ) async {
    final container = createContainer(authenticated: false);
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(536, 1160));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('care-assistant-launcher')), findsOneWidget);
  });
}

class _TestAuthenticatedIdentityController extends AppIdentityController {
  _TestAuthenticatedIdentityController(this.identity);

  final AppIdentity identity;

  @override
  AppIdentity build() => identity;
}

class _TestHospitalDirectoryController extends HospitalDirectoryController {
  _TestHospitalDirectoryController(this.hospitals);

  final List<HospitalDirectoryEntry> hospitals;

  @override
  HospitalDirectoryState build() => HospitalDirectoryState(
    entries: hospitals,
    filters: const HospitalDirectoryFilters(),
  );
}

class _StaticEmergencyLocationService implements EmergencyLocationService {
  const _StaticEmergencyLocationService(this.location);

  final EmergencyLocation location;

  @override
  Future<EmergencyLocation?> currentLocation({
    required bool requestPermission,
  }) async => location;
}

class _FeverFollowUpRepository implements CareAssistantRepository {
  int calls = 0;

  @override
  Future<CareAssistantReply> respond({
    required List<CareAssistantTurn> messages,
    required List<CareAssistantFacilitySnapshot> facilities,
    List<CareAssistantImage> images = const [],
  }) async {
    calls++;
    return const CareAssistantReply(
      message: 'A high fever can be uncomfortable.',
      intent: CareAssistantIntent.medical,
      urgency: CareAssistantUrgency.routine,
      followUpQuestion:
          'Do you know the current temperature or how long the fever has lasted?',
    );
  }
}

class _MemoryCareAssistantHistoryRepository
    implements CareAssistantHistoryRepository {
  final Map<String, Map<String, CareAssistantHistoryRecord>> _records = {};
  final List<String> loadedUserIds = [];

  List<CareAssistantHistoryRecord> recordsFor(String userId) =>
      _records[userId]?.values.toList(growable: false) ?? const [];

  @override
  Future<List<CareAssistantHistoryRecord>> loadForUser(String userId) async {
    loadedUserIds.add(userId);
    final records = recordsFor(userId).toList();
    records.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return records;
  }

  @override
  Future<void> saveForUser(
    String userId,
    CareAssistantHistoryRecord conversation,
  ) async {
    (_records[userId] ??= {})[conversation.id] = conversation;
  }

  @override
  Future<void> deleteForUser(String userId, String conversationId) async {
    _records[userId]?.remove(conversationId);
  }
}

Future<void> _drainAsyncWork() async {
  for (var index = 0; index < 6; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
