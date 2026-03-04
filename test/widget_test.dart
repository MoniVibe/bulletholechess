import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholechess/main.dart';

void main() {
  testWidgets('loads chess shell with AI and online modes', (
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

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Chess Vs AI'), findsOneWidget);
    expect(find.text('Vs AI'), findsOneWidget);
    expect(find.text('Play As'), findsOneWidget);
    expect(find.text('New Game'), findsOneWidget);

    await tester.tap(find.text('Online').first);
    await tester.pumpAndSettle();

    expect(find.text('Matchmaking'), findsOneWidget);
    expect(find.text('Backend URL'), findsOneWidget);
    expect(find.text('Display Name'), findsOneWidget);
    expect(find.text('Cooldown (seconds)'), findsOneWidget);
    expect(find.text('Check Status'), findsOneWidget);
  });
}
