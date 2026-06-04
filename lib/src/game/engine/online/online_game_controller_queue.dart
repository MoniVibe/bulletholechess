part of '../online_game_controller.dart';

extension _OnlineGameControllerQueue on OnlineGameController {
  void _onTick() {
    if (_disposed || !isConnected) {
      return;
    }
    _resolveForfeitLockTimeoutIfNeeded();

    if (_status == 'active') {
      _tryExecuteQueuedPlayerMove();
    }

    if (_status == 'active' || hasQueuedMove) {
      notifyListeners();
    }
  }

  bool _sendMove({
    required String from,
    required String to,
    String? promotion,
    required String source,
    int? queueToken,
  }) {
    final color = _myColor;
    if (!isConnected || _status != 'active' || _moveInFlight || color == null) {
      _logEvent(
        'send_move_blocked',
        details: <String, Object?>{
          'from': from,
          'to': to,
          'status': _status,
          'isConnected': isConnected,
          'moveInFlight': _moveInFlight,
          'color': color,
        },
      );
      return false;
    }
    if (_isBlockedByForfeitLock(color)) {
      _logEvent(
        'send_move_blocked',
        details: <String, Object?>{
          'from': from,
          'to': to,
          'reason': 'forfeit_lock',
          'blockedColor': _forfeitBlockedColor,
          'releaseByColor': _forfeitReleaseByColor,
        },
      );
      return false;
    }

    final moveId = _nextClientMoveId++;
    final payload = <String, dynamic>{
      'type': 'move',
      'from': from,
      'to': to,
      'clientMoveId': moveId,
      'expectedSequence': _sequence,
      'source': source,
      'queueToken': queueToken,
    };
    if (promotion != null && promotion.isNotEmpty) {
      payload['promotion'] = promotion;
    }
    if (queueToken == null) {
      payload.remove('queueToken');
    }
    _send(payload);
    _moveInFlight = true;
    _inFlightClientMoveId = moveId;
    _inFlightMoveSource = source;
    _inFlightQueueToken = queueToken;
    _logEvent(
      'send_move_payload',
      details: <String, Object?>{
        'clientMoveId': moveId,
        'expectedSequence': _sequence,
        'source': source,
        'queueToken': queueToken,
        'from': from,
        'to': to,
        'promotion': promotion,
      },
    );
    return true;
  }

  void _tryExecuteQueuedPlayerMove() {
    final color = _myColor;
    if (color == null || !hasQueuedMove || isGameOver || _moveInFlight) {
      return;
    }
    _resolveForfeitLockTimeoutIfNeeded();
    if (_isBlockedByForfeitLock(color, resolveTimeout: false)) {
      return;
    }
    if (cooldownRemaining(color).inMilliseconds > 0) {
      return;
    }

    final from = _queuedMoveFrom!;
    final to = _queuedMoveTo!;
    final promotion = _queuedPromotion;
    final queueToken = _queueToken;
    final legalMove = ChessRules.findValidatedLegalMove(
      game: _game,
      from: from,
      to: to,
      color: color,
      promotion: promotion,
    );
    if (legalMove == null) {
      _logEvent(
        'queued_move_cleared_illegal',
        details: <String, Object?>{'from': from, 'to': to},
      );
      _clearQueuedMove();
      _feedback = null;
      return;
    }

    // Invariant: queueToken must match the queue snapshot captured at send
    // time so stale queue intents cannot be acknowledged as current ones.
    final sent = _sendMove(
      from: from,
      to: to,
      promotion: promotion,
      source: 'queued',
      queueToken: queueToken,
    );
    if (sent) {
      _logEvent(
        'queued_move_executing',
        details: <String, Object?>{
          'queueToken': queueToken,
          'from': from,
          'to': to,
          'promotion': promotion,
        },
      );
      _feedback = null;
    }
  }

  void _queuePlayerMove({
    required String from,
    required String to,
    required String promotion,
  }) {
    _queueToken += 1;
    _queuedMoveFrom = from;
    _queuedMoveTo = to;
    _queuedPromotion = promotion;
    _logEvent(
      'queue_set',
      details: <String, Object?>{
        'queueToken': _queueToken,
        'from': from,
        'to': to,
        'promotion': promotion,
      },
    );
  }

  void _clearQueuedMove() {
    if (_queuedMoveFrom != null && _queuedMoveTo != null) {
      _logEvent(
        'queue_cleared',
        details: <String, Object?>{
          'queueToken': _queueToken,
          'from': _queuedMoveFrom,
          'to': _queuedMoveTo,
        },
      );
    }
    _queueToken += 1;
    _queuedMoveFrom = null;
    _queuedMoveTo = null;
    _queuedPromotion = OnlineGameController._defaultPromotion;
  }
}
