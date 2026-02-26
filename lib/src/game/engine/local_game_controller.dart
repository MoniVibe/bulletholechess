import 'dart:async';
import 'dart:math';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

import 'dumb_ai_engine.dart';

class LocalGameController extends ChangeNotifier {
  LocalGameController({
    Duration initialCooldownDuration = const Duration(seconds: 3),
    this.aiThinkDelayMin = const Duration(seconds: 2),
    this.aiThinkDelayMax = const Duration(seconds: 4),
    DumbAiEngine? aiEngine,
    Random? random,
  }) : _random = random ?? Random(),
       _aiEngine = aiEngine ?? DumbAiEngine(random: random ?? Random()),
       _cooldownDuration = initialCooldownDuration {
    _resetRuntimeState();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
    _maybeScheduleAiMove();
  }

  Duration _cooldownDuration;
  final Duration aiThinkDelayMin;
  final Duration aiThinkDelayMax;
  final Random _random;
  final DumbAiEngine _aiEngine;

  late chess.Chess _game;
  late Timer _ticker;
  Timer? _aiMoveTimer;
  bool _disposed = false;
  bool _aiMovePending = false;

  String _playerColor = 'w';
  int _version = 0;
  DateTime _whiteReadyAt = DateTime.now();
  DateTime _blackReadyAt = DateTime.now();
  String? _selectedSquare;
  Set<String> _legalTargets = <String>{};
  String? _lastMoveFrom;
  String? _lastMoveTo;
  String? _lastMoverColor;
  String? _feedback;
  String? _winnerColor;
  String? _queuedMoveFrom;
  String? _queuedMoveTo;
  String _queuedPromotion = 'q';

  int get version => _version;
  Duration get cooldownDuration => _cooldownDuration;
  String get playerColor => _playerColor;
  String get aiColor => _otherColor(playerColor);
  String get readyLabel {
    final playerReady = cooldownRemaining(playerColor).inMilliseconds == 0;
    final botReady = cooldownRemaining(aiColor).inMilliseconds == 0;
    if (playerReady && botReady) {
      return 'Both';
    }
    if (playerReady) {
      return 'You';
    }
    if (botReady) {
      return 'Bot';
    }
    return 'None';
  }

  String get turnColor => _colorCode(_game.turn);
  String get turnLabel => turnColor == 'w' ? 'White' : 'Black';
  bool get isGameOver => _winnerColor != null || _game.in_draw;
  String? get winnerColor => _winnerColor;
  String? get winnerLabel {
    if (_winnerColor == null) {
      return null;
    }
    return _winnerColor == 'w' ? 'White' : 'Black';
  }

  bool get aiMovePending => _aiMovePending;
  bool get canPlayerInteract => !isGameOver && _hasAnyLegalMove(playerColor);
  bool get hasQueuedMove => _queuedMoveFrom != null && _queuedMoveTo != null;
  String? get queuedMoveLabel {
    if (!hasQueuedMove) {
      return null;
    }
    return '$_queuedMoveFrom-$_queuedMoveTo';
  }

  String? get selectedSquare => _selectedSquare;
  Set<String> get legalTargets => _legalTargets;
  String? get lastMoveFrom => _lastMoveFrom;
  String? get lastMoveTo => _lastMoveTo;
  bool get isOpponentLastMove =>
      _lastMoverColor != null && _lastMoverColor == aiColor;
  String? get opponentLastMoveLabel {
    if (!isOpponentLastMove || _lastMoveFrom == null || _lastMoveTo == null) {
      return null;
    }
    return '$_lastMoveFrom-$_lastMoveTo';
  }

  String? get feedback => _feedback;
  List<String> get history => _game.getHistory().cast<String>();
  Map<String, String> get boardPieces => _boardPiecesFromFen(_game.fen);

