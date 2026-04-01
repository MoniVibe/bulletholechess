# Multiplayer Smoke Lab (Two Machines)

Purpose: validate multiplayer transport hygiene with thin AI clients, while
keeping gameplay logic inside each game repo and transport/session logic in
`pureflutter`.

## 1) Clone on each machine (SSH)

```powershell
mkdir C:\dev\lab
cd C:\dev\lab
git clone git@github.com:meshik/bullethole-chess.git
git clone git@github.com:meshik/backholegammon.git
git clone git@github.com:gammula/pureflutter.git
```

Checkout target branch for game repos:

```powershell
cd C:\dev\lab\bullethole-chess
git checkout gameplay-fix
cd C:\dev\lab\backholegammon
git checkout gameplay-fix
```

## 2) Point both apps to local shared package (recommended for smoke)

`C:\dev\lab\bullethole-chess\pubspec_overrides.yaml`

```yaml
dependency_overrides:
  bullethole_shared:
    path: ../pureflutter
```

`C:\dev\lab\backholegammon\pubspec_overrides.yaml`

```yaml
dependency_overrides:
  bullethole_shared:
    path: ../pureflutter
```

Then run:

```powershell
cd C:\dev\lab\bullethole-chess
flutter pub get
cd C:\dev\lab\backholegammon
flutter pub get
```

## 3) Start backend on one machine

```powershell
cd C:\dev\lab\bullethole-chess\multiplayer_node_server
npm install
npm start
```

Backend default: `http://<host-ip>:8080`

## 4) Chess AI-vs-AI (one client per machine)

Machine A:

```powershell
cd C:\dev\lab\bullethole-chess
.\run-network-ai-duel.ps1 -BackendUrl http://<host-ip>:8080 -Name ChessAI-A
```

Machine B:

```powershell
cd C:\dev\lab\bullethole-chess
.\run-network-ai-duel.ps1 -BackendUrl http://<host-ip>:8080 -Name ChessAI-B
```

## 5) Backgammon AI-vs-AI (one client per machine)

Machine A:

```powershell
cd C:\dev\lab\backholegammon
.\run-network-ai-duel.ps1 -BackendUrl http://<host-ip>:8080 -Name BackgammonAI-A -Seed 777
```

Machine B:

```powershell
cd C:\dev\lab\backholegammon
.\run-network-ai-duel.ps1 -BackendUrl http://<host-ip>:8080 -Name BackgammonAI-B -Seed 777
```

## 6) Telemetry and sanity checks

- Client logs: `debug/*.jsonl` in each game repo.
- Backend logs: `GET /debug/logs?limit=200`.
- Quick check: both client logs should contain `move_sent` (chess) or
  `turn_sent` (backgammon) events.
