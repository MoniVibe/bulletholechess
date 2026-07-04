// Characterization + regression test for the promotion-mismatch fallback in
// ChessRules.findValidatedLegalMove (~105) and movePayloadFromLegalMove's
// fallback-to-queen.
//
// The suspected "played a move I didn't pick" bug: when a caller requests a
// promotion move whose exact promotion piece is NOT among the legal candidates,
// findValidatedLegalMove used to return legalMoves.first — i.e. silently execute
// a DIFFERENT legal promotion (whatever the move generator listed first) rather
// than rejecting. This test pins down the required contract: for a promotion
// (from,to) the engine must return the move for the EXACT requested piece, and
// must NOT substitute a different promotion piece when the request is
// unsatisfiable.

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

// A position where White has a pawn on b7 that can promote by capturing on a8
// or c8, or pushing to b8. Black has rooks on a8/c8 to enable capture-promotions.
// White king e1, black king e8.
const String _promoFen = 'r1r1k3/1P6/8/8/8/8/8/4K3 w - - 0 1';

void main() {
  test('exact promotion request returns the exact promotion move', () {
    final game = chess.Chess();
    expect(game.load(_promoFen), isTrue);

    for (final piece in const ['q', 'r', 'b', 'n']) {
      final move = ChessRules.findValidatedLegalMove(
        game: game,
        from: 'b7',
        to: 'b8',
        color: 'w',
        promotion: piece,
      );
      expect(move, isNotNull, reason: 'b7-b8=$piece should be legal');
      expect(
        move!['promotion'],
        piece,
        reason: 'requested $piece must return $piece, not a substitute',
      );
      final payload = ChessRules.movePayloadFromLegalMove(move);
      expect(payload['promotion'], piece);
    }
  });

  test(
    'unsatisfiable promotion request does NOT silently substitute a different '
    'promotion move',
    () {
      final game = chess.Chess();
      expect(game.load(_promoFen), isTrue);

      // Request an invalid promotion piece ('k' - cannot promote to king, and
      // not in the legal list). The engine must NOT return some other promotion
      // move (e.g. queen) as if the player had picked it.
      final move = ChessRules.findValidatedLegalMove(
        game: game,
        from: 'b7',
        to: 'b8',
        color: 'w',
        promotion: 'k',
      );

      if (move != null) {
        final returnedPromotion = move['promotion'];
        // If a move is returned at all for a promotion square, it must not be a
        // silently-chosen DIFFERENT promotion piece. A null promotion here would
        // mean a non-promoting move on a promotion square, which is impossible
        // for b7-b8, so that too would be wrong.
        fail(
          'Unsatisfiable promotion "k" for b7-b8 must be rejected (null), but '
          'got a substituted move with promotion=$returnedPromotion. This is '
          'the "played a move I did not pick" bug.',
        );
      }

      expect(
        move,
        isNull,
        reason: 'unsatisfiable promotion request must be rejected, not '
            'silently substituted',
      );
    },
  );

  test('non-promotion moves are unaffected by the stricter contract', () {
    final game = chess.Chess();
    // Standard opening position: e2-e4 is a normal, non-promotion move. Passing
    // a bogus promotion string must not break a legal non-promotion move.
    final move = ChessRules.findValidatedLegalMove(
      game: game,
      from: 'e2',
      to: 'e4',
      color: 'w',
      promotion: 'k',
    );
    expect(move, isNotNull);
    expect(move!['promotion'], isNull);
  });
}
