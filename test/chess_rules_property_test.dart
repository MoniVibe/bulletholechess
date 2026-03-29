import 'dart:math';

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('king-count and legal-move invariants hold across seeded playouts', () {
    for (var seed = 1; seed <= 25; seed += 1) {
      _simulate(seed: seed, maxPlies: 180);
    }
  });

  test('same seed produces same terminal FEN fingerprint', () {
    const seed = 2048;
    final first = _simulate(seed: seed, maxPlies: 220);
    final second = _simulate(seed: seed, maxPlies: 220);
    expect(first, second);
  });
}

String _simulate({required int seed, required int maxPlies}) {
  final random = Random(seed);
  final game = chess.Chess();

  for (var ply = 0; ply < maxPlies; ply += 1) {
    _expectSingleKings(game);

    if (game.game_over) {
      break;
    }

    final color = ChessRules.colorCode(game.turn);
    final legalMoves = ChessRules.withTurn(
      game,
      color,
      () => game
          .moves(<String, dynamic>{'verbose': true})
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );

    if (legalMoves.isEmpty) {
      break;
    }

    final legalMove = legalMoves[random.nextInt(legalMoves.length)];
    final payload = ChessRules.movePayloadFromLegalMove(legalMove);
    final moved = game.move(payload);
    expect(
      moved,
      isTrue,
      reason: 'seed=$seed ply=$ply move=$payload should be legal',
    );
  }

  _expectSingleKings(game);
  return game.fen;
}

void _expectSingleKings(chess.Chess game) {
  final board = ChessRules.boardPiecesFromFen(game.fen);
  final whiteKings = board.values.where((piece) => piece == 'K').length;
  final blackKings = board.values.where((piece) => piece == 'k').length;
  expect(whiteKings, 1);
  expect(blackKings, 1);
}
