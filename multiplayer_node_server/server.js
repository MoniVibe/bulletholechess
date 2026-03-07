const crypto = require('crypto');
const http = require('http');

const express = require('express');
const cors = require('cors');
const { Chess } = require('chess.js');
const { WebSocketServer } = require('ws');

const PORT = Number.parseInt(process.env.PORT || '8080', 10);
const BIND = process.env.BIND || '0.0.0.0';
const DEFAULT_COOLDOWN_SECONDS = Number.parseInt(
  process.env.DEFAULT_COOLDOWN_SECONDS || '3',
  10,
);
const MIN_COOLDOWN_SECONDS = Number.parseInt(
  process.env.MIN_COOLDOWN_SECONDS || '1',
  10,
);
const MAX_COOLDOWN_SECONDS = 30;
const DEFAULT_PIECE_SKIN_ID = 'chess_classic';
const DEFAULT_GAME_TYPE = 'chess';
const GAME_TYPE_CHESS = 'chess';
const MAX_PIECE_SKIN_ID_LENGTH = 40;
const PIECE_SKIN_ID_PATTERN = /^[a-z0-9_-]+$/;
const MATCH_TTL_MS = Number.parseInt(process.env.MATCH_TTL_MS || '0', 10);
const MATCH_TIMEOUT_ENABLED =
  Number.isFinite(MATCH_TTL_MS) && MATCH_TTL_MS > 0;
const MAX_SERVER_LOGS = Number.parseInt(process.env.MAX_SERVER_LOGS || '500', 10);

const app = express();
app.use(cors());
app.use(express.json({ limit: '32kb' }));
app.options('*', cors());

const matches = new Map();
const serverLogs = [];
let logSequence = 0;

app.get('/healthz', (_req, res) => {
  res.json({ ok: true, at: new Date().toISOString() });
});

app.get('/debug/logs', (req, res) => {
  const limitRaw = Number.parseInt(String(req.query.limit ?? '100'), 10);
  const limit = Number.isFinite(limitRaw)
    ? Math.min(Math.max(limitRaw, 1), 1000)
    : 100;
  const matchIdFilter =
    typeof req.query.matchId === 'string' ? req.query.matchId.trim() : '';
  const eventFilter =
    typeof req.query.event === 'string' ? req.query.event.trim() : '';
  const levelFilter =
    typeof req.query.level === 'string' ? req.query.level.trim() : '';

  let items = [...serverLogs];
  if (matchIdFilter) {
    items = items.filter((entry) => entry.matchId === matchIdFilter);
  }
  if (eventFilter) {
    items = items.filter((entry) => entry.event === eventFilter);
  }
  if (levelFilter) {
    items = items.filter((entry) => entry.level === levelFilter);
  }

  const sliced = items.slice(-limit);
  res.json({
    count: serverLogs.length,
    returned: sliced.length,
    items: sliced,
  });
});

app.post('/api/matches/create', (req, res) => {
  joinOrCreate(req, res);
});

