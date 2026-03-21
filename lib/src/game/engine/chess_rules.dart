import 'package:chess/chess.dart' as chess;

class ChessRules {
  static const String defaultPromotion = 'q';
  static const String _files = 'abcdefgh';

  static String colorCode(chess.Color color) {
    return color == chess.Color.WHITE ? 'w' : 'b';
  }

  static chess.Color toChessColor(String color) {
    final normalized = color.trim().toLowerCase();
    return normalized == 'w' ? chess.Color.WHITE : chess.Color.BLACK;
  }

  static String oppositeColor(String color) {
    final normalized = color.trim().toLowerCase();
    return normalized == 'w' ? 'b' : 'w';
  }

  static String pieceColor(String piece) {
    return piece == piece.toUpperCase() ? 'w' : 'b';
  }

  static String formatDuration(Duration duration) {
    final seconds = duration.inMilliseconds / 1000.0;
    return '${seconds.toStringAsFixed(1)}s';
  }

  static T withTurn<T>(chess.Chess game, String color, T Function() callback) {
    final previousTurn = game.turn;
    game.turn = toChessColor(color);
    try {
      return callback();
    } finally {
      game.turn = previousTurn;
    }
  }

  static Set<String> legalDestinationsFrom({
    required chess.Chess game,
    required String square,
    required String color,
  }) {
    if (!_isValidSquare(square)) {
      return <String>{};
    }

    final legalMoves = _legalMovesForColor(game: game, color: color);

    return legalMoves
        .where((move) => move['from'] == square)
        .map((move) => move['to'] as String)
        .toSet();
  }

  static bool hasAnyLegalMove(chess.Chess game, String color) {
    return withTurn(game, color, () => game.moves().isNotEmpty);
  }

  static bool isInCheckFor(chess.Chess game, String color) {
    return withTurn(game, color, () => game.in_check);
  }

  static Map<String, dynamic>? findValidatedLegalMove({
    required chess.Chess game,
    required String from,
    required String to,
    required String color,
    required String promotion,
  }) {
    if (!_isValidSquare(from) || !_isValidSquare(to)) {
      return null;
    }

    final legalMoves = _legalMovesForColor(
      game: game,
      color: color,
    ).where((move) => move['from'] == from && move['to'] == to).toList();

    if (legalMoves.isEmpty) {
      return null;
    }

    for (final move in legalMoves) {
      if (move['promotion'] == promotion) {
        return move;
      }
    }

    for (final move in legalMoves) {
      if (move['promotion'] == null) {
        return move;
      }
    }

    // When callers pass a stale/unsupported promotion choice, still return a
    // legal option so upstream code can recover with a valid payload.
    return legalMoves.first;
  }

  static String? detectCheckmateWinner(chess.Chess game) {
    final whiteIsCheckmated = withTurn(game, 'w', () => game.in_checkmate);
    if (whiteIsCheckmated) {
      return 'b';
    }

    final blackIsCheckmated = withTurn(game, 'b', () => game.in_checkmate);
    if (blackIsCheckmated) {
      return 'w';
    }

    return null;
  }

  static Map<String, String> boardPiecesFromFen(String fen) {
    final rows = fen.split(' ').first.split('/');
    final board = <String, String>{};
    if (rows.length != 8) {
      return board;
    }

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      var fileIndex = 0;

      for (final symbol in row.split('')) {
        final emptyCount = int.tryParse(symbol);
        if (emptyCount != null) {
          fileIndex += emptyCount;
          continue;
        }

        if (fileIndex < 0 || fileIndex >= _files.length) {
          break;
        }
        final square = '${_files[fileIndex]}${8 - rowIndex}';
        board[square] = symbol;
        fileIndex += 1;
      }
    }

    return board;
  }

  static Map<String, String> movePayloadFromLegalMove(
    Map<String, dynamic> legalMove, {
    String fallbackPromotion = defaultPromotion,
  }) {
    final from = legalMove['from'];
    final to = legalMove['to'];
    if (from is! String || to is! String) {
      throw ArgumentError('Legal move is missing from/to squares.');
    }

    final payload = <String, String>{'from': from, 'to': to};
    final promotion = legalMove['promotion'];
    if (promotion is String && promotion.isNotEmpty) {
      payload['promotion'] = promotion;
    } else if (_isPromotionMove(legalMove)) {
      payload['promotion'] = fallbackPromotion;
    }
    return payload;
  }

  static Set<String> checkedKingSquares(chess.Chess game) {
    final board = boardPiecesFromFen(game.fen);
    final squares = <String>{};

    if (isInCheckFor(game, 'w')) {
      final whiteKingSquare = kingSquareFromBoard(board: board, color: 'w');
      if (whiteKingSquare != null) {
        squares.add(whiteKingSquare);
      }
    }
    if (isInCheckFor(game, 'b')) {
      final blackKingSquare = kingSquareFromBoard(board: board, color: 'b');
      if (blackKingSquare != null) {
        squares.add(blackKingSquare);
      }
    }

    return squares;
  }

  static String? kingSquareFromBoard({
    required Map<String, String> board,
    required String color,
  }) {
    final normalized = color.trim().toLowerCase();
    final target = normalized == 'w' ? 'K' : 'k';
    for (final entry in board.entries) {
      if (entry.value == target) {
        return entry.key;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> _legalMovesForColor({
    required chess.Chess game,
    required String color,
  }) {
    return withTurn(
      game,
      color,
      () => game
          .moves(<String, dynamic>{'verbose': true})
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
  }

  static bool _isValidSquare(String square) {
    if (square.length != 2) {
      return false;
    }

    final file = square[0];
    final rank = int.tryParse(square[1]);
    return _files.contains(file) && rank != null && rank >= 1 && rank <= 8;
  }

  static bool _isPromotionMove(Map<String, dynamic> legalMove) {
    final flags = legalMove['flags'];
    if (flags is String && flags.contains('p')) {
      return true;
    }
    final san = legalMove['san'];
    if (san is String && san.contains('=')) {
      return true;
    }
    return false;
  }
}