  String get statusText {
    if (_winnerColor != null) {
      return '${winnerLabel!} wins by checkmate. Start a new game.';
    }
    if (_game.in_draw) {
      return 'Draw game.';
    }

    if (hasQueuedMove) {
      final remaining = cooldownRemaining(playerColor);
      if (remaining.inMilliseconds > 0) {
        return 'Queued $queuedMoveLabel (${_formatDuration(remaining)}).';
      }
      return 'Queued $queuedMoveLabel. Executing...';
    }

    final playerReady = cooldownRemaining(playerColor).inMilliseconds == 0;
    final botReady = cooldownRemaining(aiColor).inMilliseconds == 0;
    if (playerReady && botReady) {
      if (_isInCheckFor(playerColor)) {
        return 'Both ready. You are in check, move now.';
      }
      if (_aiMovePending) {
        return 'Both ready. Bot is thinking, but you can move now.';
      }
      return 'Both ready. Move anytime.';
    }

    if (playerReady) {
      return _isInCheckFor(playerColor)
          ? 'You are in check. Move now.'
          : 'You can move now.';
    }

    final aiRemaining = cooldownRemaining(aiColor);
    if (aiRemaining.inMilliseconds == 0) {
      return _aiMovePending ? 'Bot is thinking...' : 'Bot can move now.';
    }
    return 'Cooling down...';
  }

  Duration cooldownRemaining(String color) {
    final now = DateTime.now();
    final readyAt = color == 'w' ? _whiteReadyAt : _blackReadyAt;
    final remaining = readyAt.difference(now);
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }

  void startNewGame({bool playerAsWhite = true, Duration? cooldownDuration}) {
    _cancelAiTimer();
    _playerColor = playerAsWhite ? 'w' : 'b';
    if (cooldownDuration != null) {
      _cooldownDuration = cooldownDuration;
    }
    _resetRuntimeState();
    _maybeScheduleAiMove();
    notifyListeners();
  }

  void clearQueuedMove() {
    if (!hasQueuedMove) {
      return;
    }
    _clearQueuedMove();
    _feedback = 'Queued move cleared';
    notifyListeners();
  }

  void tapSquare(String square) {
    if (!canPlayerInteract || isGameOver) {
      return;
    }

    final pieces = boardPieces;
    final piece = pieces[square];
    final isOwnPiece = piece != null && _pieceColor(piece) == playerColor;

    if (_selectedSquare == null) {
      if (isOwnPiece) {
        _selectedSquare = square;
        _legalTargets = _legalDestinationsFrom(square, playerColor);
        _feedback = null;
        notifyListeners();
      }
      return;
    }

    if (_selectedSquare == square) {
      _clearSelection();
      notifyListeners();
      return;
    }

    final from = _selectedSquare!;
    final legalMove = _findValidatedLegalMove(
      from: from,
      to: square,
      color: playerColor,
      promotion: 'q',
    );
    final legalNow = legalMove != null;

    if (legalNow) {
      final onCooldown = cooldownRemaining(playerColor).inMilliseconds > 0;
      if (onCooldown) {
        _queuePlayerMove(from: from, to: square, promotion: 'q');
        _clearSelection();
        _feedback = 'Queued $from-$square';
        notifyListeners();
        return;
      }

      final didMove = _applyMove(
        from: from,
        to: square,
        moverColor: playerColor,
      );
      if (didMove) {
        _clearQueuedMove();
        _clearSelection();
        _feedback = null;
        _maybeScheduleAiMove();
        notifyListeners();
        return;
      }
    }

    if (isOwnPiece) {
      final onCooldown = cooldownRemaining(playerColor).inMilliseconds > 0;
      if (onCooldown && _selectedSquare != square) {
        _feedback = 'Cannot queue onto your own occupied square.';
        notifyListeners();
        return;
      }
      _selectedSquare = square;
      _legalTargets = _legalDestinationsFrom(square, playerColor);
      _feedback = null;
      notifyListeners();
      return;
    }

    _feedback = 'Illegal move';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.cancel();
    _cancelAiTimer();
    super.dispose();
  }

  void _onTick() {
    if (_disposed) {
      return;
    }
    _refreshTerminalState();
    _tryExecuteQueuedPlayerMove();
    _maybeScheduleAiMove();
    notifyListeners();
  }

