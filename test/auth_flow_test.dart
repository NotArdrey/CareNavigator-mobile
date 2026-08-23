import 'package:care_navigator_ph/src/app/care_navigator_app.dart';
import 'package:care_navigator_ph/src/config/public_config.dart';
import 'package:care_navigator_ph/src/models/auth/user_role.dart';
import 'package:care_navigator_ph/src/providers/core_providers.dart';
import 'package:care_navigator_ph/src/routing/app_router.dart';
import 'package:care_navigator_ph/src/repositories/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer createContainer({
    bool authenticated = false,
    AuthRepository? authRepository,
  }) => ProviderContainer(
    overrides: [
      publicConfigProvider.overrideWithValue(
        const PublicConfig(
          supabaseUrl: '',
          supabasePublishableKey: '',
          appBaseUrl: '',
        ),
      ),
      if (authRepository != null)
        authRepositoryProvider.overrideWithValue(authRepository),
      if (authenticated)
        appIdentityProvider.overrideWith(
          _AuthenticatedPatientIdentityController.new,
        ),
    ],
  );

  Future<void> pumpRoute(
    WidgetTester tester,
    ProviderContainer container,
    String location, {
    Size size = const Size(900, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    container.read(appRouterProvider).go(location);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CareNavigatorApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('authenticated patients leave every authentication route', (
    tester,
  ) async {
    final container = createContainer(authenticated: true);
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final route in const [
      '/sign-in',
      '/register',
      '/verify-otp',
      '/forgot-password',
    ]) {
      await pumpRoute(tester, container, route);
      expect(container.read(appRouterProvider).state.path, '/patient');
    }
  });

  testWidgets('registration uses the mobile width and compact field layout', (
    tester,
  ) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpRoute(tester, container, '/register', size: const Size(375, 812));

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.getSize(find.byType(Card).first).width, closeTo(375, 1));

    Finder fieldWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

    final firstName = fieldWithLabel('First name');
    final lastName = fieldWithLabel('Last name');
    expect(tester.getTopLeft(firstName).dx, tester.getTopLeft(lastName).dx);
    expect(
      tester.getTopLeft(lastName).dy,
      greaterThan(tester.getTopLeft(firstName).dy),
    );

    final mobile = fieldWithLabel('Mobile number');
    final address = fieldWithLabel('Home address');
    expect(tester.getSize(address).height, tester.getSize(mobile).height);

    final consentText = find.text('I agree to the ');
    await tester.ensureVisible(consentText);
    await tester.tap(consentText);
    await tester.pump();
    final createButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create account'),
    );
    expect(createButton.onPressed, isNotNull);
  });

  testWidgets(
    'successful registration redirects to sign-in with confirmation',
    (tester) async {
      final container = createContainer(
        authRepository: _SuccessfulRegistrationRepository(),
      );
      addTearDown(container.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpRoute(
        tester,
        container,
        '/register',
        size: const Size(375, 812),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Patient');
      await tester.enterText(fields.at(1), 'Test');
      await tester.tap(find.text('Select date of birth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Male').last);
      await tester.enterText(fields.at(2), '09171234567');
      await tester.enterText(
        fields.at(3),
        'Unit 4B, 123 Mabini Street, Poblacion, Quezon City',
      );
      await tester.enterText(fields.at(4), 'patient@example.com');
      await tester.enterText(fields.at(5), 'PatientPass1');
      await tester.enterText(fields.at(6), 'PatientPass1');
      tester.widget<Checkbox>(find.byType(Checkbox)).onChanged!(true);
      await tester.pump();

      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create account'),
          )
          .onPressed!();
      await tester.pumpAndSettle();

      final state = container.read(appRouterProvider).state;
      expect(state.uri.path, '/sign-in');
      expect(state.uri.queryParameters['status'], 'account-created');
      expect(find.text('Account created. Check your email.'), findsOneWidget);
    },
  );

  testWidgets('sign-in keeps the production CTA and does not authenticate', (
    tester,
  ) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpRoute(tester, container, '/sign-in');

    expect(find.byType(AppBar), findsNothing);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'not-an-email');
    await tester.enterText(fields.at(1), '');
    final signIn = find.widgetWithText(FilledButton, 'Sign in');
    await tester.tap(signIn);
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);

    await tester.enterText(fields.at(0), 'patient@example.com');
    await tester.enterText(fields.at(1), 'PatientPass1');
    await tester.tap(signIn);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('We could not sign you in right now'),
      findsOneWidget,
    );
    expect(find.textContaining('Supabase'), findsNothing);
    expect(container.read(appIdentityProvider).role, UserRole.guest);
    expect(container.read(appIdentityProvider).isAuthenticated, isFalse);
  });

  testWidgets('guest login is available and reports unavailable auth cleanly', (
    tester,
  ) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpRoute(tester, container, '/sign-in');

    expect(find.text('Continue as guest'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Continue as guest'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Guest access is temporarily unavailable'),
      findsOneWidget,
    );
    expect(container.read(appIdentityProvider).role, UserRole.guest);
    expect(container.read(appIdentityProvider).isAuthenticated, isFalse);
  });

  testWidgets(
    'registration keeps the user-facing copy and does not authenticate',
    (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpRoute(tester, container, '/register');

      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('Show confirmation password'), findsOneWidget);
      expect(find.text('Terms and Conditions'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      final termsLink = find.text('Terms and Conditions');
      await tester.ensureVisible(termsLink);
      await tester.tap(termsLink);
      await tester.pump();
      expect(find.text('Service scope'), findsOneWidget);
      expect(find.text('Not an emergency service'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      final privacyLink = find.text('Privacy Policy');
      await tester.ensureVisible(privacyLink);
      await tester.tap(privacyLink);
      await tester.pump();
      expect(find.text('Information we collect'), findsOneWidget);
      expect(find.text('Storage and security'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Patient');
      await tester.enterText(fields.at(1), 'Test');
      await tester.tap(find.text('Select date of birth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Male').last);
      await tester.enterText(fields.at(2), '09171234567');
      await tester.enterText(
        fields.at(3),
        'Unit 4B, 123 Mabini Street, Poblacion, Quezon City',
      );
      await tester.enterText(fields.at(4), 'patient@example.com');
      await tester.enterText(fields.at(5), 'PatientPass1');
      await tester.enterText(fields.at(6), 'PatientPass1');
      final consentCheckbox = find.byType(Checkbox);
      tester.widget<Checkbox>(consentCheckbox).onChanged!(true);
      await tester.pump();
      final create = find.widgetWithText(FilledButton, 'Create account');
      tester.widget<FilledButton>(create).onPressed!();
      await tester.pumpAndSettle();

      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      expect(container.read(appIdentityProvider).isAuthenticated, isFalse);
    },
  );

  testWidgets('enter moves focus from password to password confirmation', (
    tester,
  ) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpRoute(tester, container, '/register');

    final fields = find.byType(TextFormField);
    final password = fields.at(5);
    final confirmation = fields.at(6);

    await tester.tap(password);
    await tester.enterText(password, 'PatientPass1');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    final confirmationEditable = find.descendant(
      of: confirmation,
      matching: find.byType(EditableText),
    );
    expect(
      tester.widget<EditableText>(confirmationEditable).focusNode.hasFocus,
      isTrue,
    );
    await tester.enterText(confirmation, 'PatientPass1');
    expect(
      tester.widget<TextFormField>(confirmation).controller?.text,
      'PatientPass1',
    );
  });

  testWidgets('OTP accepts six digits without claiming identity verification', (
    tester,
  ) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpRoute(tester, container, '/verify-otp');

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'patient@example.com');
    await tester.enterText(fields.at(1), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify code'));
    await tester.pumpAndSettle();

    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(container.read(appIdentityProvider).isAuthenticated, isFalse);
  });

  testWidgets('recovery validates an email without claiming delivery', (
    tester,
  ) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpRoute(tester, container, '/forgot-password');

    await tester.enterText(find.byType(TextFormField), 'patient@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Send recovery link'));
    await tester.pumpAndSettle();

    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
  });

  testWidgets('password reset enforces confirmation and changes no account', (
    tester,
  ) async {
    final container = createContainer();
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpRoute(tester, container, '/reset-password');

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'PatientPass1');
    await tester.enterText(fields.at(1), 'DifferentPass1');
    final update = find.widgetWithText(FilledButton, 'Update password');
    await tester.tap(update);
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);

    await tester.enterText(fields.at(1), 'PatientPass1');
    await tester.tap(update);
    await tester.pumpAndSettle();
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(container.read(appIdentityProvider).isAuthenticated, isFalse);
  });
}

class _AuthenticatedPatientIdentityController extends AppIdentityController {
  @override
  AppIdentity build() => const AppIdentity(
    role: UserRole.patient,
    status: AccountStatus.active,
    userId: 'test-patient-user',
    displayName: 'Test Patient',
  );
}

class _SuccessfulRegistrationRepository implements AuthRepository {
  @override
  Stream<AppIdentity> watchIdentity() =>
      Stream.value(const AppIdentity.guest());

  @override
  Future<AppIdentity> signInAnonymously() async => const AppIdentity.guest();

  @override
  Future<AppIdentity> signInWithPassword({
    required String email,
    required String password,
  }) async => const AppIdentity.guest();

  @override
  Future<void> register({
    required String email,
    required String password,
    required Map<String, Object?> profileInput,
  }) async {}

  @override
  Future<void> sendEmailOtp(String email) async {}

  @override
  Future<AppIdentity> verifyEmailOtp({
    required String email,
    required String token,
  }) async => const AppIdentity.guest();

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<void> signOut() async {}
}
