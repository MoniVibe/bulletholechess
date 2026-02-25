// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholechess/main.dart';

void main() {
  testWidgets('loads MVP board shell with collapsible menu', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const BulletholeChessApp());
    await tester.pump();

    expect(find.text('Bullethole Chess MVP'), findsOneWidget);
    expect(find.text('Game Menu'), findsOneWidget);
    expect(find.textContaining('Moves:'), findsOneWidget);

    await tester.tap(find.text('Game Menu'));
    await tester.pumpAndSettle();

    expect(find.text('New Game: White'), findsOneWidget);
    expect(find.text('Cooldown (seconds)'), findsOneWidget);
  });
}
