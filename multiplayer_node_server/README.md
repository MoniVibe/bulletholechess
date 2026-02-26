# Node Matchmaking + Game Backend

This service provides:
- `POST /api/matches/join` -> auto-join open match or create one
- `POST /api/matches/create` -> alias of join (kept for compatibility)
- `GET /healthz` -> health
- `WS /ws?matchId=...&playerId=...` -> real-time game channel

It runs matchmaking and authoritative move validation in one Node.js process.

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

## Docker

```bash
docker build -t bullethole-backend .
docker run --rm -p 8080:8080 bullethole-backend
```
