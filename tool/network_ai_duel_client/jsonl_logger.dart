part of '../network_ai_duel_client.dart';

class _JsonlLogger {
  _JsonlLogger({
    required this.path,
    required this.runId,
    required BughuntRole role,
    required this.seed,
  }) : _file = File(path),
       _sessionId = 'net_${_timestamp()}_$pid',
       _role = role {
    final parent = _file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
  }

  final String path;
  final String runId;
  final BughuntRole _role;
  final int seed;
  final File _file;
  final String _sessionId;
  final BughuntStateHasher _stateHasher = const BughuntStateHasher();
  Future<void> _pending = Future<void>.value();
  int _logicalTick = 0;

  Future<void> log(Map<String, Object?> event) async {
    _logicalTick += 1;
    final rawEventType = event['event']?.toString() ?? 'state_snapshot';
    final mappedEventType = _eventType(rawEventType);
    final sequence = MultiplayerClientUtils.readInt(event['sequence']) ?? 0;
    final historyLen =
        MultiplayerClientUtils.readInt(event['historyLen']) ?? sequence;
    final payload = <String, Object?>{...event};
    if (mappedEventType == 'state_snapshot') {
      final hashInput = <String, Object?>{
        'matchId': payload['matchId'],
        'sequence': payload['sequence'],
        'status': payload['status'],
        'result': payload['result'],
        'turn': payload['turn'],
        'fen': payload['fen'],
      };
      final hash = _stateHasher.hashSnapshot(hashInput);
      payload['stateHash'] = hash.value;
      payload['stateHashAlgorithm'] = hash.algorithm;
      payload['snapshotHashValid'] = true;
    }
    final severity = _severityForEvent(rawEventType);
    final sessionEvent = SessionEvent(
      schemaVersion: bughuntSchemaVersion,
      runId: runId,
      sessionId: _sessionId,
      game: 'chess',
      mode: BughuntMode.online,
      role: _role,
      appVersionOrCommitSha: Platform.environment['BULLETHOLE_COMMIT_SHA'],
      roomIdOrMatchId: event['matchId']?.toString(),
      seed: seed,
      maxTurns: null,
      deviceInfo: <String, Object?>{
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'pid': pid,
      },
      logicalTick: _logicalTick,
      wallClockTs: DateTime.now().toUtc().toIso8601String(),
      turnIndex: (historyLen ~/ 2) + 1,
      actionIndexOrPlyIndex: historyLen,
      eventType: mappedEventType,
      payload: payload,
      severity: severity,
    );
    final line = sessionEventToJsonLine(sessionEvent);
    _pending = _pending.then((_) async {
      try {
        await _file.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (_) {
        // Telemetry write failures should not crash the duel client.
      }
    });
    await _pending;
  }

  Future<void> close() async {
    await _pending;
  }

  String _eventType(String eventType) {
    final normalized = eventType.toLowerCase();
    if (normalized.contains('start')) {
      return 'app_start';
    }
    if (normalized == 'match_joined' || normalized == 'welcome') {
      return 'session_joined';
    }
    if (normalized.contains('move_sent')) {
      return 'action_launched';
    }
    if (normalized.contains('move_acked')) {
      return 'action_applied';
    }
    if (normalized.contains('action_rejected') ||
        normalized.contains('move_rejected') ||
        normalized.contains('rejected')) {
      return 'action_rejected';
    }
    if (normalized.contains('server_error') || normalized.contains('fatal')) {
      return 'invariant_failure';
    }
    if (normalized == 'game_over') {
      return 'session_complete';
    }
    if (normalized == 'opponent_left') {
      return 'disconnect';
    }
    if (normalized == 'state') {
      return 'state_snapshot';
    }
    return eventType;
  }

  BughuntSeverity _severityForEvent(String eventType) {
    final normalized = eventType.toLowerCase();
    if (normalized.contains('fatal') || normalized.contains('error')) {
      return BughuntSeverity.error;
    }
    if (normalized.contains('warn')) {
      return BughuntSeverity.warn;
    }
    return BughuntSeverity.info;
  }
}
