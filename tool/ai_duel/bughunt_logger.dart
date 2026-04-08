import 'package:bullethole_shared/bullethole_shared_runtime.dart';

import 'models.dart';

class BughuntRunLogger {
  BughuntRunLogger({
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

  void complete({required DuelSummary summary}) {
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
