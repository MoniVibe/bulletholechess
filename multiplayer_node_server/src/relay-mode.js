function createRelayMode({
  relayEventReady,
  relayEventAction,
  relayEventComplete,
  sanitizeRelayEvent,
  sanitizeMoveId,
  sanitizeCooldownSeconds,
  sanitizePieceSkinId,
  bothPlayersConnected,
  playerForColor,
  relayMetaPayload,
  logEvent,
  sendJson,
  broadcastState,
  broadcastToConnected,
  clearForfeitLock,
  resetRelaySession,
}) {
  function isRelaySessionReady(match) {
    return Boolean(match.relayReady?.w) && Boolean(match.relayReady?.b);
  }

  function defaultRelayMetaPayload(match) {
    return {
      readyW: Boolean(match.relayReady?.w),
      readyB: Boolean(match.relayReady?.b),
      actionCount: Number.isFinite(match.relayActionCount)
        ? match.relayActionCount
        : 0,
    };
  }

  function resolveRelayMetaPayload(match) {
    if (typeof relayMetaPayload === 'function') {
      return relayMetaPayload(match);
    }
    return defaultRelayMetaPayload(match);
  }

  function isValidRelayActionPayload(payload, color) {
    if (!payload || typeof payload !== 'object') {
      return false;
    }
    const kind = sanitizeRelayEvent(payload.kind);
    const actionId = sanitizeMoveId(payload.actionId);
    const actorColor =
      typeof payload.actorColor === 'string'
        ? payload.actorColor.trim().toLowerCase()
        : '';
    if (!kind || actionId === null) {
      return false;
    }
    if (!['w', 'b'].includes(actorColor)) {
      return false;
    }
    if (actorColor !== color) {
      return false;
    }
    return true;
  }

  function resetRelay(match) {
    if (typeof resetRelaySession === 'function') {
      resetRelaySession(match);
      return;
    }
    match.relayState = null;
    match.relayReady = { w: false, b: false };
    match.relayActionCount = 0;
  }

  function handleRelaySocketMessage({ match, color, socket, payload }) {
    const type = typeof payload.type === 'string' ? payload.type : '';
    switch (type) {
      case 'relay': {
        if (!match.players.white || !match.players.black) {
          sendJson(socket, {
            type: 'error',
            code: 'waiting_for_opponent',
            message: 'Waiting for opponent.',
            relayMeta: resolveRelayMetaPayload(match),
            serverNow: Date.now(),
          });
          return;
        }
        if (!bothPlayersConnected(match)) {
          sendJson(socket, {
            type: 'error',
            code: 'waiting_for_opponent',
            message: 'Waiting for opponent connection.',
            relayMeta: resolveRelayMetaPayload(match),
            serverNow: Date.now(),
          });
          return;
        }

        const event = sanitizeRelayEvent(payload.event);
        const relayPayload =
          payload.payload && typeof payload.payload === 'object'
            ? payload.payload
            : null;
        const stateHash =
          typeof payload.stateHash === 'string' ? payload.stateHash.trim() : '';
        const result =
          typeof payload.result === 'string' ? payload.result.trim() : null;

        if (!event) {
          logEvent('relay_rejected', {
            matchId: match.matchId,
            gameType: match.gameType,
            color,
            reason: 'invalid_event',
            event: payload.event,
          });
          sendJson(socket, {
            type: 'error',
            code: 'relay_invalid_event',
            message: 'Relay event is required.',
            relayMeta: resolveRelayMetaPayload(match),
            serverNow: Date.now(),
          });
          return;
        }
        if (!relayPayload) {
          logEvent('relay_rejected', {
            matchId: match.matchId,
            gameType: match.gameType,
            color,
            reason: 'invalid_payload',
            event,
          });
          sendJson(socket, {
            type: 'error',
            code: 'relay_invalid_payload',
            message: 'Relay payload must be an object.',
            event,
            relayMeta: resolveRelayMetaPayload(match),
            serverNow: Date.now(),
          });
          return;
        }

        if (event === relayEventReady) {
          match.relayReady[color] = true;
        } else if (event === relayEventAction) {
          if (!isRelaySessionReady(match)) {
            logEvent('relay_rejected', {
              matchId: match.matchId,
              gameType: match.gameType,
              color,
              reason: 'not_ready',
              event,
            });
            sendJson(socket, {
              type: 'error',
              code: 'relay_not_ready',
              message: 'Both players must send ready before actions.',
              event,
              relayMeta: resolveRelayMetaPayload(match),
              serverNow: Date.now(),
            });
            return;
          }
          if (!isValidRelayActionPayload(relayPayload, color)) {
            logEvent('relay_rejected', {
              matchId: match.matchId,
              gameType: match.gameType,
              color,
              reason: 'invalid_action_payload',
              event,
            });
            sendJson(socket, {
              type: 'error',
              code: 'relay_invalid_action',
              message:
                'Relay action payload must include kind, actionId, and actorColor.',
              event,
              relayMeta: resolveRelayMetaPayload(match),
              serverNow: Date.now(),
            });
            return;
          }
          match.relayActionCount += 1;
        } else if (event === relayEventComplete) {
          if (!isRelaySessionReady(match)) {
            logEvent('relay_rejected', {
              matchId: match.matchId,
              gameType: match.gameType,
              color,
              reason: 'not_ready',
              event,
            });
            sendJson(socket, {
              type: 'error',
              code: 'relay_not_ready',
              message: 'Cannot complete session before both sides are ready.',
              event,
              relayMeta: resolveRelayMetaPayload(match),
              serverNow: Date.now(),
            });
            return;
          }
          if (!result) {
            logEvent('relay_rejected', {
              matchId: match.matchId,
              gameType: match.gameType,
              color,
              reason: 'missing_result',
              event,
            });
            sendJson(socket, {
              type: 'error',
              code: 'relay_missing_result',
              message: 'Relay completion requires a non-empty result.',
              event,
              relayMeta: resolveRelayMetaPayload(match),
              serverNow: Date.now(),
            });
            return;
          }
        }

        const relayResult = event === relayEventComplete ? result : null;
        match.updatedAt = Date.now();
        match.sequence += 1;
        const relayMessage = {
          type: 'relay',
          sequence: match.sequence,
          matchId: match.matchId,
          gameType: match.gameType,
          fromColor: color,
          event: event ?? null,
          payload: relayPayload,
          stateHash: stateHash || null,
          result: relayResult,
          serverNow: Date.now(),
          relayMeta: resolveRelayMetaPayload(match),
        };
        match.relayState = {
          fromColor: color,
          event,
          payload: relayPayload,
          stateHash: stateHash || null,
          result: relayResult,
          at: relayMessage.serverNow,
        };
        sendJson(socket, {
          type: 'relay_ack',
          sequence: match.sequence,
          matchId: match.matchId,
          gameType: match.gameType,
          fromColor: color,
          event,
          stateHash: stateHash || null,
          result: relayResult,
          relayMeta: resolveRelayMetaPayload(match),
          serverNow: relayMessage.serverNow,
        });
        logEvent('relay_message', {
          matchId: match.matchId,
          gameType: match.gameType,
          fromColor: color,
          event,
          stateHash: stateHash || null,
          hasResult: Boolean(relayResult),
          relayMeta: resolveRelayMetaPayload(match),
        });
        broadcastToConnected(match, relayMessage);
        broadcastState(match);
        return;
      }
      case 'new_game': {
        if (!bothPlayersConnected(match)) {
          sendJson(socket, {
            type: 'error',
            code: 'waiting_for_opponent',
            message: 'Waiting for opponent connection.',
            relayMeta: resolveRelayMetaPayload(match),
            serverNow: Date.now(),
          });
          return;
        }
        const requestedCooldown = sanitizeCooldownSeconds(payload.cooldownSeconds);
        if (requestedCooldown != null) {
          match.cooldownMs = requestedCooldown * 1000;
        }
        const now = Date.now();
        match.cooldownEndsAt.w = now;
        match.cooldownEndsAt.b = now;
        clearForfeitLock(match);
        resetRelay(match);
        match.updatedAt = now;
        logEvent('new_game', {
          matchId: match.matchId,
          gameType: match.gameType,
          requestedByColor: color,
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
            gameType: match.gameType,
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
          gameType: match.gameType,
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
          gameType: match.gameType,
          color,
          reason: 'unknown_message_type',
          type,
        });
        sendJson(socket, {
          type: 'error',
          message: `Unknown message type: ${type}`,
        });
        return;
    }
  }

  return {
    handleRelaySocketMessage,
    isRelaySessionReady,
    relayMetaPayload: defaultRelayMetaPayload,
    isValidRelayActionPayload,
    resetRelaySession: resetRelay,
  };
}

module.exports = {
  createRelayMode,
};
