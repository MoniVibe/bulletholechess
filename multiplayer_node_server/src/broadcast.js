function createBroadcaster({
  defaultPieceSkinId,
  gameTypeChess,
  bothPlayersConnected,
  getTerminalStatus,
  serializeForfeitLock,
  relayMetaPayload,
  sendJson,
}) {
  function broadcastState(match, lastMove = null) {
    match.sequence += 1;
    const connected = bothPlayersConnected(match);
    if (match.gameType === gameTypeChess) {
      const terminal = getTerminalStatus(match.game);
      const payload = {
        type: 'state',
        sequence: match.sequence,
        matchId: match.matchId,
        gameType: match.gameType,
        status: !connected
          ? 'waiting'
          : terminal.gameOver
          ? 'game_over'
          : 'active',
        fen: match.game.fen(),
        turn: match.game.turn(),
        history: match.game.history(),
        players: {
          w: match.players.white ? match.players.white.name : null,
          b: match.players.black ? match.players.black.name : null,
        },
        pieceSkins: {
          w: match.players.white?.pieceSkinId ?? defaultPieceSkinId,
          b: match.players.black?.pieceSkinId ?? defaultPieceSkinId,
        },
        cooldownMs: match.cooldownMs,
        cooldownSeconds: Math.round(match.cooldownMs / 1000),
        cooldownEndsAt: match.cooldownEndsAt,
        forfeitLock: serializeForfeitLock(match.forfeitLock),
        serverNow: Date.now(),
      };

      if (lastMove) {
        payload.lastMove = lastMove;
      }
      if (terminal.gameOver && terminal.result) {
        payload.result = terminal.result;
      }

      broadcastToConnected(match, payload);
      return;
    }

    const relayResult =
      match.relayState &&
      typeof match.relayState.result === 'string' &&
      match.relayState.result.trim().length > 0
        ? match.relayState.result.trim()
        : null;
    const payload = {
      type: 'state',
      sequence: match.sequence,
      matchId: match.matchId,
      gameType: match.gameType,
      status: !connected
        ? 'waiting'
        : relayResult
        ? 'game_over'
        : 'active',
      players: {
        w: match.players.white ? match.players.white.name : null,
        b: match.players.black ? match.players.black.name : null,
      },
      pieceSkins: {
        w: match.players.white?.pieceSkinId ?? defaultPieceSkinId,
        b: match.players.black?.pieceSkinId ?? defaultPieceSkinId,
      },
      cooldownMs: match.cooldownMs,
      cooldownSeconds: Math.round(match.cooldownMs / 1000),
      cooldownEndsAt: match.cooldownEndsAt,
      forfeitLock: serializeForfeitLock(match.forfeitLock),
      relayState: match.relayState,
      relayMeta: relayMetaPayload(match),
      result: relayResult,
      serverNow: Date.now(),
    };
    broadcastToConnected(match, payload);
  }

  function broadcastToConnected(match, payload) {
    for (const p of [match.players.white, match.players.black]) {
      if (!p || !p.socket || p.socket.readyState !== p.socket.OPEN) {
        continue;
      }
      sendJson(p.socket, payload);
    }
  }

  return {
    broadcastState,
    broadcastToConnected,
  };
}

module.exports = {
  createBroadcaster,
};
