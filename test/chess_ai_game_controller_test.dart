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

    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (controller.history.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(controller.history, isNotEmpty);
    expect(controller.canPlayerInteract, isTrue);
  });

  test('player stays on own cooldown after AI move', () async {
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

    // Wait for AI reply to be applied.
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (controller.history.length < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(controller.history.length, greaterThanOrEqualTo(2));
    expect(controller.canPlayerInteract, isFalse);
    expect(controller.cooldownRemaining('w').inMilliseconds, greaterThan(0));
  });

  test('player move advances nominal turn color', () {
    final controller = ChessAiGameController(
      aiMoveDelay: const Duration(days: 1),
      initialCooldownDuration: Duration.zero,
      aiEngine: _NoopAiEngine(),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(
      playerAsWhite: true,
      cooldownDuration: Duration.zero,
    );

    controller.tapSquare('e2');
    controller.tapSquare('e4');

    expect(controller.turnColor, 'b');
  });

  test('player pawn keeps ownership after e2-e4', () {
    final controller = ChessAiGameController(
      aiMoveDelay: const Duration(days: 1),
      initialCooldownDuration: Duration.zero,
      aiEngine: _NoopAiEngine(),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(
      playerAsWhite: true,
      cooldownDuration: Duration.zero,
    );

    controller.tapSquare('e2');
    controller.tapSquare('e4');

    expect(controller.boardPieces['e4'], 'P');
    expect(controller.boardPieces.containsKey('e2'), isFalse);
  });

  test('consecutive same-color pawn pushes preserve ownership', () {
    final controller = ChessAiGameController(
      aiMoveDelay: const Duration(days: 1),
      initialCooldownDuration: Duration.zero,
      aiEngine: _NoopAiEngine(),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(
      playerAsWhite: true,
      cooldownDuration: Duration.zero,
    );

    controller.tapSquare('e2');
    controller.tapSquare('e4');
    controller.tapSquare('d2');
    controller.tapSquare('d4');

    expect(controller.boardPieces['e4'], 'P');
    expect(controller.boardPieces['d4'], 'P');
    expect(controller.boardPieces.containsKey('e2'), isFalse);
    expect(controller.boardPieces.containsKey('d2'), isFalse);
  });

  test(
    'can queue a move while AI is thinking and auto-executes when legal',
    () async {
      final controller = ChessAiGameController(
        aiMoveDelay: const Duration(milliseconds: 1),
        initialCooldownDuration: const Duration(milliseconds: 200),
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

  test(
    'player can make consecutive moves when AI does not act before cooldown ends',
    () async {
      final controller = ChessAiGameController(
        aiMoveDelay: const Duration(seconds: 5),
        initialCooldownDuration: const Duration(seconds: 1),
        aiEngine: _DeterministicAiEngine(),
      );
      addTearDown(controller.dispose);

      controller.startNewGame(
        playerAsWhite: true,
        cooldownDuration: const Duration(seconds: 1),
      );

      controller.tapSquare('e2');
      controller.tapSquare('e4');

      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(controller.canPlayerInteract, isTrue);
      controller.tapSquare('g1');
      controller.tapSquare('f3');

      expect(controller.boardPieces['f3'], 'N');
      expect(controller.playerLastMoveFrom, 'g1');
      expect(controller.playerLastMoveTo, 'f3');
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

class _NoopAiEngine extends DumbAiEngine {
  @override
  EngineMove? chooseMove(chess.Chess game) => null;
}
