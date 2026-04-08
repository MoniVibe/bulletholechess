part of '../network_ai_duel_client.dart';

class _Config {
  const _Config({
    required this.backendUrl,
    required this.displayName,
    required this.cooldownSeconds,
    required this.seed,
    required this.pollMs,
    required this.settleMs,
    required this.maxPlies,
    required this.maxSeconds,
    required this.exitOnGameOver,
    required this.logFilePath,
    required this.runId,
    required this.role,
  });

  final String backendUrl;
  final String displayName;
  final int cooldownSeconds;
  final int seed;
  final int pollMs;
  final int settleMs;
  final int maxPlies;
  final int maxSeconds;
  final bool exitOnGameOver;
  final String logFilePath;
  final String runId;
  final BughuntRole role;

  static _Config parse(List<String> args) {
    var backendUrl = 'http://localhost:8080';
    var displayName = 'ChessAI-${pid.toString().padLeft(5, '0')}';
    var cooldownSeconds = 3;
    var seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    var pollMs = 120;
    var settleMs = 250;
    var maxPlies = 240;
    var maxSeconds = 300;
    var exitOnGameOver = true;
    String? logFilePath;
    String? runId;
    var role = BughuntRole.client;

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
      if (arg.startsWith('--max-plies=')) {
        maxPlies = int.parse(arg.substring('--max-plies='.length));
        continue;
      }
      if (arg.startsWith('--max-seconds=')) {
        maxSeconds = int.parse(arg.substring('--max-seconds='.length));
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
      if (arg.startsWith('--run-id=')) {
        runId = arg.substring('--run-id='.length).trim();
        continue;
      }
      if (arg.startsWith('--role=')) {
        final parsed = parseBughuntRole(arg.substring('--role='.length).trim());
        if (parsed != null) {
          role = parsed;
        }
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
    if (maxPlies <= 0) {
      throw ArgumentError('--max-plies must be > 0');
    }
    if (maxSeconds <= 0) {
      throw ArgumentError('--max-seconds must be > 0');
    }

    logFilePath ??=
        'debug/network-ai-chess-${displayName.toLowerCase()}-${_timestamp()}.jsonl';
    runId ??= 'net_${_timestamp()}';

    return _Config(
      backendUrl: backendUrl,
      displayName: displayName,
      cooldownSeconds: cooldownSeconds,
      seed: seed,
      pollMs: pollMs,
      settleMs: settleMs,
      maxPlies: maxPlies,
      maxSeconds: maxSeconds,
      exitOnGameOver: exitOnGameOver,
      logFilePath: logFilePath,
      runId: runId,
      role: role,
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
    '[--settle-ms=250] [--max-plies=240] [--max-seconds=300] '
    '[--log-file=debug/chess-network.jsonl] [--run-id=id] [--role=host|client] [--stay-alive]',
  );
  exit(0);
}
