// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bullethole_shared/src/multiplayer/multiplayer_client_utils.dart';
import 'package:bullethole_shared/src/multiplayer/multiplayer_transport_client.dart';
import 'package:chess/chess.dart' as chess;
import 'package:http/http.dart' as http;

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';

Future<void> main(List<String> args) async {
  await runZoned(
    () async {
      final config = _Config.parse(args);
      final logger = _JsonlLogger(path: config.logFilePath);
      await logger.log(<String, Object?>{
        'event': 'client_start',
        'at': DateTime.now().toIso8601String(),
        'backendUrl': config.backendUrl,
        'name': config.displayName,
        'seed': config.seed,
        'cooldownSeconds': config.cooldownSeconds,
      });

      final httpClient = http.Client();
      final transport = MultiplayerTransportClient(
        httpClient: httpClient,
        requestTimeout: const Duration(seconds: 10),
      );

      final session = _ChessNetworkAiSession(
        config: config,
        transport: transport,
        logger: logger,
      );

      try {
        await session.run();
      } finally {
        await transport.disconnect();
        transport.dispose();
        httpClient.close();
        await logger.close();
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (_isSuppressedNoiseLine(line)) {
          return;
        }
        parent.print(zone, line);
      },
    ),
  );
}

bool _isSuppressedNoiseLine(String line) {
  final normalized = line.trim().toLowerCase();
  return normalized == 'player is in check.' ||
      normalized == 'king of opponent player is in check.';
}

class _ChessNetworkAiSession {
  _ChessNetworkAiSession({
    required this.config,
    required this.transport,
    required this.logger,
  }) : _ai = DumbAiEngine(random: Random(config.seed));

  final _Config config;
  final MultiplayerTransportClient transport;
  final _JsonlLogger logger;
  final DumbAiEngine _ai;
  final Completer<void> _done = Completer<void>();

  Timer? _ticker;
  String? _myColor;
  String _status = 'disconnected';
  String? _result;
  String? _fen;
  int _sequence = 0;
  int _clockOffsetMs = 0;
  DateTime? _lastStateAt;
  bool _moveInFlight = false;
  int _nextClientMoveId = 1;
  int? _inFlightClientMoveId;
  String? _inFlightFrom;
  String? _inFlightTo;
  int? _lastAttemptSequence;
  final Map<String, int> _cooldownEndsAt = <String, int>{'w': 0, 'b': 0};
  Map<String, dynamic>? _forfeitLock;
  bool _disposed = false;

  Future<void> run() async {
    final joined = await transport.joinMatch(
      apiBaseUrl: config.backendUrl,
      displayName: config.displayName,
      pieceSkinId: 'chess_classic',
      cooldownSeconds: config.cooldownSeconds,
      gameType: 'chess',
      metadata: <String, dynamic>{'client': 'network_ai_duel'},
    );

    await logger.log(<String, Object?>{
      'event': 'match_joined',
      'at': DateTime.now().toIso8601String(),
      'matchId': joined.matchId,
      'playerId': joined.playerId,
      'wsPath': joined.wsPath,
    });

    await transport.connectSocket(
      baseUri: joined.baseUri,
      wsPath: joined.wsPath,
      matchId: joined.matchId,
      playerId: joined.playerId,
      onMessage: _onMessage,
      onError: (Object error) {
        _finishWithError('WebSocket error: $error');
      },
      onDone: () {
        if (_disposed || _done.isCompleted) {
          return;
        }
        _finish();
      },
    );

    _ticker = Timer.periodic(
      Duration(milliseconds: config.pollMs),
      (_) => _onTick(),
    );
    await _done.future;
  }

  void _onTick() {
    if (_disposed || _done.isCompleted) {
      return;
    }
    _attemptMoveIfReady();
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      return;
    }
    final message = MultiplayerClientUtils.decodeJsonMap(raw);
    final type = message['type'] as String?;
    if (type == null) {
      return;
    }

