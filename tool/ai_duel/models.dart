class DuelSummary {
  const DuelSummary({
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
  final List<DuelFailure> failures;
  final List<WeirdEvent> weirdEvents;
  final Map<String, int> terminationReasonCounts;
}

class DuelFailure {
  const DuelFailure({
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

class WeirdEvent {
  const WeirdEvent({
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

class SafeGameStatus {
  const SafeGameStatus({this.terminalReason, this.winner, this.error});

  final String? terminalReason;
  final String? winner;
  final String? error;

  bool get isTerminal => terminalReason != null;
}
