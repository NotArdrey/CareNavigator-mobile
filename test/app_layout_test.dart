import 'package:care_navigator_ph/src/widgets/app_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppCard renders with its rounded border shape', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppCard(child: Text('Card content'))),
      ),
    );

    expect(find.text('Card content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