    switch (type) {
      case 'welcome':
        _myColor = message['color'] as String?;
        _updateClockOffset(message['serverNow']);
        _updateCooldownSnapshot(message['cooldownEndsAt']);
        _forfeitLock = _readMap(message['forfeitLock']);
        logger.log(<String, Object?>{
          'event': 'welcome',
          'at': DateTime.now().toIso8601String(),
          'matchId': message['matchId'],
          'color': _myColor,
          'gameType': message['gameType'],
          'cooldownSeconds': message['cooldownSeconds'],
        });
        _attemptMoveIfReady();
        return;
      case 'state':
        _applyStateMessage(message);
        _attemptMoveIfReady();
        return;
      case 'error':
        _moveInFlight = false;
        _inFlightClientMoveId = null;
        _inFlightFrom = null;
        _inFlightTo = null;
        _updateClockOffset(message['serverNow']);
        _updateCooldownSnapshot(message['cooldownEndsAt']);
        _forfeitLock = _readMap(message['forfeitLock']) ?? _forfeitLock;
        logger.log(<String, Object?>{
          'event': 'server_error',
          'at': DateTime.now().toIso8601String(),
          'code': message['code'],
          'message': message['message'],
          'remainingMs': message['remainingMs'],
        });
        return;
      case 'opponent_left':
        logger.log(<String, Object?>{
          'event': 'opponent_left',
          'at': DateTime.now().toIso8601String(),
          'message': message['message'],
        });
        return;
      case 'pong':
        return;
      default:
        logger.log(<String, Object?>{
          'event': 'ws_unknown',
          'at': DateTime.now().toIso8601String(),
          'type': type,
        });
        return;
    }
  }

  void _applyStateMessage(Map<String, dynamic> message) {
    final incomingSequence = MultiplayerClientUtils.readInt(
      message['sequence'],
    );
    final sequence = incomingSequence ?? (_sequence + 1);
    if (sequence < _sequence) {
      return;
    }
    _sequence = sequence;
    _status = message['status'] as String? ?? _status;
    _result = message['result'] as String?;
    _lastStateAt = DateTime.now();
    final fen = message['fen'] as String?;
    if (fen != null && fen.trim().isNotEmpty) {
      _fen = fen;
    }
    _updateClockOffset(message['serverNow']);
    _updateCooldownSnapshot(message['cooldownEndsAt']);
    _forfeitLock = _readMap(message['forfeitLock']) ?? _forfeitLock;

    final lastMove = _readMap(message['lastMove']);
    if (_inFlightClientMoveId != null && lastMove != null) {
      final ackMoveId = MultiplayerClientUtils.readInt(
        lastMove['clientMoveId'],
      );
      final ackColor = (lastMove['color'] as String?)?.trim().toLowerCase();
      final ackFrom = (lastMove['from'] as String?)?.trim().toLowerCase();
      final ackTo = (lastMove['to'] as String?)?.trim().toLowerCase();
      final ackMatchesMoveId = ackMoveId != null && ackMoveId == _inFlightClientMoveId;
      final ackMatchesSender = ackColor != null
          ? ackColor == _myColor
          : (ackFrom == _inFlightFrom && ackTo == _inFlightTo);
      if (ackMatchesMoveId && ackMatchesSender) {
        _moveInFlight = false;
        _inFlightClientMoveId = null;
        _inFlightFrom = null;
        _inFlightTo = null;
        logger.log(<String, Object?>{
          'event': 'move_acked',
          'at': DateTime.now().toIso8601String(),
          'clientMoveId': ackMoveId,
          'from': lastMove['from'],
          'to': lastMove['to'],
        });
      }
    }

    logger.log(<String, Object?>{
      'event': 'state',
      'at': DateTime.now().toIso8601String(),
      'matchId': message['matchId'],
      'sequence': _sequence,
      'status': _status,
      'result': _result,
      'turn': message['turn'],
      'cooldownRemainingMs': _myColor == null
          ? null
          : _cooldownRemainingMs(_myColor!),
      'moveInFlight': _moveInFlight,
    });

    if (_result != null && config.exitOnGameOver) {
      logger.log(<String, Object?>{
        'event': 'game_over',
        'at': DateTime.now().toIso8601String(),
        'result': _result,
      });
      _finish();
    }
  }

  void _attemptMoveIfReady() {
    if (_done.isCompleted || _disposed) {
      return;
    }
    if (_status != 'active' || _result != null) {
      return;
    }
    if (_moveInFlight) {
      return;
    }
    if (_lastAttemptSequence != null && _lastAttemptSequence == _sequence) {
      return;
    }
    final myColor = _myColor;
    final fen = _fen;
    if (myColor == null || fen == null || fen.trim().isEmpty) {
      return;
    }
    final lastStateAt = _lastStateAt;
    if (lastStateAt == null ||
        DateTime.now().difference(lastStateAt).inMilliseconds <
            config.settleMs) {
      return;
    }
    if (_isBlockedByForfeitLock(myColor)) {
      return;
    }
    if (_cooldownRemainingMs(myColor) > 0) {
      return;
    }

    final game = chess.Chess();
    final loaded = game.load(fen);
    if (!loaded) {
      _lastAttemptSequence = _sequence;
      logger.log(<String, Object?>{
        'event': 'state_load_failed',
        'at': DateTime.now().toIso8601String(),
        'sequence': _sequence,
        'fen': fen,
      });
      return;
    }

    final move = ChessRules.withTurn<EngineMove?>(
      game,
      myColor,
      () => _ai.chooseMove(game),
    );
    if (move == null) {
      logger.log(<String, Object?>{
        'event': 'no_legal_move',
        'at': DateTime.now().toIso8601String(),
        'color': myColor,
      });
      return;
    }

    final clientMoveId = _nextClientMoveId++;
    final sent = transport.sendJson(<String, dynamic>{
      'type': 'move',
      'from': move.from,
      'to': move.to,
      'promotion': move.promotion,
      'source': 'manual',
      'clientMoveId': clientMoveId,
    });
    if (!sent) {
      return;
    }

    _lastAttemptSequence = _sequence;
    _moveInFlight = true;
    _inFlightClientMoveId = clientMoveId;
    _inFlightFrom = move.from;
    _inFlightTo = move.to;
    logger.log(<String, Object?>{
      'event': 'move_sent',
      'at': DateTime.now().toIso8601String(),
      'clientMoveId': clientMoveId,
      'color': myColor,
      'from': move.from,
      'to': move.to,
      'promotion': move.promotion,
    });
  }

  int _estimatedServerNowMs() {
    return DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;
  }

  int _cooldownRemainingMs(String color) {
    final readyAt = _cooldownEndsAt[color] ?? 0;
    final remaining = readyAt - _estimatedServerNowMs();
    return remaining <= 0 ? 0 : remaining;
  }

  bool _isBlockedByForfeitLock(String color) {
    final lock = _forfeitLock;
    if (lock == null) {
      return false;
    }
    return lock['blockedColor'] == color;
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

  void _finishWithError(String message) {
    logger.log(<String, Object?>{
      'event': 'fatal',
      'at': DateTime.now().toIso8601String(),
      'message': message,
    });
    if (!_done.isCompleted) {
      _done.completeError(StateError(message));
    }
    _dispose();
  }

  void _finish() {
    if (!_done.isCompleted) {
      _done.complete();
    }
    _dispose();
  }

  void _dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _ticker?.cancel();
  }
}

