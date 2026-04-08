part of '../online_game_controller.dart';

extension _OnlineGameControllerDebug on OnlineGameController {
  Future<int> _pullServerDebugLogsImpl({
    required String apiBaseUrl,
    required int limit,
  }) async {
    final normalizedLimit = limit.clamp(1, 500);
    _logEvent(
      'server_logs_pull_start',
      details: <String, Object?>{
        'apiBase': apiBaseUrl.trim(),
        'limit': normalizedLimit,
        'matchId': _matchId,
      },
    );

    try {
      final items = await _transportClient.fetchServerDebugLogs(
        apiBaseUrl: apiBaseUrl,
        matchId: _matchId,
        limit: normalizedLimit,
      );
      var appended = 0;
      for (final map in items) {
        _appendServerLogLine(map);
        appended += 1;
      }

      _logEvent(
        'server_logs_pull_success',
        details: <String, Object?>{'appended': appended},
      );
      notifyListeners();
      return appended;
    } catch (error) {
      _logEvent(
        'server_logs_pull_failed',
        details: <String, Object?>{'error': error.toString()},
      );
      notifyListeners();
      return 0;
    }
  }

  void _logEvent(
    String event, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final ts = _now().toIso8601String();
    final detailText = details.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    final line = detailText.isEmpty
        ? '[$ts] $event'
        : '[$ts] $event | $detailText';
    _debugLogEntries.add(line);
    while (_debugLogEntries.length > OnlineGameController._maxDebugLogEntries) {
      _debugLogEntries.removeAt(0);
    }
    if (kDebugMode) {
      debugPrint('[online] $line');
    }
    _sessionLogger.logEvent(event, data: details);
  }

  void _appendServerLogLine(Map<String, dynamic> entry) {
    final at = entry['at']?.toString() ?? '-';
    final event = entry['event']?.toString() ?? 'unknown';
    final level = entry['level']?.toString() ?? 'info';
    final excluded = <String>{'id', 'at', 'event', 'level'};
    final details = entry.entries
        .where((e) => !excluded.contains(e.key) && e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    final line = details.isEmpty
        ? '[server $at] $event | level=$level'
        : '[server $at] $event | level=$level, $details';
    _debugLogEntries.add(line);
    while (_debugLogEntries.length > OnlineGameController._maxDebugLogEntries) {
      _debugLogEntries.removeAt(0);
    }
    if (kDebugMode) {
      debugPrint('[online] $line');
    }
  }
}

String _friendlyNetworkError(Object error, {required String fallback}) {
  if (error is MultiplayerTransportException) {
    return error.message;
  }
  if (error is SocketException) {
    return 'Cannot reach backend (connection refused). Server may be unavailable.';
  }

  final raw = error.toString().toLowerCase();
  if (raw.contains('connection refused')) {
    return 'Cannot reach backend (connection refused). Server may be unavailable.';
  }
  if (raw.contains('failed host lookup')) {
    return 'Backend host lookup failed.';
  }
  return fallback;
}
