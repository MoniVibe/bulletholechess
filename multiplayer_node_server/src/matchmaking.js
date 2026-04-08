function createMatchmaking({
  crypto,
  Chess,
  matches,
  gameTypeChess,
  defaultCooldownSeconds,
  matchTimeoutEnabled,
  matchTtlMs,
  matchConnectGraceMs,
  sanitizeCooldownSeconds,
  logEvent,
  broadcastState,
  sendJson,
  resetRelaySession,
  clearForfeitLock,
}) {
  function assignPlayerToMatch(
    name,
    gameType,
    requestedCooldownSeconds,
    pieceSkinId,
  ) {
    const waitingMatch = findJoinableMatch(gameType);
    if (waitingMatch) {
      const color = openColorForMatch(waitingMatch);
      const playerId = crypto.randomUUID();
      const player = {
        playerId,
        name,
        socket: null,
        pieceSkinId,
        joinedAt: Date.now(),
        hasConnected: false,
      };
      setColorSlot(waitingMatch, color, player);
      waitingMatch.playersById.set(playerId, color);
      waitingMatch.updatedAt = Date.now();
      return {
        match: waitingMatch,
        playerId,
        color,
        created: false,
      };
    }

    const cooldownSeconds =
      requestedCooldownSeconds ??
      sanitizeCooldownSeconds(defaultCooldownSeconds) ??
      3;
    const cooldownMs = Math.max(cooldownSeconds * 1000, 0);

    const matchId = crypto.randomUUID();
    const playerId = crypto.randomUUID();
    const match = createEmptyMatch({ matchId, cooldownMs, gameType });
    match.players.white = {
      playerId,
      name,
      socket: null,
      pieceSkinId,
      joinedAt: Date.now(),
      hasConnected: false,
    };
    match.playersById.set(playerId, 'w');
    matches.set(matchId, match);
    return {
      match,
      playerId,
      color: 'w',
      created: true,
    };
  }

  function createEmptyMatch({ matchId, cooldownMs, gameType }) {
    const now = Date.now();
    return {
      matchId,
      gameType,
      players: {
        white: null,
        black: null,
      },
      playersById: new Map(),
      game: gameType === gameTypeChess ? new Chess() : null,
      relayState: null,
      relayReady: { w: false, b: false },
      relayActionCount: 0,
      sequence: 0,
      cooldownMs,
      cooldownEndsAt: { w: now, b: now },
      forfeitLock: {
        blockedColor: null,
        releaseByColor: null,
      },
      createdAt: now,
      updatedAt: now,
    };
  }

  function findJoinableMatch(gameType) {
    let candidate = null;
    const now = Date.now();
    for (const match of matches.values()) {
      if (isExpired(match)) {
        continue;
      }
      if (match.gameType !== gameType) {
        continue;
      }
      const openColor = openColorForMatch(match);
      if (!openColor) {
        continue;
      }
      if (!hasNonStaleSearcher(match, openColor, now)) {
        continue;
      }
      if (!candidate || match.createdAt < candidate.createdAt) {
        candidate = match;
      }
    }
    return candidate;
  }

  function openColorForMatch(match) {
    if (!match.players.white) {
      return 'w';
    }
    if (!match.players.black) {
      return 'b';
    }
    return null;
  }

  function playerForColor(match, color) {
    return color === 'w' ? match.players.white : match.players.black;
  }

  function setColorSlot(match, color, player) {
    if (color === 'w') {
      match.players.white = player;
    } else {
      match.players.black = player;
    }
  }

  function clearColorSlot(match, color) {
    if (color === 'w') {
      match.players.white = null;
    } else {
      match.players.black = null;
    }
  }

  function cleanupMatch(matchId, options = {}) {
    const match = matches.get(matchId);
    if (!match) {
      return;
    }

    const {
      notifyMessage = null,
      closeCode = 1001,
      closeReason = 'Match closed',
    } = options;

    for (const p of [match.players.white, match.players.black]) {
      if (!p || !p.socket || p.socket.readyState !== p.socket.OPEN) {
        continue;
      }
      if (notifyMessage) {
        sendJson(p.socket, { type: 'error', message: notifyMessage });
      }
      p.socket.close(closeCode, closeReason);
    }

    logEvent('match_cleaned_up', {
      matchId,
      notifyMessage,
      closeReason,
    });
    matches.delete(matchId);
  }

  function pruneExpiredMatches() {
    if (!matchTimeoutEnabled) {
      return;
    }

    const now = Date.now();
    for (const [matchId, match] of matches.entries()) {
      if (now - match.updatedAt > matchTtlMs) {
        cleanupMatch(matchId, {
          notifyMessage: 'Match expired.',
          closeReason: 'Match expired',
        });
      }
    }
  }

  function isPlayerConnected(player) {
    return Boolean(
      player && player.socket && player.socket.readyState === player.socket.OPEN,
    );
  }

  function bothPlayersConnected(match) {
    return isPlayerConnected(match.players.white) && isPlayerConnected(match.players.black);
  }

  function hasNonStaleSearcher(match, openColor, nowMs) {
    // Only join matches that represent an actively searching opponent.
    // This prevents pairing with abandoned reservations that never connected.
    const opponentColor = openColor === 'w' ? 'b' : 'w';
    const opponent = playerForColor(match, opponentColor);
    if (!opponent) {
      return false;
    }
    if (isPlayerConnected(opponent)) {
      return true;
    }
    if (opponent.hasConnected === true) {
      return false;
    }
    const joinedAt = Number.isFinite(opponent.joinedAt)
      ? opponent.joinedAt
      : match.createdAt;
    const ageMs = nowMs - joinedAt;
    return ageMs <= matchConnectGraceMs;
  }

  function pruneStaleUnconnectedReservations() {
    const now = Date.now();
    for (const [matchId, match] of matches.entries()) {
      let changed = false;
      for (const color of ['w', 'b']) {
        const player = playerForColor(match, color);
        if (!player) {
          continue;
        }
        if (isPlayerConnected(player) || player.hasConnected === true) {
          continue;
        }
        const joinedAt = Number.isFinite(player.joinedAt)
          ? player.joinedAt
          : match.createdAt;
        const ageMs = now - joinedAt;
        if (ageMs <= matchConnectGraceMs) {
          continue;
        }
        // Never-connected players beyond the grace window are treated as stale
        // reservations and removed so matchmaking can continue.
        match.playersById.delete(player.playerId);
        clearColorSlot(match, color);
        changed = true;
        logEvent('stale_reservation_pruned', {
          matchId: match.matchId,
          color,
          playerId: player.playerId,
          ageMs,
        });
      }

      if (!changed) {
        continue;
      }

      if (match.gameType === gameTypeChess) {
        match.game = new Chess();
      } else {
        resetRelaySession(match);
      }
      match.cooldownEndsAt.w = now;
      match.cooldownEndsAt.b = now;
      clearForfeitLock(match);
      match.updatedAt = now;

      if (!match.players.white && !match.players.black) {
        cleanupMatch(matchId);
        continue;
      }
      broadcastState(match);
    }
  }

  function isExpired(match) {
    if (!matchTimeoutEnabled) {
      return false;
    }
    return Date.now() - match.updatedAt > matchTtlMs;
  }

  return {
    assignPlayerToMatch,
    findJoinableMatch,
    openColorForMatch,
    playerForColor,
    setColorSlot,
    clearColorSlot,
    cleanupMatch,
    pruneExpiredMatches,
    isPlayerConnected,
    bothPlayersConnected,
    pruneStaleUnconnectedReservations,
    isExpired,
  };
}

module.exports = {
  createMatchmaking,
};
