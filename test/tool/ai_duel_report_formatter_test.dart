import 'package:flutter_test/flutter_test.dart';

import '../../tool/ai_duel/models.dart';
import '../../tool/ai_duel/report_formatter.dart';

void main() {
  test('formatSummaryLines is deterministic and sorts termination reasons', () {
    const summary = DuelSummary(
      totalGames: 3,
      whiteWins: 1,
      blackWins: 1,
      draws: 1,
      cappedGames: 0,
      conversionFailures: 2,
      failures: <DuelFailure>[],
      weirdEvents: <WeirdEvent>[
        WeirdEvent(
          type: 'conversion_failure',
          gameIndex: 2,
          seed: 7,
          ply: 240,
          sideToMove: 'b',
          fen: 'fen',
          materialSignature: 'w(K1Q1R2B2N2P8) b(K1Q1R2B2N2P8)',
          legalMoveCount: 31,
          materialAdvantageAtCap: 5,
          message: 'capped',
          lastMoves: <String>['e2-e4'],
        ),
      ],
      terminationReasonCounts: <String, int>{
        'draw_stalemate': 1,
        'checkmate_white': 1,
        'capped': 1,
      },
    );

    final first = formatSummaryLines(
      summary: summary,
      seed: 7,
      maxPlies: 240,
      conversionFailureCapAdvThreshold: 5,
    );
    final second = formatSummaryLines(
      summary: summary,
      seed: 7,
      maxPlies: 240,
      conversionFailureCapAdvThreshold: 5,
    );

    expect(first, second);
    expect(
      first,
      containsAllInOrder(<String>[
        '    capped: 1',
        '    checkmate_white: 1',
        '    draw_stalemate: 1',
      ]),
    );
    expect(
      first,
      contains(
        '  [conversion_failure] game=2 ply=240 side=b legalMoves=31 '
        'material=w(K1Q1R2B2N2P8) b(K1Q1R2B2N2P8) capAdv=+5 note=capped',
      ),
    );
  });

  test('formatFailureLines emits stable multi-line output', () {
    const failures = <DuelFailure>[
      DuelFailure(
        gameIndex: 9,
        seed: 20260226,
        ply: 12,
        sideToMove: 'w',
        fen: 'fen-here',
        message: 'boom',
        lastMoves: <String>['e2-e4', 'e7-e5'],
      ),
    ];

    final lines = formatFailureLines(failures);

    expect(lines, <String>[
      '',
      'Failure in game #9: boom',
      '  seed: 20260226',
      '  ply: 12',
      '  side to move: w',
      '  fen: fen-here',
      '  recent moves: e2-e4, e7-e5',
    ]);
  });
}
