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
const RELAY_EVENT_READY = 'ready';
const RELAY_EVENT_ACTION = 'action';
const RELAY_EVENT_COMPLETE = 'complete';
const MAX_PIECE_SKIN_ID_LENGTH = 40;
const PIECE_SKIN_ID_PATTERN = /^[a-z0-9_-]+$/;
const MATCH_TTL_MS = Number.parseInt(process.env.MATCH_TTL_MS || '0', 10);
const MATCH_TIMEOUT_ENABLED =
  Number.isFinite(MATCH_TTL_MS) && MATCH_TTL_MS > 0;
const MATCH_CONNECT_GRACE_MS = Number.parseInt(
  process.env.MATCH_CONNECT_GRACE_MS || '15000',
  10,
);
const MAX_SERVER_LOGS = Number.parseInt(process.env.MAX_SERVER_LOGS || '500', 10);

module.exports = {
  PORT,
  BIND,
  DEFAULT_COOLDOWN_SECONDS,
  MIN_COOLDOWN_SECONDS,
  MAX_COOLDOWN_SECONDS,
  DEFAULT_PIECE_SKIN_ID,
  DEFAULT_GAME_TYPE,
  GAME_TYPE_CHESS,
  RELAY_EVENT_READY,
  RELAY_EVENT_ACTION,
  RELAY_EVENT_COMPLETE,
  MAX_PIECE_SKIN_ID_LENGTH,
  PIECE_SKIN_ID_PATTERN,
  MATCH_TTL_MS,
  MATCH_TIMEOUT_ENABLED,
  MATCH_CONNECT_GRACE_MS,
  MAX_SERVER_LOGS,
};
