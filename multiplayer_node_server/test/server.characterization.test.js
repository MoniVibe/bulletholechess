const test = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const WebSocket = require('ws');

const HOST = '127.0.0.1';
const PORT = 18123;
const BASE_URL = `http://${HOST}:${PORT}`;

let serverProcess = null;

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForHealthz(timeoutMs = 10_000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const response = await fetch(`${BASE_URL}/healthz`);
      if (response.ok) {
        return;
      }
    } catch (_error) {
      // Retry until timeout.
    }
    await sleep(100);
  }
  throw new Error('Timed out waiting for server healthz.');
}

function spawnServer() {
  const child = spawn('node', ['server.js'], {
    cwd: __dirname + '/..',
    env: {
      ...process.env,
      BIND: HOST,
      PORT: String(PORT),
      MATCH_TTL_MS: '0',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', () => {});
  child.stderr.on('data', () => {});
  return child;
}

async function createMatch(name, extraBody = {}) {
  const response = await fetch(`${BASE_URL}/api/matches/create`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name, ...extraBody }),
  });
  const json = await response.json();
  return { response, json };
}

async function joinMatch(name, extraBody = {}) {
  const response = await fetch(`${BASE_URL}/api/matches/join`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name, ...extraBody }),
  });
  const json = await response.json();
  return { response, json };
}

function uniqueGameType(prefix) {
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1_000_000)}`;
}

function createWsClient(ws) {
  const queue = [];
  const waiters = [];

  function dispatch() {
    for (let index = 0; index < waiters.length; index += 1) {
      const waiter = waiters[index];
      const messageIndex = queue.findIndex(waiter.predicate);
      if (messageIndex === -1) {
        continue;
      }
      const [matched] = queue.splice(messageIndex, 1);
      waiters.splice(index, 1);
      clearTimeout(waiter.timer);
      waiter.resolve(matched);
      return dispatch();
    }
  }

  ws.on('message', (raw) => {
    let parsed;
    try {
      parsed = JSON.parse(raw.toString('utf8'));
    } catch (_error) {
      return;
    }
    queue.push(parsed);
    dispatch();
  });

  return {
    ws,
    send(payload) {
      ws.send(JSON.stringify(payload));
    },
    close() {
      ws.close();
    },
    waitFor(predicate, timeoutMs = 5_000) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          const index = waiters.findIndex((entry) => entry.resolve === resolve);
          if (index >= 0) {
            waiters.splice(index, 1);
          }
          const queueSummary = queue.map((entry) => entry.type || 'unknown').join(',');
          reject(new Error(`Timed out waiting for WS message. queue=[${queueSummary}]`));
        }, timeoutMs);
        waiters.push({ predicate, resolve, timer });
        dispatch();
      });
    },
  };
}

function connectClient(matchId, playerId) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(
      `ws://${HOST}:${PORT}/ws?matchId=${encodeURIComponent(matchId)}&playerId=${encodeURIComponent(playerId)}`,
    );
    ws.once('open', () => resolve(createWsClient(ws)));
    ws.once('error', reject);
  });
}

test.before(async () => {
  serverProcess = spawnServer();
  await waitForHealthz();
});

test.after(async () => {
  if (!serverProcess) {
    return;
  }
  serverProcess.kill('SIGTERM');
  await new Promise((resolve) => {
    serverProcess.once('exit', () => resolve());
    setTimeout(() => resolve(), 2_000);
  });
});

test('create returns 201 and join returns 200 with unchanged schema', async () => {
  const gameType = uniqueGameType('schema');
  const create = await createMatch('alpha', { gameType });
  assert.equal(create.response.status, 201);
  assert.equal(create.json.color, 'w');
  assert.equal(create.json.wsPath, '/ws');

  const join = await joinMatch('beta', { gameType });
  assert.equal(join.response.status, 200);
  assert.equal(join.json.color, 'b');
  assert.equal(join.json.matchId, create.json.matchId);
  assert.equal(join.json.gameType, gameType);
  assert.equal(typeof join.json.playerId, 'string');
});

test('stale sequence is rejected with stale_state code', async () => {
  const p1 = await createMatch('stale-a');
  const p2 = await joinMatch('stale-b');
  assert.equal(p2.json.matchId, p1.json.matchId);

  const w = await connectClient(p1.json.matchId, p1.json.playerId);
  const b = await connectClient(p2.json.matchId, p2.json.playerId);

  const stateMessage = await w.waitFor(
    (msg) => msg.type === 'state' && Number.isFinite(msg.sequence),
  );

  w.send({
    type: 'move',
    from: 'e2',
    to: 'e4',
    expectedSequence: stateMessage.sequence + 1000,
  });

  const error = await w.waitFor(
    (msg) => msg.type === 'error' && msg.code === 'stale_state',
  );
  assert.equal(error.code, 'stale_state');
  assert.equal(Number.isFinite(error.currentSequence), true);
  assert.equal(error.currentSequence >= stateMessage.sequence, true);

  w.close();
  b.close();
});

test('cooldown rejection is preserved', async () => {
  const p1 = await createMatch('cool-a');
  const p2 = await joinMatch('cool-b');
  assert.equal(p2.json.matchId, p1.json.matchId);

  const w = await connectClient(p1.json.matchId, p1.json.playerId);
  const b = await connectClient(p2.json.matchId, p2.json.playerId);

  await w.waitFor((msg) => msg.type === 'state');

  w.send({ type: 'move', from: 'e2', to: 'e4' });
  await w.waitFor(
    (msg) => msg.type === 'state' && msg.lastMove && msg.lastMove.from === 'e2',
  );

  w.send({ type: 'move', from: 'd2', to: 'd4' });
  const cooldownError = await w.waitFor(
    (msg) => msg.type === 'error' && msg.code === 'cooldown_active',
  );
  assert.equal(cooldownError.code, 'cooldown_active');
  assert.equal(typeof cooldownError.remainingMs, 'number');

  w.close();
  b.close();
});

test('forfeit-lock rejection is preserved', async () => {
  const p1 = await createMatch('forfeit-a');
  const p2 = await joinMatch('forfeit-b');
  assert.equal(p2.json.matchId, p1.json.matchId);

  const w = await connectClient(p1.json.matchId, p1.json.playerId);
  const b = await connectClient(p2.json.matchId, p2.json.playerId);

  await b.waitFor((msg) => msg.type === 'state');

  // Black moving first (out of nominal turn) sets a forfeit lock on white.
  b.send({ type: 'move', from: 'e7', to: 'e5' });
  await b.waitFor(
    (msg) => msg.type === 'state' && msg.lastMove && msg.lastMove.from === 'e7',
  );

  w.send({ type: 'move', from: 'g1', to: 'f3' });
  const forfeitError = await w.waitFor(
    (msg) => msg.type === 'error' && msg.code === 'forfeit_waiting_release',
  );
  assert.equal(forfeitError.code, 'forfeit_waiting_release');
  assert.equal(forfeitError.blockedColor, 'w');
  assert.equal(forfeitError.releaseByColor, 'b');

  w.close();
  b.close();
});
