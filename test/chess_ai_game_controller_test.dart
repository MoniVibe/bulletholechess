import 'package:bulletholechess/src/game/engine/chess_ai_game_controller.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new white-side game allows immediate player interaction', () {
    final controller = ChessAiGameController();
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    expect(controller.playerColor, 'w');
    expect(controller.turnColor, 'w');
    expect(controller.canPlayerInteract, isTrue);
    expect(controller.aiThinking, isFalse);
  });

  test('new black-side game schedules first AI move', () async {
    final controller = ChessAiGameController(
      aiMoveDelay: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: false);
    expect(controller.playerColor, 'b');
    expect(controller.aiThinking, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.turnColor, 'b');
    expect(controller.canPlayerInteract, isTrue);
    expect(controller.aiThinking, isFalse);
  });

  test(
    'player is immediately interactive after AI move even with cooldown',
    () async {
      final controller = ChessAiGameController(
        aiMoveDelay: const Duration(milliseconds: 1),
        initialCooldownDuration: const Duration(seconds: 10),
      );
      addTearDown(controller.dispose);

      controller.startNewGame(
        playerAsWhite: true,
        cooldownDuration: const Duration(seconds: 10),
      );

      // White opening move.
      controller.tapSquare('e2');
      controller.tapSquare('e4');

      // Wait for AI reply.
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (controller.aiThinking && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(controller.aiThinking, isFalse);
      expect(controller.turnColor, 'w');
      expect(controller.canPlayerInteract, isTrue);
      expect(controller.cooldownRemaining('w'), Duration.zero);
    },
  );

  test(
    'can queue a move while AI is thinking and auto-executes when legal',
    () async {
      final controller = ChessAiGameController(
        aiMoveDelay: const Duration(milliseconds: 1),
        aiEngine: _DeterministicAiEngine(),
      );
      addTearDown(controller.dispose);

      controller.startNewGame(playerAsWhite: true);

      controller.tapSquare('e2');
      controller.tapSquare('e4');
      expect(controller.aiThinking, isTrue);

      controller.tapSquare('g1');
      controller.tapSquare('f3');
      expect(controller.queuedMoveFrom, 'g1');
      expect(controller.queuedMoveTo, 'f3');

      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (controller.hasQueuedMove && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(controller.hasQueuedMove, isFalse);
      expect(controller.boardPieces['f3'], 'N');
      expect(controller.turnColor, 'b');
    },
  );
}

class _DeterministicAiEngine extends DumbAiEngine {
  _DeterministicAiEngine();

  @override
  EngineMove? chooseMove(chess.Chess game) {
    return const EngineMove(from: 'e7', to: 'e5');
  }
}
