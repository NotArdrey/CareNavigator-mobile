import 'dart:ui' show Tristate;

import 'package:care_navigator_ph/src/widgets/data_display/content_panel.dart';
import 'package:care_navigator_ph/src/widgets/feedback/async_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('content panel exposes its title as a heading', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPrimitive(
        tester,
        const ContentPanel(title: 'Record details', child: Text('Body')),
      );

      final heading = tester.getSemantics(find.text('Record details'));
      expect(heading.flagsCollection.isHeader, isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'data state announces changes and exposes its title as a heading',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpPrimitive(
          tester,
          const DataState(
            icon: Icons.search_off,
            title: 'No matching records',
            message: 'Change the filters and try again.',
          ),
        );

        expect(
          tester
              .getSemantics(find.byType(DataState))
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(
          tester
              .getSemantics(find.text('No matching records'))
              .flagsCollection
              .isHeader,
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('status tag has a concise non-duplicated semantic label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPrimitive(
        tester,
        const StatusTag(
          label: 'Pending review',
          icon: Icons.schedule,
          color: Colors.orange,
        ),
      );

      expect(find.bySemanticsLabel('Pending review'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('busy async action is announced and remains disabled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    try {
      await _pumpPrimitive(
        tester,
        AsyncActionButton(
          label: 'Save changes',
          icon: Icons.save_outlined,
          busy: true,
          onPressed: () => presses += 1,
        ),
      );

      final node = tester.getSemantics(
        find.bySemanticsLabel('Save changes in progress'),
      );
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isLiveRegion, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);

      await tester.tap(find.text('Working…'));
      await tester.pump();
      expect(presses, 0);
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _pumpPrimitive(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}
