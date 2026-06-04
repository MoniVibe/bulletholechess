const { Chess } = require('chess.js');

function registerWebSocketHandlers({
  wss,
  matches,
  gameTypeChess,
  defaultPieceSkinId,
  sanitizeSquare,
  sanitizePromotion,
  sanitizeMoveId,
  sanitizeSequence,
  sanitizeMoveSource,
  sanitizeCooldownSeconds,
  sanitizePieceSkinId,
  playerForColor,
  clearColorSlot,
  bothPlayersConnected,
  isExpired,
  cleanupMatch,
  broadcastState,
  broadcastToConnected,
  clearForfeitLock,
  setForfeitLock,
  setCooldownForMover,
  maybeResolveForfeitLockTimeout,
  isColorBlockedByForfeitLock,
  serializeForfeitLock,
  hasAnyLegalMoveForColor,
  findValidatedLegalMove,
  movePayloadFromLegalMove,
  applyMoveAsColor,
  getTerminalStatus,
  handleRelaySocketMessage,
  resetRelaySession,
  logEvent,
  sendJson,
}) {
  wss.on('connection', (socket, req) => {
    const url = new URL(req.url, 'http://localhost');
    const matchId = url.searchParams.get('matchId');
    const playerId = url.searchParams.get('playerId');

    if (!matchId || !playerId) {
      logEvent('ws_connect_rejected', {
        reason: 'missing_parameters',
        matchId,
        playerId,
      });
      sendJson(socket, {
        type: 'error',
        message: 'matchId and playerId are required.',
      });
      socket.close(1008, 'Missing parameters');
      return;
    }

    const match = matches.get(matchId);
    if (!match || isExpired(match)) {
      logEvent('ws_connect_rejected', {
        reason: 'match_unavailable',
        matchId,
        playerId,
      });
      cleanupMatch(matchId, {
        notifyMessage: 'Match expired.',
        closeReason: 'Match expired',
      });
      sendJson(socket, { type: 'error', message: 'Match not found.' });
      socket.close(1008, 'Match unavailable');
      return;
    }

    const color = match.playersById.get(playerId);
    if (!color) {
      logEvent('ws_connect_rejected', {
        reason: 'invalid_player_session',
        matchId,
        playerId,
      });
      sendJson(socket, { type: 'error', message: 'Invalid player session.' });
      socket.close(1008, 'Invalid player');
      return;
    }

    const player = playerForColor(match, color);
    if (!player || player.playerId !== playerId) {
      logEvent('ws_connect_rejected', {
        reason: 'player_slot_unavailable',
        matchId,
        playerId,
        color,
      });
      sendJson(socket, { type: 'error', message: 'Player slot unavailable.' });
      socket.close(1008, 'Player unavailable');
      return;
    }

    if (player.socket && player.socket.readyState === player.socket.OPEN) {
      player.socket.close(1000, 'Replaced by new connection');
    }

    if (!Number.isFinite(player.joinedAt)) {
      player.joinedAt = Date.now();
    }
    player.hasConnected = true;
    player.socket = socket;
    match.updatedAt = Date.now();
    logEvent('ws_connected', {
      matchId,
      gameType: match.gameType,
      playerId,
      color,
      players: {
        w: match.players.white?.name ?? null,
        b: match.players.black?.name ?? null,
      },
    });

    sendJson(socket, {
      type: 'welcome',
      matchId,
      gameType: match.gameType,
      playerId,
      color,
      pieceSkinId: player.pieceSkinId ?? defaultPieceSkinId,
      cooldownSeconds: Math.round(match.cooldownMs / 1000),
      forfeitLock: serializeForfeitLock(match.forfeitLock),
      serverNow: Date.now(),
    });
    broadcastState(match);

    socket.on('message', (raw) => {
      let payload;
      try {
        payload = JSON.parse(raw.toString('utf8'));
      } catch (_error) {
        logEvent('ws_invalid_json', {
          matchId: match.matchId,
          playerId,
          color,
        });
        sendJson(socket, { type: 'error', message: 'Invalid JSON payload.' });
        return;
      }

      if (!payload || typeof payload !== 'object') {
        logEvent('ws_invalid_payload', {
          matchId: match.matchId,
          playerId,
          color,
        });
        sendJson(socket, { type: 'error', message: 'Invalid payload.' });
        return;
      }

      handleSocketMessage({ match, color, socket, payload });
    });

    socket.on('close', () => {
      if (player.socket !== socket) {
        return;
      }

      player.socket = null;
      match.playersById.delete(playerId);
      clearColorSlot(match, color);
      if (match.gameType === gameTypeChess) {
        match.game = new Chess();
      } else {
        resetRelaySession(match);
      }
      const now = Date.now();
      match.cooldownEndsAt.w = now;
      match.cooldownEndsAt.b = now;
      clearForfeitLock(match);
      match.updatedAt = now;

      if (!match.players.white && !match.players.black) {
        logEvent('ws_disconnected', {
          matchId: match.matchId,
          playerId,
          color,
          removedMatch: true,
        });
        cleanupMatch(matchId);
        return;
      }

      logEvent('ws_disconnected', {
        matchId: match.matchId,
        playerId,
        color,
        removedMatch: false,
      });

      broadcastToConnected(match, {
        type: 'opponent_left',
        message: 'Your opponent disconnected.',
      });
      broadcastState(match);
    });
  });

  function handleSocketMessage({ match, color, socket, payload }) {
    if (match.gameType !== gameTypeChess) {
      handleRelaySocketMessage({ match, color, socket, payload });
      return;
    }

    const type = typeof payload.type === 'string' ? payload.type : '';
    switch (type) {
      case 'move': {
        const attemptedFrom = sanitizeSquare(payload.from);
        const attemptedTo = sanitizeSquare(payload.to);
        const attemptedPromotion = sanitizePromotion(payload.promotion);
        const clientMoveId = sanitizeMoveId(payload.clientMoveId);
        const expectedSequence = sanitizeSequence(payload.expectedSequence);
        const source = sanitizeMoveSource(payload.source);
        const queueToken = sanitizeMoveId(payload.queueToken);
        const player = playerForColor(match, color);
        const playerId = player?.playerId ?? null;
        logEvent('move_attempt', {
          matchId: match.matchId,
          color,
          playerId,
          from: attemptedFrom,
          to: attemptedTo,
          promotion: attemptedPromotion,
          clientMoveId,
          expectedSequence,
          source,
          queueToken,
        });

        if (!match.players.white || !match.players.black) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            reason: 'waiting_for_opponent',
          });
          sendJson(socket, { type: 'error', message: 'Waiting for opponent.' });
          return;
        }
        if (!bothPlayersConnected(match)) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            reason: 'opponent_not_connected',
          });
          sendJson(socket, {
            type: 'error',
            code: 'waiting_for_opponent',
            message: 'Waiting for opponent connection.',
          });
          return;
        }

        const terminal = getTerminalStatus(match.game);
        if (terminal.gameOver) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            reason: 'game_over',
            result: terminal.result,
          });
          sendJson(socket, {
            type: 'error',
            message: 'Game over. Start a new game.',
          });
          return;
        }

        const now = Date.now();
        maybeResolveForfeitLockTimeout(match, now);
        if (isColorBlockedByForfeitLock(match, color)) {
          const releaseByColor = match.forfeitLock.releaseByColor;
          const releaseReadyAt = releaseByColor
            ? match.cooldownEndsAt[releaseByColor] || 0
            : 0;
          const remainingMs = Math.max(0, releaseReadyAt - now);
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            reason: 'forfeit_waiting_release',
            blockedColor: match.forfeitLock.blockedColor,
            releaseByColor,
            remainingMs,
          });
          sendJson(socket, {
            type: 'error',
            message: 'You forfeited the overdue turn. Wait for the opponent move or timeout.',
            code: 'forfeit_waiting_release',
            blockedColor: match.forfeitLock.blockedColor,
            releaseByColor,
            remainingMs,
            cooldownEndsAt: match.cooldownEndsAt,
            forfeitLock: serializeForfeitLock(match.forfeitLock),
            serverNow: now,
          });
          return;
        }
        if (expectedSequence !== null && expectedSequence !== match.sequence) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            reason: 'stale_state',
            expectedSequence,
            currentSequence: match.sequence,
          });
          sendJson(socket, {
            type: 'error',
            code: 'stale_state',
            message: 'Client state is stale. Wait for latest board update.',
            expectedSequence,
            currentSequence: match.sequence,
            cooldownEndsAt: match.cooldownEndsAt,
            forfeitLock: serializeForfeitLock(match.forfeitLock),
            serverNow: Date.now(),
          });
          return;
        }
        const readyAt = match.cooldownEndsAt[color] || 0;
        if (now < readyAt) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            reason: 'cooldown_active',
            remainingMs: readyAt - now,
          });
          sendJson(socket, {
            type: 'error',
            message: `Cooldown active for ${readyAt - now}ms.`,
            code: 'cooldown_active',
            remainingMs: readyAt - now,
            serverNow: now,
            cooldownEndsAt: match.cooldownEndsAt,
          });
          return;
        }

        if (!hasAnyLegalMoveForColor(match.game, color)) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            reason: 'no_legal_moves',
          });
          sendJson(socket, {
            type: 'error',
            message: 'No legal moves available.',
          });
          return;
        }

        const from = attemptedFrom;
        const to = attemptedTo;
        const promotion = attemptedPromotion;
        if (!from || !to) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            reason: 'invalid_coordinates',
            from: payload.from,
            to: payload.to,
          });
          sendJson(socket, {
            type: 'error',
            message: 'Invalid move coordinates.',
          });
          return;
        }

        const fromPiece = match.game.get(from);
        const toPiece = match.game.get(to);
        if (!fromPiece) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            clientMoveId,
            source,
            queueToken,
            reason: 'from_square_empty',
            from,
            to,
          });
          sendJson(socket, {
            type: 'error',
            code: 'from_square_empty',
            message: 'No piece at from-square.',
          });
          return;
        }
        if (fromPiece.color !== color) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            clientMoveId,
            source,
            queueToken,
            reason: 'piece_not_owned',
            from,
            to,
            fromPieceType: fromPiece.type,
            fromPieceColor: fromPiece.color,
          });
          sendJson(socket, {
            type: 'error',
            code: 'piece_not_owned',
            message: 'Cannot move an opponent piece.',
          });
          return;
        }
        if (toPiece && toPiece.color === color) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            clientMoveId,
            source,
            queueToken,
            reason: 'destination_occupied_by_own_piece',
            from,
            to,
            toPieceType: toPiece.type,
            toPieceColor: toPiece.color,
          });
          sendJson(socket, {
            type: 'error',
            code: 'destination_occupied_by_own_piece',
            message: 'Cannot capture your own piece.',
          });
          return;
        }

        const legalMove = findValidatedLegalMove({
          game: match.game,
          from,
          to,
          promotion,
          color,
        });
        if (!legalMove) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            clientMoveId,
            source,
            queueToken,
            reason: 'illegal_move',
            from,
            to,
            promotion,
          });
          sendJson(socket, { type: 'error', message: 'Illegal move.' });
          return;
        }

        const nominalTurnColor = match.game.turn();
        const movePayload = movePayloadFromLegalMove(legalMove);
        const moved = applyMoveAsColor(match.game, color, movePayload);
        if (!moved) {
          logEvent('move_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            clientMoveId,
            source,
            queueToken,
            reason: 'move_apply_failed',
            from,
            to,
            promotion,
          });
          sendJson(socket, { type: 'error', message: 'Illegal move.' });
          return;
        }

        setCooldownForMover(match, color, now);
        if (
          match.forfeitLock.blockedColor === nominalTurnColor &&
          match.forfeitLock.releaseByColor === color
        ) {
          clearForfeitLock(match);
        } else if (nominalTurnColor !== color) {
          setForfeitLock(match, {
            blockedColor: nominalTurnColor,
            releaseByColor: color,
          });
        } else if (
          match.forfeitLock.releaseByColor === color &&
          match.forfeitLock.blockedColor
        ) {
          clearForfeitLock(match);
        }
        match.updatedAt = now;
        logEvent('move_accepted', {
          matchId: match.matchId,
          color,
          playerId,
          clientMoveId,
          source,
          queueToken,
          from,
          to,
          promotion,
          cooldownEndsAt: {
            w: match.cooldownEndsAt.w,
            b: match.cooldownEndsAt.b,
          },
          forfeitLock: serializeForfeitLock(match.forfeitLock),
        });
        broadcastState(match, {
          from,
          to,
          promotion,
          color,
          clientMoveId,
          source,
          queueToken,
        });
        return;
      }
      case 'new_game': {
        if (!bothPlayersConnected(match)) {
          sendJson(socket, {
            type: 'error',
            code: 'waiting_for_opponent',
            message: 'Waiting for opponent connection.',
          });
          return;
        }
        const requestedCooldown = sanitizeCooldownSeconds(payload.cooldownSeconds);
        if (requestedCooldown != null) {
          match.cooldownMs = requestedCooldown * 1000;
        }
        const player = playerForColor(match, color);
        const playerId = player?.playerId ?? null;

        match.game = new Chess();
        const now = Date.now();
        match.cooldownEndsAt.w = now;
        match.cooldownEndsAt.b = now;
        clearForfeitLock(match);
        match.updatedAt = now;
        logEvent('new_game', {
          matchId: match.matchId,
          requestedByColor: color,
          requestedByPlayerId: playerId,
          cooldownSeconds: Math.round(match.cooldownMs / 1000),
        });
        broadcastState(match);
        return;
      }
      case 'set_piece_skin': {
        const pieceSkinId = sanitizePieceSkinId(payload.pieceSkinId);
        const player = playerForColor(match, color);
        const playerId = player?.playerId ?? null;
        if (!player) {
          sendJson(socket, {
            type: 'error',
            message: 'Player slot unavailable.',
          });
          return;
        }
        if (!pieceSkinId) {
          logEvent('piece_skin_rejected', {
            matchId: match.matchId,
            color,
            playerId,
            reason: 'invalid_skin_id',
            pieceSkinId: payload.pieceSkinId,
          });
          sendJson(socket, {
            type: 'error',
            message: 'Invalid piece skin id.',
          });
          return;
        }
        if (player.pieceSkinId === pieceSkinId) {
          return;
        }
        player.pieceSkinId = pieceSkinId;
        match.updatedAt = Date.now();
        logEvent('piece_skin_updated', {
          matchId: match.matchId,
          color,
          playerId,
          pieceSkinId,
        });
        broadcastState(match);
        return;
      }
      case 'ping':
        sendJson(socket, { type: 'pong', at: new Date().toISOString() });
        return;
      default:
        logEvent('message_rejected', {
          matchId: match.matchId,
          color,
          reason: 'unknown_message_type',
          type,
        });
        sendJson(socket, {
          type: 'error',
          message: `Unknown message type: ${type}`,
        });
    }
  }
}

module.exports = {
  registerWebSocketHandlers,
};
