function registerRoutes({
  app,
  sanitizeName,
  sanitizeCooldownSeconds,
  sanitizeGameType,
  sanitizePieceSkinId,
  defaultGameType,
  defaultPieceSkinId,
  pruneExpiredMatches,
  pruneStaleUnconnectedReservations,
  assignPlayerToMatch,
  queryLogs,
  logEvent,
}) {
  app.get('/healthz', (_req, res) => {
    res.json({ ok: true, at: new Date().toISOString() });
  });

  app.get('/debug/logs', (req, res) => {
    const limitRaw = Number.parseInt(String(req.query.limit ?? '100'), 10);
    const matchIdFilter =
      typeof req.query.matchId === 'string' ? req.query.matchId.trim() : '';
    const eventFilter =
      typeof req.query.event === 'string' ? req.query.event.trim() : '';
    const levelFilter =
      typeof req.query.level === 'string' ? req.query.level.trim() : '';

    res.json(
      queryLogs({
        limitRaw,
        matchIdFilter,
        eventFilter,
        levelFilter,
      }),
    );
  });

  app.post('/api/matches/create', (req, res) => {
    joinOrCreate(req, res);
  });

  app.post('/api/matches/join', (req, res) => {
    joinOrCreate(req, res);
  });

  function joinOrCreate(req, res) {
    const name = sanitizeName(req.body?.name);
    if (!name) {
      res.status(400).json({ error: 'Name is required (1-24 chars).' });
      return;
    }

    const requestedCooldownSeconds = sanitizeCooldownSeconds(
      req.body?.cooldownSeconds,
    );
    const gameType = sanitizeGameType(req.body?.gameType) ?? defaultGameType;
    const requestedPieceSkinId =
      sanitizePieceSkinId(req.body?.pieceSkinId) ?? defaultPieceSkinId;

    pruneExpiredMatches();
    pruneStaleUnconnectedReservations();
    const assignment = assignPlayerToMatch(
      name,
      gameType,
      requestedCooldownSeconds,
      requestedPieceSkinId,
    );
    logEvent('match_join_or_create', {
      matchId: assignment.match.matchId,
      playerId: assignment.playerId,
      color: assignment.color,
      created: assignment.created,
      gameType: assignment.match.gameType,
      cooldownSeconds: Math.round(assignment.match.cooldownMs / 1000),
      pieceSkinId: requestedPieceSkinId,
      playerName: name,
    });
    const status = assignment.created ? 201 : 200;
    res.status(status).json({
      matchId: assignment.match.matchId,
      playerId: assignment.playerId,
      color: assignment.color,
      gameType: assignment.match.gameType,
      wsPath: '/ws',
      cooldownSeconds: Math.round(assignment.match.cooldownMs / 1000),
      pieceSkinId: requestedPieceSkinId,
    });
  }
}

module.exports = {
  registerRoutes,
};
