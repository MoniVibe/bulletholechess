import 'package:flutter_test/flutter_test.dart';

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
}
