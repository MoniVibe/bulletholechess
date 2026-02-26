const crypto = require('crypto');
const http = require('http');

const express = require('express');
const cors = require('cors');
const { Chess } = require('chess.js');
const { WebSocketServer } = require('ws');

const PORT = Number.parseInt(process.env.PORT || '8080', 10);
const BIND = process.env.BIND || '0.0.0.0';
const MATCH_TTL_MS = Number.parseInt(process.env.MATCH_TTL_MS || '0', 10);
const MATCH_TIMEOUT_ENABLED =
  Number.isFinite(MATCH_TTL_MS) && MATCH_TTL_MS > 0;

const app = express();
app.use(cors());
app.use(express.json({ limit: '32kb' }));
app.options('*', cors());

const matches = new Map();

app.get('/healthz', (_req, res) => {
  res.json({ ok: true, at: new Date().toISOString() });
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
    sendJson(socket, {
      type: 'error',
      message: 'matchId and playerId are required.',
    });
    socket.close(1008, 'Missing parameters');
    return;
  }

  const match = matches.get(matchId);
  if (!match || isExpired(match)) {
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
    sendJson(socket, { type: 'error', message: 'Invalid player session.' });
    socket.close(1008, 'Invalid player');
    return;
  }

  const player = playerForColor(match, color);
  if (!player || player.playerId !== playerId) {
    sendJson(socket, { type: 'error', message: 'Player slot unavailable.' });
    socket.close(1008, 'Player unavailable');
    return;
  }

  if (player.socket && player.socket.readyState === player.socket.OPEN) {
    player.socket.close(1000, 'Replaced by new connection');
  }

  player.socket = socket;
  match.updatedAt = Date.now();

  sendJson(socket, {
    type: 'welcome',
    matchId,
    playerId,
    color,
  });
  broadcastState(match);

  socket.on('message', (raw) => {
    let payload;
    try {
      payload = JSON.parse(raw.toString('utf8'));
    } catch (_error) {
      sendJson(socket, { type: 'error', message: 'Invalid JSON payload.' });
      return;
    }

    if (!payload || typeof payload !== 'object') {
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
    match.game = new Chess();
    match.updatedAt = Date.now();

    if (!match.players.white && !match.players.black) {
      cleanupMatch(matchId);
      return;
    }

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
});

function joinOrCreate(req, res) {
  const name = sanitizeName(req.body?.name);
  if (!name) {
    res.status(400).json({ error: 'Name is required (1-24 chars).' });
    return;
  }

  pruneExpiredMatches();
  const assignment = assignPlayerToMatch(name);
  const status = assignment.created ? 201 : 200;
  res.status(status).json({
    matchId: assignment.match.matchId,
    playerId: assignment.playerId,
    color: assignment.color,
    wsPath: '/ws',
  });
}

function assignPlayerToMatch(name) {
  const waitingMatch = findJoinableMatch();
  if (waitingMatch) {
    const color = openColorForMatch(waitingMatch);
    const playerId = crypto.randomUUID();
    const player = { playerId, name, socket: null };
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

  const matchId = crypto.randomUUID();
  const playerId = crypto.randomUUID();
  const match = createEmptyMatch({ matchId });
  match.players.white = { playerId, name, socket: null };
  match.playersById.set(playerId, 'w');
  matches.set(matchId, match);
  return {
    match,
    playerId,
    color: 'w',
    created: true,
  };
}

function findJoinableMatch() {
  let candidate = null;
  for (const match of matches.values()) {
    if (isExpired(match)) {
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
  const type = typeof payload.type === 'string' ? payload.type : '';
  switch (type) {
    case 'move':
      if (!match.players.white || !match.players.black) {
        sendJson(socket, { type: 'error', message: 'Waiting for opponent.' });
        return;
      }
      if (match.game.isGameOver()) {
        sendJson(socket, {
          type: 'error',
          message: 'Game over. Start a new game.',
        });
        return;
      }
      if (match.game.turn() !== color) {
        sendJson(socket, { type: 'error', message: 'Not your turn.' });
        return;
      }

      const from = sanitizeSquare(payload.from);
      const to = sanitizeSquare(payload.to);
      const promotion = sanitizePromotion(payload.promotion);
      if (!from || !to) {
        sendJson(socket, {
          type: 'error',
          message: 'Invalid move coordinates.',
        });
        return;
      }

      const moved = match.game.move({ from, to, promotion });
      if (!moved) {
        sendJson(socket, { type: 'error', message: 'Illegal move.' });
        return;
      }

      match.updatedAt = Date.now();
      broadcastState(match, {
        from,
        to,
        promotion,
      });
      return;
    case 'new_game':
      match.game = new Chess();
      match.updatedAt = Date.now();
      broadcastState(match);
      return;
    case 'ping':
      sendJson(socket, { type: 'pong', at: new Date().toISOString() });
      return;
    default:
      sendJson(socket, {
        type: 'error',
        message: `Unknown message type: ${type}`,
      });
  }
}

function createEmptyMatch({ matchId }) {
  return {
    matchId,
    players: {
      white: null,
      black: null,
    },
    playersById: new Map(),
    game: new Chess(),
    sequence: 0,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
}

function broadcastState(match, lastMove = null) {
  match.sequence += 1;
  const payload = {
    type: 'state',
    sequence: match.sequence,
    matchId: match.matchId,
    status: match.players.white && match.players.black ? 'active' : 'waiting',
    fen: match.game.fen(),
    turn: match.game.turn(),
    history: match.game.history(),
    players: {
      w: match.players.white ? match.players.white.name : null,
      b: match.players.black ? match.players.black.name : null,
    },
  };

  if (lastMove) {
    payload.lastMove = lastMove;
  }
  if (match.game.isGameOver()) {
    payload.result = gameResult(match.game);
  }

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

function gameResult(game) {
  if (game.isCheckmate()) {
    return game.turn() === 'w'
      ? 'black_wins_checkmate'
      : 'white_wins_checkmate';
  }
  if (game.isDraw()) {
    return 'draw';
  }
  return 'game_over';
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

function sanitizeSquare(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const text = value.trim().toLowerCase();
  return /^[a-h][1-8]$/.test(text) ? text : null;
}

function sanitizePromotion(value) {
  if (typeof value !== 'string') {
    return 'q';
  }
  const text = value.trim().toLowerCase();
  return ['q', 'r', 'b', 'n'].includes(text) ? text : 'q';
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
