import 'dart:async';
import 'dart:math';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

import 'chess_rules.dart';
import 'dumb_ai_engine.dart';
import 'turn_state_primitives.dart';

class LocalGameController extends ChangeNotifier {
  static const String _defaultPromotion = ChessRules.defaultPromotion;

  LocalGameController({
    Duration initialCooldownDuration = const Duration(seconds: 3),
    this.aiThinkDelayMin = const Duration(seconds: 2),
    this.aiThinkDelayMax = const Duration(seconds: 4),
    DumbAiEngine? aiEngine,
    Random? random,
    DateTime Function()? nowProvider,
  }) : _random = random ?? Random(),
       _aiEngine = aiEngine ?? DumbAiEngine(random: random ?? Random()),
       _cooldownDuration = initialCooldownDuration,
       _now = nowProvider ?? DateTime.now {
    _cooldowns = TurnCooldownTracker(
      nowMsProvider: () => _now().millisecondsSinceEpoch,
    );
    _resetRuntimeState(activateGame: false);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
  }

  Duration _cooldownDuration;
  final Duration aiThinkDelayMin;
  final Duration aiThinkDelayMax;
  final Random _random;
  final DumbAiEngine _aiEngine;
  final DateTime Function() _now;
  late final TurnCooldownTracker _cooldowns;
  final QueuedMoveState _queuedMove = QueuedMoveState(
    defaultPromotion: _defaultPromotion,
  );
  final ForfeitLockState _forfeitLock = ForfeitLockState();
  final GameSessionLogger _sessionLogger = GameSessionLogger(
    applicationId: 'bulletholechess',
    gameId: 'chess',
    mode: 'local_duel',
  );

  late chess.Chess _game;
  late Timer _ticker;
  Timer? _aiMoveTimer;
  bool _disposed = false;
  bool _aiMovePending = false;
  bool _hasActiveGame = false;

  String _playerColor = 'w';
  int _version = 0;
  String? _selectedSquare;
  Set<String> _legalTargets = <String>{};
  String? _playerLastMoveFrom;
  String? _playerLastMoveTo;
  String? _opponentLastMoveFrom;
  String? _opponentLastMoveTo;
  String? _feedback;
  String? _winnerColor;

  int get version => _version;
  Duration get cooldownDuration => _cooldownDuration;
  String get playerColor => _playerColor;
  String get aiColor => ChessRules.oppositeColor(playerColor);
  bool get hasActiveGame => _hasActiveGame;

  String get turnColor => ChessRules.colorCode(_game.turn);
  String get turnLabel => turnColor == 'w' ? 'White' : 'Black';
  bool get isGameOver => _winnerColor != null;
  String? get winnerColor => _winnerColor;
  String? get winnerLabel {
    if (_winnerColor == null) {
      return null;
    }
    return _winnerColor == 'w' ? 'White' : 'Black';
  }

  bool get aiMovePending => _aiMovePending;
  bool get canPlayerInteract =>
      _hasActiveGame &&
      !isGameOver &&
      ChessRules.hasAnyLegalMove(_game, playerColor);
  bool get hasQueuedMove => _queuedMove.hasMove;
  String? get queuedMoveLabel => _queuedMove.label;
  String? get queuedMoveFrom => _queuedMove.from;
  String? get queuedMoveTo => _queuedMove.to;

  String? get selectedSquare => _selectedSquare;
  Set<String> get legalTargets => _legalTargets;
  String? get playerLastMoveFrom => _playerLastMoveFrom;
  String? get playerLastMoveTo => _playerLastMoveTo;
  String? get opponentLastMoveFrom => _opponentLastMoveFrom;
  String? get opponentLastMoveTo => _opponentLastMoveTo;
  String? get opponentLastMoveLabel {
    if (_opponentLastMoveFrom == null || _opponentLastMoveTo == null) {
      return null;
    }
    return '$_opponentLastMoveFrom-$_opponentLastMoveTo';
  }

  String? get feedback => _feedback;
  List<String> get history => _game.getHistory().cast<String>();
  Map<String, String> get boardPieces =>
      ChessRules.boardPiecesFromFen(_game.fen);
  Set<String> get checkedKingSquares {
    if (!_hasActiveGame) {
      return const <String>{};
    }
    return ChessRules.checkedKingSquares(_game);
  }

