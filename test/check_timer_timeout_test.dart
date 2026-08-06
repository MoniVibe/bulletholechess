import 'package:bulletholechess/src/game/engine/chess_ai_game_controller.dart';
import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';
import 'package:chess/chess.dart' as chess;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives a passive (never-moving) black king into check by marching a white
/// knight b1->c3->b5->d6. With the NoOp AI, black stays in check, which lets us
/// exercise the check-escape timer deterministically under a fake clock.
void _checkPassiveBlackKing(ChessAiGameController controller) {
  controller.tapSquare('b1');
  controller.tapSquare('c3');
  controller.tapSquare('c3');
  controller.tapSquare('b5');
  controller.tapSquare('b5');
  controller.tapSquare('d6');
}

void main() {
  test('checked side loses when the check timer expires', () {
    fakeAsync((async) {
      var now = DateTime.utc(2026, 3, 18, 12, 0, 0);
      final controller = ChessAiGameController(
        aiMoveDelay: const Duration(days: 1),
        initialCooldownDuration: Duration.zero,
        initialCheckTimeoutDuration: const Duration(seconds: 5),
        aiEngine: _NoopAiEngine(),
        nowProvider: () => now,
      );

      controller.startNewGame(
        playerAsWhite: true,
        cooldownDuration: Duration.zero,
        checkTimeoutDuration: const Duration(seconds: 5),
      );

      _checkPassiveBlackKing(controller);

      // Nd6+ puts the passive black king on a running check clock.
      expect(controller.checkTimerColor, 'b');
      expect(controller.isCheckCountdownActive, isTrue);
      expect(controller.isGameOver, isFalse);
      expect(controller.checkTimeRemaining('b').inMilliseconds, 5000);

      // Run past the 5s escape window; the periodic ticker enforces the loss.
      now = now.add(const Duration(seconds: 6));
      async.elapse(const Duration(seconds: 6));

      expect(controller.isGameOver, isTrue);
      expect(controller.isCheckTimeoutLoss, isTrue);
      expect(controller.checkTimeoutLoserColor, 'b');
      expect(controller.winnerLabel, 'White');
      expect(controller.isCheckmate, isFalse);

      controller.dispose();
    });
  });

  test('a side that escapes check clears the clock and avoids a loss', () {
    fakeAsync((async) {
      var now = DateTime.utc(2026, 3, 18, 12, 0, 0);
      final controller = ChessAiGameController(
        aiMoveDelay: const Duration(milliseconds: 500),
        initialCooldownDuration: Duration.zero,
        initialCheckTimeoutDuration: const Duration(seconds: 5),
        aiEngine: _CaptureD6KnightAiEngine(),
        nowProvider: () => now,
      );

      controller.startNewGame(
        playerAsWhite: true,
        cooldownDuration: Duration.zero,
        checkTimeoutDuration: const Duration(seconds: 5),
      );

      _checkPassiveBlackKing(controller);
      expect(controller.checkTimerColor, 'b');
      expect(controller.isCheckCountdownActive, isTrue);

      // The AI escapes by capturing the checking knight (exd6) ~500ms in,
      // well inside the 5s window. The check clock must clear.
      now = now.add(const Duration(milliseconds: 700));
      async.elapse(const Duration(milliseconds: 700));
      expect(controller.boardPieces['d6'], 'p');
      expect(controller.checkTimerColor, isNull);
      expect(controller.isCheckCountdownActive, isFalse);
      expect(controller.isGameOver, isFalse);

      // Long past the original deadline: no false loss, because black escaped.
      now = now.add(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 10));
      expect(controller.isGameOver, isFalse);
      expect(controller.isCheckTimeoutLoss, isFalse);

      controller.dispose();
    });
  });

  test('check timer Off never triggers a timeout loss', () {
    fakeAsync((async) {
      var now = DateTime.utc(2026, 3, 18, 12, 0, 0);
      final controller = ChessAiGameController(
        aiMoveDelay: const Duration(days: 1),
        initialCooldownDuration: Duration.zero,
        initialCheckTimeoutDuration: Duration.zero,
        aiEngine: _NoopAiEngine(),
        nowProvider: () => now,
      );

      controller.startNewGame(
        playerAsWhite: true,
        cooldownDuration: Duration.zero,
        checkTimeoutDuration: Duration.zero,
      );

      _checkPassiveBlackKing(controller);

      expect(controller.hasCheckTimeout, isFalse);
      expect(controller.checkTimerColor, isNull);
      expect(controller.isCheckCountdownActive, isFalse);

      now = now.add(const Duration(minutes: 5));
      async.elapse(const Duration(minutes: 5));

      expect(controller.isGameOver, isFalse);
      expect(controller.isCheckTimeoutLoss, isFalse);

      controller.dispose();
    });
  });
}

class _NoopAiEngine extends DumbAiEngine {
  @override
  EngineMove? chooseMove(chess.Chess game) => null;
}

/// Escapes Nd6+ by capturing the checking knight with the e7 pawn (exd6),
/// then stays passive.
class _CaptureD6KnightAiEngine extends DumbAiEngine {
  @override
  EngineMove? chooseMove(chess.Chess game) {
    final board = ChessRules.boardPiecesFromFen(game.fen);
    if (board['d6'] == 'N') {
      return const EngineMove(from: 'e7', to: 'd6');
    }
    return null;
  }
}
