import 'package:care_navigator_ph/src/widgets/data_display/hospital_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('legacy missing asset paths use the hospital fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HospitalImage(
          imageUrl: 'assets/images/hospital-fallback.png',
          height: 120,
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.local_hospital_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
