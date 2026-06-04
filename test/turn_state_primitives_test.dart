import 'package:bulletholechess/src/game/engine/turn_state_primitives.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurnCooldownTracker', () {
    test('tracks and expires cooldown for each color independently', () {
      var nowMs = 1_000;
      final tracker = TurnCooldownTracker(nowMsProvider: () => nowMs);
      tracker.resetReadyNow();

      tracker.startCooldown(
        color: 'w',
        cooldownDuration: const Duration(milliseconds: 500),
      );

      expect(tracker.remaining('w').inMilliseconds, 500);
      expect(tracker.remaining('b'), Duration.zero);

      nowMs = 1_300;
      expect(tracker.remaining('w').inMilliseconds, 200);

      nowMs = 1_500;
      expect(tracker.remaining('w'), Duration.zero);
    });
  });

  group('QueuedMoveState', () {
    test('stores, exposes, and clears queued move atomically', () {
      final queue = QueuedMoveState(defaultPromotion: 'q');

      expect(queue.hasMove, isFalse);
      expect(queue.promotion, 'q');

      queue.queue(from: 'e2', to: 'e4', promotion: 'q');

      expect(queue.hasMove, isTrue);
      expect(queue.from, 'e2');
      expect(queue.to, 'e4');
      expect(queue.label, 'e2-e4');
      expect(queue.promotion, 'q');

      final cleared = queue.clear();
      expect(cleared, isNotNull);
      expect(cleared!.from, 'e2');
      expect(cleared.to, 'e4');
      expect(cleared.promotion, 'q');
      expect(queue.hasMove, isFalse);
      expect(queue.from, isNull);
      expect(queue.to, isNull);
      expect(queue.promotion, 'q');
    });
  });

  group('ForfeitLockState', () {
    test('blocks forfeited color until release-by mover cooldown expires', () {
      final lock = ForfeitLockState();
      final cooldowns = <String, Duration>{
        'w': Duration.zero,
        'b': const Duration(milliseconds: 100),
      };

      Duration remaining(String color) => cooldowns[color] ?? Duration.zero;

      lock.updateAfterMove(moverColor: 'b', nominalTurnColor: 'w');
      expect(
        lock.isBlocked(
          'w',
          resolveTimeout: false,
          cooldownRemaining: remaining,
        ),
        isTrue,
      );
      expect(lock.isBlocked('b', cooldownRemaining: remaining), isFalse);
      expect(lock.isBlocked('w', cooldownRemaining: remaining), isTrue);

      cooldowns['b'] = Duration.zero;
      expect(lock.isBlocked('w', cooldownRemaining: remaining), isFalse);
    });

    test('clears immediately when release-by mover resolves lock via move', () {
      final lock = ForfeitLockState();

      lock.updateAfterMove(moverColor: 'b', nominalTurnColor: 'w');
      lock.updateAfterMove(moverColor: 'b', nominalTurnColor: 'w');

      expect(
        lock.isBlocked('w', cooldownRemaining: (_) => Duration.zero),
        isFalse,
      );
      expect(
        lock.isBlocked('b', cooldownRemaining: (_) => Duration.zero),
        isFalse,
      );
    });
  });
}
