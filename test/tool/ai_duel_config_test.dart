import 'package:flutter_test/flutter_test.dart';

import '../../tool/ai_duel/config.dart';

Never _throwUsage() {
  throw StateError('usage');
}

void main() {
  group('DuelConfig.parse', () {
    test('uses defaults when no args are provided', () {
      final config = DuelConfig.parse(
        const <String>[],
        printUsageAndExit: _throwUsage,
      );

      expect(config.games, defaultGames);
      expect(config.maxPlies, defaultMaxPlies);
      expect(config.seed, defaultSeed);
      expect(config.repetitionAlertCount, defaultRepetitionAlertCount);
      expect(config.halfmoveAlertThreshold, defaultHalfmoveAlertThreshold);
      expect(
        config.conversionFailureCapAdvThreshold,
        defaultConversionFailureCapAdvThreshold,
      );
      expect(config.maxConversionFailures, defaultMaxConversionFailures);
      expect(config.progressEvery, defaultProgressEvery);
      expect(config.logFilePath, isNull);
      expect(config.pgnDirPath, isNull);
      expect(config.runId, isNull);
    });

    test('derives pgn dir from log file when not explicitly provided', () {
      final config = DuelConfig.parse(const <String>[
        '--log-file=debug/ai-duel-weird.jsonl',
      ], printUsageAndExit: _throwUsage);

      expect(config.logFilePath, 'debug/ai-duel-weird.jsonl');
      expect(config.pgnDirPath, joinPath('debug', 'ai-duel-weird-pgn'));
    });

    test('keeps explicit pgn dir when provided', () {
      final config = DuelConfig.parse(const <String>[
        '--log-file=debug/ai-duel-weird.jsonl',
        '--pgn-dir=debug/custom',
      ], printUsageAndExit: _throwUsage);

      expect(config.pgnDirPath, 'debug/custom');
    });

    test('throws for invalid repeat-alert value', () {
      expect(
        () => DuelConfig.parse(const <String>[
          '--repeat-alert=1',
        ], printUsageAndExit: _throwUsage),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            '--repeat-alert must be > 1',
          ),
        ),
      );
    });

    test('throws for unknown argument', () {
      expect(
        () => DuelConfig.parse(const <String>[
          '--unexpected=1',
        ], printUsageAndExit: _throwUsage),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Unknown argument: --unexpected=1',
          ),
        ),
      );
    });

    test('delegates --help to usage callback', () {
      expect(
        () => DuelConfig.parse(const <String>[
          '--help',
        ], printUsageAndExit: _throwUsage),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'usage',
          ),
        ),
      );
    });
  });

  group('deriveDefaultPgnDirPathFromLogFile', () {
    test('falls back to default stem for empty filename stem', () {
      final pgnDir = deriveDefaultPgnDirPathFromLogFile('');

      expect(pgnDir, '$defaultPgnDirName-pgn');
    });
  });
}
