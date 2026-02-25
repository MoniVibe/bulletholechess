const crypto = require('crypto');
const http = require('http');

const express = require('express');
const cors = require('cors');
const { Chess } = require('chess.js');
const { WebSocketServer } = require('ws');

const PORT = Number.parseInt(process.env.PORT || '8080', 10);
const BIND = process.env.BIND || '0.0.0.0';
const MATCH_TTL_MS = Number.parseInt(process.env.MATCH_TTL_MS || `${6 * 60 * 60 * 1000}`, 10);

const app = express();
app.use(cors());
app.use(express.json({ limit: '32kb' }));
app.options('*', cors());

const matches = new Map();
const matchByJoinCode = new Map();

app.get('/healthz', (_req, res) => {
  res.json({ ok: true, at: new Date().toISOString() });
});

app.post('/api/matches/create', (req, res) => {
  const name = sanitizeName(req.body?.name);
  if (!name) {
    res.status(400).json({ error: 'Name is required (1-24 chars).' });
    return;
  }

  const matchId = crypto.randomUUID();
  const joinCode = generateJoinCode();
  const playerId = crypto.randomUUID();

  const match = createEmptyMatch({ matchId, joinCode });
  match.players.white = { playerId, name, socket: null };
  match.playersById.set(playerId, 'w');

  matches.set(matchId, match);
  matchByJoinCode.set(joinCode, matchId);

  res.status(201).json({
    matchId,
    joinCode,
    playerId,
    color: 'w',
    wsPath: '/ws',
  });
});

app.post('/api/matches/join', (req, res) => {
  const rawJoinCode = String(req.body?.joinCode || '').trim().toUpperCase();
  const name = sanitizeName(req.body?.name);
  if (!rawJoinCode || !name) {
    res.status(400).json({ error: 'joinCode and name are required.' });
    return;
  }

  const matchId = matchByJoinCode.get(rawJoinCode);
  if (!matchId) {
    res.status(404).json({ error: 'Invite code not found.' });
    return;
  }

  const match = matches.get(matchId);
  if (!match || isExpired(match)) {
    cleanupMatch(matchId);
    res.status(404).json({ error: 'Invite expired.' });
    return;
  }

  if (match.players.black) {
    res.status(409).json({ error: 'Match already full.' });
    return;
  }

  const playerId = crypto.randomUUID();
  match.players.black = { playerId, name, socket: null };
  match.playersById.set(playerId, 'b');
  match.updatedAt = Date.now();

  res.json({
    matchId,
    joinCode: match.joinCode,
    playerId,
    color: 'b',
    wsPath: '/ws',
  });
});

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (socket, req) => {
  const url = new URL(req.url, 'http://localhost');
  const matchId = url.searchParams.get('matchId');
  const playerId = url.searchParams.get('playerId');

  if (!matchId || !playerId) {
    sendJson(socket, { type: 'error', message: 'matchId and playerId are required.' });
    socket.close(1008, 'Missing parameters');
    return;
  }

  const match = matches.get(matchId);
  if (!match || isExpired(match)) {
    cleanupMatch(matchId);
    sendJson(socket, { type: 'error', message: 'Match not found or expired.' });
    socket.close(1008, 'Match unavailable');
    return;
  }

  const color = match.playersById.get(playerId);
  if (!color) {
    sendJson(socket, { type: 'error', message: 'Invalid player session.' });
    socket.close(1008, 'Invalid player');
    return;
  }

  const player = color === 'w' ? match.players.white : match.players.black;
  if (!player) {
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
    joinCode: match.joinCode,
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
    if (player.socket === socket) {
      player.socket = null;
      match.updatedAt = Date.now();
      broadcastToConnected(match, {
        type: 'opponent_left',
        message: 'Your opponent disconnected.',
      });
      broadcastState(match);
    }
  });
});

setInterval(() => {
  const now = Date.now();
  for (const [matchId, match] of matches.entries()) {
    if (now - match.updatedAt > MATCH_TTL_MS) {
      cleanupMatch(matchId);
    }
  }
}, 30_000).unref();

server.listen(PORT, BIND, () => {
  console.log(`Bullethole backend listening on http://${BIND}:${PORT}`);
});

function handleSocketMessage({ match, color, socket, payload }) {
  const type = typeof payload.type === 'string' ? payload.type : '';
  switch (type) {
    case 'move':
      if (!match.players.white || !match.players.black) {
        sendJson(socket, { type: 'error', message: 'Waiting for opponent.' });
        return;
      }
      if (match.game.isGameOver()) {
        sendJson(socket, { type: 'error', message: 'Game over. Start a new game.' });
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
        sendJson(socket, { type: 'error', message: 'Invalid move coordinates.' });
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
      sendJson(socket, { type: 'error', message: `Unknown message type: ${type}` });
  }
}

function createEmptyMatch({ matchId, joinCode }) {
  return {
    matchId,
    joinCode,
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
    joinCode: match.joinCode,
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

function cleanupMatch(matchId) {
  const match = matches.get(matchId);
  if (!match) {
    return;
  }

  for (const p of [match.players.white, match.players.black]) {
    if (p && p.socket && p.socket.readyState === p.socket.OPEN) {
      sendJson(p.socket, { type: 'error', message: 'Match expired.' });
      p.socket.close(1001, 'Match expired');
    }
  }

  matchByJoinCode.delete(match.joinCode);
  matches.delete(matchId);
}

function gameResult(game) {
  if (game.isCheckmate()) {
    return game.turn() === 'w' ? 'black_wins_checkmate' : 'white_wins_checkmate';
  }
  if (game.isDraw()) {
    return 'draw';
  }
  return 'game_over';
}

function generateJoinCode() {
  for (let attempts = 0; attempts < 20; attempts += 1) {
    const code = crypto.randomInt(0, 36 ** 6).toString(36).toUpperCase().padStart(6, '0');
    if (!matchByJoinCode.has(code)) {
      return code;
    }
  }

  return crypto.randomUUID().slice(0, 6).toUpperCase();
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
  return Date.now() - match.updatedAt > MATCH_TTL_MS;
}

function sendJson(socket, payload) {
  socket.send(JSON.stringify(payload));
}