app.post('/api/matches/join', (req, res) => {
  joinOrCreate(req, res);
});

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

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
    pieceSkinId: player.pieceSkinId ?? DEFAULT_PIECE_SKIN_ID,
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
    if (match.gameType === GAME_TYPE_CHESS) {
      match.game = new Chess();
    } else {
      match.relayState = null;
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

if (MATCH_TIMEOUT_ENABLED) {
  setInterval(() => {
    pruneExpiredMatches();
  }, 30_000).unref();
}

server.listen(PORT, BIND, () => {
  console.log(`Bullethole backend listening on http://${BIND}:${PORT}`);
  logEvent('server_started', { bind: BIND, port: PORT });
});

function joinOrCreate(req, res) {
  const name = sanitizeName(req.body?.name);
  if (!name) {
    res.status(400).json({ error: 'Name is required (1-24 chars).' });
    return;
  }

  const requestedCooldownSeconds = sanitizeCooldownSeconds(
    req.body?.cooldownSeconds,
  );
  const gameType = sanitizeGameType(req.body?.gameType) ?? DEFAULT_GAME_TYPE;
  const requestedPieceSkinId =
    sanitizePieceSkinId(req.body?.pieceSkinId) ?? DEFAULT_PIECE_SKIN_ID;

  pruneExpiredMatches();
  const assignment = assignPlayerToMatch(
    name,
    gameType,
    requestedCooldownSeconds,
    requestedPieceSkinId,
  );
  logEvent('match_join_or_create', {
    matchId: assignment.match.matchId,
    playerId: assignment.playerId,
    color: assignment.color,
    created: assignment.created,
    gameType: assignment.match.gameType,
    cooldownSeconds: Math.round(assignment.match.cooldownMs / 1000),
    pieceSkinId: requestedPieceSkinId,
    playerName: name,
  });
  const status = assignment.created ? 201 : 200;
  res.status(status).json({
    matchId: assignment.match.matchId,
    playerId: assignment.playerId,
    color: assignment.color,
    gameType: assignment.match.gameType,
    wsPath: '/ws',
    cooldownSeconds: Math.round(assignment.match.cooldownMs / 1000),
    pieceSkinId: requestedPieceSkinId,
  });
}

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
    const player = { playerId, name, socket: null, pieceSkinId };
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
    sanitizeCooldownSeconds(DEFAULT_COOLDOWN_SECONDS) ??
    3;
  const cooldownMs = Math.max(cooldownSeconds * 1000, 0);

  const matchId = crypto.randomUUID();
  const playerId = crypto.randomUUID();
  const match = createEmptyMatch({ matchId, cooldownMs, gameType });
  match.players.white = { playerId, name, socket: null, pieceSkinId };
  match.playersById.set(playerId, 'w');
  matches.set(matchId, match);
  return {
    match,
    playerId,
    color: 'w',
    created: true,
  };
}

