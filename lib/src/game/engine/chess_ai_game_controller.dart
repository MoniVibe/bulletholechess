import 'dart:async';

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

import 'chess_rules.dart';
import 'dumb_ai_engine.dart';

/// Local chess game controller for player-vs-AI sessions.
class ChessAiGameController extends ChangeNotifier {
  ChessAiGameController({
    this.aiMoveDelay = const Duration(milliseconds: 550),
    Duration initialCooldownDuration = const Duration(seconds: 3),
    DumbAiEngine? aiEngine,
  }) : _aiEngine = aiEngine ?? DumbAiEngine(),
       _cooldownDuration = initialCooldownDuration {
    final now = DateTime.now().millisecondsSinceEpoch;
    _whiteReadyAtMs = now;
    _blackReadyAtMs = now;
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
  }

  final Duration aiMoveDelay;
  final DumbAiEngine _aiEngine;
  final chess.Chess _game = chess.Chess();
  final GameSessionLogger _sessionLogger = GameSessionLogger(
    applicationId: 'bulletholechess',
    gameId: 'chess',
    mode: 'vs_ai',
  );

  late final Timer _ticker;
  Timer? _aiMoveTimer;
  bool _disposed = false;
  bool _aiThinking = false;
  bool _hasActiveGame = false;

  Duration _cooldownDuration;
  int _whiteReadyAtMs = 0;
  int _blackReadyAtMs = 0;
  String _playerColor = 'w';
  String? _selectedSquare;
  Set<String> _legalTargets = <String>{};
  String? _feedback;

  String? _playerLastMoveFrom;
  String? _playerLastMoveTo;
  String? _aiLastMoveFrom;
  String? _aiLastMoveTo;
  String? _queuedMoveFrom;
  String? _queuedMoveTo;
  String _queuedPromotion = ChessRules.defaultPromotion;

  String get playerColor => _playerColor;
  String get aiColor => ChessRules.oppositeColor(_playerColor);
  String get turnColor => ChessRules.colorCode(_game.turn);
  Duration get cooldownDuration => _cooldownDuration;
  bool get hasActiveGame => _hasActiveGame;
  bool get isGameOver => _game.game_over;
  bool get isCheckmate => _game.in_checkmate;
  bool get isDraw => _game.in_draw;
  String? get winnerLabel {
    if (!isCheckmate) {
      return null;
    }
    return turnColor == 'w' ? 'Black' : 'White';
  }

  bool get aiThinking => _aiThinking;
  String? get selectedSquare => _selectedSquare;
  Set<String> get legalTargets => _legalTargets;
  String? get feedback => _feedback;
  String? get playerLastMoveFrom => _playerLastMoveFrom;
  String? get playerLastMoveTo => _playerLastMoveTo;
  String? get aiLastMoveFrom => _aiLastMoveFrom;
  String? get aiLastMoveTo => _aiLastMoveTo;
  String? get queuedMoveFrom => _queuedMoveFrom;
  String? get queuedMoveTo => _queuedMoveTo;
  bool get hasQueuedMove => _queuedMoveFrom != null && _queuedMoveTo != null;
  String? get queuedMoveLabel {
    if (!hasQueuedMove) {
      return null;
    }
    return '$_queuedMoveFrom-$_queuedMoveTo';
  }

  Map<String, String> get boardPieces =>
      ChessRules.boardPiecesFromFen(_game.fen);
  List<String> get history => _game.getHistory().cast<String>();

  Duration cooldownRemaining(String color) {
    if (!_hasActiveGame || isGameOver) {
      return Duration.zero;
    }
    final now = _estimatedNowMs();
    final readyAt = color == 'w' ? _whiteReadyAtMs : _blackReadyAtMs;
    final remaining = readyAt - now;
    if (remaining <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: remaining);
  }

  bool get canPlayerInteract {
    return _canColorMoveNow(_playerColor);
  }

