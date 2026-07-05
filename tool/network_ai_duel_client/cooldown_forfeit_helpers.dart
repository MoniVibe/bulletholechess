part of '../network_ai_duel_client.dart';

extension _CooldownForfeitHelpers on _ChessNetworkAiSession {
  int _estimatedServerNowMs() {
    return DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;
  }

  int _cooldownRemainingMs(String color) {
    final readyAt = _cooldownEndsAt[color] ?? 0;
    final remaining = readyAt - _estimatedServerNowMs();
    return remaining <= 0 ? 0 : remaining;
  }

  bool _isBlockedByForfeitLock(String color) {
    _resolveForfeitLockTimeoutIfNeeded();
    final lock = _forfeitLock;
    if (lock == null) {
      return false;
    }
    return lock['blockedColor'] == color;
  }

  /// Liveness fallback mirroring the app controller: clear a latched forfeit
  /// lock once the release-by color's cooldown has elapsed. Without this, if the
  /// harness latches a SET lock and never observes a subsequent CLEARED payload
  /// (dropped/misordered frame), `_isBlockedByForfeitLock` would keep the client
  /// blocked indefinitely -- the wedge seen in network-ai-chess-qa-prod-a.
  void _resolveForfeitLockTimeoutIfNeeded() {
    final lock = _forfeitLock;
    if (lock == null) {
      return;
    }
    final releaseBy = lock['releaseByColor'];
    if (releaseBy is! String || (releaseBy != 'w' && releaseBy != 'b')) {
      return;
    }
    if (_cooldownRemainingMs(releaseBy) <= 0) {
      _forfeitLock = null;
    }
  }

  void _updateClockOffset(dynamic serverNowRaw) {
    final serverNow = MultiplayerClientUtils.readInt(serverNowRaw);
    if (serverNow == null) {
      return;
    }
    _clockOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
  }

  void _updateCooldownSnapshot(dynamic raw) {
    final map = _readMap(raw);
    if (map == null) {
      return;
    }
    final w = MultiplayerClientUtils.readInt(map['w']);
    final b = MultiplayerClientUtils.readInt(map['b']);
    if (w != null) {
      _cooldownEndsAt['w'] = w;
    }
    if (b != null) {
      _cooldownEndsAt['b'] = b;
    }
  }

  Map<String, dynamic>? _readMap(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }
}