function findJoinableMatch(gameType) {
  let candidate = null;
  for (const match of matches.values()) {
    if (isExpired(match)) {
      continue;
    }
    if (match.gameType !== gameType) {
      continue;
    }
    if (!openColorForMatch(match)) {
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

function handleSocketMessage({ match, color, socket, payload }) {
  if (match.gameType !== GAME_TYPE_CHESS) {
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

function handleRelaySocketMessage({ match, color, socket, payload }) {
  const type = typeof payload.type === 'string' ? payload.type : '';
  switch (type) {
    case 'relay': {
      const event = sanitizeGameType(payload.event);
      const relayPayload =
        payload.payload && typeof payload.payload === 'object'
          ? payload.payload
          : {};
      const stateHash =
        typeof payload.stateHash === 'string' ? payload.stateHash.trim() : '';
      const result =
        typeof payload.result === 'string' ? payload.result.trim() : null;

      if (!match.players.white || !match.players.black) {
        sendJson(socket, { type: 'error', message: 'Waiting for opponent.' });
        return;
      }

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
        result,
        serverNow: Date.now(),
      };
      match.relayState = {
        fromColor: color,
        event: event ?? null,
        payload: relayPayload,
        stateHash: stateHash || null,
        result,
        at: relayMessage.serverNow,
      };
      logEvent('relay_message', {
        matchId: match.matchId,
        gameType: match.gameType,
        fromColor: color,
        event: event ?? null,
        stateHash: stateHash || null,
        hasResult: Boolean(result),
      });
      broadcastToConnected(match, relayMessage);
      return;
    }
    case 'new_game': {
      const requestedCooldown = sanitizeCooldownSeconds(payload.cooldownSeconds);
      if (requestedCooldown != null) {
        match.cooldownMs = requestedCooldown * 1000;
      }
      const now = Date.now();
      match.cooldownEndsAt.w = now;
      match.cooldownEndsAt.b = now;
      clearForfeitLock(match);
      match.relayState = null;
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
    game: gameType === GAME_TYPE_CHESS ? new Chess() : null,
    relayState: null,
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

function broadcastState(match, lastMove = null) {
  match.sequence += 1;
  if (match.gameType === GAME_TYPE_CHESS) {
    const terminal = getTerminalStatus(match.game);
    const payload = {
      type: 'state',
      sequence: match.sequence,
      matchId: match.matchId,
      gameType: match.gameType,
      status: !match.players.white || !match.players.black
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
        w: match.players.white?.pieceSkinId ?? DEFAULT_PIECE_SKIN_ID,
        b: match.players.black?.pieceSkinId ?? DEFAULT_PIECE_SKIN_ID,
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
    status: !match.players.white || !match.players.black
      ? 'waiting'
      : relayResult
      ? 'game_over'
      : 'active',
    players: {
      w: match.players.white ? match.players.white.name : null,
      b: match.players.black ? match.players.black.name : null,
    },
    pieceSkins: {
      w: match.players.white?.pieceSkinId ?? DEFAULT_PIECE_SKIN_ID,
      b: match.players.black?.pieceSkinId ?? DEFAULT_PIECE_SKIN_ID,
    },
    cooldownMs: match.cooldownMs,
    cooldownSeconds: Math.round(match.cooldownMs / 1000),
    cooldownEndsAt: match.cooldownEndsAt,
    forfeitLock: serializeForfeitLock(match.forfeitLock),
    relayState: match.relayState,
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
  if (!MATCH_TIMEOUT_ENABLED) {
    return;
  }

  const now = Date.now();
  for (const [matchId, match] of matches.entries()) {
    if (now - match.updatedAt > MATCH_TTL_MS) {
      cleanupMatch(matchId, {
        notifyMessage: 'Match expired.',
        closeReason: 'Match expired',
      });
    }
  }
}

function setCooldownForMover(match, moverColor, atMs) {
  const nextReady = atMs + match.cooldownMs;
  if (moverColor === 'w') {
    match.cooldownEndsAt.w = nextReady;
    return;
  }
  match.cooldownEndsAt.b = nextReady;
}

function setForfeitLock(match, { blockedColor, releaseByColor }) {
  if (!['w', 'b'].includes(blockedColor) || !['w', 'b'].includes(releaseByColor)) {
    return;
  }
  match.forfeitLock.blockedColor = blockedColor;
  match.forfeitLock.releaseByColor = releaseByColor;
}

function clearForfeitLock(match) {
  match.forfeitLock.blockedColor = null;
  match.forfeitLock.releaseByColor = null;
}

function maybeResolveForfeitLockTimeout(match, nowMs) {
  const releaseByColor = match.forfeitLock.releaseByColor;
  if (!releaseByColor) {
    return;
  }
  const releaseReadyAt = match.cooldownEndsAt[releaseByColor] || 0;
  if (nowMs >= releaseReadyAt) {
    clearForfeitLock(match);
  }
}

function isColorBlockedByForfeitLock(match, color) {
  return match.forfeitLock.blockedColor === color;
}

function serializeForfeitLock(lock) {
  if (!lock) {
    return { blockedColor: null, releaseByColor: null };
  }
  return {
    blockedColor: lock.blockedColor ?? null,
    releaseByColor: lock.releaseByColor ?? null,
  };
}

function getTerminalStatus(game) {
  if (isCheckmateForColor(game, 'w')) {
    return { gameOver: true, result: 'black_wins_checkmate' };
  }
  if (isCheckmateForColor(game, 'b')) {
    return { gameOver: true, result: 'white_wins_checkmate' };
  }
  if (game.isDraw()) {
    return { gameOver: true, result: 'draw' };
  }
  return { gameOver: false, result: null };
}

function isCheckmateForColor(game, color) {
  return withColorTurn(game, color, () => game.isCheckmate());
}

function isInCheckForColor(game, color) {
  return withColorTurn(game, color, () => game.isCheck());
}

function hasAnyLegalMoveForColor(game, color) {
  return withColorTurn(game, color, () => game.moves().length > 0);
}

function findValidatedLegalMove({ game, from, to, promotion, color }) {
  return withColorTurn(game, color, () => {
    const legalMoves = game.moves({ verbose: true });
    for (const move of legalMoves) {
      if (move.from !== from || move.to !== to) {
        continue;
      }
      if (!move.promotion) {
        return move;
      }
      if (move.promotion === promotion) {
        return move;
      }
    }
    return null;
  });
}

function withColorTurn(game, color, callback) {
  const previousTurn = game.turn();
  game._turn = color;
  try {
    return callback();
  } finally {
    game._turn = previousTurn;
  }
}

function applyMoveAsColor(game, color, movePayload) {
  const previousTurn = game.turn();
  game._turn = color;
  const moved = game.move(movePayload);
  if (!moved) {
    game._turn = previousTurn;
    return null;
  }
  // Keep the turn value produced by `game.move(...)` so FEN metadata stays valid.
  return moved;
}

function sanitizeName(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed.length < 1 || trimmed.length > 24) {
    return null;
  }
  return trimmed;
}

function sanitizeGameType(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const normalized = value.trim().toLowerCase();
  if (
    normalized.length < 1 ||
    normalized.length > MAX_PIECE_SKIN_ID_LENGTH ||
    !PIECE_SKIN_ID_PATTERN.test(normalized)
  ) {
    return null;
  }
  return normalized;
}

function sanitizeCooldownSeconds(value) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) {
    return null;
  }
  if (parsed < MIN_COOLDOWN_SECONDS || parsed > MAX_COOLDOWN_SECONDS) {
    return null;
  }
  return parsed;
}

function sanitizeSquare(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const text = value.trim().toLowerCase();
  return /^[a-h][1-8]$/.test(text) ? text : null;
}

function sanitizePromotion(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const text = value.trim().toLowerCase();
  return ['q', 'r', 'b', 'n'].includes(text) ? text : null;
}

function sanitizeMoveId(value) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return parsed;
}

function sanitizeSequence(value) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return null;
  }
  return parsed;
}

function sanitizeMoveSource(value) {
  if (value === 'manual' || value === 'queued') {
    return value;
  }
  return 'unknown';
}

function sanitizePieceSkinId(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const normalized = value.trim();
  if (
    normalized.length < 1 ||
    normalized.length > MAX_PIECE_SKIN_ID_LENGTH ||
    !PIECE_SKIN_ID_PATTERN.test(normalized)
  ) {
    return null;
  }
  return normalized;
}

function movePayloadFromLegalMove(move) {
  if (!move || typeof move !== 'object') {
    return null;
  }

  const payload = {
    from: move.from,
    to: move.to,
  };
  if (typeof move.promotion === 'string' && move.promotion.length > 0) {
    payload.promotion = move.promotion;
  }
  return payload;
}

function isExpired(match) {
  if (!MATCH_TIMEOUT_ENABLED) {
    return false;
  }
  return Date.now() - match.updatedAt > MATCH_TTL_MS;
}

function sendJson(socket, payload) {
  socket.send(JSON.stringify(payload));
}

function logEvent(event, data = {}, level = 'info') {
  const entry = {
    id: ++logSequence,
    at: new Date().toISOString(),
    level,
    event,
    ...sanitizeLogData(data),
  };
  serverLogs.push(entry);
  while (serverLogs.length > MAX_SERVER_LOGS) {
    serverLogs.shift();
  }
  if (level === 'error') {
    console.error(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

function sanitizeLogData(data) {
  if (!data || typeof data !== 'object') {
    return {};
  }
  const out = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === undefined) {
      continue;
    }
    if (typeof value === 'function') {
      continue;
    }
    if (value && typeof value === 'object') {
      out[key] = JSON.parse(JSON.stringify(value));
      continue;
    }
    out[key] = value;
  }
  return out;
}
