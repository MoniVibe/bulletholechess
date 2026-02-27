import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';
import 'package:bulletholechess/src/game/engine/local_game_controller.dart';

void main() {
  test('own-piece tap during cooldown can queue speculative recapture', () {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(seconds: 5),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    controller.tapSquare('e2');
    controller.tapSquare('e4');

    expect(controller.cooldownRemaining('w').inMilliseconds, greaterThan(0));

    controller.tapSquare('g1');
    controller.tapSquare('h2');

    expect(controller.hasQueuedMove, isTrue);
    expect(controller.queuedMoveFrom, 'g1');
    expect(controller.queuedMoveTo, 'h2');
    expect(controller.selectedSquare, isNull);
  });

  test('queued move executes when cooldown expires', () async {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(milliseconds: 250),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    controller.tapSquare('e2');
    controller.tapSquare('e4');

    controller.tapSquare('d2');
    controller.tapSquare('d4');

    expect(controller.hasQueuedMove, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(controller.hasQueuedMove, isFalse);
    expect(controller.boardPieces['d4'], 'P');
    expect(controller.boardPieces.containsKey('d2'), isFalse);
  });

  test('player can still move legally while in check', () async {
    final controller = LocalGameController(
      initialCooldownDuration: Duration.zero,
      aiThinkDelayMin: const Duration(milliseconds: 10),
      aiThinkDelayMax: const Duration(milliseconds: 10),
      aiEngine: _ScriptedAiEngine(<EngineMove>[
        const EngineMove(from: 'e7', to: 'e5'),
        const EngineMove(from: 'd8', to: 'h4'),
      ]),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    controller.tapSquare('f2');
    controller.tapSquare('f3');
    await _waitUntil(() => controller.boardPieces['e5'] == 'p');

    controller.tapSquare('a2');
    controller.tapSquare('a3');
    await _waitUntil(() => controller.boardPieces['h4'] == 'q');

    expect(controller.isGameOver, isFalse);
    expect(controller.statusText, contains('in check'));
    expect(controller.canPlayerInteract, isTrue);

    controller.tapSquare('g2');
    expect(controller.selectedSquare, 'g2');
    expect(controller.legalTargets.contains('g3'), isTrue);

    controller.tapSquare('g3');
    expect(controller.boardPieces['g3'], 'P');
    expect(controller.boardPieces.containsKey('g2'), isFalse);
  });

  test('player can castle kingside when legal', () {
    final controller = LocalGameController(
      initialCooldownDuration: Duration.zero,
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      aiEngine: _ScriptedAiEngine(const <EngineMove>[]),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    controller.tapSquare('e2');
    controller.tapSquare('e4');
    controller.tapSquare('g1');
    controller.tapSquare('f3');
    controller.tapSquare('f1');
    controller.tapSquare('e2');
    controller.tapSquare('e1');
    controller.tapSquare('g1');

    expect(controller.boardPieces['g1'], 'K');
    expect(controller.boardPieces['f1'], 'R');
    expect(controller.boardPieces.containsKey('e1'), isFalse);
    expect(controller.boardPieces.containsKey('h1'), isFalse);
  });
}

class _ScriptedAiEngine extends DumbAiEngine {
  _ScriptedAiEngine(this._scriptedMoves);

  final List<EngineMove> _scriptedMoves;

  @override
  EngineMove? chooseMove(chess.Chess game) {
    while (_scriptedMoves.isNotEmpty) {
      final candidate = _scriptedMoves.removeAt(0);
      if (_isLegal(game, candidate)) {
        return candidate;
      }
    }
    return null;
  }

  bool _isLegal(chess.Chess game, EngineMove move) {
    final legalMoves = game
        .moves({'verbose': true})
        .map((dynamic item) => Map<String, dynamic>.from(item as Map));

    for (final legal in legalMoves) {
      if (legal['from'] == move.from && legal['to'] == move.to) {
        final promotion = legal['promotion'] as String?;
        return promotion == null || promotion == move.promotion;
      }
    }
    return false;
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  Duration pollEvery = const Duration(milliseconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(pollEvery);
  }
  fail('Timed out waiting for condition.');
}
