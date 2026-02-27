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

class DumbAiEngine {
  DumbAiEngine({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<String> _recentPositionKeys = <String>[];
  String? _lastObservedPositionKey;

  static const int _recentPositionWindow = 24;
  static const int _captureBaseScore = 8;
  static const int _promotionScore = 10;
  static const int _checkScore = 25;
  static const int _checkmateScore = 1000;
  static const int _repetitionPenalty = 20;

  EngineMove? chooseMove(chess.Chess game) {
    final rawMoves = game.moves({'verbose': true});
    if (rawMoves.isEmpty) {
      return null;
    }

    final moves = rawMoves
        .map((dynamic item) => Map<String, dynamic>.from(item as Map))
        .toList();
    _recordCurrentPosition(game);

    var bestScore = -1 << 30;
    final topMoves = <Map<String, dynamic>>[];
    for (final move in moves) {
      final score = _scoreMove(game, move);
      if (score > bestScore) {
        bestScore = score;
        topMoves
          ..clear()
          ..add(move);
        continue;
      }
      if (score == bestScore) {
        topMoves.add(move);
      }
    }

    final selected = topMoves[_random.nextInt(topMoves.length)];

    return EngineMove(
      from: selected['from'] as String,
      to: selected['to'] as String,
      promotion: selected['promotion'] as String? ?? 'q',
    );
  }

  int _scoreMove(chess.Chess game, Map<String, dynamic> move) {
    final flags = move['flags'] as String? ?? '';
    final san = move['san'] as String? ?? '';
    final captured = move['captured'];

    var score = 0;
    if (flags.contains('c') || flags.contains('e')) {
      score += _captureBaseScore + _pieceValue(captured);
    }
    if (flags.contains('p')) {
      score += _promotionScore;
    }
    if (san.contains('#')) {
      score += _checkmateScore;
    } else if (san.contains('+')) {
      score += _checkScore;
    }

    final nextPositionKey = _nextPositionKey(game, move);
    final repeatedCount = _recentPositionKeys
        .where((key) => key == nextPositionKey)
        .length;
    score -= repeatedCount * _repetitionPenalty;
    return score;
  }

  int _pieceValue(dynamic piece) {
    final symbol = piece?.toString().toLowerCase();
    switch (symbol) {
      case 'q':
        return 9;
      case 'r':
        return 5;
      case 'b':
      case 'n':
        return 3;
      case 'p':
        return 1;
      default:
        return 0;
    }
  }

  String _nextPositionKey(chess.Chess game, Map<String, dynamic> move) {
    final sandbox = game.copy();
    final moved = sandbox.move(ChessRules.movePayloadFromLegalMove(move));
    if (!moved) {
      return _normalizedPositionKey(game.fen);
    }
    return _normalizedPositionKey(sandbox.fen);
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
}
