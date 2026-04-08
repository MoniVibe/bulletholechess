// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';
import 'package:chess/chess.dart' as chess;

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';

const int _defaultGames = 100;
const int _defaultMaxPlies = 220;
const int _defaultSeed = 20260226;
const int _defaultRepetitionAlertCount = 3;
const int _defaultHalfmoveAlertThreshold = 90;
const int _defaultConversionFailureCapAdvThreshold = 5;
const int _defaultMaxConversionFailures = -1;
const int _defaultProgressEvery = 10;
const String _defaultPgnDirName = 'ai-duel-weird-pgn';

void main(List<String> args) {
  final config = _DuelConfig.parse(args);
  final bughuntLogger = _BughuntRunLogger(
    game: 'chess',
    mode: BughuntMode.ai,
    role: BughuntRole.localA,
    seed: config.seed,
    maxTurns: config.maxPlies,
    runId: config.runId,
  )..begin();
  final summary = _runDuels(config, logger: bughuntLogger);

  print('AI duel summary:');
  print('  games: ${summary.totalGames}');
  print('  white wins: ${summary.whiteWins}');
  print('  black wins: ${summary.blackWins}');
  print('  draws: ${summary.draws}');
  print('  capped games: ${summary.cappedGames}');
  print('  seed: ${config.seed}');
  print('  max plies: ${config.maxPlies}');
  print('  weird logs: ${summary.weirdEvents.length}');
  print(
    '  conversion failures: ${summary.conversionFailures} '
    '(capAdv abs >= ${config.conversionFailureCapAdvThreshold})',
  );
  print('  termination reasons:');
  final terminationEntries = summary.terminationReasonCounts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in terminationEntries) {
    print('    ${entry.key}: ${entry.value}');
  }

  if (summary.weirdEvents.isNotEmpty) {
    print('');
    print('Weird logs:');
    for (final weird in summary.weirdEvents) {
      final capAdvLabel = _formatCapAdvForDisplay(weird.materialAdvantageAtCap);
      print(
        '  [${weird.type}] game=${weird.gameIndex} ply=${weird.ply} '
        'side=${weird.sideToMove} legalMoves=${weird.legalMoveCount} '
        'material=${weird.materialSignature}$capAdvLabel note=${weird.message}',
      );
    }
  }

  if (config.logFilePath != null) {
    _writeWeirdLogFile(config.logFilePath!, summary.weirdEvents);
    print('');
    print('Saved weird logs to ${config.logFilePath}');
  }
  if (config.pgnDirPath != null && summary.weirdEvents.isNotEmpty) {
    print('Saved weird PGNs to ${config.pgnDirPath}');
  }

  bughuntLogger.complete(summary: summary);

  if (summary.failures.isNotEmpty) {
    for (final failure in summary.failures) {
      print('');
      print('Failure in game #${failure.gameIndex}: ${failure.message}');
      print('  seed: ${failure.seed}');
      print('  ply: ${failure.ply}');
      print('  side to move: ${failure.sideToMove}');
      print('  fen: ${failure.fen}');
      if (failure.lastMoves.isNotEmpty) {
        print('  recent moves: ${failure.lastMoves.join(', ')}');
      }
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

_DuelSummary _runDuels(_DuelConfig config, {_BughuntRunLogger? logger}) {
  if (config.pgnDirPath != null) {
    _preparePgnOutputDir(config.pgnDirPath!);
  }

  final runRandom = Random(config.seed);
  final failures = <_DuelFailure>[];
  final weirdEvents = <_WeirdEvent>[];
  final terminationReasonCounts = <String, int>{};
  var conversionFailures = 0;

  var whiteWins = 0;
  var blackWins = 0;
  var draws = 0;
  var cappedGames = 0;
  final progressStopwatch = Stopwatch()..start();

  void maybePrintProgress(int gameIndex) {
    if (config.progressEvery <= 0) {
      return;
    }
    if (gameIndex % config.progressEvery != 0 && gameIndex != config.games) {
      return;
    }
    final elapsed = progressStopwatch.elapsed;
    final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
    final gamesPerMinute = elapsedSeconds <= 0
        ? 0.0
        : gameIndex / (elapsedSeconds / 60.0);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    print(
      'Progress: game $gameIndex/${config.games} '
      'elapsed=${minutes}m${seconds.toString().padLeft(2, '0')}s '
      'wins(w/b)=$whiteWins/$blackWins draws=$draws capped=$cappedGames '
      'failures=${failures.length} weird=${weirdEvents.length} '
      'rate=${gamesPerMinute.toStringAsFixed(2)} games/min',
    );
  }

  for (var gameIndex = 1; gameIndex <= config.games; gameIndex++) {
    logger?.event(
      'session_joined',
      payload: <String, Object?>{'gameIndex': gameIndex},
      turnIndex: 1,
      actionIndexOrPlyIndex: 0,
    );
    final failuresBeforeGame = failures.length;
    final game = chess.Chess();
    final whiteAi = DumbAiEngine(random: Random(runRandom.nextInt(1 << 31)));
    final blackAi = DumbAiEngine(random: Random(runRandom.nextInt(1 << 31)));
    var ply = 0;
    final playedMoves = <String>[];
    final gameWeirdEvents = <_WeirdEvent>[];
    var wasCapped = false;
    var gameFailed = false;
    String? gameTerminationReason;
    String? gameWinner;
    final initialPositionKey = _normalizedPositionKey(game.fen);
    final positionSeenCount = <String, int>{initialPositionKey: 1};
    var halfmoveAlerted = false;

    while (ply < config.maxPlies) {
      final fenAtTurnStart = game.fen;
      if (_hasUnpromotedBackRankPawn(fenAtTurnStart)) {
        final weird = _WeirdEvent(
          type: 'promotion_state_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: ChessRules.colorCode(game.turn),
          fen: fenAtTurnStart,
          materialSignature: _materialSignatureFromFen(fenAtTurnStart),
          legalMoveCount: _safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message:
              'Detected pawn on back rank at turn start; treating game as '
              'draw to avoid crashing the soak run.',
          lastMoves: _tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        gameTerminationReason = 'draw_promotion_state_error';
        gameWinner = null;
        break;
      }

      final status = _safeEvaluateGameStatus(
        game: game,
        positionSeenCount: positionSeenCount,
      );
      if (status.error != null) {
        final fen = game.fen;
        final weird = _WeirdEvent(
          type: 'engine_state_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: ChessRules.colorCode(game.turn),
          fen: fen,
          materialSignature: _materialSignatureFromFen(fen),
          legalMoveCount: _safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message: status.error!,
          lastMoves: _tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        failures.add(
          _DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: ChessRules.colorCode(game.turn),
            fen: fen,
            message: status.error!,
            lastMoves: _tail(playedMoves, 8),
          ),
        );
        gameFailed = true;
        break;
      }

      if (status.isTerminal) {
        gameTerminationReason = status.terminalReason;
        gameWinner = status.winner;
        break;
      }

      final side = ChessRules.colorCode(game.turn);
      final ai = side == 'w' ? whiteAi : blackAi;
      EngineMove? move;
      try {
        move = ai.chooseMove(game);
      } catch (error) {
        final fen = game.fen;
        final message = 'AI move selection failed: $error';
        final weird = _WeirdEvent(
          type: 'engine_state_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: side,
          fen: fen,
          materialSignature: _materialSignatureFromFen(fen),
          legalMoveCount: _safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message: message,
          lastMoves: _tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        failures.add(
          _DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: fen,
            message: message,
            lastMoves: _tail(playedMoves, 8),
          ),
        );
        gameFailed = true;
        break;
      }

      if (move == null) {
        failures.add(
          _DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: game.fen,
            message: 'AI returned null despite legal moves existing.',
            lastMoves: _tail(playedMoves, 8),
          ),
        );
        gameFailed = true;
        break;
      }

      Map<String, String> movePayload = <String, String>{
        'from': move.from,
        'to': move.to,
      };
      if (_looksLikePromotionMove(from: move.from, to: move.to, side: side)) {
        movePayload['promotion'] = move.promotion;
      }
      final currentSideBeforeApply = ChessRules.colorCode(game.turn);
      if (currentSideBeforeApply != side) {
        final fen = game.fen;
        final weird = _WeirdEvent(
          type: 'turn_desync',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: currentSideBeforeApply,
          fen: fen,
          materialSignature: _materialSignatureFromFen(fen),
          legalMoveCount: _safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message:
              'Turn drift detected before apply; expected $side but saw '
              '$currentSideBeforeApply. Resyncing turn to $side.',
          lastMoves: _tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        game.turn = ChessRules.toChessColor(side);
      }
      try {
        final legal = ChessRules.findValidatedLegalMove(
          game: game,
          from: move.from,
          to: move.to,
          color: side,
          promotion: move.promotion,
        );
        if (legal != null) {
          movePayload = ChessRules.movePayloadFromLegalMove(
            legal,
            fallbackPromotion: move.promotion,
          );
          if (_looksLikePromotionMove(
                from: move.from,
                to: move.to,
                side: side,
              ) &&
              (movePayload['promotion'] == null ||
                  movePayload['promotion']!.isEmpty)) {
            movePayload['promotion'] = move.promotion;
          }
        } else {
          final fen = game.fen;
          final weird = _WeirdEvent(
            type: 'legal_validation_miss',
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: fen,
            materialSignature: _materialSignatureFromFen(fen),
            legalMoveCount: _safeLegalMoveCount(game),
            materialAdvantageAtCap: null,
            message:
                'Validation did not find ${move.from}-${move.to}'
                '(${move.promotion}); trying direct apply.',
            lastMoves: _tail(playedMoves, 8),
          );
          weirdEvents.add(weird);
          gameWeirdEvents.add(weird);
        }
      } catch (error) {
        final fen = game.fen;
        final weird = _WeirdEvent(
          type: 'legal_validation_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: side,
          fen: fen,
          materialSignature: _materialSignatureFromFen(fen),
          legalMoveCount: _safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message: 'Legal move validation failed: $error; trying direct apply.',
          lastMoves: _tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
      }

      bool moved;
      try {
        moved = game.move(movePayload);
      } catch (error) {
        final fen = game.fen;
        final errorText = '$error';
        final legalMoveCountAtError = _safeLegalMoveCount(game);
        final weird = _WeirdEvent(
          type: 'move_apply_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: side,
          fen: fen,
          materialSignature: _materialSignatureFromFen(fen),
          legalMoveCount: legalMoveCountAtError,
          materialAdvantageAtCap: null,
          message:
              'Engine threw while applying move payload '
              '${jsonEncode(movePayload)}: $error',
          lastMoves: _tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        final isEngineStateRangeError =
            errorText.contains('RangeError') || legalMoveCountAtError == -1;
        if (isEngineStateRangeError) {
          gameTerminationReason = 'draw_engine_state_error';
          gameWinner = null;
          break;
        }
        failures.add(
          _DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: fen,
            message:
                'Engine threw while applying move '
                '${move.from}-${move.to}(${move.promotion}): $error',
            lastMoves: _tail(playedMoves, 8),
          ),
        );
        gameFailed = true;
        break;
      }

      if (!moved) {
        failures.add(
          _DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: game.fen,
            message:
                'Engine rejected move ${move.from}-${move.to}(${move.promotion}) after apply.',
            lastMoves: _tail(playedMoves, 8),
          ),
        );
        gameFailed = true;
        break;
      }

      ply += 1;
      playedMoves.add('${move.from}-${move.to}');
      logger?.event(
        'action_applied',
        payload: <String, Object?>{
          'gameIndex': gameIndex,
          'actorColor': side,
          'from': move.from,
          'to': move.to,
          'promotion': move.promotion,
          'fen': game.fen,
        },
        turnIndex: (ply ~/ 2) + 1,
        actionIndexOrPlyIndex: ply,
      );

      final fen = game.fen;
      final legalMoveCount = _safeLegalMoveCount(game);
      final materialSignature = _materialSignatureFromFen(fen);
      if (_hasUnpromotedBackRankPawn(fen)) {
        final weird = _WeirdEvent(
          type: 'promotion_state_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: ChessRules.colorCode(game.turn),
          fen: fen,
          materialSignature: materialSignature,
          legalMoveCount: legalMoveCount,
          materialAdvantageAtCap: null,
          message:
              'Detected pawn on back rank after move apply; treating game as '
              'draw to avoid crashing the soak run.',
          lastMoves: _tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        gameTerminationReason = 'draw_promotion_state_error';
        gameWinner = null;
        break;
      }
      final positionKey = _normalizedPositionKey(fen);
      final repeatedCount = (positionSeenCount[positionKey] ?? 0) + 1;
      positionSeenCount[positionKey] = repeatedCount;
      if (repeatedCount == config.repetitionAlertCount) {
        final weird = _WeirdEvent(
          type: 'state_repetition',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: ChessRules.colorCode(game.turn),
          fen: fen,
          materialSignature: materialSignature,
          legalMoveCount: legalMoveCount,
          materialAdvantageAtCap: null,
          message:
              'Position repeated $repeatedCount times in this game (possible loop).',
          lastMoves: _tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
      }

      final halfmoveClock = _parseHalfmoveClock(fen);
      if (!halfmoveAlerted &&
          halfmoveClock >= config.halfmoveAlertThreshold &&
          gameTerminationReason == null) {
        halfmoveAlerted = true;
        final weird = _WeirdEvent(
          type: 'long_no_progress',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: ChessRules.colorCode(game.turn),
          fen: fen,
          materialSignature: materialSignature,
          legalMoveCount: legalMoveCount,
          materialAdvantageAtCap: null,
          message:
              'Halfmove clock reached $halfmoveClock (long no-capture/no-pawn sequence).',
          lastMoves: _tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
      }

      final stateFailure = _validateBoardState(
        game: game,
        gameIndex: gameIndex,
        ply: ply,
        seed: config.seed,
        sideToMove: ChessRules.colorCode(game.turn),
        playedMoves: playedMoves,
      );
      if (stateFailure != null) {
        failures.add(stateFailure);
        gameFailed = true;
        break;
      }
    }

    if (failures.length > failuresBeforeGame || gameFailed) {
      if (failures.length > failuresBeforeGame) {
        final failure = failures.last;
        logger?.invariantFailure(
          code: invariantSessionTerminationInvalid,
          message: failure.message,
          turnIndex: (failure.ply ~/ 2) + 1,
          actionIndexOrPlyIndex: failure.ply,
          context: <String, Object?>{
            'gameIndex': failure.gameIndex,
            'fen': failure.fen,
            'sideToMove': failure.sideToMove,
          },
        );
      }
      _incrementCount(terminationReasonCounts, 'failure');
      if (config.pgnDirPath != null && gameWeirdEvents.isNotEmpty) {
        _writeWeirdGamePgn(
          pgnDirPath: config.pgnDirPath!,
          game: game,
          gameIndex: gameIndex,
          seed: config.seed,
          weirdEventsForGame: gameWeirdEvents,
          resultTag: '*',
        );
      }
      maybePrintProgress(gameIndex);
      continue;
    }

    if (gameTerminationReason == null && ply >= config.maxPlies) {
      cappedGames += 1;
      wasCapped = true;
      final cappedFen = game.fen;
      final capMaterialAdvantage = _materialAdvantageFromFen(cappedFen);
      final isConversionFailure =
          capMaterialAdvantage.abs() >= config.conversionFailureCapAdvThreshold;
      final leadingSide = capMaterialAdvantage > 0
          ? 'white'
          : capMaterialAdvantage < 0
          ? 'black'
          : 'none';
      final eventType = isConversionFailure
          ? 'conversion_failure'
          : 'ply_cap_reached';
      final eventMessage = isConversionFailure
          ? 'Game reached max plies (${config.maxPlies}) and was capped with '
                '$leadingSide up ${capMaterialAdvantage.abs()} material.'
          : 'Game reached max plies (${config.maxPlies}) and was capped.';

      final weird = _WeirdEvent(
        type: eventType,
        gameIndex: gameIndex,
        seed: config.seed,
        ply: ply,
        sideToMove: ChessRules.colorCode(game.turn),
        fen: cappedFen,
        materialSignature: _materialSignatureFromFen(cappedFen),
        legalMoveCount: _safeLegalMoveCount(game),
        materialAdvantageAtCap: capMaterialAdvantage,
        message: eventMessage,
        lastMoves: _tail(playedMoves, 8),
      );
      weirdEvents.add(weird);
      gameWeirdEvents.add(weird);
      if (isConversionFailure) {
        conversionFailures += 1;
      }
    }

    if (config.pgnDirPath != null && gameWeirdEvents.isNotEmpty) {
      _writeWeirdGamePgn(
        pgnDirPath: config.pgnDirPath!,
        game: game,
        gameIndex: gameIndex,
        seed: config.seed,
        weirdEventsForGame: gameWeirdEvents,
        resultTag: _resultTagForGame(
          wasCapped: wasCapped,
          winner: gameWinner,
          terminationReason: gameTerminationReason,
        ),
      );
    }

    if (wasCapped) {
      _incrementCount(terminationReasonCounts, 'capped');
      maybePrintProgress(gameIndex);
      continue;
    }

    if (gameTerminationReason == null) {
      failures.add(
        _DuelFailure(
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: ChessRules.colorCode(game.turn),
          fen: game.fen,
          message: 'Game ended without terminal reason or cap.',
          lastMoves: _tail(playedMoves, 8),
        ),
      );
      _incrementCount(terminationReasonCounts, 'failure');
      maybePrintProgress(gameIndex);
      continue;
    }

    _incrementCount(terminationReasonCounts, gameTerminationReason);
    if (gameWinner == 'w') {
      whiteWins += 1;
    } else if (gameWinner == 'b') {
      blackWins += 1;
    } else {
      draws += 1;
    }
    maybePrintProgress(gameIndex);
  }

  return _DuelSummary(
    totalGames: config.games,
    whiteWins: whiteWins,
    blackWins: blackWins,
    draws: draws,
    cappedGames: cappedGames,
    failures: failures,
    weirdEvents: weirdEvents,
    terminationReasonCounts: terminationReasonCounts,
    conversionFailures: conversionFailures,
  );
}

String _normalizedPositionKey(String fen) {
  final parts = fen.split(' ');
  if (parts.length < 4) {
    return fen;
  }
  // Threefold repetition should ignore halfmove/fullmove counters.
  return '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';
}

int _parseHalfmoveClock(String fen) {
  final parts = fen.split(' ');
  if (parts.length < 5) {
    return 0;
  }
  return int.tryParse(parts[4]) ?? 0;
}

void _writeWeirdLogFile(String path, List<_WeirdEvent> weirdEvents) {
  final file = File(path);
  if (file.parent.path.isNotEmpty && file.parent.path != '.') {
    file.parent.createSync(recursive: true);
  }

  final buffer = StringBuffer();
  for (final weird in weirdEvents) {
    buffer.writeln(jsonEncode(weird.toJson()));
  }
  file.writeAsStringSync(buffer.toString());
}

void _writeWeirdGamePgn({
  required String pgnDirPath,
  required chess.Chess game,
  required int gameIndex,
  required int seed,
  required List<_WeirdEvent> weirdEventsForGame,
  required String resultTag,
}) {
  final pgnDir = Directory(pgnDirPath);
  pgnDir.createSync(recursive: true);

  final pgnGame = game.copy();
  pgnGame.set_header(<String>[
    'Event',
    'Bullethole Chess AI Duel Weird Game',
    'Site',
    'local',
    'Round',
    gameIndex.toString(),
    'White',
    'DumbAI-White',
    'Black',
    'DumbAI-Black',
    'Result',
    resultTag,
  ]);
  final pgnBody = pgnGame.pgn(<String, dynamic>{'max_width': 100});

  final eventTypes = weirdEventsForGame
      .map((event) => event.type)
      .toSet()
      .join(',');
  final fileName = 'game-${gameIndex.toString().padLeft(4, '0')}.pgn';
  final filePath = _joinPath(pgnDir.path, fileName);
  final output = StringBuffer()
    ..writeln('; AI duel weird game dump')
    ..writeln('; seed: $seed')
    ..writeln('; gameIndex: $gameIndex')
    ..writeln('; weirdTypes: $eventTypes')
    ..writeln('; weirdCount: ${weirdEventsForGame.length}')
    ..writeln('; finalFen: ${game.fen}');

  for (final event in weirdEventsForGame) {
    final capAdvLabel = _formatCapAdvForDisplay(event.materialAdvantageAtCap);
    output.writeln(
      '; [${event.type}] ply=${event.ply} side=${event.sideToMove} '
      'legalMoves=${event.legalMoveCount} material=${event.materialSignature}'
      '$capAdvLabel note=${event.message}',
    );
  }

  output
    ..writeln()
    ..writeln(pgnBody);

  File(filePath).writeAsStringSync(output.toString());
}

void _preparePgnOutputDir(String pgnDirPath) {
  final pgnDir = Directory(pgnDirPath);
  if (!pgnDir.existsSync()) {
    pgnDir.createSync(recursive: true);
    return;
  }

  for (final entity in pgnDir.listSync(recursive: false, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.pgn')) {
      entity.deleteSync();
    }
  }
}

String _joinPath(String left, String right) {
  if (left.endsWith('/') || left.endsWith('\\')) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

String _deriveDefaultPgnDirPath(String logFilePath) {
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
    stem = _defaultPgnDirName;
  }

  final pgnDirName = '$stem-pgn';
  if (parent.trim().isEmpty || parent == '.') {
    return pgnDirName;
  }
  return _joinPath(parent, pgnDirName);
}

String _materialSignatureFromFen(String fen) {
  final board = ChessRules.boardPiecesFromFen(fen);
  final white = <String, int>{'K': 0, 'Q': 0, 'R': 0, 'B': 0, 'N': 0, 'P': 0};
  final black = <String, int>{'K': 0, 'Q': 0, 'R': 0, 'B': 0, 'N': 0, 'P': 0};

  for (final piece in board.values) {
    final type = piece.toUpperCase();
    if (!white.containsKey(type)) {
      continue;
    }
    if (piece == piece.toUpperCase()) {
      white[type] = white[type]! + 1;
    } else {
      black[type] = black[type]! + 1;
    }
  }

  String encode(Map<String, int> counts) {
    return 'K${counts['K']}Q${counts['Q']}R${counts['R']}'
        'B${counts['B']}N${counts['N']}P${counts['P']}';
  }

  return 'w(${encode(white)}) b(${encode(black)})';
}

int _materialAdvantageFromFen(String fen) {
  const pieceValue = <String, int>{
    'K': 0,
    'Q': 9,
    'R': 5,
    'B': 3,
    'N': 3,
    'P': 1,
  };
  final board = ChessRules.boardPiecesFromFen(fen);
  var whiteScore = 0;
  var blackScore = 0;

  for (final piece in board.values) {
    final type = piece.toUpperCase();
    final value = pieceValue[type];
    if (value == null) {
      continue;
    }
    if (piece == piece.toUpperCase()) {
      whiteScore += value;
    } else {
      blackScore += value;
    }
  }

  return whiteScore - blackScore;
}

int _safeLegalMoveCount(chess.Chess game) {
  try {
    return game.moves().length;
  } catch (_) {
    return -1;
  }
}

bool _hasUnpromotedBackRankPawn(String fen) {
  final board = ChessRules.boardPiecesFromFen(fen);
  for (final entry in board.entries) {
    final square = entry.key;
    final piece = entry.value;
    if (piece.toLowerCase() != 'p') {
      continue;
    }
    if (square.endsWith('1') || square.endsWith('8')) {
      return true;
    }
  }
  return false;
}

bool _looksLikePromotionMove({
  required String from,
  required String to,
  required String side,
}) {
  if (from.length != 2 || to.length != 2) {
    return false;
  }
  final fromRank = int.tryParse(from[1]);
  final toRank = int.tryParse(to[1]);
  if (fromRank == null || toRank == null) {
    return false;
  }
  if (side == 'w') {
    return fromRank == 7 && toRank == 8;
  }
  return fromRank == 2 && toRank == 1;
}

String _formatCapAdvForDisplay(int? materialAdvantageAtCap) {
  if (materialAdvantageAtCap == null) {
    return '';
  }
  final sign = materialAdvantageAtCap >= 0 ? '+' : '';
  return ' capAdv=$sign$materialAdvantageAtCap';
}

void _incrementCount(Map<String, int> counts, String key) {
  counts[key] = (counts[key] ?? 0) + 1;
}

String _resultTagForGame({
  required bool wasCapped,
  required String? winner,
  required String? terminationReason,
}) {
  if (wasCapped || terminationReason == null) {
    return '*';
  }
  if (winner == 'w') {
    return '1-0';
  }
  if (winner == 'b') {
    return '0-1';
  }
  if (terminationReason.startsWith('draw_')) {
    return '1/2-1/2';
  }
  return '*';
}

_SafeGameStatus _safeEvaluateGameStatus({
  required chess.Chess game,
  required Map<String, int> positionSeenCount,
}) {
  List<dynamic> legalMoves;
  try {
    legalMoves = game.moves();
  } catch (error) {
    return _SafeGameStatus(error: 'Legal move generation failed: $error');
  }

  if (legalMoves.isEmpty) {
    bool inCheck;
    try {
      inCheck = game.in_check;
    } catch (error) {
      return _SafeGameStatus(error: 'Check status evaluation failed: $error');
    }

    if (inCheck) {
      final checkedSide = ChessRules.colorCode(game.turn);
      final winner = checkedSide == 'w' ? 'b' : 'w';
      final reason = winner == 'w' ? 'checkmate_white' : 'checkmate_black';
      return _SafeGameStatus(terminalReason: reason, winner: winner);
    }
    return const _SafeGameStatus(terminalReason: 'draw_stalemate');
  }

  if (game.half_moves >= 100) {
    return const _SafeGameStatus(terminalReason: 'draw_fifty_move_rule');
  }

  if (_maxPositionRepetition(positionSeenCount) >= 3) {
    return const _SafeGameStatus(terminalReason: 'draw_threefold_repetition');
  }

  if (_isInsufficientMaterialFromFen(game.fen)) {
    return const _SafeGameStatus(terminalReason: 'draw_insufficient_material');
  }

  return const _SafeGameStatus();
}

int _maxPositionRepetition(Map<String, int> positionSeenCount) {
  var maxCount = 0;
  for (final count in positionSeenCount.values) {
    if (count > maxCount) {
      maxCount = count;
    }
  }
  return maxCount;
}

bool _isInsufficientMaterialFromFen(String fen) {
  final board = ChessRules.boardPiecesFromFen(fen);
  final nonKingEntries = board.entries
      .where((entry) => entry.value.toUpperCase() != 'K')
      .toList();
  if (nonKingEntries.isEmpty) {
    return true;
  }

  final pieces = nonKingEntries
      .map((entry) => entry.value.toUpperCase())
      .toList();

  if (pieces.length == 1 && (pieces.first == 'N' || pieces.first == 'B')) {
    return true;
  }

  final hasMajorOrPawn = pieces.any(
    (piece) => piece == 'Q' || piece == 'R' || piece == 'P',
  );
  if (hasMajorOrPawn) {
    return false;
  }

  final allBishops = pieces.every((piece) => piece == 'B');
  if (!allBishops) {
    return false;
  }

  final bishopColors = nonKingEntries
      .map((entry) => _squareColorParity(entry.key))
      .toSet();
  return bishopColors.length == 1;
}

int _squareColorParity(String square) {
  final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
  final rank = int.parse(square.substring(1)) - 1;
  return (file + rank) % 2;
}

_DuelFailure? _validateBoardState({
  required chess.Chess game,
  required int gameIndex,
  required int ply,
  required int seed,
  required String sideToMove,
  required List<String> playedMoves,
}) {
  final pieces = ChessRules.boardPiecesFromFen(game.fen);
  final whiteKings = pieces.values.where((piece) => piece == 'K').length;
  final blackKings = pieces.values.where((piece) => piece == 'k').length;

  if (whiteKings != 1 || blackKings != 1) {
    return _DuelFailure(
      gameIndex: gameIndex,
      seed: seed,
      ply: ply,
      sideToMove: sideToMove,
      fen: game.fen,
      message:
          'Invalid king count (white: $whiteKings, black: $blackKings) after move.',
      lastMoves: _tail(playedMoves, 8),
    );
  }

  if (game.in_checkmate && game.moves().isNotEmpty) {
    return _DuelFailure(
      gameIndex: gameIndex,
      seed: seed,
      ply: ply,
      sideToMove: sideToMove,
      fen: game.fen,
      message: 'Checkmate flagged while legal moves still exist.',
      lastMoves: _tail(playedMoves, 8),
    );
  }

  return null;
}

List<String> _tail(List<String> values, int count) {
  if (values.length <= count) {
    return List<String>.from(values);
  }
  return values.sublist(values.length - count);
}

class _SafeGameStatus {
  const _SafeGameStatus({this.terminalReason, this.winner, this.error});

  final String? terminalReason;
  final String? winner;
  final String? error;

  bool get isTerminal => terminalReason != null;
}

class _DuelConfig {
  const _DuelConfig({
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

  static _DuelConfig parse(List<String> args) {
    var games = _defaultGames;
    var maxPlies = _defaultMaxPlies;
    var seed = _defaultSeed;
    var repetitionAlertCount = _defaultRepetitionAlertCount;
    var halfmoveAlertThreshold = _defaultHalfmoveAlertThreshold;
    var conversionFailureCapAdvThreshold =
        _defaultConversionFailureCapAdvThreshold;
    var maxConversionFailures = _defaultMaxConversionFailures;
    var progressEvery = _defaultProgressEvery;
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
        _printUsageAndExit();
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
      pgnDirPath = _deriveDefaultPgnDirPath(logFilePath);
    }

    return _DuelConfig(
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

class _DuelSummary {
  const _DuelSummary({
    required this.totalGames,
    required this.whiteWins,
    required this.blackWins,
    required this.draws,
    required this.cappedGames,
    required this.failures,
    required this.weirdEvents,
    required this.terminationReasonCounts,
    required this.conversionFailures,
  });

  final int totalGames;
  final int whiteWins;
  final int blackWins;
  final int draws;
  final int cappedGames;
  final int conversionFailures;
  final List<_DuelFailure> failures;
  final List<_WeirdEvent> weirdEvents;
  final Map<String, int> terminationReasonCounts;
}

class _DuelFailure {
  const _DuelFailure({
    required this.gameIndex,
    required this.seed,
    required this.ply,
    required this.sideToMove,
    required this.fen,
    required this.message,
    required this.lastMoves,
  });

  final int gameIndex;
  final int seed;
  final int ply;
  final String sideToMove;
  final String fen;
  final String message;
  final List<String> lastMoves;
}

class _WeirdEvent {
  const _WeirdEvent({
    required this.type,
    required this.gameIndex,
    required this.seed,
    required this.ply,
    required this.sideToMove,
    required this.fen,
    required this.materialSignature,
    required this.legalMoveCount,
    this.materialAdvantageAtCap,
    required this.message,
    required this.lastMoves,
  });

  final String type;
  final int gameIndex;
  final int seed;
  final int ply;
  final String sideToMove;
  final String fen;
  final String materialSignature;
  final int legalMoveCount;
  final int? materialAdvantageAtCap;
  final String message;
  final List<String> lastMoves;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    'gameIndex': gameIndex,
    'seed': seed,
    'ply': ply,
    'sideToMove': sideToMove,
    'fen': fen,
    'materialSignature': materialSignature,
    'legalMoveCount': legalMoveCount,
    'materialAdvantageAtCap': materialAdvantageAtCap,
    'message': message,
    'lastMoves': lastMoves,
  };
}

class _BughuntRunLogger {
  _BughuntRunLogger({
    required this.game,
    required this.mode,
    required this.role,
    required this.seed,
    required this.maxTurns,
    required this.runId,
  }) : _logger = GameSessionLogger(
         applicationId: 'bulletholechess',
         gameId: game,
         mode: mode.name,
         bughuntConfig: BughuntConfig(
           runId: runId ?? 'adhoc_ai_duel',
           mode: mode,
           role: role,
           seed: seed,
           maxTurns: maxTurns,
         ),
       );

  final String game;
  final BughuntMode mode;
  final BughuntRole role;
  final int seed;
  final int maxTurns;
  final String? runId;
  final GameSessionLogger _logger;

  void begin() {
    _logger.beginSession(
      sessionLabel: 'ai_duel',
      context: <String, Object?>{'seed': seed, 'maxTurns': maxTurns},
    );
  }

  void event(
    String eventType, {
    Map<String, Object?> payload = const <String, Object?>{},
    int? turnIndex,
    int? actionIndexOrPlyIndex,
  }) {
    _logger.logBughuntEvent(
      eventType,
      payload: payload,
      turnIndex: turnIndex,
      actionIndexOrPlyIndex: actionIndexOrPlyIndex,
    );
  }

  void invariantFailure({
    required String code,
    required String message,
    required int turnIndex,
    required int actionIndexOrPlyIndex,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    _logger.recordInvariantFailure(
      failureCode: code,
      message: message,
      turnIndex: turnIndex,
      actionIndexOrPlyIndex: actionIndexOrPlyIndex,
      context: context,
    );
  }

  void complete({required _DuelSummary summary}) {
    _logger.closeSession(
      reason: summary.failures.isEmpty ? 'completed' : 'failed',
      summary: <String, Object?>{
        'games': summary.totalGames,
        'whiteWins': summary.whiteWins,
        'blackWins': summary.blackWins,
        'draws': summary.draws,
        'cappedGames': summary.cappedGames,
        'conversionFailures': summary.conversionFailures,
        'failures': summary.failures.length,
      },
    );
  }
}

Never _printUsageAndExit() {
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