  String get statusText {
    if (!_hasActiveGame) {
      return 'Start a new game to begin.';
    }
    if (_winnerColor != null) {
      return '${winnerLabel!} wins by checkmate. Start a new game.';
    }
    if (ChessRules.isInCheckFor(_game, playerColor)) {
      return 'Your king is in check. Play a legal response.';
    }

    if (hasQueuedMove) {
      final remaining = cooldownRemaining(playerColor);
      if (remaining.inMilliseconds > 0) {
        return 'Queued $queuedMoveLabel (${ChessRules.formatDuration(remaining)}).';
      }
      return 'Queued $queuedMoveLabel. Executing...';
    }

    _resolveForfeitLockTimeoutIfNeeded();
    final playerReady =
        cooldownRemaining(playerColor).inMilliseconds == 0 &&
        !_isBlockedByForfeitLock(playerColor, resolveTimeout: false);
    final botReady =
        cooldownRemaining(aiColor).inMilliseconds == 0 &&
        !_isBlockedByForfeitLock(aiColor, resolveTimeout: false);
    if (playerReady && botReady) {
      if (ChessRules.isInCheckFor(_game, playerColor)) {
        return 'Both ready. You are in check, move now.';
      }
      if (_aiMovePending) {
        return 'Both ready. Bot is thinking, but you can move now.';
      }
      return 'Both ready. Move anytime.';
    }

    if (playerReady) {
      return ChessRules.isInCheckFor(_game, playerColor)
          ? 'You are in check. Move now.'
          : 'You can move now.';
    }

    if (_isBlockedByForfeitLock(playerColor)) {
      final releaseBy = _forfeitLock.releaseByColor;
      if (releaseBy != null) {
        final releaseRemaining = cooldownRemaining(releaseBy);
        if (releaseRemaining.inMilliseconds > 0) {
          return 'Overtime turn forfeited. Waiting ${ChessRules.formatDuration(releaseRemaining)}.';
        }
      }
      return 'Overtime turn forfeited. Waiting for opponent.';
    }

    final aiRemaining = cooldownRemaining(aiColor);
    if (aiRemaining.inMilliseconds == 0) {
      return _aiMovePending ? 'Bot is thinking...' : 'Bot can move now.';
    }
    return 'Cooling down...';
  }

  Duration cooldownRemaining(String color) {
    return _cooldowns.remaining(color);
  }

