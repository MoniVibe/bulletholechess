part of '../network_ai_duel_client.dart';

extension _ProtocolMessageHandling on _ChessNetworkAiSession {
  void _onMessage(dynamic raw) {
    if (raw is! String) {
      return;
    }
    final message = MultiplayerClientUtils.decodeJsonMap(raw);
    final type = message['type'] as String?;
    if (type == null) {
      return;
    }

    switch (type) {
      case 'welcome':
        _myColor = message['color'] as String?;
        _updateClockOffset(message['serverNow']);
        _updateCooldownSnapshot(message['cooldownEndsAt']);
        _forfeitLock = _readMap(message['forfeitLock']);
        logger.log(<String, Object?>{
          'event': 'welcome',
          'at': DateTime.now().toIso8601String(),
          'matchId': message['matchId'],
          'color': _myColor,
          'gameType': message['gameType'],
          'cooldownSeconds': message['cooldownSeconds'],
        });
        _attemptMoveIfReady();
        return;
      case 'state':
        _applyStateMessage(message);
        _attemptMoveIfReady();
        return;
      case 'error':
        _moveInFlight = false;
        _inFlightClientMoveId = null;
        _inFlightFrom = null;
        _inFlightTo = null;
        _updateClockOffset(message['serverNow']);
        _updateCooldownSnapshot(message['cooldownEndsAt']);
        _forfeitLock = _readMap(message['forfeitLock']) ?? _forfeitLock;
        final code = message['code']?.toString();
        logger.log(<String, Object?>{
          'event': _classifyServerErrorEvent(
            code: code,
            message: message['message']?.toString(),
          ),
          'at': DateTime.now().toIso8601String(),
          'code': code,
          'message': message['message'],
          'remainingMs': message['remainingMs'],
        });
        return;
      case 'opponent_left':
        logger.log(<String, Object?>{
          'event': 'opponent_left',
          'at': DateTime.now().toIso8601String(),
          'message': message['message'],
        });
        return;
      case 'pong':
        return;
      default:
        logger.log(<String, Object?>{
          'event': 'ws_unknown',
          'at': DateTime.now().toIso8601String(),
          'type': type,
        });
        return;
    }
  }

  void _applyStateMessage(Map<String, dynamic> message) {
    final incomingSequence = MultiplayerClientUtils.readInt(
      message['sequence'],
    );
    final sequence = incomingSequence ?? (_sequence + 1);
    if (sequence < _sequence) {
      return;
    }
    _sequence = sequence;
    _status = message['status'] as String? ?? _status;
    _result = message['result'] as String?;
    _lastStateAt = DateTime.now();
    final fen = message['fen'] as String?;
    if (fen != null && fen.trim().isNotEmpty) {
      _fen = fen;
    }
    _updateClockOffset(message['serverNow']);
    _updateCooldownSnapshot(message['cooldownEndsAt']);
    _forfeitLock = _readMap(message['forfeitLock']) ?? _forfeitLock;

    final lastMove = _readMap(message['lastMove']);
    if (_inFlightClientMoveId != null && lastMove != null) {
      final ackMoveId = MultiplayerClientUtils.readInt(
        lastMove['clientMoveId'],
      );
      final ackColor = (lastMove['color'] as String?)?.trim().toLowerCase();
      final ackFrom = (lastMove['from'] as String?)?.trim().toLowerCase();
      final ackTo = (lastMove['to'] as String?)?.trim().toLowerCase();
      final ackMatchesMoveId =
          ackMoveId != null && ackMoveId == _inFlightClientMoveId;
      final ackMatchesSender = ackColor != null
          ? ackColor == _myColor
          : (ackFrom == _inFlightFrom && ackTo == _inFlightTo);
      if (ackMatchesMoveId && ackMatchesSender) {
        _moveInFlight = false;
        _inFlightClientMoveId = null;
        _inFlightFrom = null;
        _inFlightTo = null;
        logger.log(<String, Object?>{
          'event': 'move_acked',
          'at': DateTime.now().toIso8601String(),
          'clientMoveId': ackMoveId,
          'from': lastMove['from'],
          'to': lastMove['to'],
        });
      }
    }

    logger.log(<String, Object?>{
      'event': 'state',
      'at': DateTime.now().toIso8601String(),
      'matchId': message['matchId'],
      'sequence': _sequence,
      'status': _status,
      'result': _result,
      'turn': message['turn'],
      'fen': _fen,
      'cooldownRemainingMs': _myColor == null
          ? null
          : _cooldownRemainingMs(_myColor!),
      'moveInFlight': _moveInFlight,
    });

    if (_sequence >= config.maxPlies) {
      logger.log(<String, Object?>{
        'event': 'game_over',
        'at': DateTime.now().toIso8601String(),
        'result': 'max_ply_cutoff',
        'sequence': _sequence,
      });
      _finish();
      return;
    }

    if (_result != null && config.exitOnGameOver) {
      logger.log(<String, Object?>{
        'event': 'game_over',
        'at': DateTime.now().toIso8601String(),
        'result': _result,
      });
      _finish();
    }
  }

  String _classifyServerErrorEvent({String? code, String? message}) {
    final normalizedCode = code?.trim().toLowerCase() ?? '';
    final normalizedMessage = message?.trim().toLowerCase() ?? '';
    const recoverableCodes = <String>{
      'stale_state',
      'cooldown_active',
      'not_your_turn',
      'invalid_move',
      'illegal_move',
      'forfeit_waiting_release',
      'queue_rejected',
      'queue_conflict',
    };
    if (recoverableCodes.contains(normalizedCode) ||
        normalizedMessage.contains('illegal move') ||
        normalizedMessage.contains('invalid move') ||
        normalizedMessage.contains('not your turn') ||
        normalizedMessage.contains('waiting for opponent')) {
      return 'action_rejected';
    }
    return 'server_error';
  }
}
