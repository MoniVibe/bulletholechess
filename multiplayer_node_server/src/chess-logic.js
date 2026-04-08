function createChessLogic({ Chess }) {
  function setCooldownForMover(match, moverColor, atMs) {
    const nextReady = atMs + match.cooldownMs;
    if (moverColor === 'w') {
      match.cooldownEndsAt.w = nextReady;
      return;
    }
    match.cooldownEndsAt.b = nextReady;
  }

  function setForfeitLock(match, { blockedColor, releaseByColor }) {
    if (!['w', 'b'].includes(blockedColor) || !['w', 'b'].includes(releaseByColor)) {
      return;
    }
    match.forfeitLock.blockedColor = blockedColor;
    match.forfeitLock.releaseByColor = releaseByColor;
  }

  function clearForfeitLock(match) {
    match.forfeitLock.blockedColor = null;
    match.forfeitLock.releaseByColor = null;
  }

  function maybeResolveForfeitLockTimeout(match, nowMs) {
    const releaseByColor = match.forfeitLock.releaseByColor;
    if (!releaseByColor) {
      return;
    }
    const releaseReadyAt = match.cooldownEndsAt[releaseByColor] || 0;
    if (nowMs >= releaseReadyAt) {
      clearForfeitLock(match);
    }
  }

  function isColorBlockedByForfeitLock(match, color) {
    return match.forfeitLock.blockedColor === color;
  }

  function serializeForfeitLock(lock) {
    if (!lock) {
      return { blockedColor: null, releaseByColor: null };
    }
    return {
      blockedColor: lock.blockedColor ?? null,
      releaseByColor: lock.releaseByColor ?? null,
    };
  }

  function getTerminalStatus(game) {
    if (isCheckmateForColor(game, 'w')) {
      return { gameOver: true, result: 'black_wins_checkmate' };
    }
    if (isCheckmateForColor(game, 'b')) {
      return { gameOver: true, result: 'white_wins_checkmate' };
    }
    if (game.isDraw()) {
      return { gameOver: true, result: 'draw' };
    }
    return { gameOver: false, result: null };
  }

  function isCheckmateForColor(game, color) {
    const gameForColor = cloneGameWithTurn(game, color);
    return gameForColor.isCheckmate();
  }

  function isInCheckForColor(game, color) {
    const gameForColor = cloneGameWithTurn(game, color);
    return gameForColor.isCheck();
  }

  function hasAnyLegalMoveForColor(game, color) {
    const gameForColor = cloneGameWithTurn(game, color);
    return gameForColor.moves().length > 0;
  }

  function findValidatedLegalMove({ game, from, to, promotion, color }) {
    const gameForColor = cloneGameWithTurn(game, color);
    const legalMoves = gameForColor.moves({ verbose: true });
    for (const move of legalMoves) {
      if (move.from !== from || move.to !== to) {
        continue;
      }
      if (!move.promotion) {
        return move;
      }
      if (move.promotion === promotion) {
        return move;
      }
    }
    return null;
  }

  function applyMoveAsColor(game, color, movePayload) {
    const gameForColor = cloneGameWithTurn(game, color);
    let moved = null;
    try {
      moved = gameForColor.move(movePayload);
    } catch (_error) {
      return null;
    }
    if (!moved) {
      return null;
    }
    try {
      game.load(gameForColor.fen());
    } catch (_error) {
      return null;
    }
    return moved;
  }

  function cloneGameWithTurn(game, color) {
    const fen = game.fen();
    const parts = fen.split(' ');
    if (parts.length >= 6) {
      const originalTurn = parts[1];
      parts[1] = color;
      if (originalTurn !== color) {
        // If we force-turn to the opposite color, stale en-passant squares can
        // become illegal in chess.js for that turn.
        parts[3] = '-';
      }
    }
    try {
      return new Chess(parts.join(' '));
    } catch (_error) {
      // Last-resort normalization keeps the backend alive for diagnostics runs.
      if (parts.length >= 6) {
        const fallbackFen = [parts[0], parts[1], parts[2], '-', parts[4], parts[5]].join(' ');
        return new Chess(fallbackFen);
      }
      return new Chess(fen);
    }
  }

  function movePayloadFromLegalMove(move) {
    if (!move || typeof move !== 'object') {
      return null;
    }

    const payload = {
      from: move.from,
      to: move.to,
    };
    if (typeof move.promotion === 'string' && move.promotion.length > 0) {
      payload.promotion = move.promotion;
    }
    return payload;
  }

  return {
    setCooldownForMover,
    setForfeitLock,
    clearForfeitLock,
    maybeResolveForfeitLockTimeout,
    isColorBlockedByForfeitLock,
    serializeForfeitLock,
    getTerminalStatus,
    isCheckmateForColor,
    isInCheckForColor,
    hasAnyLegalMoveForColor,
    findValidatedLegalMove,
    applyMoveAsColor,
    cloneGameWithTurn,
    movePayloadFromLegalMove,
  };
}

module.exports = {
  createChessLogic,
};