class _JsonlLogger {
  _JsonlLogger({required this.path}) : _file = File(path) {
    final parent = _file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
  }

  final String path;
  final File _file;
  Future<void> _pending = Future<void>.value();

  Future<void> log(Map<String, Object?> event) async {
    final line = '${jsonEncode(event)}\n';
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
}

class _Config {
  const _Config({
    required this.backendUrl,
    required this.displayName,
    required this.cooldownSeconds,
    required this.seed,
    required this.pollMs,
    required this.settleMs,
    required this.exitOnGameOver,
    required this.logFilePath,
  });

  final String backendUrl;
  final String displayName;
  final int cooldownSeconds;
  final int seed;
  final int pollMs;
  final int settleMs;
  final bool exitOnGameOver;
  final String logFilePath;

  static _Config parse(List<String> args) {
    var backendUrl = 'http://localhost:8080';
    var displayName = 'ChessAI-${pid.toString().padLeft(5, '0')}';
    var cooldownSeconds = 3;
    var seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    var pollMs = 120;
    var settleMs = 250;
    var exitOnGameOver = true;
    String? logFilePath;

    for (final arg in args) {
      if (arg.startsWith('--backend-url=')) {
        backendUrl = arg.substring('--backend-url='.length).trim();
        continue;
      }
      if (arg.startsWith('--name=')) {
        displayName = arg.substring('--name='.length).trim();
        continue;
      }
      if (arg.startsWith('--cooldown-seconds=')) {
        cooldownSeconds = int.parse(
          arg.substring('--cooldown-seconds='.length),
        );
        continue;
      }
      if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
        continue;
      }
      if (arg.startsWith('--poll-ms=')) {
        pollMs = int.parse(arg.substring('--poll-ms='.length));
        continue;
      }
      if (arg.startsWith('--settle-ms=')) {
        settleMs = int.parse(arg.substring('--settle-ms='.length));
        continue;
      }
      if (arg == '--stay-alive') {
        exitOnGameOver = false;
        continue;
      }
      if (arg.startsWith('--log-file=')) {
        logFilePath = arg.substring('--log-file='.length).trim();
        continue;
      }
      if (arg == '--help' || arg == '-h') {
        _printUsageAndExit();
      }
      throw ArgumentError('Unknown argument: $arg');
    }

    if (displayName.isEmpty) {
      throw ArgumentError('--name must not be empty');
    }
    if (cooldownSeconds < 0) {
      throw ArgumentError('--cooldown-seconds must be >= 0');
    }
    if (pollMs <= 0) {
      throw ArgumentError('--poll-ms must be > 0');
    }
    if (settleMs < 0) {
      throw ArgumentError('--settle-ms must be >= 0');
    }

    logFilePath ??=
        'debug/network-ai-chess-${displayName.toLowerCase()}-${_timestamp()}.jsonl';

    return _Config(
      backendUrl: backendUrl,
      displayName: displayName,
      cooldownSeconds: cooldownSeconds,
      seed: seed,
      pollMs: pollMs,
      settleMs: settleMs,
      exitOnGameOver: exitOnGameOver,
      logFilePath: logFilePath,
    );
  }
}

String _timestamp() {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final hh = now.hour.toString().padLeft(2, '0');
  final mm = now.minute.toString().padLeft(2, '0');
  final ss = now.second.toString().padLeft(2, '0');
  return '$y$m$d-$hh$mm$ss';
}

Never _printUsageAndExit() {
  print(
    'Usage: dart run tool/network_ai_duel_client.dart '
    '[--backend-url=http://localhost:8080] [--name=ChessAI-A] '
    '[--cooldown-seconds=0] [--seed=123] [--poll-ms=120] '
    '[--settle-ms=250] '
    '[--log-file=debug/chess-network.jsonl] [--stay-alive]',
  );
  exit(0);
}