  void _maybeScheduleAiMove() {
    if (_aiMovePending ||
        isGameOver ||
        cooldownRemaining(aiColor).inMilliseconds > 0 ||
        !_hasAnyLegalMove(aiColor)) {
      return;
    }

    _aiMovePending = true;
    _aiMoveTimer = Timer(_nextAiThinkDelay(), _runAiMove);
  }

  void _runAiMove() {
    if (_disposed) {
      return;
    }

    if (isGameOver ||
        cooldownRemaining(aiColor).inMilliseconds > 0 ||
        !_hasAnyLegalMove(aiColor)) {
      _aiMovePending = false;
      notifyListeners();
      return;
    }

    final move = _withTurn(aiColor, () => _aiEngine.chooseMove(_game));
    if (move != null) {
      _applyMove(
        from: move.from,
        to: move.to,
        promotion: move.promotion,
        moverColor: aiColor,
      );
    }

    _refreshSelectionForCurrentBoard();
    _aiMovePending = false;
    _feedback = null;
    notifyListeners();
  }

  void _resetRuntimeState() {
    _game = chess.Chess();
    _version = 0;
    _selectedSquare = null;
    _legalTargets = <String>{};
    _lastMoveFrom = null;
    _lastMoveTo = null;
    _lastMoverColor = null;
    _feedback = null;
    _aiMovePending = false;
    _queuedMoveFrom = null;
    _queuedMoveTo = null;
    _queuedPromotion = 'q';
    _winnerColor = null;

    final now = DateTime.now();
    _whiteReadyAt = now;
    _blackReadyAt = now;
    _refreshTerminalState();
  }

  bool _applyMove({
    required String from,
    required String to,
    required String moverColor,
    String promotion = 'q',
  }) {
    if (isGameOver || cooldownRemaining(moverColor).inMilliseconds > 0) {
      return false;
    }

    final legalMove = _findValidatedLegalMove(
      from: from,
      to: to,
      color: moverColor,
      promotion: promotion,
    );
    if (legalMove == null) {
      return false;
    }

    final previousTurn = _game.turn;
    _game.turn = _toChessColor(moverColor);
    final moved = _game.move({'from': from, 'to': to, 'promotion': promotion});

    if (!moved) {
      _game.turn = previousTurn;
      return false;
    }

    if (_aiMovePending && moverColor == playerColor) {
      _cancelAiTimer();
      _aiMovePending = false;
    }

    _version += 1;
    _lastMoveFrom = from;
    _lastMoveTo = to;
    _lastMoverColor = moverColor;
    _setCooldownForMover(moverColor);
    _refreshSelectionForCurrentBoard();
    _refreshTerminalState();
    return true;
  }

  void _setCooldownForMover(String mover) {
    final now = DateTime.now();
    if (mover == 'w') {
      _whiteReadyAt = now.add(_cooldownDuration);
      _blackReadyAt = now;
      return;
    }

    _blackReadyAt = now.add(_cooldownDuration);
    _whiteReadyAt = now;
  }

  Set<String> _legalDestinationsFrom(String square, String color) {
    final legalMoves = _withTurn(
      color,
      () => _game
          .moves({'verbose': true})
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );

    return legalMoves
        .where((move) => move['from'] == square)
        .map((move) => move['to'] as String)
        .toSet();
  }

  bool _hasAnyLegalMove(String color) {
    return _withTurn(color, () => _game.moves().isNotEmpty);
  }

  bool _isInCheckFor(String color) {
    return _withTurn(color, () => _game.in_check);
  }

  Map<String, dynamic>? _findValidatedLegalMove({
    required String from,
    required String to,
    required String color,
    required String promotion,
  }) {
    return _withTurn(color, () {
      final legalMoves = _game
          .moves({'verbose': true})
          .map((dynamic item) => Map<String, dynamic>.from(item as Map))
          .toList();

      for (final move in legalMoves) {
        if (move['from'] != from || move['to'] != to) {
          continue;
        }
        final movePromotion = move['promotion'] as String?;
        if (movePromotion == null) {
          if (_passesSpecialMoveValidation(move: move, moverColor: color)) {
            return move;
          }
          return null;
        }
        if (movePromotion == promotion &&
            _passesSpecialMoveValidation(move: move, moverColor: color)) {
          return move;
        }
      }

      return null;
    });
  }

