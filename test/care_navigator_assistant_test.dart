import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/care_assistant_provider.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/repositories/care_assistant_repository.dart';
import 'package:care_navigator_ph/src/repositories/public_settings_repository.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer createContainer({bool authenticated = true}) =>
      ProviderContainer(
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
          if (authenticated)
            appIdentityProvider.overrideWith(
              _TestAuthenticatedIdentityController.new,
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
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpDirectory(tester, container);

    await tester.tap(find.text('Care assistant'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      "I am gasping and can't breathe.",
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send_outlined));
    await tester.pumpAndSettle();

    expect(
      container.read(careAssistantProvider).status,
      CareAssistantStatus.emergency,
    );
    await tester.drag(
      find.byKey(const Key('care-assistant-messages')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    expect(find.text('Call 911'), findsOneWidget);
    expect(find.text('Open emergency facilities'), findsOneWidget);
  });

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
  @override
  AppIdentity build() => const AppIdentity(
    role: UserRole.patient,
    status: AccountStatus.active,
    userId: 'test-user-id',
    displayName: 'Test User',
  );
}
