import 'package:care_navigator_ph/src/widgets/auth/auth_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('auth card renders the hospital background asset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1350);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const AuthCard(
            showHospitalBackground: true,
            title: 'Welcome back',
            description: 'Sign in to access your CareNavigator account.',
            child: SizedBox(height: 280),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.image(
        const AssetImage('assets/images/auth_hospital_background_v2.png'),
      ),
      findsOneWidget,
    );

    final bytes = await rootBundle.load(
      'assets/images/auth_hospital_background_v2.png',
    );
    expect(bytes.lengthInBytes, greaterThan(2_000_000));
  });
}
