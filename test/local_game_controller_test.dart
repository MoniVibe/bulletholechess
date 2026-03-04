import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:bulletholechess/src/game/engine/local_game_controller.dart';

void main() {
  test('startNewGame creates a valid 15-checker state per side', () {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(seconds: 3),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      random: Random(7),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    int totalFor(String color) {
      var total = controller.barCount(color) + controller.borneOffCount(color);
      for (final point in controller.points) {
        if (point.color == color) {
          total += point.count;
        }
      }
      return total;
    }

    expect(controller.hasActiveGame, isTrue);
    expect(totalFor('w'), 15);
    expect(totalFor('b'), 15);
    expect(controller.remainingDice.length, greaterThanOrEqualTo(2));
  });

  test('turn passes to opponent when active timer expires', () async {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(milliseconds: 250),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      random: Random(11),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);
    final initialTurn = controller.turnColor;

    await Future<void>.delayed(const Duration(milliseconds: 520));

    expect(controller.turnColor, isNot(initialTurn));
    expect(
      controller.history.any((entry) => entry.contains('time expired')),
      isTrue,
    );
    expect(controller.cooldownRemaining(initialTurn).inMilliseconds, 0);
  });

  test(
    'cooldown resets only for the mover side after a completed turn',
    () async {
      final controller = LocalGameController(
        initialCooldownDuration: const Duration(milliseconds: 600),
        aiThinkDelayMin: const Duration(days: 1),
        aiThinkDelayMax: const Duration(days: 1),
        random: _FixedRandom(<int>[
          5, 1, // opening roll -> white starts.
          1, 2, // initial turn dice.
          3, 4, // next turn dice.
        ]),
      );
      addTearDown(controller.dispose);

      controller.startNewGame(playerAsWhite: true);
      expect(controller.turnColor, 'w');

      await _playOutTurn(controller);
      expect(controller.turnColor, 'b');

      expect(controller.cooldownRemaining('w').inMilliseconds, greaterThan(0));
      expect(controller.cooldownRemaining('b').inMilliseconds, 0);
    },
  );

  test('player turn exposes playable source highlights', () {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(seconds: 1),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      random: _FixedRandom(<int>[5, 1, 2, 3]),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    expect(controller.turnColor, controller.playerColor);
    expect(controller.playableSourcePoints, isNotEmpty);
    expect(
      controller.sourceDiceUsageHints.keys.toSet(),
      containsAll(controller.playableSourcePoints),
    );
  });

  test('selected checker exposes dice-spend hints for legal targets', () {
    final controller = LocalGameController(
      initialCooldownDuration: const Duration(seconds: 1),
      aiThinkDelayMin: const Duration(days: 1),
      aiThinkDelayMax: const Duration(days: 1),
      random: _FixedRandom(<int>[5, 1, 1, 1]),
    );
    addTearDown(controller.dispose);

    controller.startNewGame(playerAsWhite: true);

    final source = controller.playableSourcePoints.toList()..sort();
    expect(source, isNotEmpty);
    controller.tapPoint(source.first);

    expect(controller.legalTargetPoints, isNotEmpty);
    expect(
      controller.targetDiceSpentHints.keys.toSet(),
      equals(controller.legalTargetPoints),
    );
    expect(
      controller.targetDiceSpentHints.values.every((value) => value >= 1),
      isTrue,
    );
  });
}

Future<void> _playOutTurn(LocalGameController controller) async {
  var guard = 0;
  while (controller.turnColor == controller.playerColor && guard < 20) {
    guard += 1;
    if (controller.canEnterFromBar) {
      controller.tapBar();
      final targets = controller.legalTargetPoints.toList()..sort();
      if (targets.isEmpty) {
        break;
      }
      controller.tapPoint(targets.first);
    } else {
      final sources = controller.playableSourcePoints.toList()..sort();
      if (sources.isEmpty) {
        break;
      }
      controller.tapPoint(sources.first);
      final targets = controller.legalTargetPoints.toList()..sort();
      if (targets.isEmpty) {
        break;
      }
      controller.tapPoint(targets.first);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FixedRandom implements Random {
  _FixedRandom(this._values);

  final List<int> _values;
  int _index = 0;

  @override
  bool nextBool() {
    return nextInt(2) == 1;
  }

  @override
  double nextDouble() {
    return (nextInt(1000000) / 1000000);
  }

  @override
  int nextInt(int max) {
    final value = _values[_index % _values.length];
    _index += 1;
    return value % max;
  }
}
