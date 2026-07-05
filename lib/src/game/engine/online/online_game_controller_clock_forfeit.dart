part of '../online_game_controller.dart';

extension _OnlineGameControllerClockForfeit on OnlineGameController {
  void _applyCooldownForMover(String moverColor, int atMs) {
    final nextReady = atMs + _cooldownDuration.inMilliseconds;
    if (moverColor == 'w') {
      _whiteReadyAtMs = nextReady;
      return;
    }
    _blackReadyAtMs = nextReady;
  }

  void _setReadyAtForColor(String color, int readyAtMs) {
    if (color == 'w') {
      _whiteReadyAtMs = readyAtMs;
      return;
    }
    _blackReadyAtMs = readyAtMs;
  }

  int _estimatedServerNowMs() {
    return _now().millisecondsSinceEpoch + _clockOffsetMs;
  }

  bool _isRetriableQueueError(String? code, String message) {
    if (code == 'cooldown_active' ||
        code == 'forfeit_waiting_release' ||
        code == 'stale_state') {
      return true;
    }
    final lowered = message.toLowerCase();
    return lowered.contains('cooldown') ||
        lowered.contains('forfeit') ||
        lowered.contains('stale');
  }

  /// Whether a server `error` frame pertains to the in-flight move (a move
  /// rejection) rather than an unrelated failure (piece-skin / new_game /
  /// parse / unknown-type). The server sends `type:'error'` for both and does
  /// not echo the clientMoveId on errors, so classification is by the set of
  /// codes/messages the move handler in `websocket.js` emits when rejecting a
  /// move. Move-related errors end the current in-flight attempt; unrelated
  /// ones must leave it untouched so a legitimate move stays tracked.
  static const Set<String> _moveRejectionCodes = <String>{
    'cooldown_active',
    'forfeit_waiting_release',
    'stale_state',
    'waiting_for_opponent',
    'from_square_empty',
    'piece_not_owned',
    'destination_occupied_by_own_piece',
  };

  bool _isMoveRelatedError(String? code, String message) {
    if (code != null && _moveRejectionCodes.contains(code)) {
      return true;
    }
    // Retriable-queue errors are inherently move-related.
    if (_isRetriableQueueError(code, message)) {
      return true;
    }
    // Code-less move rejections the server emits by message only.
    final lowered = message.toLowerCase();
    return lowered.contains('illegal move') ||
        lowered.contains('invalid move') ||
        lowered.contains('no legal moves') ||
        lowered.contains('waiting for opponent') ||
        lowered.contains('game over');
  }

  bool _isBlockedByForfeitLock(String color, {bool resolveTimeout = true}) {
    if (_forfeitBlockedColor != color) {
      return false;
    }
    if (resolveTimeout) {
      _resolveForfeitLockTimeoutIfNeeded();
      if (_forfeitBlockedColor != color) {
        return false;
      }
    }
    return true;
  }

  void _resolveForfeitLockTimeoutIfNeeded() {
    final releaseBy = _forfeitReleaseByColor;
    if (releaseBy == null) {
      return;
    }
    if (cooldownRemaining(releaseBy).inMilliseconds <= 0) {
      _clearForfeitLock();
    }
  }

  void _applyForfeitLockFromPayload(Map<String, dynamic> payload) {
    final rawLock = payload['forfeitLock'];
    if (rawLock is! Map) {
      _clearForfeitLock();
      return;
    }

    final lock = Map<String, dynamic>.from(rawLock);
    final blockedColor = _normalizeColor(lock['blockedColor']);
    final releaseByColor = _normalizeColor(lock['releaseByColor']);
    if (blockedColor == null || releaseByColor == null) {
      _clearForfeitLock();
      return;
    }

    _forfeitBlockedColor = blockedColor;
    _forfeitReleaseByColor = releaseByColor;
  }

  void _clearForfeitLock() {
    _forfeitBlockedColor = null;
    _forfeitReleaseByColor = null;
  }

  String? _normalizeColor(Object? raw) {
    if (raw is! String) {
      return null;
    }
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'w' || normalized == 'b') {
      return normalized;
    }
    return null;
  }
}
