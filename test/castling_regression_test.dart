import 'package:bulletholechess/src/game/engine/chess_ai_game_controller.dart';
import 'package:bulletholechess/src/game/engine/local_game_controller.dart';
import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

class _NoopAiEngine extends DumbAiEngine {
  @override
  EngineMove? chooseMove(chess.Chess game) => null;
}

void main() {
  test('kingside castling target is present for king selection', () {
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
    controller.tapSquare('g1');
    controller.tapSquare('f3');
    controller.tapSquare('f1');
    controller.tapSquare('e2');

    controller.tapSquare('e1');

    expect(controller.legalTargets.contains('g1'), isTrue);
  });

  test('castling target exists with opposite turn and en-passant marker', () {
    final game = chess.Chess();
    final loaded = game.load('r3k2r/8/8/8/8/8/8/R3K2R b KQkq e3 0 1');
    expect(loaded, isTrue);

    final targets = ChessRules.legalDestinationsFrom(
      game: game,
      square: 'e1',
      color: 'w',
    );

    expect(targets.contains('g1'), isTrue);
    expect(targets.contains('c1'), isTrue);
  });

  test('black kingside castling target is present for king selection', () {
    final controller = LocalGameController(
      initialCooldownDuration: Duration.zero,
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      aiEngine: _NoopAiEngine(),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(
      playerAsWhite: false,
      cooldownDuration: Duration.zero,
    );

    controller.tapSquare('e7');
    controller.tapSquare('e5');
    controller.tapSquare('g8');
    controller.tapSquare('f6');
    controller.tapSquare('f8');
    controller.tapSquare('e7');

    controller.tapSquare('e8');

    expect(controller.legalTargets.contains('g8'), isTrue);
  });
}
