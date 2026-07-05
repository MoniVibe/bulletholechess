import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bulletholechess/main.dart';
import 'package:bulletholechess/src/game/engine/online_game_controller.dart';
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

    // Hermetic transport: the online panel's automatic backend health check
    // (and any other transport call) is served by an in-memory MockClient, so
    // the test never opens a real socket to the Azure matchmaker. This makes
    // the online-tab switch deterministic and independent of test order /
    // network state.
    var healthChecks = 0;
    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/healthz')) {
        healthChecks += 1;
        return http.Response('{"message":"Healthy."}', 200);
      }
      // Any other transport call in this screen stays offline-safe.
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      BulletholeChessApp(
        onlineControllerFactory: () =>
            OnlineGameController(httpClient: mockClient),
      ),
    );
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

    // The panel's initState health check ran against the stub, not the network.
    expect(healthChecks, greaterThanOrEqualTo(1));
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
