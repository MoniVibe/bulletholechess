import 'dart:math';

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dumb AI does not throw on nightly regression positions', () {
    const failingFens = <String>[
      'rn2P1kr/ppp3p1/8/7p/P1bP4/5Q2/1PP2PPP/RNB1K1NR b - - 0 17',
      '8/1N4kr/p7/1p1KP3/P6p/8/P1R5/8 b - - 0 48',
      '6k1/8/2P5/5P2/7p/8/4K3/8 b - - 0 31',
      '8/8/8/4B1k1/8/8/4P3/4K3 b - - 0 55',
    ];

    for (final fen in failingFens) {
      final game = chess.Chess();
      expect(game.load(fen), isTrue, reason: 'failed to load FEN: $fen');

      for (var i = 0; i < 8; i += 1) {
        final ai = DumbAiEngine(random: Random(i + 1));
        EngineMove? selectedMove;
        expect(
          () => selectedMove = ai.chooseMove(game),
          returnsNormally,
          reason: 'chooseMove threw for fen=$fen seed=${i + 1}',
        );

        if (selectedMove != null) {
          final legalMove = ChessRules.findValidatedLegalMove(
            game: game,
            from: selectedMove!.from,
            to: selectedMove!.to,
            color: ChessRules.colorCode(game.turn),
            promotion: selectedMove!.promotion,
          );
          expect(
            legalMove,
            isNotNull,
            reason:
                'AI emitted non-legal move for fen=$fen move='
                '${selectedMove!.from}-${selectedMove!.to}',
          );
        }
      }
    }
  });
}
