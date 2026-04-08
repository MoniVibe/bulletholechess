import 'package:chess/chess.dart' as chess;

import 'package:bulletholechess/src/game/engine/chess_rules.dart';

import 'models.dart';

SafeGameStatus safeEvaluateGameStatus({
  required chess.Chess game,
  required Map<String, int> positionSeenCount,
}) {
  List<dynamic> legalMoves;
  try {
    legalMoves = game.moves();
  } catch (error) {
    return SafeGameStatus(error: 'Legal move generation failed: $error');
  }

  if (legalMoves.isEmpty) {
    bool inCheck;
    try {
      inCheck = game.in_check;
    } catch (error) {
      return SafeGameStatus(error: 'Check status evaluation failed: $error');
    }

    if (inCheck) {
      final checkedSide = ChessRules.colorCode(game.turn);
      final winner = checkedSide == 'w' ? 'b' : 'w';
      final reason = winner == 'w' ? 'checkmate_white' : 'checkmate_black';
      return SafeGameStatus(terminalReason: reason, winner: winner);
    }
    return const SafeGameStatus(terminalReason: 'draw_stalemate');
  }

  if (game.half_moves >= 100) {
    return const SafeGameStatus(terminalReason: 'draw_fifty_move_rule');
  }

  if (maxPositionRepetition(positionSeenCount) >= 3) {
    return const SafeGameStatus(terminalReason: 'draw_threefold_repetition');
  }

  if (isInsufficientMaterialFromFen(game.fen)) {
    return const SafeGameStatus(terminalReason: 'draw_insufficient_material');
  }

  return const SafeGameStatus();
}

int maxPositionRepetition(Map<String, int> positionSeenCount) {
  var maxCount = 0;
  for (final count in positionSeenCount.values) {
    if (count > maxCount) {
      maxCount = count;
    }
  }
  return maxCount;
}

bool isInsufficientMaterialFromFen(String fen) {
  final board = ChessRules.boardPiecesFromFen(fen);
  final nonKingEntries = board.entries
      .where((entry) => entry.value.toUpperCase() != 'K')
      .toList();
  if (nonKingEntries.isEmpty) {
    return true;
  }

  final pieces = nonKingEntries
      .map((entry) => entry.value.toUpperCase())
      .toList();

  if (pieces.length == 1 && (pieces.first == 'N' || pieces.first == 'B')) {
    return true;
  }

  final hasMajorOrPawn = pieces.any(
    (piece) => piece == 'Q' || piece == 'R' || piece == 'P',
  );
  if (hasMajorOrPawn) {
    return false;
  }

  final allBishops = pieces.every((piece) => piece == 'B');
  if (!allBishops) {
    return false;
  }

  final bishopColors = nonKingEntries
      .map((entry) => squareColorParity(entry.key))
      .toSet();
  return bishopColors.length == 1;
}

int squareColorParity(String square) {
  final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
  final rank = int.parse(square.substring(1)) - 1;
  return (file + rank) % 2;
}

String normalizedPositionKey(String fen) {
  final parts = fen.split(' ');
  if (parts.length < 4) {
    return fen;
  }
  // Threefold repetition should ignore halfmove/fullmove counters.
  return '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';
}

int parseHalfmoveClock(String fen) {
  final parts = fen.split(' ');
  if (parts.length < 5) {
    return 0;
  }
  return int.tryParse(parts[4]) ?? 0;
}

String materialSignatureFromFen(String fen) {
  final board = ChessRules.boardPiecesFromFen(fen);
  final white = <String, int>{'K': 0, 'Q': 0, 'R': 0, 'B': 0, 'N': 0, 'P': 0};
  final black = <String, int>{'K': 0, 'Q': 0, 'R': 0, 'B': 0, 'N': 0, 'P': 0};

  for (final piece in board.values) {
    final type = piece.toUpperCase();
    if (!white.containsKey(type)) {
      continue;
    }
    if (piece == piece.toUpperCase()) {
      white[type] = white[type]! + 1;
    } else {
      black[type] = black[type]! + 1;
    }
  }

  String encode(Map<String, int> counts) {
    return 'K${counts['K']}Q${counts['Q']}R${counts['R']}'
        'B${counts['B']}N${counts['N']}P${counts['P']}';
  }

  return 'w(${encode(white)}) b(${encode(black)})';
}

int materialAdvantageFromFen(String fen) {
  const pieceValue = <String, int>{
    'K': 0,
    'Q': 9,
    'R': 5,
    'B': 3,
    'N': 3,
    'P': 1,
  };
  final board = ChessRules.boardPiecesFromFen(fen);
  var whiteScore = 0;
  var blackScore = 0;

  for (final piece in board.values) {
    final type = piece.toUpperCase();
    final value = pieceValue[type];
    if (value == null) {
      continue;
    }
    if (piece == piece.toUpperCase()) {
      whiteScore += value;
    } else {
      blackScore += value;
    }
  }

  return whiteScore - blackScore;
}

int safeLegalMoveCount(chess.Chess game) {
  try {
    return game.moves().length;
  } catch (_) {
    return -1;
  }
}

bool hasUnpromotedBackRankPawn(String fen) {
  final board = ChessRules.boardPiecesFromFen(fen);
  for (final entry in board.entries) {
    final square = entry.key;
    final piece = entry.value;
    if (piece.toLowerCase() != 'p') {
      continue;
    }
    if (square.endsWith('1') || square.endsWith('8')) {
      return true;
    }
  }
  return false;
}

bool looksLikePromotionMove({
  required String from,
  required String to,
  required String side,
}) {
  if (from.length != 2 || to.length != 2) {
    return false;
  }
  final fromRank = int.tryParse(from[1]);
  final toRank = int.tryParse(to[1]);
  if (fromRank == null || toRank == null) {
    return false;
  }
  if (side == 'w') {
    return fromRank == 7 && toRank == 8;
  }
  return fromRank == 2 && toRank == 1;
}

DuelFailure? validateBoardState({
  required chess.Chess game,
  required int gameIndex,
  required int ply,
  required int seed,
  required String sideToMove,
  required List<String> playedMoves,
}) {
  final pieces = ChessRules.boardPiecesFromFen(game.fen);
  final whiteKings = pieces.values.where((piece) => piece == 'K').length;
  final blackKings = pieces.values.where((piece) => piece == 'k').length;

  if (whiteKings != 1 || blackKings != 1) {
    return DuelFailure(
      gameIndex: gameIndex,
      seed: seed,
      ply: ply,
      sideToMove: sideToMove,
      fen: game.fen,
      message:
          'Invalid king count (white: $whiteKings, black: $blackKings) after move.',
      lastMoves: tail(playedMoves, 8),
    );
  }

  if (game.in_checkmate && game.moves().isNotEmpty) {
    return DuelFailure(
      gameIndex: gameIndex,
      seed: seed,
      ply: ply,
      sideToMove: sideToMove,
      fen: game.fen,
      message: 'Checkmate flagged while legal moves still exist.',
      lastMoves: tail(playedMoves, 8),
    );
  }

  return null;
}

List<String> tail(List<String> values, int count) {
  if (values.length <= count) {
    return List<String>.from(values);
  }
  return values.sublist(values.length - count);
}

void incrementCount(Map<String, int> counts, String key) {
  counts[key] = (counts[key] ?? 0) + 1;
}
