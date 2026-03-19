import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholechess/src/game/engine/local_game_controller.dart';

void main() {
  test('cooldown progression is deterministic with injected clock', () {
    fakeAsync((async) {
      var now = DateTime.utc(2026, 3, 18, 12, 0, 0);
      final controller = LocalGameController(
        initialCooldownDuration: const Duration(seconds: 1),
        aiThinkDelayMin: const Duration(days: 1),
        aiThinkDelayMax: const Duration(days: 1),
        nowProvider: () => now,
      );

      controller.startNewGame(playerAsWhite: true);
      controller.tapSquare('e2');
      controller.tapSquare('e4');

      expect(controller.cooldownRemaining('w').inMilliseconds, 1000);

      now = now.add(const Duration(milliseconds: 400));
      async.elapse(const Duration(milliseconds: 400));
      expect(controller.cooldownRemaining('w').inMilliseconds, 600);

      now = now.add(const Duration(milliseconds: 700));
      async.elapse(const Duration(milliseconds: 700));
      expect(controller.cooldownRemaining('w'), Duration.zero);

      controller.dispose();
    });
  });
}
