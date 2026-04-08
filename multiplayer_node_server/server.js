const crypto = require('crypto');
const http = require('http');

const express = require('express');
const cors = require('cors');
const { Chess } = require('chess.js');
const { WebSocketServer } = require('ws');

const constants = require('./src/constants');
const { sendJson } = require('./src/socket-json');
const { createLogger } = require('./src/logging');
const { createSanitizers } = require('./src/sanitization');
const { createChessLogic } = require('./src/chess-logic');
const { createMatchmaking } = require('./src/matchmaking');
const { createRelayMode } = require('./src/relay-mode');
const { createBroadcaster } = require('./src/broadcast');
const { registerRoutes } = require('./src/routes');
const { registerWebSocketHandlers } = require('./src/websocket');

const app = express();
app.use(cors());
app.use(express.json({ limit: '32kb' }));
app.options('*', cors());

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });
const matches = new Map();

const logger = createLogger({
  maxServerLogs: constants.MAX_SERVER_LOGS,
});

const sanitizers = createSanitizers({
  minCooldownSeconds: constants.MIN_COOLDOWN_SECONDS,
  maxCooldownSeconds: constants.MAX_COOLDOWN_SECONDS,
  maxPieceSkinIdLength: constants.MAX_PIECE_SKIN_ID_LENGTH,
  pieceSkinIdPattern: constants.PIECE_SKIN_ID_PATTERN,
});

const chessLogic = createChessLogic({ Chess });

let broadcastStateRef = () => {};
let broadcastToConnectedRef = () => {};

const matchmaking = createMatchmaking({
  crypto,
  Chess,
  matches,
  gameTypeChess: constants.GAME_TYPE_CHESS,
  defaultCooldownSeconds: constants.DEFAULT_COOLDOWN_SECONDS,
  matchTimeoutEnabled: constants.MATCH_TIMEOUT_ENABLED,
  matchTtlMs: constants.MATCH_TTL_MS,
  matchConnectGraceMs: constants.MATCH_CONNECT_GRACE_MS,
  sanitizeCooldownSeconds: sanitizers.sanitizeCooldownSeconds,
  logEvent: logger.logEvent,
  broadcastState: (...args) => broadcastStateRef(...args),
  sendJson,
  resetRelaySession: (match) => {
    match.relayState = null;
    match.relayReady = { w: false, b: false };
    match.relayActionCount = 0;
  },
  clearForfeitLock: chessLogic.clearForfeitLock,
});

const relayMode = createRelayMode({
  relayEventReady: constants.RELAY_EVENT_READY,
  relayEventAction: constants.RELAY_EVENT_ACTION,
  relayEventComplete: constants.RELAY_EVENT_COMPLETE,
  sanitizeRelayEvent: sanitizers.sanitizeRelayEvent,
  sanitizeMoveId: sanitizers.sanitizeMoveId,
  sanitizeCooldownSeconds: sanitizers.sanitizeCooldownSeconds,
  sanitizePieceSkinId: sanitizers.sanitizePieceSkinId,
  bothPlayersConnected: matchmaking.bothPlayersConnected,
  playerForColor: matchmaking.playerForColor,
  logEvent: logger.logEvent,
  sendJson,
  broadcastState: (...args) => broadcastStateRef(...args),
  broadcastToConnected: (...args) => broadcastToConnectedRef(...args),
  clearForfeitLock: chessLogic.clearForfeitLock,
  resetRelaySession: undefined,
});

const broadcaster = createBroadcaster({
  defaultPieceSkinId: constants.DEFAULT_PIECE_SKIN_ID,
  gameTypeChess: constants.GAME_TYPE_CHESS,
  bothPlayersConnected: matchmaking.bothPlayersConnected,
  getTerminalStatus: chessLogic.getTerminalStatus,
  serializeForfeitLock: chessLogic.serializeForfeitLock,
  relayMetaPayload: relayMode.relayMetaPayload,
  sendJson,
});

broadcastStateRef = broadcaster.broadcastState;
broadcastToConnectedRef = broadcaster.broadcastToConnected;

registerRoutes({
  app,
  sanitizeName: sanitizers.sanitizeName,
  sanitizeCooldownSeconds: sanitizers.sanitizeCooldownSeconds,
  sanitizeGameType: sanitizers.sanitizeGameType,
  sanitizePieceSkinId: sanitizers.sanitizePieceSkinId,
  defaultGameType: constants.DEFAULT_GAME_TYPE,
  defaultPieceSkinId: constants.DEFAULT_PIECE_SKIN_ID,
  pruneExpiredMatches: matchmaking.pruneExpiredMatches,
  pruneStaleUnconnectedReservations: matchmaking.pruneStaleUnconnectedReservations,
  assignPlayerToMatch: matchmaking.assignPlayerToMatch,
  queryLogs: logger.queryLogs,
  logEvent: logger.logEvent,
});

registerWebSocketHandlers({
  wss,
  matches,
  gameTypeChess: constants.GAME_TYPE_CHESS,
  defaultPieceSkinId: constants.DEFAULT_PIECE_SKIN_ID,
  sanitizeSquare: sanitizers.sanitizeSquare,
  sanitizePromotion: sanitizers.sanitizePromotion,
  sanitizeMoveId: sanitizers.sanitizeMoveId,
  sanitizeSequence: sanitizers.sanitizeSequence,
  sanitizeMoveSource: sanitizers.sanitizeMoveSource,
  sanitizeCooldownSeconds: sanitizers.sanitizeCooldownSeconds,
  sanitizePieceSkinId: sanitizers.sanitizePieceSkinId,
  playerForColor: matchmaking.playerForColor,
  clearColorSlot: matchmaking.clearColorSlot,
  bothPlayersConnected: matchmaking.bothPlayersConnected,
  isExpired: matchmaking.isExpired,
  cleanupMatch: matchmaking.cleanupMatch,
  broadcastState: broadcaster.broadcastState,
  broadcastToConnected: broadcaster.broadcastToConnected,
  clearForfeitLock: chessLogic.clearForfeitLock,
  setForfeitLock: chessLogic.setForfeitLock,
  setCooldownForMover: chessLogic.setCooldownForMover,
  maybeResolveForfeitLockTimeout: chessLogic.maybeResolveForfeitLockTimeout,
  isColorBlockedByForfeitLock: chessLogic.isColorBlockedByForfeitLock,
  serializeForfeitLock: chessLogic.serializeForfeitLock,
  hasAnyLegalMoveForColor: chessLogic.hasAnyLegalMoveForColor,
  findValidatedLegalMove: chessLogic.findValidatedLegalMove,
  movePayloadFromLegalMove: chessLogic.movePayloadFromLegalMove,
  applyMoveAsColor: chessLogic.applyMoveAsColor,
  getTerminalStatus: chessLogic.getTerminalStatus,
  handleRelaySocketMessage: relayMode.handleRelaySocketMessage,
  resetRelaySession: relayMode.resetRelaySession,
  logEvent: logger.logEvent,
  sendJson,
});

if (constants.MATCH_TIMEOUT_ENABLED) {
  setInterval(() => {
    matchmaking.pruneExpiredMatches();
  }, 30_000).unref();
}

server.listen(constants.PORT, constants.BIND, () => {
  console.log(`Bullethole backend listening on http://${constants.BIND}:${constants.PORT}`);
  logger.logEvent('server_started', { bind: constants.BIND, port: constants.PORT });
});
