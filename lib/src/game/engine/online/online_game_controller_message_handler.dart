part of '../online_game_controller.dart';

extension _OnlineGameControllerMessageHandler on OnlineGameController {
  Future<void> _connectWebSocket({
    required Uri baseUri,
    required String wsPath,
    required String matchId,
    required String playerId,
  }) async {
    _logEvent(
      'ws_connect_start',
      details: <String, Object?>{
        'matchId': matchId,
        'playerId': playerId,
        'wsPath': wsPath,
      },
    );
    await disconnect(notify: false);

    try {
      _matchId = matchId;
      final wsUri = await _transportClient.connectSocket(
        baseUri: baseUri,
        wsPath: wsPath,
        matchId: matchId,
        playerId: playerId,
        onMessage: _onMessage,
        onError: (Object error) {
          _logEvent(
            'ws_stream_error',
            details: <String, Object?>{'error': error.toString()},
          );
          _feedback = _friendlyNetworkError(
            error,
            fallback: 'Connection error: $error',
          );
          _connectionState = OnlineConnectionState.disconnected;
          notifyListeners();
        },
        onDone: () {
          _logEvent('ws_stream_done');
          _connectionState = OnlineConnectionState.disconnected;
          _feedback = 'Disconnected from server.';
          notifyListeners();
        },
      );

      _connectionState = OnlineConnectionState.connected;
      _logEvent(
        'ws_connected',
        details: <String, Object?>{'matchId': matchId, 'uri': wsUri.toString()},
      );
      notifyListeners();
    } catch (error) {
      _logEvent(
        'ws_connect_failed',
        details: <String, Object?>{'error': error.toString()},
      );
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = _friendlyNetworkError(
        error,
        fallback: 'Unable to connect game socket: $error',
      );
      notifyListeners();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      _logEvent('ws_message_ignored_non_string');
      return;
    }

    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _logEvent('ws_message_ignored_non_map');
        return;
      }
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      _logEvent('ws_message_parse_failed');
      return;
    }

    final type = map['type'];
    if (type is! String) {
      _logEvent('ws_message_missing_type');
      return;
    }

    switch (type) {
      case 'welcome':
        _connectionState = OnlineConnectionState.connected;
        _matchId = map['matchId'] as String? ?? _matchId;
        _sessionLogger.setRoomOrMatchId(_matchId);
        _myColor = map['color'] as String?;
        final welcomePieceSkinId = MultiplayerClientUtils.sanitizeIdentifier(
          map['pieceSkinId'],
        );
        if (welcomePieceSkinId != null) {
          _myPieceSkinId = welcomePieceSkinId;
          if (_myColor != null) {
            _pieceSkinByColor[_myColor!] = welcomePieceSkinId;
          }
        }

        final welcomeCooldown = MultiplayerClientUtils.readInt(
          map['cooldownSeconds'],
        );
        if (welcomeCooldown != null && welcomeCooldown > 0) {
          _cooldownDuration = Duration(seconds: welcomeCooldown);
        }
        final serverNow = MultiplayerClientUtils.readInt(map['serverNow']);
        if (serverNow != null) {
          _clockOffsetMs = serverNow - _now().millisecondsSinceEpoch;
        }
        _applyForfeitLockFromPayload(map);

        _feedback = null;
        _logEvent(
          'ws_welcome',
          details: <String, Object?>{
            'matchId': _matchId,
            'myColor': _myColor,
            'pieceSkinId': _myPieceSkinId,
            'cooldownSeconds': _cooldownDuration.inSeconds,
          },
        );
        notifyListeners();
        return;
      case 'state':
        _applyState(map);
        return;
      case 'opponent_left':
        _logEvent(
          'ws_opponent_left',
          details: <String, Object?>{'message': map['message']},
        );
        _feedback = map['message'] as String? ?? 'Opponent disconnected.';
        notifyListeners();
        return;
      case 'error':
        _moveInFlight = false;
        _inFlightClientMoveId = null;
        _inFlightMoveSource = null;
        _inFlightQueueToken = null;
        final errorCode = map['code'] as String?;
        final message = map['message'] as String? ?? 'Server error';
        _feedback = message;
        final serverNow = MultiplayerClientUtils.readInt(map['serverNow']);
        if (serverNow != null) {
          _clockOffsetMs = serverNow - _now().millisecondsSinceEpoch;
        }
        _applyForfeitLockFromPayload(map);

        var receivedCooldownSnapshot = false;
        final cooldownEndsAt = map['cooldownEndsAt'];
        if (cooldownEndsAt is Map) {
          final w = MultiplayerClientUtils.readInt(cooldownEndsAt['w']);
          final b = MultiplayerClientUtils.readInt(cooldownEndsAt['b']);
          if (w != null) {
            _whiteReadyAtMs = w;
            receivedCooldownSnapshot = true;
          }
          if (b != null) {
            _blackReadyAtMs = b;
            receivedCooldownSnapshot = true;
          }
        }

        if (!receivedCooldownSnapshot && errorCode == 'cooldown_active') {
          final remainingMs = MultiplayerClientUtils.readInt(
            map['remainingMs'],
          );
          final color = _myColor;
          if (color != null && remainingMs != null && remainingMs > 0) {
            final baseNow = serverNow ?? _estimatedServerNowMs();
            _setReadyAtForColor(color, baseNow + remainingMs);
          }
        }

        if (hasQueuedMove && !_isRetriableQueueError(errorCode, message)) {
          _logEvent(
            'queued_move_cleared_on_error',
            details: <String, Object?>{'code': errorCode, 'message': message},
          );
          _clearQueuedMove();
        }
        _logEvent(
          'ws_error',
          details: <String, Object?>{
            'code': errorCode,
            'message': message,
            'matchId': _matchId,
          },
        );
        notifyListeners();
        return;
      case 'pong':
        _logEvent('ws_pong');
        return;
      default:
        _logEvent(
          'ws_message_unknown_type',
          details: <String, Object?>{'type': type},
        );
        return;
    }
  }

  void _applyState(Map<String, dynamic> state) {
    final nextSequence = state['sequence'] as int? ?? (_sequence + 1);
    if (nextSequence < _sequence) {
      _logEvent(
        'state_ignored_outdated',
        details: <String, Object?>{
          'nextSequence': nextSequence,
          'currentSequence': _sequence,
        },
      );
      return;
    }
    _sequence = nextSequence;

    final serverNow = MultiplayerClientUtils.readInt(state['serverNow']);
    if (serverNow != null) {
      _clockOffsetMs = serverNow - _now().millisecondsSinceEpoch;
    }

    final cooldownSeconds = MultiplayerClientUtils.readInt(
      state['cooldownSeconds'],
    );
    if (cooldownSeconds != null && cooldownSeconds > 0) {
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    final cooldownMs = MultiplayerClientUtils.readInt(state['cooldownMs']);
    if ((cooldownSeconds == null || cooldownSeconds <= 0) &&
        cooldownMs != null &&
        cooldownMs > 0) {
      _cooldownDuration = Duration(milliseconds: cooldownMs);
    }

    var receivedCooldownSnapshot = false;
    final cooldownEndsAt = state['cooldownEndsAt'];
    if (cooldownEndsAt is Map) {
      final w = MultiplayerClientUtils.readInt(cooldownEndsAt['w']);
      final b = MultiplayerClientUtils.readInt(cooldownEndsAt['b']);
      if (w != null) {
        _whiteReadyAtMs = w;
        receivedCooldownSnapshot = true;
      }
      if (b != null) {
        _blackReadyAtMs = b;
        receivedCooldownSnapshot = true;
      }
    }

    final fen = state['fen'] as String?;
    if (fen != null) {
      final loaded = _game.load(fen);
      if (!loaded) {
        _logEvent('state_invalid_fen', details: <String, Object?>{'fen': fen});
        _feedback = 'Received invalid board state from server.';
      }
    }

    _status = state['status'] as String? ?? _status;
    _result = state['result'] as String?;
    _applyForfeitLockFromPayload(state);

    final players = state['players'];
    if (players is Map<String, dynamic>) {
      _whitePlayerName = players['w'] as String?;
      _blackPlayerName = players['b'] as String?;
    }

    final pieceSkins = state['pieceSkins'];
    if (pieceSkins is Map) {
      final whiteSkin = MultiplayerClientUtils.sanitizeIdentifier(
        pieceSkins['w'],
      );
      final blackSkin = MultiplayerClientUtils.sanitizeIdentifier(
        pieceSkins['b'],
      );
      if (whiteSkin != null) {
        _pieceSkinByColor['w'] = whiteSkin;
      }
      if (blackSkin != null) {
        _pieceSkinByColor['b'] = blackSkin;
      }
      final myColor = _myColor;
      if (myColor != null) {
        final mySkin = _pieceSkinByColor[myColor];
        if (mySkin != null) {
          _myPieceSkinId = mySkin;
        }
      }
    }

    final lastMove = state['lastMove'];
    if (lastMove is Map<String, dynamic>) {
      _lastMoveFrom = lastMove['from'] as String?;
      _lastMoveTo = lastMove['to'] as String?;
      final lastMoveId = MultiplayerClientUtils.readInt(
        lastMove['clientMoveId'],
      );
      final lastMoveSource = lastMove['source'] as String?;
      final lastMoveQueueToken = MultiplayerClientUtils.readInt(
        lastMove['queueToken'],
      );
      final turnAfterMove = state['turn'] as String? ?? turnColor;
      final moverColor = ChessRules.oppositeColor(turnAfterMove);
      _lastMoverColor = moverColor;
      if (!receivedCooldownSnapshot) {
        // Compatibility fallback for older/custom backends that don't emit
        // `cooldownEndsAt` in state payloads. This keeps local timer HUD and
        // queue behavior functional after a confirmed move.
        final fallbackNow = serverNow ?? _estimatedServerNowMs();
        _applyCooldownForMover(moverColor, fallbackNow);
      }
      if (_myColor != null && moverColor == _myColor) {
        _myLastMoveFrom = _lastMoveFrom;
        _myLastMoveTo = _lastMoveTo;
      } else {
        _opponentLastMoveFrom = _lastMoveFrom;
        _opponentLastMoveTo = _lastMoveTo;
      }

      if (hasQueuedMove &&
          _myColor != null &&
          moverColor == _myColor &&
          _queuedMoveFrom == _lastMoveFrom &&
          _queuedMoveTo == _lastMoveTo) {
        _logEvent(
          'queued_move_confirmed',
          details: <String, Object?>{'from': _lastMoveFrom, 'to': _lastMoveTo},
        );
        _clearQueuedMove();
      }
      if (_myColor != null &&
          moverColor == _myColor &&
          _inFlightClientMoveId != null &&
          lastMoveId != null &&
          _inFlightClientMoveId == lastMoveId) {
        _logEvent(
          'in_flight_move_confirmed',
          details: <String, Object?>{
            'clientMoveId': lastMoveId,
            'source': lastMoveSource,
            'queueToken': lastMoveQueueToken,
          },
        );
        _inFlightClientMoveId = null;
        _inFlightMoveSource = null;
        _inFlightQueueToken = null;
      }
    } else {
      final history = state['history'];
      if (history is List && history.isEmpty) {
        _myLastMoveFrom = null;
        _myLastMoveTo = null;
        _opponentLastMoveFrom = null;
        _opponentLastMoveTo = null;
        _lastMoveFrom = null;
        _lastMoveTo = null;
        _lastMoverColor = null;
        _clearQueuedMove();
      }
    }

    _moveInFlight = false;
    _logEvent(
      'state_applied',
      details: <String, Object?>{
        'sequence': _sequence,
        'status': _status,
        'turn': turnColor,
        'result': _result,
        'historyLen': history.length,
      },
    );
    if (_lastMoverColor != null) {
      _sessionLogger.logBughuntEvent(
        'turn_ended',
        payload: <String, Object?>{
          'moverColor': _lastMoverColor,
          ..._sessionSnapshot(),
        },
        turnIndex: _derivedTurnIndex(),
        actionIndexOrPlyIndex: _derivedActionIndex(),
      );
    }
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
    _refreshSelectionForCurrentBoard();
    notifyListeners();
  }
}
