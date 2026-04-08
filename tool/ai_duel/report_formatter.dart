import 'models.dart';

List<String> formatSummaryLines({
  required DuelSummary summary,
  required int seed,
  required int maxPlies,
  required int conversionFailureCapAdvThreshold,
}) {
  final lines = <String>[
    'AI duel summary:',
    '  games: ${summary.totalGames}',
    '  white wins: ${summary.whiteWins}',
    '  black wins: ${summary.blackWins}',
    '  draws: ${summary.draws}',
    '  capped games: ${summary.cappedGames}',
    '  seed: $seed',
    '  max plies: $maxPlies',
    '  weird logs: ${summary.weirdEvents.length}',
    '  conversion failures: ${summary.conversionFailures} '
        '(capAdv abs >= $conversionFailureCapAdvThreshold)',
    '  termination reasons:',
  ];

  final terminationEntries = summary.terminationReasonCounts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in terminationEntries) {
    lines.add('    ${entry.key}: ${entry.value}');
  }

  if (summary.weirdEvents.isNotEmpty) {
    lines.add('');
    lines.add('Weird logs:');
    for (final weird in summary.weirdEvents) {
      final capAdvLabel = formatCapAdvForDisplay(weird.materialAdvantageAtCap);
      lines.add(
        '  [${weird.type}] game=${weird.gameIndex} ply=${weird.ply} '
        'side=${weird.sideToMove} legalMoves=${weird.legalMoveCount} '
        'material=${weird.materialSignature}$capAdvLabel note=${weird.message}',
      );
    }
  }

  return lines;
}

List<String> formatFailureLines(List<DuelFailure> failures) {
  final lines = <String>[];
  for (final failure in failures) {
    lines.add('');
    lines.add('Failure in game #${failure.gameIndex}: ${failure.message}');
    lines.add('  seed: ${failure.seed}');
    lines.add('  ply: ${failure.ply}');
    lines.add('  side to move: ${failure.sideToMove}');
    lines.add('  fen: ${failure.fen}');
    if (failure.lastMoves.isNotEmpty) {
      lines.add('  recent moves: ${failure.lastMoves.join(', ')}');
    }
  }
  return lines;
}

String formatCapAdvForDisplay(int? materialAdvantageAtCap) {
  if (materialAdvantageAtCap == null) {
    return '';
  }
  final sign = materialAdvantageAtCap >= 0 ? '+' : '';
  return ' capAdv=$sign$materialAdvantageAtCap';
}