  bool _passesSpecialMoveValidation({
    required Map<String, dynamic> move,
    required String moverColor,
  }) {
    return _isEnPassantStructurallyValid(move: move, moverColor: moverColor) &&
        _isCastlingStructurallyValid(move: move, moverColor: moverColor);
  }

  bool _isEnPassantStructurallyValid({
    required Map<String, dynamic> move,
    required String moverColor,
  }) {
    final flags = move['flags'] as String? ?? '';
    if (!flags.contains('e')) {
      return true;
    }

    final from = move['from'] as String?;
    final to = move['to'] as String?;
    if (from == null || to == null) {
      return false;
    }

    final fromFile = from.codeUnitAt(0);
    final toFile = to.codeUnitAt(0);
    final fromRank = int.tryParse(from[1]);
    final toRank = int.tryParse(to[1]);
    if (fromRank == null || toRank == null) {
      return false;
    }
    if ((fromFile - toFile).abs() != 1) {
      return false;
    }

    if (moverColor == 'w') {
      if (fromRank != 5 || toRank != 6) {
        return false;
      }
    } else {
      if (fromRank != 4 || toRank != 3) {
        return false;
      }
    }

    final fenTokens = _game.fen.split(' ');
    if (fenTokens.length < 4 || fenTokens[3] != to) {
      return false;
    }

    final capturedRank = moverColor == 'w' ? toRank - 1 : toRank + 1;
    final capturedSquare = '${to[0]}$capturedRank';
    final capturedPiece = boardPieces[capturedSquare];
    if (capturedPiece == null || capturedPiece.toLowerCase() != 'p') {
      return false;
    }
    if (_pieceColor(capturedPiece) == moverColor) {
      return false;
    }

    return true;
  }

  bool _isCastlingStructurallyValid({
    required Map<String, dynamic> move,
    required String moverColor,
  }) {
    final flags = move['flags'] as String? ?? '';
    final kingSide = flags.contains('k');
    final queenSide = flags.contains('q');
    if (!kingSide && !queenSide) {
      return true;
    }

    final from = move['from'] as String?;
    final to = move['to'] as String?;
    if (from == null || to == null) {
      return false;
    }

    final isWhite = moverColor == 'w';
    final expectedFrom = isWhite ? 'e1' : 'e8';
    if (from != expectedFrom) {
      return false;
    }

    final expectedTo = kingSide
        ? (isWhite ? 'g1' : 'g8')
        : (isWhite ? 'c1' : 'c8');
    if (to != expectedTo) {
      return false;
    }

    final pieces = boardPieces;
    final kingPiece = pieces[expectedFrom];
    if (kingPiece == null ||
        kingPiece.toLowerCase() != 'k' ||
        _pieceColor(kingPiece) != moverColor) {
      return false;
    }

    final rookSquare = kingSide
        ? (isWhite ? 'h1' : 'h8')
        : (isWhite ? 'a1' : 'a8');
    final rookPiece = pieces[rookSquare];
    if (rookPiece == null ||
        rookPiece.toLowerCase() != 'r' ||
        _pieceColor(rookPiece) != moverColor) {
      return false;
    }

    final mustBeEmpty = kingSide
        ? (isWhite ? const ['f1', 'g1'] : const ['f8', 'g8'])
        : (isWhite ? const ['d1', 'c1', 'b1'] : const ['d8', 'c8', 'b8']);
    for (final square in mustBeEmpty) {
      if (pieces[square] != null) {
        return false;
      }
    }

    final enemyColor = isWhite ? chess.Color.BLACK : chess.Color.WHITE;
    final kingPathSquares = kingSide
        ? (isWhite ? const ['e1', 'f1', 'g1'] : const ['e8', 'f8', 'g8'])
        : (isWhite ? const ['e1', 'd1', 'c1'] : const ['e8', 'd8', 'c8']);
    for (final square in kingPathSquares) {
      if (_isSquareThreatenedBy(square: square, byColor: enemyColor)) {
        return false;
      }
    }

    return true;
  }

