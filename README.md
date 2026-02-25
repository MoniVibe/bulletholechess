# bulletholechess

Bullethole Chess Flutter app with:
- `Local vs Bot`
- `Online Prototype` (invite code multiplayer)

## App

```bash
flutter pub get
flutter run
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
