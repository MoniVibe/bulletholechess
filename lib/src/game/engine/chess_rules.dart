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
    final requestedTurn = toChessColor(color);
    // Snapshot the en-passant target. When we force the side-to-move to the
    // OTHER color, any live en-passant square becomes bogus: it was created for
    // the natural mover, and move-generation for the forced color can synthesize
    // an illegal en-passant capture against it. The `chess` 0.8.1 engine
    // materializes moves for check/checkmate SAN by make/undo directly on this
    // live board, and undoing that bogus EP capture RESURRECTS a phantom pawn
    // (observed: a white pawn reappearing on b7 after black's out-of-turn b7-b5
    // push, the "piece appears out of nowhere" glitch). Clearing the stale EP
    // square while the turn is flipped mirrors the same defensive reasoning
    // already applied in `_cloneForColor`, and prevents the corruption at the
    // single shared seam every out-of-turn read/enumeration flows through.
    final previousEpSquare = game.ep_square;
    final flippingTurn = previousTurn != requestedTurn;
    game.turn = requestedTurn;
    if (flippingTurn) {
      game.ep_square = chess.Chess.EMPTY;
    }
    try {
      return callback();
    } finally {
      game.turn = previousTurn;
      if (flippingTurn) {
        game.ep_square = previousEpSquare;
      }
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
    final gameForColor = _cloneForColor(game: game, color: color);
    if (gameForColor == null) {
      return false;
    }
    return gameForColor.moves().isNotEmpty;
  }

  static bool isInCheckFor(chess.Chess game, String color) {
    final gameForColor = _cloneForColor(game: game, color: color);
    if (gameForColor == null) {
      return false;
    }
    return gameForColor.in_check;
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

    // NOTE: the `chess` 0.8.1 verbose move map does NOT populate a 'promotion'
    // key; the chosen promotion piece is only encoded in the SAN string
    // (e.g. "b8=Q", "bxa8=N"). We derive it from SAN and stamp a normalized
    // 'promotion' onto the returned map so downstream payload construction
    // (movePayloadFromLegalMove) selects the EXACT piece the caller asked for
    // instead of silently defaulting/substituting.
    final promotionMoves =
        legalMoves.where(_isPromotionMove).toList(growable: false);

    if (promotionMoves.isEmpty) {
      // Non-promotion (from,to): the promotion argument is irrelevant. Return
      // the single legal move (there is at most one non-promotion move per
      // from/to pair).
      return legalMoves.first;
    }

    // Promotion square: honor the caller's exact requested piece. If it is not
    // among the legal promotion candidates, REJECT rather than silently
    // executing a different promotion ("played a move I didn't pick" bug).
    final requested = promotion.trim().toLowerCase();
    for (final move in promotionMoves) {
      if (_promotionPieceFromSan(move) == requested) {
        return _withResolvedPromotion(move, requested);
      }
    }

    return null;
  }

  /// Reads the promotion piece letter ('q'/'r'/'b'/'n') from a verbose move's
  /// SAN (e.g. "b8=Q", "bxa8=N+"), lower-cased. Returns null when the move is
  /// not a promotion or the SAN cannot be parsed.
  static String? _promotionPieceFromSan(Map<String, dynamic> legalMove) {
    final existing = legalMove['promotion'];
    if (existing is String && existing.isNotEmpty) {
      return existing.toLowerCase();
    }
    final san = legalMove['san'];
    if (san is! String) {
      return null;
    }
    final eq = san.indexOf('=');
    if (eq < 0 || eq + 1 >= san.length) {
      return null;
    }
    final piece = san[eq + 1].toLowerCase();
    if (!'qrbn'.contains(piece)) {
      return null;
    }
    return piece;
  }

  static Map<String, dynamic> _withResolvedPromotion(
    Map<String, dynamic> legalMove,
    String promotion,
  ) {
    final resolved = Map<String, dynamic>.from(legalMove);
    resolved['promotion'] = promotion;
    return resolved;
  }

  static bool applyValidatedLegalMoveForColor({
    required chess.Chess game,
    required Map<String, dynamic> legalMove,
    required String color,
    required String promotion,
  }) {
    // Snapshot the pre-move position so we can (a) integrity-check the result and
    // (b) roll back cleanly if the underlying engine produces a corrupt board.
    final previousFen = _safeFen(game);
    final beforeCount = previousFen == null ? null : _liveBoardPieceCount(game);

    final gameForColor = _cloneForColor(game: game, color: color);
    if (gameForColor == null) {
      return false;
    }

    final payload = movePayloadFromLegalMove(
      legalMove,
      fallbackPromotion: promotion,
    );
    final moved = gameForColor.move(payload);
    if (!moved) {
      return false;
    }

    try {
      final loaded = game.load(gameForColor.fen);
      if (!loaded) {
        return false;
      }
    } catch (_) {
      return false;
    }

    // Board-integrity guard. A single legal ply can only keep or REDUCE the
    // piece count (captures, en-passant, promotion all preserve or shrink it);
    // no legal move can add a piece. The cooldown-based out-of-turn variant
    // repeatedly rewrites the active-color FEN field and reloads through the
    // `chess` 0.8.1 engine, and that combination can, in rare en-passant/turn-
    // desync positions, resurrect a phantom pawn (a vacated en-passant square
    // reappears occupied, sometimes as the wrong color) -- the observed
    // "a piece appears out of nowhere" glitch. The controllers' existing
    // revert-guard only checks the mover's destination square and therefore
    // never catches a phantom that lands on an unrelated square. Catch it here,
    // at the single shared apply chokepoint, and roll the whole position back so
    // no caller (local, vs-AI, or online) can ever commit a corrupt board.
    if (beforeCount != null && previousFen != null) {
      final afterCount = _liveBoardPieceCount(game);
      if (afterCount > beforeCount) {
        _tryLoadFen(game, previousFen);
        return false;
      }
    }
    return true;
  }

  /// Counts pieces by scanning the engine's live board via `get()` for all 64
  /// squares. This reads the internal board array directly rather than the FEN
  /// string, which `chess` 0.8.1 can report stale/clean immediately after a
  /// `load()` even when the internal state has been corrupted -- the exact case
  /// that lets an out-of-turn en-passant resurrection ("phantom pawn") slip past
  /// a FEN-string check.
  static int _liveBoardPieceCount(chess.Chess game) {
    var count = 0;
    for (final file in _files.split('')) {
      for (var rank = 1; rank <= 8; rank += 1) {
        try {
          if (game.get('$file$rank') != null) {
            count += 1;
          }
        } catch (_) {
          // ignore unreadable squares
        }
      }
    }
    return count;
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
    final gameForColor = _cloneForColor(game: game, color: color);
    if (gameForColor == null) {
      return const <Map<String, dynamic>>[];
    }
    return gameForColor
        .moves(<String, dynamic>{'verbose': true})
        .map((dynamic item) => Map<String, dynamic>.from(item as Map))
        .toList();
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

  static chess.Chess? _cloneForColor({
    required chess.Chess game,
    required String color,
  }) {
    final fen = _safeFen(game);
    if (fen == null) {
      return null;
    }
    final fenParts = fen.split(' ');
    if (fenParts.length < 6) {
      return null;
    }

    final normalizedColor = color.trim().toLowerCase() == 'w' ? 'w' : 'b';
    final originalTurn = fenParts[1];
    fenParts[1] = normalizedColor;
    fenParts[3] = _sanitizeEnPassantTarget(
      target: fenParts[3],
      turnColor: normalizedColor,
    );

    // When forcing a different turn, stale en-passant targets can produce
    // illegal move-generation artifacts in some chess positions.
    if (originalTurn != normalizedColor) {
      fenParts[3] = '-';
    }

    final clonedGame = chess.Chess();
    if (_tryLoadFen(clonedGame, fenParts.join(' '))) {
      return clonedGame;
    }

    // Fallback: clear en-passant square when FEN validation rejects it.
    fenParts[3] = '-';
    if (_tryLoadFen(clonedGame, fenParts.join(' '))) {
      return clonedGame;
    }

    return null;
  }

  static String? _safeFen(chess.Chess game) {
    try {
      return game.fen;
    } catch (_) {
      return null;
    }
  }

  static bool _tryLoadFen(chess.Chess game, String fen) {
    try {
      return game.load(fen);
    } catch (_) {
      return false;
    }
  }

  static String _sanitizeEnPassantTarget({
    required String target,
    required String turnColor,
  }) {
    final normalizedTarget = target.trim().toLowerCase();
    if (normalizedTarget == '-') {
      return '-';
    }
    if (normalizedTarget.length != 2) {
      return '-';
    }

    final file = normalizedTarget[0];
    if (!_files.contains(file)) {
      return '-';
    }

    final rank = int.tryParse(normalizedTarget[1]);
    if (rank == null) {
      return '-';
    }

    final expectedRank = turnColor == 'w' ? 6 : 3;
    if (rank != expectedRank) {
      return '-';
    }

    return normalizedTarget;
  }
}
