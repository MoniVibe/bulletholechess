import 'dart:io';

const int defaultGames = 100;
const int defaultMaxPlies = 220;
const int defaultSeed = 20260226;
const int defaultRepetitionAlertCount = 3;
const int defaultHalfmoveAlertThreshold = 90;
const int defaultConversionFailureCapAdvThreshold = 5;
const int defaultMaxConversionFailures = -1;
const int defaultProgressEvery = 10;
const String defaultPgnDirName = 'ai-duel-weird-pgn';

class DuelConfig {
  const DuelConfig({
    required this.games,
    required this.maxPlies,
    required this.seed,
    required this.repetitionAlertCount,
    required this.halfmoveAlertThreshold,
    required this.conversionFailureCapAdvThreshold,
    required this.maxConversionFailures,
    required this.progressEvery,
    required this.logFilePath,
    required this.pgnDirPath,
    required this.runId,
  });

  final int games;
  final int maxPlies;
  final int seed;
  final int repetitionAlertCount;
  final int halfmoveAlertThreshold;
  final int conversionFailureCapAdvThreshold;
  final int maxConversionFailures;
  final int progressEvery;
  final String? logFilePath;
  final String? pgnDirPath;
  final String? runId;

  static DuelConfig parse(
    List<String> args, {
    required Never Function() printUsageAndExit,
    String Function(String logFilePath)? deriveDefaultPgnDirPath,
  }) {
    final derivePgnDirPath =
        deriveDefaultPgnDirPath ?? deriveDefaultPgnDirPathFromLogFile;

    var games = defaultGames;
    var maxPlies = defaultMaxPlies;
    var seed = defaultSeed;
    var repetitionAlertCount = defaultRepetitionAlertCount;
    var halfmoveAlertThreshold = defaultHalfmoveAlertThreshold;
    var conversionFailureCapAdvThreshold =
        defaultConversionFailureCapAdvThreshold;
    var maxConversionFailures = defaultMaxConversionFailures;
    var progressEvery = defaultProgressEvery;
    String? logFilePath;
    String? pgnDirPath;
    String? runId;

    for (final arg in args) {
      if (arg.startsWith('--games=')) {
        games = int.parse(arg.substring('--games='.length));
        continue;
      }
      if (arg.startsWith('--max-plies=')) {
        maxPlies = int.parse(arg.substring('--max-plies='.length));
        continue;
      }
      if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
        continue;
      }
      if (arg.startsWith('--repeat-alert=')) {
        repetitionAlertCount = int.parse(
          arg.substring('--repeat-alert='.length),
        );
        continue;
      }
      if (arg.startsWith('--halfmove-alert=')) {
        halfmoveAlertThreshold = int.parse(
          arg.substring('--halfmove-alert='.length),
        );
        continue;
      }
      if (arg.startsWith('--conversion-fail-cap-adv=')) {
        conversionFailureCapAdvThreshold = int.parse(
          arg.substring('--conversion-fail-cap-adv='.length),
        );
        continue;
      }
      if (arg.startsWith('--max-conversion-failures=')) {
        maxConversionFailures = int.parse(
          arg.substring('--max-conversion-failures='.length),
        );
        continue;
      }
      if (arg.startsWith('--progress-every=')) {
        progressEvery = int.parse(arg.substring('--progress-every='.length));
        continue;
      }
      if (arg.startsWith('--log-file=')) {
        logFilePath = arg.substring('--log-file='.length);
        continue;
      }
      if (arg.startsWith('--pgn-dir=')) {
        pgnDirPath = arg.substring('--pgn-dir='.length);
        continue;
      }
      if (arg.startsWith('--run-id=')) {
        runId = arg.substring('--run-id='.length).trim();
        continue;
      }
      if (arg == '--help' || arg == '-h') {
        printUsageAndExit();
      }
      throw ArgumentError('Unknown argument: $arg');
    }

    if (games <= 0) {
      throw ArgumentError('--games must be > 0');
    }
    if (maxPlies <= 0) {
      throw ArgumentError('--max-plies must be > 0');
    }
    if (repetitionAlertCount <= 1) {
      throw ArgumentError('--repeat-alert must be > 1');
    }
    if (halfmoveAlertThreshold <= 0) {
      throw ArgumentError('--halfmove-alert must be > 0');
    }
    if (conversionFailureCapAdvThreshold <= 0) {
      throw ArgumentError('--conversion-fail-cap-adv must be > 0');
    }
    if (maxConversionFailures < -1) {
      throw ArgumentError('--max-conversion-failures must be >= -1');
    }
    if (progressEvery <= 0) {
      throw ArgumentError('--progress-every must be > 0');
    }
    if (pgnDirPath != null && pgnDirPath.trim().isEmpty) {
      throw ArgumentError('--pgn-dir must not be empty');
    }

    if (pgnDirPath == null && logFilePath != null) {
      pgnDirPath = derivePgnDirPath(logFilePath);
    }

    return DuelConfig(
      games: games,
      maxPlies: maxPlies,
      seed: seed,
      repetitionAlertCount: repetitionAlertCount,
      halfmoveAlertThreshold: halfmoveAlertThreshold,
      conversionFailureCapAdvThreshold: conversionFailureCapAdvThreshold,
      maxConversionFailures: maxConversionFailures,
      progressEvery: progressEvery,
      logFilePath: logFilePath,
      pgnDirPath: pgnDirPath,
      runId: runId,
    );
  }
}

String deriveDefaultPgnDirPathFromLogFile(String logFilePath) {
  final normalized = logFilePath.replaceAll('\\', '/');
  final separatorIndex = normalized.lastIndexOf('/');
  final parent = separatorIndex >= 0
      ? normalized.substring(0, separatorIndex)
      : '';
  final fileName = separatorIndex >= 0
      ? normalized.substring(separatorIndex + 1)
      : normalized;

  var stem = fileName.trim();
  final dotIndex = stem.lastIndexOf('.');
  if (dotIndex > 0) {
    stem = stem.substring(0, dotIndex);
  }
  if (stem.isEmpty) {
    stem = defaultPgnDirName;
  }

  final pgnDirName = '$stem-pgn';
  if (parent.trim().isEmpty || parent == '.') {
    return pgnDirName;
  }
  return joinPath(parent, pgnDirName);
}

String joinPath(String left, String right) {
  if (left.endsWith('/') || left.endsWith('\\')) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}
