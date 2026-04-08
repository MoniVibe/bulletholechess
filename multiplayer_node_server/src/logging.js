function createLogger({ maxServerLogs }) {
  const serverLogs = [];
  let logSequence = 0;

  function logEvent(event, data = {}, level = 'info') {
    const entry = {
      id: ++logSequence,
      at: new Date().toISOString(),
      level,
      event,
      ...sanitizeLogData(data),
    };
    serverLogs.push(entry);
    while (serverLogs.length > maxServerLogs) {
      serverLogs.shift();
    }
    if (level === 'error') {
      console.error(JSON.stringify(entry));
    } else {
      console.log(JSON.stringify(entry));
    }
  }

  function sanitizeLogData(data) {
    if (!data || typeof data !== 'object') {
      return {};
    }
    const out = {};
    for (const [key, value] of Object.entries(data)) {
      if (value === undefined) {
        continue;
      }
      if (typeof value === 'function') {
        continue;
      }
      if (value && typeof value === 'object') {
        out[key] = JSON.parse(JSON.stringify(value));
        continue;
      }
      out[key] = value;
    }
    return out;
  }

  function queryLogs({ limitRaw, matchIdFilter, eventFilter, levelFilter }) {
    const limit = Number.isFinite(limitRaw)
      ? Math.min(Math.max(limitRaw, 1), 1000)
      : 100;

    let items = [...serverLogs];
    if (matchIdFilter) {
      items = items.filter((entry) => entry.matchId === matchIdFilter);
    }
    if (eventFilter) {
      items = items.filter((entry) => entry.event === eventFilter);
    }
    if (levelFilter) {
      items = items.filter((entry) => entry.level === levelFilter);
    }

    const sliced = items.slice(-limit);
    return {
      count: serverLogs.length,
      returned: sliced.length,
      items: sliced,
    };
  }

  return {
    logEvent,
    queryLogs,
  };
}

module.exports = {
  createLogger,
};
