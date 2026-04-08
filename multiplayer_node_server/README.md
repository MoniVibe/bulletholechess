# Node Matchmaking + Game Backend

This service provides:
- `POST /api/matches/join` -> auto-join open match or create one
- `POST /api/matches/create` -> alias of join (kept for compatibility)
- `GET /healthz` -> health
- `GET /debug/logs` -> structured in-memory server event log
- `WS /ws?matchId=...&playerId=...` -> real-time game channel

`GET /debug/logs` query params:
- `limit` (default `100`, max `1000`)
- `matchId` (optional filter)
- `event` (optional filter)
- `level` (optional filter)

`POST /api/matches/join` and `POST /api/matches/create` accept:
- `name` (required)
- `cooldownSeconds` (optional, only used when creating a new waiting match)
- `pieceSkinId` (optional, defaults to `chess_classic`)

It runs matchmaking and authoritative move validation in one Node.js process.

## Server Architecture

`server.js` is now the composition root only. It wires dependencies and starts HTTP/WS listeners.

Core modules under `src/`:
- `constants.js`: environment-driven runtime constants.
- `logging.js`: bounded in-memory structured logs + debug query filtering.
- `sanitization.js`: payload and input sanitizers/validators.
- `chess-logic.js`: chess move validation/application, cooldown, and forfeit-lock primitives.
- `matchmaking.js`: match create/join assignment, stale reservation pruning, and TTL lifecycle cleanup.
- `relay-mode.js`: non-chess relay protocol handling (`ready` / `action` / `complete`).
- `broadcast.js`: state/opponent event fan-out to connected sockets.
- `routes.js`: HTTP routes (`/healthz`, `/debug/logs`, `/api/matches/create`, `/api/matches/join`).
- `websocket.js`: connection/session checks and WS message dispatch.
- `socket-json.js`: JSON send helper used across WS paths.

## Relay Protocol (Non-Chess gameType)

For `gameType` values other than `chess` (for example `backgammon`), the
backend uses a relay lane with minimal authoritative checks:

- Client submit: `{ "type": "relay", "event": "...", "payload": { ... } }`
- Server ack: `{ "type": "relay_ack", "sequence": N, "event": "...", ... }`
- Server reject: `{ "type": "error", "code": "relay_*", "message": "..." }`
- Broadcast state includes:
  - `relayState` (last accepted relay envelope)
  - `relayMeta.readyW`, `relayMeta.readyB`, `relayMeta.actionCount`

Supported relay events for bughunt v1.1:

- `ready`
- `action` (requires payload: `kind`, `actionId`, `actorColor`)
- `complete` (requires non-empty `result`)

## Run locally

```bash
npm install
npm start
```

Defaults:
- bind `0.0.0.0`
- port `8080`
- match TTL disabled (`0`)

Env vars:
- `PORT`
- `BIND`
- `MATCH_TTL_MS` (`>0` enables expiry cleanup)
- `DEFAULT_COOLDOWN_SECONDS` (default `3`)
- `MATCH_CONNECT_GRACE_MS` (default `15000`; stale unconnected reservations are pruned)
- `MAX_SERVER_LOGS` (default `500`)

Match status notes:
- `waiting`: either seat missing or opponent not currently connected over WebSocket
- `active`: both players are connected

## Docker

```bash
docker build -t bullethole-backend .
docker run --rm -p 8080:8080 bullethole-backend
```
