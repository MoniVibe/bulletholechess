# Node Matchmaking + Game Backend

This service provides:
- `POST /api/matches/create` -> create invite code as White
- `POST /api/matches/join` -> join invite code as Black
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
- match TTL `6h`

Env vars:
- `PORT`
- `BIND`
- `MATCH_TTL_MS`

## Docker

```bash
docker build -t bullethole-backend .
docker run --rm -p 8080:8080 bullethole-backend
```
