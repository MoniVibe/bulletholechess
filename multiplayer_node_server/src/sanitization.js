function createSanitizers({
  minCooldownSeconds,
  maxCooldownSeconds,
  maxPieceSkinIdLength,
  pieceSkinIdPattern,
}) {
  function sanitizeName(value) {
    if (typeof value !== 'string') {
      return null;
    }
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 24) {
      return null;
    }
    return trimmed;
  }

  function sanitizeGameType(value) {
    if (typeof value !== 'string') {
      return null;
    }
    const normalized = value.trim().toLowerCase();
    if (
      normalized.length < 1 ||
      normalized.length > maxPieceSkinIdLength ||
      !pieceSkinIdPattern.test(normalized)
    ) {
      return null;
    }
    return normalized;
  }

  function sanitizeRelayEvent(value) {
    return sanitizeGameType(value);
  }

  function sanitizeCooldownSeconds(value) {
    const parsed = Number.parseInt(String(value ?? ''), 10);
    if (!Number.isFinite(parsed)) {
      return null;
    }
    if (parsed < minCooldownSeconds || parsed > maxCooldownSeconds) {
      return null;
    }
    return parsed;
  }

  function sanitizeSquare(value) {
    if (typeof value !== 'string') {
      return null;
    }
    const text = value.trim().toLowerCase();
    return /^[a-h][1-8]$/.test(text) ? text : null;
  }

  function sanitizePromotion(value) {
    if (typeof value !== 'string') {
      return null;
    }
    const text = value.trim().toLowerCase();
    return ['q', 'r', 'b', 'n'].includes(text) ? text : null;
  }

  function sanitizeMoveId(value) {
    const parsed = Number.parseInt(String(value ?? ''), 10);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  function sanitizeSequence(value) {
    const parsed = Number.parseInt(String(value ?? ''), 10);
    if (!Number.isFinite(parsed) || parsed < 0) {
      return null;
    }
    return parsed;
  }

  function sanitizeMoveSource(value) {
    if (value === 'manual' || value === 'queued') {
      return value;
    }
    return 'unknown';
  }

  function sanitizePieceSkinId(value) {
    if (typeof value !== 'string') {
      return null;
    }
    const normalized = value.trim();
    if (
      normalized.length < 1 ||
      normalized.length > maxPieceSkinIdLength ||
      !pieceSkinIdPattern.test(normalized)
    ) {
      return null;
    }
    return normalized;
  }

  return {
    sanitizeName,
    sanitizeGameType,
    sanitizeRelayEvent,
    sanitizeCooldownSeconds,
    sanitizeSquare,
    sanitizePromotion,
    sanitizeMoveId,
    sanitizeSequence,
    sanitizeMoveSource,
    sanitizePieceSkinId,
  };
}

module.exports = {
  createSanitizers,
};
