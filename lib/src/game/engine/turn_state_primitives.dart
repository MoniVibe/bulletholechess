/// Shared turn-state primitives used by local controller variants.
///
/// Invariants:
/// - Colors are always standard `'w'` or `'b'`.
/// - Cooldown timestamps are expressed as Unix epoch milliseconds.
/// - Queued move state is atomic: either all move fields are set, or none.
class TurnCooldownTracker {
  TurnCooldownTracker({required int Function() nowMsProvider})
    : _nowMs = nowMsProvider;

  final int Function() _nowMs;
  int _whiteReadyAtMs = 0;
  int _blackReadyAtMs = 0;

  void resetReadyNow() {
    final now = _nowMs();
    _whiteReadyAtMs = now;
    _blackReadyAtMs = now;
  }

  void startCooldown({
    required String color,
    required Duration cooldownDuration,
  }) {
    final readyAt = _nowMs() + cooldownDuration.inMilliseconds;
    setReadyAt(color: color, readyAtMs: readyAt);
  }

  void setReadyAt({required String color, required int readyAtMs}) {
    if (color == 'w') {
      _whiteReadyAtMs = readyAtMs;
      return;
    }
    _blackReadyAtMs = readyAtMs;
  }

  Duration remaining(String color) {
    final readyAt = color == 'w' ? _whiteReadyAtMs : _blackReadyAtMs;
    final remainingMs = readyAt - _nowMs();
    if (remainingMs <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: remainingMs);
  }
}

class QueuedMoveState {
  QueuedMoveState({required this.defaultPromotion});

  final String defaultPromotion;
  QueuedMove? _queuedMove;

  bool get hasMove => _queuedMove != null;
  String? get from => _queuedMove?.from;
  String? get to => _queuedMove?.to;
  String get promotion => _queuedMove?.promotion ?? defaultPromotion;
  String? get label =>
      hasMove ? '${_queuedMove!.from}-${_queuedMove!.to}' : null;

  void queue({
    required String from,
    required String to,
    required String promotion,
  }) {
    _queuedMove = QueuedMove(from: from, to: to, promotion: promotion);
  }

  QueuedMove? clear() {
    final previous = _queuedMove;
    _queuedMove = null;
    return previous;
  }
}

class QueuedMove {
  const QueuedMove({
    required this.from,
    required this.to,
    required this.promotion,
  });

  final String from;
  final String to;
  final String promotion;
}

class ForfeitLockState {
  String? _blockedColor;
  String? _releaseByColor;

  String? get blockedColor => _blockedColor;
  String? get releaseByColor => _releaseByColor;

  void clear() {
    _blockedColor = null;
    _releaseByColor = null;
  }

  void updateAfterMove({
    required String moverColor,
    required String nominalTurnColor,
  }) {
    if (_blockedColor == nominalTurnColor && _releaseByColor == moverColor) {
      clear();
      return;
    }
    if (moverColor != nominalTurnColor) {
      _blockedColor = nominalTurnColor;
      _releaseByColor = moverColor;
      return;
    }
    if (_releaseByColor == moverColor && _blockedColor != null) {
      clear();
    }
  }

  bool isBlocked(
    String color, {
    bool resolveTimeout = true,
    required Duration Function(String color) cooldownRemaining,
  }) {
    if (_blockedColor != color) {
      return false;
    }
    if (resolveTimeout) {
      resolveTimeoutIfNeeded(cooldownRemaining: cooldownRemaining);
      if (_blockedColor != color) {
        return false;
      }
    }
    return true;
  }

  void resolveTimeoutIfNeeded({
    required Duration Function(String color) cooldownRemaining,
  }) {
    final releaseBy = _releaseByColor;
    if (releaseBy == null) {
      return;
    }
    if (cooldownRemaining(releaseBy).inMilliseconds <= 0) {
      clear();
    }
  }
}
