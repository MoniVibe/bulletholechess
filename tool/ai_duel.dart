// ignore_for_file: avoid_print

import 'dart:io';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';

import 'ai_duel/bughunt_logger.dart';
import 'ai_duel/config.dart';
import 'ai_duel/file_io.dart';
import 'ai_duel/report_formatter.dart';
import 'ai_duel/runner.dart';

void main(List<String> args) {
  final config = DuelConfig.parse(args, printUsageAndExit: printUsageAndExit);
  final bughuntLogger = BughuntRunLogger(
    game: 'chess',
    mode: BughuntMode.ai,
    role: BughuntRole.localA,
    seed: config.seed,
    maxTurns: config.maxPlies,
    runId: config.runId,
  )..begin();
  final summary = runDuels(config, logger: bughuntLogger);

  for (final line in formatSummaryLines(
    summary: summary,
    seed: config.seed,
    maxPlies: config.maxPlies,
    conversionFailureCapAdvThreshold: config.conversionFailureCapAdvThreshold,
  )) {
    print(line);
  }

  if (config.logFilePath != null) {
    writeWeirdLogFile(config.logFilePath!, summary.weirdEvents);
    print('');
    print('Saved weird logs to ${config.logFilePath}');
  }
  if (config.pgnDirPath != null && summary.weirdEvents.isNotEmpty) {
    print('Saved weird PGNs to ${config.pgnDirPath}');
  }

  bughuntLogger.complete(summary: summary);

  if (summary.failures.isNotEmpty) {
    for (final line in formatFailureLines(summary.failures)) {
      print(line);
    }
    throw StateError(
      'AI duel run failed with ${summary.failures.length} failure(s).',
    );
  }

  if (config.maxConversionFailures >= 0 &&
      summary.conversionFailures > config.maxConversionFailures) {
    throw StateError(
      'Conversion failures (${summary.conversionFailures}) exceeded '
      'allowed maximum (${config.maxConversionFailures}).',
    );
  }
}

Never printUsageAndExit() {
  print(
    'Usage: dart run tool/ai_duel.dart '
    '[--games=N] [--max-plies=N] [--seed=N] '
    '[--repeat-alert=N] [--halfmove-alert=N] '
    '[--conversion-fail-cap-adv=N] [--max-conversion-failures=N] '
    '[--progress-every=N] '
    '[--log-file=path] [--pgn-dir=path] [--run-id=id]',
  );
  exit(0);
}
