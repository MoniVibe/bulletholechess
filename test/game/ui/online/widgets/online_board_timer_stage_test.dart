import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholechess/src/game/ui/app_assets.dart';
import 'package:bulletholechess/src/game/ui/online/widgets/online_board_timer_stage.dart';

void main() {
  Widget _wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 500, height: 700, child: child)),
    );
  }

  OnlineBoardTimerStage _buildStage({
    required bool isConnected,
    required bool canStart,
    required bool isWaitingForOpponent,
    required bool isMatchActive,
    required bool isGameOver,
    required bool showMatchFoundOverlay,
  }) {
    return OnlineBoardTimerStage(
      pieces: const <String, String>{},
      playerColor: 'w',
      boardAssetPath: 'assets/images/chess/chess_board_classic.png',
      playableInsetRatio: AppAssets.chessBoardPlayableInsetRatio,
      playableSizeRatio: AppAssets.chessBoardPlayableSizeRatio,
      whitePieceSprites: const <String, String>{},
      blackPieceSprites: const <String, String>{},
      whitePieceScale: 1,
      blackPieceScale: 1,
      whitePieceYOffset: 0,
      blackPieceYOffset: 0,
      invertBlackPieceColors: false,
      selectedSquare: null,
      legalTargets: const <String>{},
      playerLastMoveFrom: null,
      playerLastMoveTo: null,
      opponentLastMoveFrom: null,
      opponentLastMoveTo: null,
      queuedMoveFrom: null,
      queuedMoveTo: null,
      checkedKingSquares: const <String>{},
      isOnlineCheckmate: false,
      boardMessage: null,
      onSquareTap: (_) {},
      isConnected: isConnected,
      isWaitingForOpponent: isWaitingForOpponent,
      isMatchActive: isMatchActive,
      isGameOver: isGameOver,
      canStart: canStart,
      onFindMatch: () {},
      showMatchFoundOverlay: showMatchFoundOverlay,
      matchFoundOverlay: const ColoredBox(
        color: Colors.transparent,
        child: Center(child: Text('Match Found!')),
      ),
      victoryOverlay: const ColoredBox(
        color: Colors.transparent,
        child: Center(child: Text('Request New Game')),
      ),
      timeBarOrientation: TimeBarOrientation.horizontal,
      topColor: 'b',
      bottomColor: 'w',
      topRemaining: Duration.zero,
      bottomRemaining: Duration.zero,
      cooldownDuration: const Duration(seconds: 3),
      timerHasStarted: true,
      topIsActiveWindow: false,
      bottomIsActiveWindow: true,
      topIsPlayer: false,
      bottomIsPlayer: true,
    );
  }

  testWidgets('disconnected state shows overlay find match button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _buildStage(
          isConnected: false,
          canStart: false,
          isWaitingForOpponent: false,
          isMatchActive: false,
          isGameOver: false,
          showMatchFoundOverlay: false,
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('chess_online_find_match_overlay')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Find Match'), findsOneWidget);
  });

  testWidgets('connected waiting state shows waiting overlay', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _buildStage(
          isConnected: true,
          canStart: true,
          isWaitingForOpponent: true,
          isMatchActive: false,
          isGameOver: false,
          showMatchFoundOverlay: false,
        ),
      ),
    );

    expect(find.text('Waiting for opponent...'), findsOneWidget);
    expect(find.text('Match Found!'), findsNothing);
  });

  testWidgets('active match state shows two cooldown bars and no overlays', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _buildStage(
          isConnected: true,
          canStart: true,
          isWaitingForOpponent: false,
          isMatchActive: true,
          isGameOver: false,
          showMatchFoundOverlay: false,
        ),
      ),
    );

    expect(find.byType(CooldownMeter), findsNWidgets(2));
    expect(find.text('Waiting for opponent...'), findsNothing);
    expect(find.text('Request New Game'), findsNothing);
  });

  testWidgets('match found overlay appears during active non-game-over state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _buildStage(
          isConnected: true,
          canStart: true,
          isWaitingForOpponent: false,
          isMatchActive: true,
          isGameOver: false,
          showMatchFoundOverlay: true,
        ),
      ),
    );

    expect(find.text('Match Found!'), findsOneWidget);
  });

  testWidgets('game over state shows victory overlay', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _buildStage(
          isConnected: true,
          canStart: true,
          isWaitingForOpponent: false,
          isMatchActive: true,
          isGameOver: true,
          showMatchFoundOverlay: true,
        ),
      ),
    );

    expect(find.text('Request New Game'), findsOneWidget);
    expect(find.text('Match Found!'), findsNothing);
  });
}
