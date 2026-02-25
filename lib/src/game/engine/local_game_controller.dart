import 'dart:async';
import 'dart:math';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

import 'dumb_ai_engine.dart';

class LocalGameController extends ChangeNotifier {
  LocalGameController({
    this.cooldownDuration = const Duration(seconds: 3),
    this.aiThinkDelayMin = const Duration(seconds: 2),
    this.aiThinkDelayMax = const Duration(seconds: 4),
    DumbAiEngine? aiEngine,
    Random? random,
  }) : _random = random ?? Random(),
       _aiEngine = aiEngine ?? DumbAiEngine(random: random ?? Random()) {
    _resetRuntimeState();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
    _maybeScheduleAiMove();
  }

  final Duration cooldownDuration;
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
  String? _feedback;

  int get version => _version;
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
  bool get isGameOver => _game.game_over;
  bool get aiMovePending => _aiMovePending;
  bool get canPlayerInteract =>
      !isGameOver &&
      cooldownRemaining(playerColor).inMilliseconds == 0 &&
      _hasAnyLegalMove(playerColor);
  String? get selectedSquare => _selectedSquare;
  Set<String> get legalTargets => _legalTargets;
  String? get lastMoveFrom => _lastMoveFrom;
  String? get lastMoveTo => _lastMoveTo;
  String? get feedback => _feedback;
  List<String> get history => _game.getHistory().cast<String>();
  Map<String, String> get boardPieces => _boardPiecesFromFen(_game.fen);

  String get statusText {
    if (_game.in_checkmate) {
      final winner = turnColor == 'w' ? 'Black' : 'White';
      return '$winner wins by checkmate.';
    }
    if (_game.in_draw) {
      return 'Draw game.';
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

  void startNewGame({bool playerAsWhite = true}) {
    _cancelAiTimer();
    _playerColor = playerAsWhite ? 'w' : 'b';
    _resetRuntimeState();
    _maybeScheduleAiMove();
    notifyListeners();
  }

  void tapSquare(String square) {
    if (!canPlayerInteract) {
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

    final didMove = _applyMove(
      from: _selectedSquare!,
      to: square,
      moverColor: playerColor,
    );
    if (didMove) {
      _clearSelection();
      _feedback = null;
      _maybeScheduleAiMove();
      notifyListeners();
      return;
    }

    if (isOwnPiece) {
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
    _feedback = null;
    _aiMovePending = false;

    final now = DateTime.now();
    _whiteReadyAt = now;
    _blackReadyAt = now;
  }

  bool _applyMove({
    required String from,
    required String to,
    required String moverColor,
    String promotion = 'q',
  }) {
    if (cooldownRemaining(moverColor).inMilliseconds > 0) {
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
    _setCooldownForMover(moverColor);
    return true;
  }

  void _setCooldownForMover(String mover) {
    final now = DateTime.now();
    if (mover == 'w') {
      _whiteReadyAt = now.add(cooldownDuration);
      _blackReadyAt = now;
      return;
    }

    _blackReadyAt = now.add(cooldownDuration);
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

  void _clearSelection() {
    _selectedSquare = null;
    _legalTargets = <String>{};
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
