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
        final errorCode = map['code'] as String?;
        final message = map['message'] as String? ?? 'Server error';
        // Only end the current in-flight attempt when the error actually
        // pertains to the move (a move rejection) -- an unrelated error
        // (skin/new_game/parse/unknown-type) arriving mid-flight must NOT clear
        // the flag, or a premature second move could be emitted before the real
        // ack. The server sends `type:'error'` for both classes and does not
        // echo the clientMoveId on errors, so we discriminate by code/message.
        if (_isMoveRelatedError(errorCode, message)) {
          _clearInFlight();
        }
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
    // Drop strictly-older frames AND exact duplicates of the last applied
    // sequence (WS reconnect retransmits the last frame verbatim, which would
    // otherwise re-run last-move-highlight / queue-confirm side effects and
    // produce a "ghost" move). The omitted-sequence path defaults nextSequence
    // to _sequence + 1, so it is never equal and keeps applying normally.
    if (nextSequence <= _sequence) {
      _logEvent(
        'state_ignored_outdated',
        details: <String, Object?>{
          'nextSequence': nextSequence,
          'currentSequence': _sequence,
        },
      );
      return;
    }

    // Validate the board BEFORE committing any state from this frame. When a
    // frame carries a FEN that the engine rejects, the whole frame is
    // untrustworthy: applying its status/result/lastMove/cooldowns while the
    // board stays on the previously-loaded (rejected) position leaves the client
    // desynced -- metadata advances off a board we refused to load. Short-circuit
    // the entire apply. We intentionally do NOT advance `_sequence` here, so a
    // corrected retransmit (same or next sequence) can still be applied instead
    // of being swallowed by the duplicate/outdated gate. `chess` 0.8.1's
    // `load()` validates before mutating, so a rejected FEN leaves `_game`
    // untouched (board remains the last good position).
    final fen = state['fen'] as String?;
    if (fen != null && !_game.load(fen)) {
      _logEvent('state_invalid_fen', details: <String, Object?>{'fen': fen});
      _feedback = 'Received invalid board state from server.';
      notifyListeners();
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
      if (_moveInFlight && _myColor != null && moverColor == _myColor) {
        // Primary confirm: the frame echoes our in-flight clientMoveId.
        final idEchoConfirms =
            _inFlightClientMoveId != null &&
            lastMoveId != null &&
            _inFlightClientMoveId == lastMoveId;
        // No-echo fallback: older/relay backends may not echo `clientMoveId`.
        // If this frame shows OUR color as the mover and the from/to match our
        // in-flight move, treat it as confirmation so the in-flight flag can
        // never wedge waiting for an id that will never arrive.
        final noEchoConfirms =
            lastMoveId == null &&
            _inFlightFrom != null &&
            _inFlightTo != null &&
            _lastMoveFrom == _inFlightFrom &&
            _lastMoveTo == _inFlightTo;
        if (idEchoConfirms || noEchoConfirms) {
          _logEvent(
            'in_flight_move_confirmed',
            details: <String, Object?>{
              'clientMoveId': lastMoveId,
              'source': lastMoveSource,
              'queueToken': lastMoveQueueToken,
              'confirmedVia': idEchoConfirms ? 'id_echo' : 'no_echo_fallback',
            },
          );
          _clearInFlight();
        }
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

    // In-flight tracking is cleared ONLY when this frame actually confirms our
    // move (the lastMove block above) or the game reached a terminal state.
    // It is NOT cleared unconditionally: in this simultaneous-move variant an
    // opponent frame arrives while our move is still unacked, and clearing here
    // would defeat the `_sendMove` / `clearQueuedMove` in-flight guards and let
    // a premature second move through. A silently dropped move is handled by
    // the bounded in-flight timeout on the ticker.
    if (_status == 'game_over' || _result != null) {
      _clearInFlight();
    }
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
