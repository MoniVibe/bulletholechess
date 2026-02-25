import 'dart:math';

import 'package:chess/chess.dart' as chess;

class EngineMove {
  const EngineMove({
    required this.from,
    required this.to,
    this.promotion = 'q',
  });

  final String from;
  final String to;
  final String promotion;
}

class DumbAiEngine {
  DumbAiEngine({Random? random}) : _random = random ?? Random();

  final Random _random;

  EngineMove? chooseMove(chess.Chess game) {
    final rawMoves = game.moves({'verbose': true});
    if (rawMoves.isEmpty) {
      return null;
    }

    final moves = rawMoves
        .map((dynamic item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final tacticalMoves = moves.where((move) {
      final flags = move['flags'] as String? ?? '';
      return flags.contains('c') || flags.contains('e');
    }).toList();

    final pool = tacticalMoves.isNotEmpty ? tacticalMoves : moves;
    final selected = pool[_random.nextInt(pool.length)];

    return EngineMove(
      from: selected['from'] as String,
      to: selected['to'] as String,
    );
  }
}