  String get statusText {
    if (!_hasActiveGame) {
      return 'Start a new game to begin.';
    }
    if (isGameOver) {
      if (_game.in_checkmate) {
        final winner = turnColor == 'w' ? 'Black' : 'White';
        return '$winner wins by checkmate.';
      }
      if (_game.in_draw) {
        return 'Draw game.';
      }
      return 'Game over.';
    }
    final remaining = cooldownRemaining(_playerColor);
    if (hasQueuedMove) {
      if (remaining.inMilliseconds > 0) {
        return 'Queued $queuedMoveLabel (${_formatStatusDuration(remaining)}).';
      }
      return 'Queued $queuedMoveLabel. Executing...';
    }
    final whiteCooldown = cooldownRemaining('w');
    final blackCooldown = cooldownRemaining('b');
    String? activeWindowColor;
    Duration activeWindowRemaining = Duration.zero;
    if (whiteCooldown.inMilliseconds > 0 && blackCooldown.inMilliseconds <= 0) {
      activeWindowColor = 'b';
      activeWindowRemaining = whiteCooldown;
    } else if (blackCooldown.inMilliseconds > 0 &&
        whiteCooldown.inMilliseconds <= 0) {
      activeWindowColor = 'w';
      activeWindowRemaining = blackCooldown;
    }

    if (activeWindowColor != null) {
      final isPlayerWindow = activeWindowColor == _playerColor;
      final sideLabel = activeWindowColor == 'w' ? 'White' : 'Black';
      final formatted = _formatStatusDuration(activeWindowRemaining);
      if (isPlayerWindow) {
        return 'Your timer is running ($formatted). Move now.';
      }
      return '$sideLabel timer is running ($formatted). Waiting.';
    }

    if (_aiThinking) {
      return 'Both sides unlocked. AI is planning.';
    }
    return 'Both sides unlocked. First move takes initiative.';
  }

