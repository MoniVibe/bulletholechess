import 'dart:math';

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chess core invariants hold across seeded playouts', () {
    for (var seed = 1; seed <= 25; seed += 1) {
      _simulate(seed: seed, maxPlies: 180);
    }
  });

  test('same seed reproduces identical FEN and legal-count sequence', () {
    const seed = 2048;
    final first = _simulate(seed: seed, maxPlies: 220);
    final second = _simulate(seed: seed, maxPlies: 220);
    expect(first.finalFen, second.finalFen);
    expect(first.fenSequence, second.fenSequence);
    expect(first.legalMoveCounts, second.legalMoveCounts);
  });
}

_SimulationResult _simulate({required int seed, required int maxPlies}) {
  final random = Random(seed);
  final game = chess.Chess();
  final fenSequence = <String>[game.fen];
  final legalMoveCounts = <int>[];

  for (var ply = 0; ply < maxPlies; ply += 1) {
    _expectSingleKings(game);
    _expectFenRoundTrip(game);
    _expectTerminalCoherence(game);

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
    legalMoveCounts.add(legalMoves.length);

    if (legalMoves.isEmpty) {
      _expectTerminalCoherence(game);
      break;
    }

    final sideBeforeMove = color;
    final legalMove = legalMoves[random.nextInt(legalMoves.length)];
    final payload = ChessRules.movePayloadFromLegalMove(legalMove);
    final moved = game.move(payload);
    expect(
      moved,
      isTrue,
      reason: 'seed=$seed ply=$ply move=$payload should be legal',
    );
    final sideAfterMove = ChessRules.colorCode(game.turn);
    expect(sideAfterMove, ChessRules.oppositeColor(sideBeforeMove));
    _expectSingleKings(game);
    _expectFenRoundTrip(game);
    _expectTerminalCoherence(game);
    fenSequence.add(game.fen);
  }

  _expectSingleKings(game);
  _expectFenRoundTrip(game);
  _expectTerminalCoherence(game);
  return _SimulationResult(
    finalFen: game.fen,
    fenSequence: fenSequence,
    legalMoveCounts: legalMoveCounts,
  );
}

void _expectSingleKings(chess.Chess game) {
  final board = ChessRules.boardPiecesFromFen(game.fen);
  final whiteKings = board.values.where((piece) => piece == 'K').length;
  final blackKings = board.values.where((piece) => piece == 'k').length;
  expect(whiteKings, 1);
  expect(blackKings, 1);
}

void _expectFenRoundTrip(chess.Chess game) {
  final roundTrip = chess.Chess();
  expect(roundTrip.load(game.fen), isTrue);
  expect(roundTrip.fen, game.fen);
}

void _expectTerminalCoherence(chess.Chess game) {
  expect(!(game.in_checkmate && game.in_stalemate), isTrue);
  if (game.in_checkmate) {
    expect(game.in_check, isTrue);
    expect(game.moves().isEmpty, isTrue);
  }
  if (game.in_stalemate) {
    expect(game.in_check, isFalse);
    expect(game.moves().isEmpty, isTrue);
  }
}

class _SimulationResult {
  const _SimulationResult({
    required this.finalFen,
    required this.fenSequence,
    required this.legalMoveCounts,
  });

  final String finalFen;
  final List<String> fenSequence;
  final List<int> legalMoveCounts;
}
