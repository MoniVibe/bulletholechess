import 'dart:math';

import 'package:chess/chess.dart' as chess;

import 'chess_rules.dart';

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

/// Minimax/alpha-beta based engine.
///
/// Keeps the existing class name to avoid touching controller wiring, but this
/// is no longer purely "dumb". It is still lightweight enough for UI smoke
/// runs, with deterministic anti-loop nudges to avoid repetitive rook shuffles.
class DumbAiEngine {
  DumbAiEngine({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<String> _recentPositionKeys = <String>[];
  String? _lastObservedPositionKey;

  static const int _infinity = 1 << 30;
  static const int _mateScore = 100000;
  static const int _recentPositionWindow = 24;
  static const int _repetitionPenalty = 26;
  static const int _repeatMovePenaltyStep = 18;
  static const int _immediateBacktrackPenalty = 95;
  static const int _overusedMovePenalty = 1200;
  static const int _maxSameMoveCount = 3;
  static const int _recentOwnMoveWindowPlies = 24;

  EngineMove? chooseMove(chess.Chess game) {
    final rawMoves = game.moves(const <String, dynamic>{'verbose': true});
    if (rawMoves.isEmpty) {
      return null;
    }
    final moves = rawMoves
        .map((dynamic item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);

    _recordCurrentPosition(game);

    final rootColor = ChessRules.colorCode(game.turn);
    final depth = _searchDepthForPosition(game);
    final ownMoveStats = _collectOwnMoveStats(game);

    var bestScore = -_infinity;
    final topMoves = <Map<String, dynamic>>[];
    for (final move in _orderedMoves(moves)) {
      var moved = false;
      try {
        moved = game.move(ChessRules.movePayloadFromLegalMove(move));
        if (!moved) {
          continue;
        }
        final nextPositionKey = _normalizedPositionKey(game.fen);

        var score = _search(
          game: game,
          depth: depth - 1,
          alpha: -_infinity,
          beta: _infinity,
          rootColor: rootColor,
        );
        score -= _rootLoopPenalty(move, ownMoveStats, nextPositionKey);

        if (score > bestScore) {
          bestScore = score;
          topMoves
            ..clear()
            ..add(move);
        } else if (score == bestScore) {
          topMoves.add(move);
        }
      } catch (_) {
        // Keep search resilient in pathological states surfaced by soak runs.
        continue;
      } finally {
        if (moved) {
          game.undo();
        }
      }
    }

    final pool = topMoves.isEmpty ? moves : topMoves;
    final selected = pool[_random.nextInt(pool.length)];
    return EngineMove(
      from: selected['from'] as String,
      to: selected['to'] as String,
      promotion: selected['promotion'] as String? ?? 'q',
    );
  }

  int _search({
    required chess.Chess game,
    required int depth,
    required int alpha,
    required int beta,
    required String rootColor,
  }) {
    if (depth <= 0 || game.game_over) {
      return _evaluate(game, rootColor, depth);
    }

    final rawMoves = game.moves(const <String, dynamic>{'verbose': true});
    if (rawMoves.isEmpty) {
      return _evaluate(game, rootColor, depth);
    }
    final moves = rawMoves
        .map((dynamic item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);

    final turnColor = ChessRules.colorCode(game.turn);
    final maximizing = turnColor == rootColor;

    if (maximizing) {
      var value = -_infinity;
      for (final move in _orderedMoves(moves)) {
        var moved = false;
        late final int score;
        try {
          moved = game.move(ChessRules.movePayloadFromLegalMove(move));
          if (!moved) {
            continue;
          }
          score = _search(
            game: game,
            depth: depth - 1,
            alpha: alpha,
            beta: beta,
            rootColor: rootColor,
          );
        } finally {
          if (moved) {
            game.undo();
          }
        }
        if (score > value) {
          value = score;
        }
        if (value > alpha) {
          alpha = value;
        }
        if (alpha >= beta) {
          break;
        }
      }
      return value;
    }

    var value = _infinity;
    for (final move in _orderedMoves(moves)) {
      var moved = false;
      late final int score;
      try {
        moved = game.move(ChessRules.movePayloadFromLegalMove(move));
        if (!moved) {
          continue;
        }
        score = _search(
          game: game,
          depth: depth - 1,
          alpha: alpha,
          beta: beta,
          rootColor: rootColor,
        );
      } finally {
        if (moved) {
          game.undo();
        }
      }
      if (score < value) {
        value = score;
      }
      if (value < beta) {
        beta = value;
      }
      if (alpha >= beta) {
        break;
      }
    }
    return value;
  }

  int _evaluate(chess.Chess game, String rootColor, int depth) {
    if (game.in_checkmate) {
      final loser = ChessRules.colorCode(game.turn);
      final winner = ChessRules.oppositeColor(loser);
      final score = _mateScore + depth;
      return winner == rootColor ? score : -score;
    }

    if (game.in_stalemate || game.insufficient_material || game.in_draw) {
      return 0;
    }

    final board = ChessRules.boardPiecesFromFen(game.fen);
    var whiteScore = 0;

    for (final entry in board.entries) {
      final square = entry.key;
      final piece = entry.value;
      final color = ChessRules.pieceColor(piece);
      final pieceScore =
          _pieceBaseValue(piece) +
          _pieceSquareBonus(piece: piece, square: square);
      whiteScore += color == 'w' ? pieceScore : -pieceScore;
    }

    final whiteMobility = ChessRules.withTurn(
      game,
      'w',
      () => _safeMoveCount(game),
    );
    final blackMobility = ChessRules.withTurn(
      game,
      'b',
      () => _safeMoveCount(game),
    );
    whiteScore += (whiteMobility - blackMobility) * 2;

    final whiteInCheck = ChessRules.withTurn(
      game,
      'w',
      () => _safeInCheck(game),
    );
    final blackInCheck = ChessRules.withTurn(
      game,
      'b',
      () => _safeInCheck(game),
    );
    if (whiteInCheck) {
      whiteScore -= 24;
    }
    if (blackInCheck) {
      whiteScore += 24;
    }

    // Small deterministic jitter to break perfect ties.
    whiteScore += _random.nextInt(3) - 1;
    return rootColor == 'w' ? whiteScore : -whiteScore;
  }

  int _searchDepthForPosition(chess.Chess game) {
    final pieces = ChessRules.boardPiecesFromFen(game.fen).length;
    if (pieces <= 8) {
      return 4;
    }
    if (pieces <= 14) {
      return 3;
    }
    return 2;
  }

  Iterable<Map<String, dynamic>> _orderedMoves(
    List<Map<String, dynamic>> moves,
  ) {
    final sorted = List<Map<String, dynamic>>.from(moves);
    sorted.sort((a, b) => _moveOrderScore(b).compareTo(_moveOrderScore(a)));
    return sorted;
  }

  int _moveOrderScore(Map<String, dynamic> move) {
    final flags = move['flags'] as String? ?? '';
    final san = move['san'] as String? ?? '';
    var score = 0;
    if (flags.contains('c') || flags.contains('e')) {
      score += 90 + _pieceBaseValue((move['captured'] ?? '').toString());
    }
    if (flags.contains('p')) {
      score += 120;
    }
    if (san.contains('+')) {
      score += 30;
    }
    if (san.contains('#')) {
      score += 1000;
    }
    return score;
  }

  int _rootLoopPenalty(
    Map<String, dynamic> move,
    _OwnMoveStats ownMoveStats,
    String nextPositionKey,
  ) {
    final from = move['from'] as String?;
    final to = move['to'] as String?;
    if (from == null || to == null) {
      return 0;
    }

    var penalty = 0;
    final moveKey = '$from-$to';
    final sameMoveCount = ownMoveStats.moveCountByKey[moveKey] ?? 0;
    penalty += sameMoveCount * _repeatMovePenaltyStep;
    if (sameMoveCount >= _maxSameMoveCount) {
      penalty += _overusedMovePenalty;
    }
    if (ownMoveStats.lastFrom == to && ownMoveStats.lastTo == from) {
      penalty += _immediateBacktrackPenalty;
    }

    final repeatedCount = _recentPositionKeys
        .where((key) => key == nextPositionKey)
        .length;
    penalty += repeatedCount * _repetitionPenalty;
    return penalty;
  }

  int _pieceBaseValue(String piece) {
    switch (piece.toLowerCase()) {
      case 'p':
        return 100;
      case 'n':
        return 320;
      case 'b':
        return 330;
      case 'r':
        return 500;
      case 'q':
        return 900;
      case 'k':
        return 0;
      default:
        return 0;
    }
  }

  int _pieceSquareBonus({required String piece, required String square}) {
    if (square.length != 2) {
      return 0;
    }
    final fileCode = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.tryParse(square[1]) ?? 1;
    if (fileCode < 0 || fileCode > 7 || rank < 1 || rank > 8) {
      return 0;
    }

    final fileDistanceToCenter = min(
      (fileCode - 3).abs(),
      (fileCode - 4).abs(),
    );
    final rankDistanceToCenter = min((rank - 4).abs(), (rank - 5).abs());
    final centerBonus = 4 - fileDistanceToCenter - rankDistanceToCenter;

    if (piece.toLowerCase() == 'p') {
      if (piece == piece.toUpperCase()) {
        return centerBonus * 2 + (rank - 2) * 3;
      }
      return centerBonus * 2 + (7 - rank) * 3;
    }

    if (piece.toLowerCase() == 'k') {
      // Mildly encourage central king only in simplified positions.
      return centerBonus;
    }

    return centerBonus * 2;
  }

  void _recordCurrentPosition(chess.Chess game) {
    if (game.history.length <= 1) {
      _recentPositionKeys.clear();
      _lastObservedPositionKey = null;
    }

    final currentKey = _normalizedPositionKey(game.fen);
    if (_lastObservedPositionKey == currentKey) {
      return;
    }

    _recentPositionKeys.add(currentKey);
    if (_recentPositionKeys.length > _recentPositionWindow) {
      _recentPositionKeys.removeAt(0);
    }
    _lastObservedPositionKey = currentKey;
  }

  String _normalizedPositionKey(String fen) {
    final parts = fen.split(' ');
    if (parts.length < 4) {
      return fen;
    }
    return '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';
  }

  _OwnMoveStats _collectOwnMoveStats(chess.Chess game) {
    final currentSideIsWhite = game.turn == chess.Color.WHITE;
    final history = game.getHistory(<String, dynamic>{'verbose': true});
    final moveCountByKey = <String, int>{};
    String? lastFrom;
    String? lastTo;

    final start = max(0, history.length - _recentOwnMoveWindowPlies);
    for (var i = start; i < history.length; i += 1) {
      final entry = history[i];
      if (entry is! Map) {
        continue;
      }
      final sideIsWhite = i.isEven;
      if (sideIsWhite != currentSideIsWhite) {
        continue;
      }
      final from = entry['from'] as String?;
      final to = entry['to'] as String?;
      if (from == null || to == null) {
        continue;
      }
      final key = '$from-$to';
      moveCountByKey[key] = (moveCountByKey[key] ?? 0) + 1;
      lastFrom = from;
      lastTo = to;
    }

    return _OwnMoveStats(
      moveCountByKey: moveCountByKey,
      lastFrom: lastFrom,
      lastTo: lastTo,
    );
  }

  int _safeMoveCount(chess.Chess game) {
    try {
      return game.moves().length;
    } catch (_) {
      return 0;
    }
  }

  bool _safeInCheck(chess.Chess game) {
    try {
      return game.in_check;
    } catch (_) {
      return false;
    }
  }
}

class _OwnMoveStats {
  const _OwnMoveStats({
    required this.moveCountByKey,
    required this.lastFrom,
    required this.lastTo,
  });

  final Map<String, int> moveCountByKey;
  final String? lastFrom;
  final String? lastTo;
}