  static String _formatStatusDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) {
      return '0.0s';
    }
    final halfSteps = (ms / 500).ceil();
    final halfSecondValue = halfSteps / 2;
    return '${halfSecondValue.toStringAsFixed(1)}s';
  }

  void startNewGame({required bool playerAsWhite, Duration? cooldownDuration}) {
    _cancelAiMoveTimer();
    if (cooldownDuration != null) {
      _cooldownDuration = cooldownDuration;
    }
    _sessionLogger.beginSession(
      sessionLabel: 'new_game',
      context: <String, Object?>{
        'playerAsWhite': playerAsWhite,
        'cooldownSeconds': _cooldownDuration.inSeconds,
      },
    );
    _game.reset();
    _hasActiveGame = true;
    _playerColor = playerAsWhite ? 'w' : 'b';
    _aiThinking = false;
    _feedback = null;
    _playerLastMoveFrom = null;
    _playerLastMoveTo = null;
    _aiLastMoveFrom = null;
    _aiLastMoveTo = null;
    _clearQueuedMove();
    final now = _estimatedNowMs();
    _whiteReadyAtMs = now;
    _blackReadyAtMs = now;
    _clearSelection();
    _scheduleAiMoveIfNeeded();
    _sessionLogger.logEvent('new_game_started', data: _sessionSnapshot());
    notifyListeners();
  }

  void tapSquare(String square) {
    if (!_hasActiveGame) {
      return;
    }
    final canQueuePlannedMove =
        !isGameOver && cooldownRemaining(_playerColor).inMilliseconds > 0;
    final canHandleTap = canPlayerInteract || canQueuePlannedMove;
    if (!canHandleTap) {
      if (!isGameOver) {
        final remaining = cooldownRemaining(_playerColor);
        if (remaining.inMilliseconds > 0) {
          _feedback = 'Cooling down (${ChessRules.formatDuration(remaining)}).';
        } else {
          _feedback = 'No legal moves available.';
        }
        notifyListeners();
      }
      return;
    }

    final piece = boardPieces[square];
    final isOwnPiece =
        piece != null && ChessRules.pieceColor(piece) == _playerColor;

    if (_selectedSquare == null) {
      if (!isOwnPiece) {
        return;
      }
      _selectedSquare = square;
      _legalTargets = ChessRules.legalDestinationsFrom(
        game: _game,
        square: square,
        color: _playerColor,
      );
      _feedback = null;
      notifyListeners();
      return;
    }

    if (_selectedSquare == square) {
      _clearSelection();
      notifyListeners();
      return;
    }

    final from = _selectedSquare!;
    final validatedMove = ChessRules.findValidatedLegalMove(
      game: _game,
      from: from,
      to: square,
      color: _playerColor,
      promotion: ChessRules.defaultPromotion,
    );
    if (validatedMove != null) {
      final promotion =
          validatedMove['promotion'] as String? ?? ChessRules.defaultPromotion;
      if (!canPlayerInteract) {
        _queueMove(from: from, to: square, promotion: promotion);
        _clearSelection();
        _feedback = 'Queued $from-$square';
        _sessionLogger.logEvent(
          'player_move_queued',
          data: <String, Object?>{
            ..._sessionSnapshot(),
            'from': from,
            'to': square,
            'promotion': promotion,
          },
        );
        notifyListeners();
        return;
      }
      _applyPlayerMove(from: from, to: square, promotion: promotion);
      return;
    }

    if (isOwnPiece) {
      _selectedSquare = square;
      _legalTargets = ChessRules.legalDestinationsFrom(
        game: _game,
        square: square,
        color: _playerColor,
      );
      _feedback = null;
      notifyListeners();
      return;
    }

    _feedback = 'That move is not legal.';
    notifyListeners();
  }

  void _applyPlayerMove({
    required String from,
    required String to,
    required String promotion,
  }) {
    final moved = _applyMoveForColor(
      color: _playerColor,
      from: from,
      to: to,
      promotion: promotion,
    );
    if (!moved) {
      _feedback = 'Move could not be applied.';
      notifyListeners();
      return;
    }

    _playerLastMoveFrom = from;
    _playerLastMoveTo = to;
    _clearQueuedMove();
    _startCooldown(_playerColor);
    _feedback = null;
    _clearSelection();

    if (!isGameOver) {
      _scheduleAiMoveIfNeeded();
    }
    _sessionLogger.logEvent(
      'player_move_applied',
      data: <String, Object?>{
        ..._sessionSnapshot(),
        'from': from,
        'to': to,
        'promotion': promotion,
      },
    );
    notifyListeners();
  }

  void _scheduleAiMoveIfNeeded() {
    if (_disposed || !_hasActiveGame || isGameOver) {
      return;
    }
    if (_aiThinking || _aiMoveTimer != null) {
      return;
    }
    // Keep opening behavior familiar: white starts when no move was made yet.
    if (_game.getHistory().isEmpty && turnColor != aiColor) {
      return;
    }
    if (!ChessRules.hasAnyLegalMove(_game, aiColor)) {
      return;
    }

    _aiThinking = true;
    var delay = aiMoveDelay;
    final cooldown = cooldownRemaining(aiColor);
    if (cooldown.inMilliseconds > 0) {
      delay += cooldown;
    }
    _aiMoveTimer = Timer(delay, _performAiMove);
    notifyListeners();
  }

  void _performAiMove() {
    _aiMoveTimer = null;
    if (_disposed) {
      return;
    }
    if (isGameOver || !ChessRules.hasAnyLegalMove(_game, aiColor)) {
      _aiThinking = false;
      notifyListeners();
      return;
    }

    final cooldown = cooldownRemaining(aiColor);
    if (cooldown.inMilliseconds > 0) {
      _aiMoveTimer = Timer(cooldown, _performAiMove);
      return;
    }

    final aiMove = ChessRules.withTurn<EngineMove?>(
      _game,
      aiColor,
      () => _aiEngine.chooseMove(_game),
    );
    if (aiMove == null) {
      _aiThinking = false;
      notifyListeners();
      return;
    }

    final moved = _applyMoveForColor(
      color: aiColor,
      from: aiMove.from,
      to: aiMove.to,
      promotion: aiMove.promotion,
    );
    _aiThinking = false;
    if (!moved) {
      _feedback = 'AI move failed.';
      notifyListeners();
      return;
    }

    _aiLastMoveFrom = aiMove.from;
    _aiLastMoveTo = aiMove.to;
    _startCooldown(aiColor);
    _feedback = null;
    _tryExecuteQueuedMoveIfReady();
    _scheduleAiMoveIfNeeded();
    _sessionLogger.logEvent(
      'ai_move_applied',
      data: <String, Object?>{
        ..._sessionSnapshot(),
        'from': aiMove.from,
        'to': aiMove.to,
        'promotion': aiMove.promotion,
      },
    );
    notifyListeners();
  }

  int _estimatedNowMs() => DateTime.now().millisecondsSinceEpoch;

  void _startCooldown(String color) {
    final now = _estimatedNowMs();
    final readyAt = now + _cooldownDuration.inMilliseconds;
    if (color == 'w') {
      _whiteReadyAtMs = readyAt;
    } else {
      _blackReadyAtMs = readyAt;
    }
  }

  void _onTick() {
    if (_disposed || !_hasActiveGame) {
      return;
    }

    if (_tryExecuteQueuedMoveIfReady()) {
      return;
    }

    if (_aiThinking ||
        cooldownRemaining('w').inMilliseconds > 0 ||
        cooldownRemaining('b').inMilliseconds > 0 ||
        hasQueuedMove) {
      notifyListeners();
    }
  }

  bool _tryExecuteQueuedMoveIfReady() {
    if (_disposed || !_hasActiveGame || !hasQueuedMove || isGameOver) {
      return false;
    }
    if (cooldownRemaining(_playerColor).inMilliseconds > 0) {
      return false;
    }

    final from = _queuedMoveFrom!;
    final to = _queuedMoveTo!;
    final promotion = _queuedPromotion;
    final validatedMove = ChessRules.findValidatedLegalMove(
      game: _game,
      from: from,
      to: to,
      color: _playerColor,
      promotion: promotion,
    );
    if (validatedMove == null) {
      _clearQueuedMove();
      _feedback = 'Queued move is no longer legal.';
      _sessionLogger.logEvent(
        'queued_move_invalidated',
        data: <String, Object?>{..._sessionSnapshot(), 'from': from, 'to': to},
      );
      notifyListeners();
      return true;
    }

    _clearQueuedMove();
    _applyPlayerMove(
      from: from,
      to: to,
      promotion:
          validatedMove['promotion'] as String? ?? ChessRules.defaultPromotion,
    );
    return true;
  }

  bool _canColorMoveNow(String color) {
    if (!_hasActiveGame || isGameOver) {
      return false;
    }
    return cooldownRemaining(color).inMilliseconds <= 0 &&
        ChessRules.hasAnyLegalMove(_game, color);
  }

  bool _applyMoveForColor({
    required String color,
    required String from,
    required String to,
    required String promotion,
  }) {
    final moved = ChessRules.withTurn<bool>(
      _game,
      color,
      () => _game.move(<String, String>{
        'from': from,
        'to': to,
        'promotion': promotion,
      }),
    );
    return moved;
  }

  void _queueMove({
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
    _queuedPromotion = ChessRules.defaultPromotion;
  }

  void _clearSelection() {
    _selectedSquare = null;
    _legalTargets = <String>{};
  }

  void _cancelAiMoveTimer() {
    _aiMoveTimer?.cancel();
    _aiMoveTimer = null;
  }

  @override
  void dispose() {
    _sessionLogger.closeSession(
      reason: 'controller_dispose',
      summary: _sessionSnapshot(),
    );
    _disposed = true;
    _ticker.cancel();
    _cancelAiMoveTimer();
    super.dispose();
  }

  Map<String, Object?> _sessionSnapshot() {
    return <String, Object?>{
      'playerColor': _playerColor,
      'turnColor': turnColor,
      'hasActiveGame': _hasActiveGame,
      'isGameOver': isGameOver,
      'isCheckmate': isCheckmate,
      'isDraw': isDraw,
      'historyLen': history.length,
      'fen': _game.fen,
      'cooldownSeconds': _cooldownDuration.inSeconds,
      'whiteRemainingMs': cooldownRemaining('w').inMilliseconds,
      'blackRemainingMs': cooldownRemaining('b').inMilliseconds,
      'feedback': _feedback,
    };
  }
}