  void startNewGame({bool playerAsWhite = true, Duration? cooldownDuration}) {
    _cancelAiTimer();
    _playerColor = playerAsWhite ? 'w' : 'b';
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
    _resetRuntimeState(activateGame: true);
    _sessionLogger.logEvent('new_game_started', data: _sessionSnapshot());
    _sessionLogger.logBughuntEvent(
      'turn_started',
      payload: <String, Object?>{'turnColor': turnColor, ..._sessionSnapshot()},
      turnIndex: _derivedTurnIndex(),
      actionIndexOrPlyIndex: _derivedActionIndex(),
    );
    _sessionLogger.recordStateSnapshot(
      _sessionSnapshot(),
      turnIndex: _derivedTurnIndex(),
      actionIndexOrPlyIndex: _derivedActionIndex(),
    );
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
    final isOwnPiece =
        piece != null && ChessRules.pieceColor(piece) == playerColor;

    if (_selectedSquare == null) {
      if (isOwnPiece) {
        _selectedSquare = square;
        _legalTargets = ChessRules.legalDestinationsFrom(
          game: _game,
          square: square,
          color: playerColor,
        );
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
    final legalMove = ChessRules.findValidatedLegalMove(
      game: _game,
      from: from,
      to: square,
      color: playerColor,
      promotion: _defaultPromotion,
    );
    final legalNow = legalMove != null;

    if (legalNow) {
      final chosenPromotion =
          legalMove['promotion'] as String? ?? _defaultPromotion;
      final onCooldown =
          cooldownRemaining(playerColor).inMilliseconds > 0 ||
          _isBlockedByForfeitLock(playerColor);
      if (onCooldown) {
        _queuePlayerMove(from: from, to: square, promotion: chosenPromotion);
        _clearSelection();
        _feedback = null;
        notifyListeners();
        return;
      }

      final didMove = _applyMove(
        from: from,
        to: square,
        promotion: chosenPromotion,
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
      _selectedSquare = square;
      _legalTargets = ChessRules.legalDestinationsFrom(
        game: _game,
        square: square,
        color: playerColor,
      );
      _feedback = null;
      notifyListeners();
      return;
    }

    _feedback = 'Illegal move';
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionLogger.closeSession(
      reason: 'controller_dispose',
      summary: _sessionSnapshot(),
    );
    _disposed = true;
    _ticker.cancel();
    _cancelAiTimer();
    super.dispose();
  }

  void _onTick() {
    if (_disposed) {
      return;
    }
    if (!_hasActiveGame) {
      return;
    }
    _resolveForfeitLockTimeoutIfNeeded();
    _refreshTerminalState();
    _tryExecuteQueuedPlayerMove();
    _maybeScheduleAiMove();
    notifyListeners();
  }

  void _maybeScheduleAiMove() {
    if (!_hasActiveGame ||
        _aiMovePending ||
        isGameOver ||
        !_canColorMoveNow(aiColor)) {
      return;
    }

    _aiMovePending = true;
    _aiMoveTimer = Timer(_nextAiThinkDelay(), _runAiMove);
  }

  void _runAiMove() {
    if (_disposed) {
      return;
    }

    if (!_hasActiveGame || isGameOver || !_canColorMoveNow(aiColor)) {
      _aiMovePending = false;
      notifyListeners();
      return;
    }

    final move = ChessRules.withTurn(
      _game,
      aiColor,
      () => _aiEngine.chooseMove(_game),
    );
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

  void _resetRuntimeState({required bool activateGame}) {
    _game = chess.Chess();
    _hasActiveGame = activateGame;
    _version = 0;
    _selectedSquare = null;
    _legalTargets = <String>{};
    _playerLastMoveFrom = null;
    _playerLastMoveTo = null;
    _opponentLastMoveFrom = null;
    _opponentLastMoveTo = null;
    _feedback = null;
    _aiMovePending = false;
    _queuedMove.clear();
    _winnerColor = null;
    _cooldowns.resetReadyNow();
    _forfeitLock.clear();
    _refreshTerminalState();
  }

  bool _applyMove({
    required String from,
    required String to,
    required String moverColor,
    String promotion = _defaultPromotion,
  }) {
    if (!_hasActiveGame ||
        isGameOver ||
        cooldownRemaining(moverColor).inMilliseconds > 0 ||
        _isBlockedByForfeitLock(moverColor)) {
      return false;
    }

    final nominalTurnColor = turnColor;
    final legalMove = ChessRules.findValidatedLegalMove(
      game: _game,
      from: from,
      to: to,
      color: moverColor,
      promotion: promotion,
    );
    if (legalMove == null) {
      return false;
    }

    final previousTurn = _game.turn;
    _game.turn = ChessRules.toChessColor(moverColor);
    final payload = ChessRules.movePayloadFromLegalMove(
      legalMove,
      fallbackPromotion: promotion,
    );
    final moved = _game.move(payload);

    if (!moved) {
      _game.turn = previousTurn;
      return false;
    }

    if (_aiMovePending && moverColor == playerColor) {
      _cancelAiTimer();
      _aiMovePending = false;
    }

    _version += 1;
    if (moverColor == playerColor) {
      _playerLastMoveFrom = from;
      _playerLastMoveTo = to;
    } else {
      _opponentLastMoveFrom = from;
      _opponentLastMoveTo = to;
    }
    _cooldowns.startCooldown(
      color: moverColor,
      cooldownDuration: _cooldownDuration,
    );
    _updateForfeitLockAfterMove(
      moverColor: moverColor,
      nominalTurnColor: nominalTurnColor,
    );
    _refreshSelectionForCurrentBoard();
    _refreshTerminalState();
    _sessionLogger.logEvent(
      'move_applied',
      data: <String, Object?>{
        ..._sessionSnapshot(),
        'moverColor': moverColor,
        'from': from,
        'to': to,
        'promotion': promotion,
      },
    );
    _sessionLogger.logBughuntEvent(
      'turn_ended',
      payload: <String, Object?>{
        'moverColor': moverColor,
        ..._sessionSnapshot(),
      },
      turnIndex: _derivedTurnIndex(),
      actionIndexOrPlyIndex: _derivedActionIndex(),
    );
    _sessionLogger.logBughuntEvent(
      'turn_started',
      payload: <String, Object?>{'turnColor': turnColor, ..._sessionSnapshot()},
      turnIndex: _derivedTurnIndex(),
      actionIndexOrPlyIndex: _derivedActionIndex(),
    );
    _sessionLogger.recordStateSnapshot(
      _sessionSnapshot(),
      turnIndex: _derivedTurnIndex(),
      actionIndexOrPlyIndex: _derivedActionIndex(),
    );
    return true;
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
    _queuedMove.queue(from: from, to: to, promotion: promotion);
    _sessionLogger.logBughuntEvent(
      'action_queued',
      payload: <String, Object?>{
        'from': from,
        'to': to,
        'promotion': promotion,
        ..._sessionSnapshot(),
      },
      turnIndex: _derivedTurnIndex(),
      actionIndexOrPlyIndex: _derivedActionIndex(),
    );
  }

  void _clearQueuedMove() {
    final previous = _queuedMove.clear();
    if (previous != null) {
      _sessionLogger.logBughuntEvent(
        'action_cancelled',
        payload: <String, Object?>{
          'from': previous.from,
          'to': previous.to,
          ..._sessionSnapshot(),
        },
        turnIndex: _derivedTurnIndex(),
        actionIndexOrPlyIndex: _derivedActionIndex(),
      );
    }
  }

  void _tryExecuteQueuedPlayerMove() {
    if (!_hasActiveGame || !hasQueuedMove || isGameOver) {
      return;
    }
    _resolveForfeitLockTimeoutIfNeeded();
    if (_isBlockedByForfeitLock(playerColor, resolveTimeout: false)) {
      return;
    }
    if (cooldownRemaining(playerColor).inMilliseconds > 0) {
      return;
    }

    final from = _queuedMove.from!;
    final to = _queuedMove.to!;
    final promotion = _queuedMove.promotion;
    final legalMove = ChessRules.findValidatedLegalMove(
      game: _game,
      from: from,
      to: to,
      color: playerColor,
      promotion: promotion,
    );
    if (legalMove == null) {
      _clearQueuedMove();
      _feedback = null;
      _sessionLogger.logBughuntEvent(
        'action_rejected',
        payload: <String, Object?>{
          'from': from,
          'to': to,
          'reason': 'queued_move_invalidated',
          ..._sessionSnapshot(),
        },
        severity: BughuntSeverity.warn,
        turnIndex: _derivedTurnIndex(),
        actionIndexOrPlyIndex: _derivedActionIndex(),
      );
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
      _feedback = null;
      return;
    }

    _clearQueuedMove();
    _feedback = null;
    _maybeScheduleAiMove();
  }

  bool _canColorMoveNow(String color) {
    if (cooldownRemaining(color).inMilliseconds > 0) {
      return false;
    }
    if (_isBlockedByForfeitLock(color)) {
      return false;
    }
    return ChessRules.hasAnyLegalMove(_game, color);
  }

  void _updateForfeitLockAfterMove({
    required String moverColor,
    required String nominalTurnColor,
  }) {
    _forfeitLock.updateAfterMove(
      moverColor: moverColor,
      nominalTurnColor: nominalTurnColor,
    );
  }

  bool _isBlockedByForfeitLock(String color, {bool resolveTimeout = true}) {
    return _forfeitLock.isBlocked(
      color,
      resolveTimeout: resolveTimeout,
      cooldownRemaining: cooldownRemaining,
    );
  }

  void _resolveForfeitLockTimeoutIfNeeded() {
    _forfeitLock.resolveTimeoutIfNeeded(cooldownRemaining: cooldownRemaining);
  }

  void _refreshSelectionForCurrentBoard() {
    if (_selectedSquare == null) {
      return;
    }

    final piece = boardPieces[_selectedSquare!];
    if (piece == null || ChessRules.pieceColor(piece) != playerColor) {
      _clearSelection();
      return;
    }

    _legalTargets = ChessRules.legalDestinationsFrom(
      game: _game,
      square: _selectedSquare!,
      color: playerColor,
    );
  }

  void _refreshTerminalState() {
    if (!_hasActiveGame) {
      _winnerColor = null;
      return;
    }
    final winner = ChessRules.detectCheckmateWinner(_game);
    _winnerColor = winner;
    if (_winnerColor != null) {
      _cancelAiTimer();
      _aiMovePending = false;
      _clearQueuedMove();
      _clearSelection();
    }
  }

  void _cancelAiTimer() {
    _aiMoveTimer?.cancel();
    _aiMoveTimer = null;
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

  int _derivedActionIndex() => _game.getHistory().length;

  int _derivedTurnIndex() => (_derivedActionIndex() ~/ 2) + 1;

  Map<String, Object?> _sessionSnapshot() {
    return <String, Object?>{
      'turnIndex': _derivedTurnIndex(),
      'actionIndexOrPlyIndex': _derivedActionIndex(),
      'playerColor': _playerColor,
      'turnColor': turnColor,
      'hasActiveGame': _hasActiveGame,
      'isGameOver': isGameOver,
      'winnerColor': _winnerColor,
      'historyLen': _game.getHistory().length,
      'fen': _game.fen,
      'cooldownSeconds': _cooldownDuration.inSeconds,
      'whiteRemainingMs': cooldownRemaining('w').inMilliseconds,
      'blackRemainingMs': cooldownRemaining('b').inMilliseconds,
      'feedback': _feedback,
      'queuedMove': queuedMoveLabel,
    };
  }
}
