# bulletholechess

Bullethole Chess Flutter app with:
- `Local vs Bot`
- `Online Prototype` (invite code multiplayer)

## App

```bash
flutter pub get
flutter run
```

### Windows quick launch (double-click)

- Double-click `launch-dev.cmd` from the repo root.
- It opens:
  - backend (`multiplayer_node_server`, `npm start`)
  - app (`flutter run -d windows` with `DEFAULT_BACKEND_URL=http://localhost:8080`)

Optional CLI usage:

```powershell
.\launch-dev.ps1
.\launch-dev.ps1 -Device chrome
.\launch-dev.ps1 -BackendUrl https://your-backend.example.com -SkipBackend
.\launch-dev.ps1 -DryRun
```

## Seamless Cross-Continent Multiplayer (Prototype)

Use the Node backend in `multiplayer_node_server/` and deploy it to one public HTTPS URL.

### 1) Run backend locally

```bash
cd multiplayer_node_server
npm install
npm start
```

### 2) Play from app

In `Online Prototype` mode:
- set `Backend URL` (example: `https://your-backend.example.com`)
- host clicks `Create Invite`
- share invite code
- friend enters same `Backend URL` + code and clicks `Join Invite`

No port forwarding or custom peer-to-peer networking is needed.

## Azure Prototype Deployment (Container Apps)

1. Build and push container (ACR):
```bash
az acr create -n <acrName> -g <rg> --sku Basic
az acr build -r <acrName> -t bullethole-backend:latest multiplayer_node_server
```

2. Create Container App environment and app:
```bash
az containerapp env create -n <envName> -g <rg> -l <region>
az containerapp create -n bullethole-backend -g <rg> \
  --environment <envName> \
  --image <acrName>.azurecr.io/bullethole-backend:latest \
  --target-port 8080 --ingress external --query properties.configuration.ingress.fqdn
```

3. Use the returned FQDN in the app as:
- `Backend URL`: `https://<fqdn>`

Container Apps handles TLS; the app upgrades automatically to `wss://` for game socket.

## Azure CI/CD (Current Setup)

This repo uses two GitHub Actions workflows:

- `.github/workflows/azure-static-web-apps-brave-pond-03a16080f.yml`
  - builds Flutter web (`flutter build web --release`)
  - deploys `build/web` to Azure Static Web Apps
  - triggers only when frontend files change
- `.github/workflows/matchmaker-AutoDeployTrigger-ec9e000a-64af-40bb-850c-f7a973ad71e1.yml`
  - deploys `multiplayer_node_server/` source to Azure Container Apps
  - enforces single-instance scaling by default (`min=0`, `max=1`)
  - triggers only when backend files change

### Required GitHub repository secrets

- `AZURE_STATIC_WEB_APPS_API_TOKEN_BRAVE_POND_03A16080F`
- `MATCHMAKER_AZURE_CLIENT_ID`
- `MATCHMAKER_AZURE_TENANT_ID`
- `MATCHMAKER_AZURE_SUBSCRIPTION_ID`

### Optional GitHub repository variables

- `DEFAULT_BACKEND_URL`
  - Example: `https://matchmaker.<region>.azurecontainerapps.io`
  - Used at web build time so the app defaults to your deployed backend instead of localhost.
- `MATCHMAKER_MIN_REPLICAS`
  - Default: `0` (cheapest, allows scale-to-zero)
- `MATCHMAKER_MAX_REPLICAS`
  - Default: `1` (important for current in-memory match state)
- `MATCH_TTL_MS`
  - Optional backend env var for auto-expiring inactive matches

## Why this is seamless

- one hosted URL for both matchmaking and gameplay
- invite code flow, no manual room naming needed
- authoritative backend validates legal moves
- works globally anywhere both clients can reach HTTPS

## Production notes

This prototype is intentionally in-memory and single-instance.
For production scale and reliability you should add:
- Redis for match/session storage and pub/sub fanout
- stateless app replicas behind a load balancer
- auth/token-based player sessions
- reconnection + resume logic
- metrics/rate limits/abuse controls

`Node.js for matchmaking` is a good choice, but not mandatory. It is a practical fit due to mature WebSocket ecosystem, I/O performance, and easy horizontal scaling with Redis.
