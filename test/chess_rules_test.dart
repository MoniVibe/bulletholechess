import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legalDestinationsFrom returns empty set for invalid square', () {
    final game = chess.Chess();

    final destinations = ChessRules.legalDestinationsFrom(
      game: game,
      square: 'z9',
      color: 'w',
    );

    expect(destinations, isEmpty);
  });

  test('findValidatedLegalMove rejects an unsatisfiable promotion request', () {
    // A promotion square must honor the caller's EXACT requested piece. An
    // invalid/unsupported promotion ('x') must be rejected (null), never
    // silently substituted with a different legal promotion ("played a move I
    // didn't pick" bug). See chess_rules_promotion_fallback_test.dart.
    final game = chess.Chess();
    final loaded = game.load('8/P7/8/8/8/8/8/k6K w - - 0 1');
    expect(loaded, isTrue);

    final substituted = ChessRules.findValidatedLegalMove(
      game: game,
      from: 'a7',
      to: 'a8',
      color: 'w',
      promotion: 'x',
    );
    expect(substituted, isNull);

    // A valid, explicit promotion request returns the exact piece.
    for (final piece in const ['q', 'r', 'b', 'n']) {
      final legalMove = ChessRules.findValidatedLegalMove(
        game: game,
        from: 'a7',
        to: 'a8',
        color: 'w',
        promotion: piece,
      );
      expect(legalMove, isNotNull, reason: 'a7-a8=$piece should be legal');
      expect(legalMove!['from'], 'a7');
      expect(legalMove['to'], 'a8');
      expect(legalMove['promotion'], piece);
    }
  });

  test('movePayloadFromLegalMove excludes promotion when not present', () {
    final payload = ChessRules.movePayloadFromLegalMove(<String, dynamic>{
      'from': 'e2',
      'to': 'e4',
      'promotion': null,
    });

    expect(payload, <String, String>{'from': 'e2', 'to': 'e4'});
  });

  test('movePayloadFromLegalMove includes promotion when present', () {
    final payload = ChessRules.movePayloadFromLegalMove(<String, dynamic>{
      'from': 'a7',
      'to': 'a8',
      'promotion': 'n',
    });

    expect(payload, <String, String>{
      'from': 'a7',
      'to': 'a8',
      'promotion': 'n',
    });
  });

  test(
    'movePayloadFromLegalMove injects fallback promotion when legal move omits promotion field',
    () {
      final game = chess.Chess();
      final loaded = game.load('8/P7/8/8/8/8/8/k6K w - - 0 1');
      expect(loaded, isTrue);

      final legalMove = ChessRules.findValidatedLegalMove(
        game: game,
        from: 'a7',
        to: 'a8',
        color: 'w',
        promotion: ChessRules.defaultPromotion,
      );
      expect(legalMove, isNotNull);

      final payload = ChessRules.movePayloadFromLegalMove(legalMove!);
      expect(payload['promotion'], ChessRules.defaultPromotion);

      final moved = game.move(payload);
      expect(moved, isTrue);
      expect(game.get('a8')?.type.toString().toLowerCase(), contains('q'));
      expect(game.get('a8')?.color, chess.Color.WHITE);
    },
  );

  test('legal king move list excludes adjacent enemy-king squares', () {
    final game = chess.Chess();
    final loaded = game.load('8/8/8/8/8/4k3/8/4K3 w - - 0 1');
    expect(loaded, isTrue);

    final kingTargets = ChessRules.legalDestinationsFrom(
      game: game,
      square: 'e1',
      color: 'w',
    );

    expect(kingTargets.contains('e2'), isFalse);
    expect(kingTargets.contains('d2'), isFalse);
    expect(kingTargets.contains('f2'), isFalse);
  });

  test('checkedKingSquares returns checked king location', () {
    final game = chess.Chess();
    final loaded = game.load('4k3/8/8/8/8/8/4r3/4K3 w - - 0 1');
    expect(loaded, isTrue);

    final squares = ChessRules.checkedKingSquares(game);

    expect(squares, <String>{'e1'});
  });

  test(
    'legal king move list preserves castling when evaluating opposite turn with en-passant marker',
    () {
      final game = chess.Chess();
      final loaded = game.load('r3k2r/8/8/8/8/8/8/R3K2R b KQkq e3 0 1');
      expect(loaded, isTrue);

      final kingTargets = ChessRules.legalDestinationsFrom(
        game: game,
        square: 'e1',
        color: 'w',
      );

      expect(kingTargets.contains('g1'), isTrue);
      expect(kingTargets.contains('c1'), isTrue);
    },
  );

  test(
    'legal move generation tolerates inconsistent turn/en-passant state without throwing',
    () {
      final game = chess.Chess();
      final loaded = game.load('r3k2r/8/8/8/8/8/8/R3K2R b KQkq e3 0 1');
      expect(loaded, isTrue);

      // Simulate a transient engine state where turn and en-passant marker are
      // inconsistent, which previously could throw during cloned FEN loads.
      game.turn = chess.Color.WHITE;

      expect(
        () => ChessRules.legalDestinationsFrom(
          game: game,
          square: 'e1',
          color: 'w',
        ),
        returnsNormally,
      );
    },
  );
}
