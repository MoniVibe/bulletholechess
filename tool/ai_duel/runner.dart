import 'dart:convert';
import 'dart:math';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';
import 'package:chess/chess.dart' as chess;

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';

import 'anomaly_rules.dart';
import 'bughunt_logger.dart';
import 'config.dart';
import 'file_io.dart';
import 'models.dart';

DuelSummary runDuels(DuelConfig config, {BughuntRunLogger? logger}) {
  if (config.pgnDirPath != null) {
    preparePgnOutputDir(config.pgnDirPath!);
  }

  final runRandom = Random(config.seed);
  final failures = <DuelFailure>[];
  final weirdEvents = <WeirdEvent>[];
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
    final gameWeirdEvents = <WeirdEvent>[];
    var wasCapped = false;
    var gameFailed = false;
    String? gameTerminationReason;
    String? gameWinner;
    final initialPositionKey = normalizedPositionKey(game.fen);
    final positionSeenCount = <String, int>{initialPositionKey: 1};
    var halfmoveAlerted = false;

    while (ply < config.maxPlies) {
      final fenAtTurnStart = game.fen;
      if (hasUnpromotedBackRankPawn(fenAtTurnStart)) {
        final weird = WeirdEvent(
          type: 'promotion_state_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: ChessRules.colorCode(game.turn),
          fen: fenAtTurnStart,
          materialSignature: materialSignatureFromFen(fenAtTurnStart),
          legalMoveCount: safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message:
              'Detected pawn on back rank at turn start; treating game as '
              'draw to avoid crashing the soak run.',
          lastMoves: tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        gameTerminationReason = 'draw_promotion_state_error';
        gameWinner = null;
        break;
      }

      final status = safeEvaluateGameStatus(
        game: game,
        positionSeenCount: positionSeenCount,
      );
      if (status.error != null) {
        final fen = game.fen;
        final weird = WeirdEvent(
          type: 'engine_state_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: ChessRules.colorCode(game.turn),
          fen: fen,
          materialSignature: materialSignatureFromFen(fen),
          legalMoveCount: safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message: status.error!,
          lastMoves: tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        failures.add(
          DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: ChessRules.colorCode(game.turn),
            fen: fen,
            message: status.error!,
            lastMoves: tail(playedMoves, 8),
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
        final weird = WeirdEvent(
          type: 'engine_state_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: side,
          fen: fen,
          materialSignature: materialSignatureFromFen(fen),
          legalMoveCount: safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message: message,
          lastMoves: tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        failures.add(
          DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: fen,
            message: message,
            lastMoves: tail(playedMoves, 8),
          ),
        );
        gameFailed = true;
        break;
      }

      if (move == null) {
        failures.add(
          DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: game.fen,
            message: 'AI returned null despite legal moves existing.',
            lastMoves: tail(playedMoves, 8),
          ),
        );
        gameFailed = true;
        break;
      }

      Map<String, String> movePayload = <String, String>{
        'from': move.from,
        'to': move.to,
      };
      if (looksLikePromotionMove(from: move.from, to: move.to, side: side)) {
        movePayload['promotion'] = move.promotion;
      }
      final currentSideBeforeApply = ChessRules.colorCode(game.turn);
      if (currentSideBeforeApply != side) {
        final fen = game.fen;
        final weird = WeirdEvent(
          type: 'turn_desync',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: currentSideBeforeApply,
          fen: fen,
          materialSignature: materialSignatureFromFen(fen),
          legalMoveCount: safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message:
              'Turn drift detected before apply; expected $side but saw '
              '$currentSideBeforeApply. Resyncing turn to $side.',
          lastMoves: tail(playedMoves, 8),
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
          if (looksLikePromotionMove(
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
          final weird = WeirdEvent(
            type: 'legal_validation_miss',
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: fen,
            materialSignature: materialSignatureFromFen(fen),
            legalMoveCount: safeLegalMoveCount(game),
            materialAdvantageAtCap: null,
            message:
                'Validation did not find ${move.from}-${move.to}'
                '(${move.promotion}); trying direct apply.',
            lastMoves: tail(playedMoves, 8),
          );
          weirdEvents.add(weird);
          gameWeirdEvents.add(weird);
        }
      } catch (error) {
        final fen = game.fen;
        final weird = WeirdEvent(
          type: 'legal_validation_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: side,
          fen: fen,
          materialSignature: materialSignatureFromFen(fen),
          legalMoveCount: safeLegalMoveCount(game),
          materialAdvantageAtCap: null,
          message: 'Legal move validation failed: $error; trying direct apply.',
          lastMoves: tail(playedMoves, 8),
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
        final legalMoveCountAtError = safeLegalMoveCount(game);
        final weird = WeirdEvent(
          type: 'move_apply_error',
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: side,
          fen: fen,
          materialSignature: materialSignatureFromFen(fen),
          legalMoveCount: legalMoveCountAtError,
          materialAdvantageAtCap: null,
          message:
              'Engine threw while applying move payload '
              '${jsonEncode(movePayload)}: $error',
          lastMoves: tail(playedMoves, 8),
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
          DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: fen,
            message:
                'Engine threw while applying move '
                '${move.from}-${move.to}(${move.promotion}): $error',
            lastMoves: tail(playedMoves, 8),
          ),
        );
        gameFailed = true;
        break;
      }

      if (!moved) {
        failures.add(
          DuelFailure(
            gameIndex: gameIndex,
            seed: config.seed,
            ply: ply,
            sideToMove: side,
            fen: game.fen,
            message:
                'Engine rejected move ${move.from}-${move.to}(${move.promotion}) after apply.',
            lastMoves: tail(playedMoves, 8),
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
      final legalMoveCount = safeLegalMoveCount(game);
      final materialSignature = materialSignatureFromFen(fen);
      if (hasUnpromotedBackRankPawn(fen)) {
        final weird = WeirdEvent(
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
          lastMoves: tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
        gameTerminationReason = 'draw_promotion_state_error';
        gameWinner = null;
        break;
      }
      final positionKey = normalizedPositionKey(fen);
      final repeatedCount = (positionSeenCount[positionKey] ?? 0) + 1;
      positionSeenCount[positionKey] = repeatedCount;
      if (repeatedCount == config.repetitionAlertCount) {
        final weird = WeirdEvent(
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
          lastMoves: tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
      }

      final halfmoveClock = parseHalfmoveClock(fen);
      if (!halfmoveAlerted &&
          halfmoveClock >= config.halfmoveAlertThreshold &&
          gameTerminationReason == null) {
        halfmoveAlerted = true;
        final weird = WeirdEvent(
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
          lastMoves: tail(playedMoves, 8),
        );
        weirdEvents.add(weird);
        gameWeirdEvents.add(weird);
      }

      final stateFailure = validateBoardState(
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
      incrementCount(terminationReasonCounts, 'failure');
      if (config.pgnDirPath != null && gameWeirdEvents.isNotEmpty) {
        writeWeirdGamePgn(
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
      final capMaterialAdvantage = materialAdvantageFromFen(cappedFen);
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

      final weird = WeirdEvent(
        type: eventType,
        gameIndex: gameIndex,
        seed: config.seed,
        ply: ply,
        sideToMove: ChessRules.colorCode(game.turn),
        fen: cappedFen,
        materialSignature: materialSignatureFromFen(cappedFen),
        legalMoveCount: safeLegalMoveCount(game),
        materialAdvantageAtCap: capMaterialAdvantage,
        message: eventMessage,
        lastMoves: tail(playedMoves, 8),
      );
      weirdEvents.add(weird);
      gameWeirdEvents.add(weird);
      if (isConversionFailure) {
        conversionFailures += 1;
      }
    }

    if (config.pgnDirPath != null && gameWeirdEvents.isNotEmpty) {
      writeWeirdGamePgn(
        pgnDirPath: config.pgnDirPath!,
        game: game,
        gameIndex: gameIndex,
        seed: config.seed,
        weirdEventsForGame: gameWeirdEvents,
        resultTag: resultTagForGame(
          wasCapped: wasCapped,
          winner: gameWinner,
          terminationReason: gameTerminationReason,
        ),
      );
    }

    if (wasCapped) {
      incrementCount(terminationReasonCounts, 'capped');
      maybePrintProgress(gameIndex);
      continue;
    }

    if (gameTerminationReason == null) {
      failures.add(
        DuelFailure(
          gameIndex: gameIndex,
          seed: config.seed,
          ply: ply,
          sideToMove: ChessRules.colorCode(game.turn),
          fen: game.fen,
          message: 'Game ended without terminal reason or cap.',
          lastMoves: tail(playedMoves, 8),
        ),
      );
      incrementCount(terminationReasonCounts, 'failure');
      maybePrintProgress(gameIndex);
      continue;
    }

    incrementCount(terminationReasonCounts, gameTerminationReason);
    if (gameWinner == 'w') {
      whiteWins += 1;
    } else if (gameWinner == 'b') {
      blackWins += 1;
    } else {
      draws += 1;
    }
    maybePrintProgress(gameIndex);
  }

  return DuelSummary(
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
