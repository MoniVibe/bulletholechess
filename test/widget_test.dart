import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholechess/main.dart';
import 'package:bulletholechess/src/game/ui/chess_board_view.dart';

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
    expect(find.text('Backend URL'), findsNothing);
    expect(find.text('Display Name'), findsOneWidget);
    expect(find.text('Cooldown (seconds)'), findsOneWidget);
    expect(find.text('Check Status'), findsOneWidget);
  });

  testWidgets('AI new game leaves desktop board at playable size', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const BulletholeChessApp());
    await tester.pumpAndSettle();

    const newGameKey = ValueKey<String>('chess_ai_new_game');
    expect(find.byKey(newGameKey), findsOneWidget);

    await tester.tap(find.byKey(newGameKey));
    await tester.pumpAndSettle();

    expect(find.byType(ChessBoardView), findsOneWidget);
    expect(tester.getSize(find.byType(ChessBoardView)).width, greaterThan(280));
  });
}
