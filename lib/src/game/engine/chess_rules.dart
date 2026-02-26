import 'package:chess/chess.dart' as chess;

class ChessRules {
  static const String defaultPromotion = 'q';

  static String colorCode(chess.Color color) {
    return color == chess.Color.WHITE ? 'w' : 'b';
  }

  static chess.Color toChessColor(String color) {
    return color == 'w' ? chess.Color.WHITE : chess.Color.BLACK;
  }

  static String oppositeColor(String color) {
    return color == 'w' ? 'b' : 'w';
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
    final legalMoves = withTurn(
      game,
      color,
      () => game
          .moves(<String, dynamic>{'verbose': true})
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );

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
    return withTurn(game, color, () {
      final legalMoves = game
          .moves(<String, dynamic>{'verbose': true})
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .where((move) => move['from'] == from && move['to'] == to)
          .toList();

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

      return null;
    });
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
    const files = 'abcdefgh';
    final rows = fen.split(' ').first.split('/');
    final board = <String, String>{};

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      var fileIndex = 0;

      for (final symbol in row.split('')) {
        final emptyCount = int.tryParse(symbol);
        if (emptyCount != null) {
          fileIndex += emptyCount;
          continue;
        }

        final square = '${files[fileIndex]}${8 - rowIndex}';
        board[square] = symbol;
        fileIndex += 1;
      }
    }

    return board;
  }
}