  bool _isSquareThreatenedBy({
    required String square,
    required chess.Color byColor,
  }) {
    final index = chess.Chess.SQUARES[square];
    if (index is! int) {
      return false;
    }
    return _game.attacked(byColor, index);
  }

  void _clearSelection() {
    _selectedSquare = null;
    _legalTargets = <String>{};
  }

  void _queuePlayerMove({
    required String from,
    required String to,
    required String promotion,
  }) {
    _queuedMoveFrom = from;
    _queuedMoveTo = to;
    _queuedPromotion = promotion;
  }

  void _clearQueuedMove() {
    _queuedMoveFrom = null;
    _queuedMoveTo = null;
    _queuedPromotion = 'q';
  }

  void _tryExecuteQueuedPlayerMove() {
    if (!hasQueuedMove || isGameOver) {
      return;
    }
    if (cooldownRemaining(playerColor).inMilliseconds > 0) {
      return;
    }

    final from = _queuedMoveFrom!;
    final to = _queuedMoveTo!;
    final promotion = _queuedPromotion;
    final legalMove = _findValidatedLegalMove(
      from: from,
      to: to,
      color: playerColor,
      promotion: promotion,
    );
    if (legalMove == null) {
      _clearQueuedMove();
      _feedback = 'Queued move expired';
      return;
    }

    final moved = _applyMove(
      from: from,
      to: to,
      promotion: promotion,
      moverColor: playerColor,
    );
    if (!moved) {
      _clearQueuedMove();
      _feedback = 'Queued move failed';
      return;
    }

    _clearQueuedMove();
    _feedback = null;
    _maybeScheduleAiMove();
  }

  void _refreshSelectionForCurrentBoard() {
    if (_selectedSquare == null) {
      return;
    }

    final piece = boardPieces[_selectedSquare!];
    if (piece == null || _pieceColor(piece) != playerColor) {
      _clearSelection();
      return;
    }

    _legalTargets = _legalDestinationsFrom(_selectedSquare!, playerColor);
  }

  void _refreshTerminalState() {
    final winner = _detectCheckmateWinner();
    _winnerColor = winner;

    if (_winnerColor != null) {
      _cancelAiTimer();
      _aiMovePending = false;
      _clearQueuedMove();
      _clearSelection();
    }
  }

  String? _detectCheckmateWinner() {
    final whiteIsCheckmated = _withTurn('w', () => _game.in_checkmate);
    if (whiteIsCheckmated) {
      return 'b';
    }

    final blackIsCheckmated = _withTurn('b', () => _game.in_checkmate);
    if (blackIsCheckmated) {
      return 'w';
    }

    return null;
  }

  void _cancelAiTimer() {
    _aiMoveTimer?.cancel();
    _aiMoveTimer = null;
  }

  static String _colorCode(chess.Color color) {
    return color == chess.Color.WHITE ? 'w' : 'b';
  }

  static chess.Color _toChessColor(String color) {
    return color == 'w' ? chess.Color.WHITE : chess.Color.BLACK;
  }

  static String _otherColor(String color) {
    return color == 'w' ? 'b' : 'w';
  }

  static String _pieceColor(String piece) {
    return piece == piece.toUpperCase() ? 'w' : 'b';
  }

  static String _formatDuration(Duration duration) {
    final seconds = duration.inMilliseconds / 1000.0;
    return '${seconds.toStringAsFixed(1)}s';
  }

  T _withTurn<T>(String color, T Function() callback) {
    final previousTurn = _game.turn;
    _game.turn = _toChessColor(color);
    try {
      return callback();
    } finally {
      _game.turn = previousTurn;
    }
  }

  Duration _nextAiThinkDelay() {
    final minMs = aiThinkDelayMin.inMilliseconds;
    final maxMs = aiThinkDelayMax.inMilliseconds;
    if (maxMs <= minMs) {
      return Duration(milliseconds: minMs);
    }
    final delta = _random.nextInt(maxMs - minMs + 1);
    return Duration(milliseconds: minMs + delta);
  }

  static Map<String, String> _boardPiecesFromFen(String fen) {
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
