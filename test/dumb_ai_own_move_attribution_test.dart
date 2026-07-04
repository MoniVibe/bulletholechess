import 'dart:math';

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

/// Bug B regression: `_collectOwnMoveStats` used index parity (`i.isEven`) to
/// label each history ply's color. In this variant a side can move twice in a
/// row, after which every later parity label is wrong, so the AI's own-move
/// repetition penalties are computed against a mislabeled history.
///
/// Here white pushes the d-pawn twice in a row (d2->d4, then d4->d5). It is
/// white to move. Both plies belong to white, so both must appear in white's
/// own-move counts. Under the parity bug the second push (odd index) is
/// mislabeled black and dropped.
void main() {
  test('same-color double-move attributes both plies to the mover', () {
    final game = chess.Chess();

    // White moves twice in a row via withTurn, exactly how the variant applies
    // out-of-alternation moves.
    ChessRules.withTurn<void>(game, 'w', () {
      expect(game.move(<String, String>{'from': 'd2', 'to': 'd4'}), isTrue);
    });
    ChessRules.withTurn<void>(game, 'w', () {
      expect(game.move(<String, String>{'from': 'd4', 'to': 'd5'}), isTrue);
    });

    // After two white moves the package turn is back to white.
    expect(game.turn, chess.Color.WHITE);

    final ai = DumbAiEngine(random: Random(1));
    final counts = ai.debugOwnMoveCounts(game);

    // Both of white's plies belong to white and must be counted.
    expect(
      counts['d2-d4'],
      1,
      reason: 'first white push must be attributed to white',
    );
    expect(
      counts['d4-d5'],
      1,
      reason:
          'second white push must be attributed to white, not dropped as black',
    );
  });
}
