import 'dart:async';

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
    startNewGame(
      playerAsWhite: true,
      cooldownDuration: initialCooldownDuration,
    );
  }

  final Duration aiMoveDelay;
  final DumbAiEngine _aiEngine;
  final chess.Chess _game = chess.Chess();

  late final Timer _ticker;
  Timer? _aiMoveTimer;
  bool _disposed = false;
  bool _aiThinking = false;

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
  bool get isGameOver => _game.game_over;
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
    final now = _estimatedNowMs();
    final readyAt = color == 'w' ? _whiteReadyAtMs : _blackReadyAtMs;
    final remaining = readyAt - now;
    if (remaining <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: remaining);
  }

  bool get canPlayerInteract {
    return !_aiThinking &&
        !isGameOver &&
        turnColor == _playerColor &&
        cooldownRemaining(_playerColor).inMilliseconds <= 0 &&
        ChessRules.hasAnyLegalMove(_game, _playerColor);
  }

  String get statusText {
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
    if (_aiThinking) {
      if (hasQueuedMove) {
        return 'AI is thinking... Queued $queuedMoveLabel.';
      }
      return 'AI is thinking...';
    }

    if (turnColor == _playerColor) {
      final remaining = cooldownRemaining(_playerColor);
      if (remaining.inMilliseconds > 0) {
        return 'Cooling down (${ChessRules.formatDuration(remaining)}).';
      }
      return 'Your move.';
    }

    final aiRemaining = cooldownRemaining(aiColor);
    if (aiRemaining.inMilliseconds > 0) {
      return 'AI cooling down (${ChessRules.formatDuration(aiRemaining)}).';
    }
    return 'AI move.';
  }

  void startNewGame({required bool playerAsWhite, Duration? cooldownDuration}) {
    _cancelAiMoveTimer();
    if (cooldownDuration != null) {
      _cooldownDuration = cooldownDuration;
    }
    _game.reset();
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
    notifyListeners();
  }

  void tapSquare(String square) {
    final canQueuePlannedMove =
        !isGameOver &&
        (_aiThinking ||
            turnColor != _playerColor ||
            cooldownRemaining(_playerColor).inMilliseconds > 0);
    final canHandleTap = canPlayerInteract || canQueuePlannedMove;
    if (!canHandleTap) {
      if (!isGameOver && turnColor == _playerColor) {
        final remaining = cooldownRemaining(_playerColor);
        if (remaining.inMilliseconds > 0) {
          _feedback = 'Cooling down (${ChessRules.formatDuration(remaining)}).';
          notifyListeners();
        }
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
    final moved = _game.move(<String, String>{
      'from': from,
      'to': to,
      'promotion': promotion,
    });
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
    notifyListeners();
  }

  void _scheduleAiMoveIfNeeded() {
    if (_disposed || isGameOver || turnColor != aiColor) {
      return;
    }
    _cancelAiMoveTimer();
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
    if (_disposed) {
      return;
    }
    if (isGameOver || turnColor != aiColor) {
      _aiThinking = false;
      notifyListeners();
      return;
    }

    final cooldown = cooldownRemaining(aiColor);
    if (cooldown.inMilliseconds > 0) {
      _aiMoveTimer = Timer(cooldown, _performAiMove);
      return;
    }

    final aiMove = _aiEngine.chooseMove(_game);
    if (aiMove == null) {
      _aiThinking = false;
      notifyListeners();
      return;
    }

    final moved = _game.move(<String, String>{
      'from': aiMove.from,
      'to': aiMove.to,
      'promotion': aiMove.promotion,
    });
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
    if (_tryExecuteQueuedMoveIfReady()) {
      return;
    }
    notifyListeners();
  }

  int _estimatedNowMs() => DateTime.now().millisecondsSinceEpoch;

  void _startCooldown(String color) {
    final now = _estimatedNowMs();
    final readyAt = now + _cooldownDuration.inMilliseconds;
    if (color == 'w') {
      _whiteReadyAtMs = readyAt;
      _blackReadyAtMs = now;
    } else {
      _blackReadyAtMs = readyAt;
      _whiteReadyAtMs = now;
    }
  }

  void _onTick() {
    if (_disposed) {
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
    if (_disposed ||
        !hasQueuedMove ||
        _aiThinking ||
        isGameOver ||
        turnColor != _playerColor) {
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
    _disposed = true;
    _ticker.cancel();
    _cancelAiMoveTimer();
    super.dispose();
  }
}
