// Seeded fuzz / property test for the out-of-turn ("cooldown-based simultaneous")
// chess variant. The stock property test (chess_rules_property_test.dart) asserts
// strict White/Black alternation and therefore never exercises the variant apply
// path where a side moves while the engine thinks it is the other side's turn.
//
// This test drives the SAME facade the live controllers use to apply out-of-turn
// moves:
//   ChessRules.findValidatedLegalMove(...) -> ChessRules.applyValidatedLegalMoveForColor(...)
// and it replicates the controllers' post-move ownership-revert guard verbatim
// (see LocalGameController._applyMove ~449 and ChessAiGameController ~569) so the
// shipped behaviour, guard included, is under test.
//
// The scheduler deliberately produces the scenarios the alternation-asserting test
// cannot reach: same-side double moves and out-of-turn bursts (both colors moving
// regardless of engine turn). On EVERY applied ply it asserts:
//   (a) every occupied square holds a piece of a valid color (w/b);
//   (b) the piece on the destination is owned by the mover (no ownership flip);
//   (c) total piece count is non-increasing except via legal promotion (count
//       preserved); no destination gains a piece unless the source clears
//       (no phantom / duplicate pieces);
//   (d) exactly one king per side at all times.
//
// A fixed seed list keeps failures deterministic and reproducible, and the test
// asserts (non-vacuously) that the generator actually produced same-side doubles
// and out-of-turn moves so a green result is meaningful coverage, not a no-op.

import 'dart:math';

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('variant out-of-turn apply path holds ownership/phantom invariants', () {
    final seeds = List<int>.generate(220, (i) => i + 1);
    final agg = _CoverageAggregate();

    for (final seed in seeds) {
      final result = _simulateVariant(seed: seed, maxPlies: 320);
      agg.add(result);
    }

    // Non-vacuity: prove the generator actually exercised the variant scenarios
    // the alternation-asserting property test can never reach. If these are zero,
    // a green run proves nothing, so fail loudly.
    expect(
      agg.sameSideDoubles,
      greaterThan(0),
      reason: 'Generator must produce same-side double moves to be meaningful.',
    );
    expect(
      agg.outOfTurnMoves,
      greaterThan(0),
      reason: 'Generator must produce out-of-turn moves to be meaningful.',
    );
    // Also require they be substantial, not a lone accident.
    expect(agg.sameSideDoubles, greaterThan(1000));
    expect(agg.outOfTurnMoves, greaterThan(1000));

    // Emit coverage so the run's meaning is visible in test output.
    // ignore: avoid_print
    print(
      'variant-fuzz coverage: seeds=${seeds.length} '
      'appliedPlies=${agg.appliedPlies} '
      'outOfTurnMoves=${agg.outOfTurnMoves} '
      'sameSideDoubles=${agg.sameSideDoubles} '
      'sameSideRuns(len>=3)=${agg.longSameSideRuns} '
      'promotions=${agg.promotions} '
      'guardReverts=${agg.guardReverts} '
      'maxPliesInAGame=${agg.maxPliesInAGame}',
    );
  });

  test('same seed reproduces identical variant playout', () {
    final a = _simulateVariant(seed: 4242, maxPlies: 300);
    final b = _simulateVariant(seed: 4242, maxPlies: 300);
    expect(a.finalFen, b.finalFen);
    expect(a.fenSequence, b.fenSequence);
    expect(a.appliedPlies, b.appliedPlies);
  });
}

/// Simulate one seeded variant game through the real out-of-turn apply facade.
_GameResult _simulateVariant({required int seed, required int maxPlies}) {
  final random = Random(seed);
  final game = chess.Chess();
  final fenSequence = <String>[game.fen];

  var appliedPlies = 0;
  var outOfTurnMoves = 0;
  var sameSideDoubles = 0;
  var longSameSideRuns = 0;
  var promotions = 0;
  var guardReverts = 0;

  String? lastMover;
  var currentRunLen = 0;

  for (var ply = 0; ply < maxPlies; ply += 1) {
    _assertInvariantsStandalone(game, seed: seed, ply: ply);

    // Variant scheduler: choose which color moves NOW, ignoring engine turn.
    // Bias hard toward same-side repeats so we manufacture same-side doubles and
    // out-of-turn bursts. Roughly: 55% keep the same mover (double/burst), else
    // pick a fresh color at random. This intentionally desyncs from engine turn.
    final String mover;
    if (lastMover != null && random.nextInt(100) < 55) {
      mover = lastMover; // repeat -> same-side double / burst
    } else {
      mover = random.nextBool() ? 'w' : 'b';
    }

    // Does this side have any legal move right now (out of turn is fine)?
    final verboseMoves = _legalVerboseMoves(game, mover);
    if (verboseMoves.isEmpty) {
      // Try the other color; if neither can move, game is dead-locked -> stop.
      final other = ChessRules.oppositeColor(mover);
      final otherMoves = _legalVerboseMoves(game, other);
      if (otherMoves.isEmpty) {
        break;
      }
      // fall through with the other color as mover
      final picked = otherMoves[random.nextInt(otherMoves.length)];
      final outcome = _applyOneMove(
        game: game,
        mover: other,
        chosen: picked,
        random: random,
      );
      if (outcome == _MoveOutcome.guardReverted) guardReverts += 1;
      if (outcome != _MoveOutcome.applied) continue;
      appliedPlies += 1;
      if (picked.isPromotion) promotions += 1;
      final wasOutOfTurn = outcome == _MoveOutcome.applied &&
          _wasOutOfTurn(fenSequence.last, other);
      if (wasOutOfTurn) outOfTurnMoves += 1;
      _updateRun(
        mover: other,
        lastMover: lastMover,
        onSameSideDouble: () => sameSideDoubles += 1,
      );
      if (lastMover == other) {
        currentRunLen += 1;
        if (currentRunLen == 3) longSameSideRuns += 1;
      } else {
        currentRunLen = 1;
      }
      lastMover = other;
      _assertInvariantsAfterMove(
        before: fenSequence.last,
        game: game,
        mover: other,
        chosen: picked,
        seed: seed,
        ply: ply,
      );
      fenSequence.add(game.fen);
      continue;
    }

    final beforeFen = game.fen;
    final chosen = verboseMoves[random.nextInt(verboseMoves.length)];
    final outcome = _applyOneMove(
      game: game,
      mover: mover,
      chosen: chosen,
      random: random,
    );
    if (outcome == _MoveOutcome.guardReverted) {
      guardReverts += 1;
      // Guard rejected: board must be unchanged; do not count as a ply.
      expect(
        game.fen,
        beforeFen,
        reason: 'seed=$seed ply=$ply guard revert must restore prior FEN',
      );
      continue;
    }
    if (outcome != _MoveOutcome.applied) {
      continue;
    }

    appliedPlies += 1;
    if (chosen.isPromotion) promotions += 1;

    final wasOutOfTurn = _wasOutOfTurn(beforeFen, mover);
    if (wasOutOfTurn) outOfTurnMoves += 1;

    if (lastMover == mover) {
      sameSideDoubles += 1;
      currentRunLen += 1;
      if (currentRunLen == 3) longSameSideRuns += 1;
    } else {
      currentRunLen = 1;
    }
    lastMover = mover;

    _assertInvariantsAfterMove(
      before: beforeFen,
      game: game,
      mover: mover,
      chosen: chosen,
      seed: seed,
      ply: ply,
    );
    fenSequence.add(game.fen);
  }

  _assertInvariantsStandalone(game, seed: seed, ply: maxPlies);

  return _GameResult(
    finalFen: game.fen,
    fenSequence: fenSequence,
    appliedPlies: appliedPlies,
    outOfTurnMoves: outOfTurnMoves,
    sameSideDoubles: sameSideDoubles,
    longSameSideRuns: longSameSideRuns,
    promotions: promotions,
    guardReverts: guardReverts,
  );
}

enum _MoveOutcome { applied, rejected, guardReverted }

/// Apply exactly one out-of-turn move through the production facade, replicating
/// the controllers' post-move ownership-revert guard verbatim.
_MoveOutcome _applyOneMove({
  required chess.Chess game,
  required String mover,
  required _Move chosen,
  required Random random,
}) {
  final legalMove = ChessRules.findValidatedLegalMove(
    game: game,
    from: chosen.from,
    to: chosen.to,
    color: mover,
    promotion: chosen.promotion ?? ChessRules.defaultPromotion,
  );
  if (legalMove == null) {
    return _MoveOutcome.rejected;
  }

  final previousFen = game.fen;
  final payload = ChessRules.movePayloadFromLegalMove(
    legalMove,
    fallbackPromotion: chosen.promotion ?? ChessRules.defaultPromotion,
  );
  final moved = ChessRules.applyValidatedLegalMoveForColor(
    game: game,
    legalMove: legalMove,
    color: mover,
    promotion: payload['promotion'] ?? ChessRules.defaultPromotion,
  );
  if (!moved) {
    return _MoveOutcome.rejected;
  }

  // Verbatim controller guard: destination must hold a piece of the mover.
  final movedPiece = game.get(chosen.to);
  final movedPieceColor =
      movedPiece == null ? null : ChessRules.colorCode(movedPiece.color);
  if (movedPieceColor != mover) {
    game.load(previousFen);
    return _MoveOutcome.guardReverted;
  }

  return _MoveOutcome.applied;
}

List<_Move> _legalVerboseMoves(chess.Chess game, String color) {
  final cloned = _cloneForColorPublicMirror(game, color);
  if (cloned == null) {
    return const <_Move>[];
  }
  return cloned
      .moves(<String, dynamic>{'verbose': true})
      .map((dynamic item) => Map<String, dynamic>.from(item as Map))
      .map(
        (m) => _Move(
          from: m['from'] as String,
          to: m['to'] as String,
          promotion: m['promotion'] as String?,
          flags: m['flags'] as String?,
          san: m['san'] as String?,
        ),
      )
      .toList();
}

/// Mirror of ChessRules._cloneForColor for move *enumeration* only. We cannot
/// call the private method, but enumerating legal candidate moves for a color is
/// exactly the "rewrite the FEN turn field and reload" operation the variant uses
/// under the hood; findValidatedLegalMove/applyValidatedLegalMoveForColor remain
/// the real apply path (they call the private clone internally). This mirror only
/// picks candidate (from,to) pairs to feed into that real path.
chess.Chess? _cloneForColorPublicMirror(chess.Chess game, String color) {
  final fen = game.fen;
  final parts = fen.split(' ');
  if (parts.length < 6) return null;
  final normalized = color.trim().toLowerCase() == 'w' ? 'w' : 'b';
  parts[1] = normalized;
  parts[3] = '-'; // conservative: drop en-passant when forcing turn
  final cloned = chess.Chess();
  if (cloned.load(parts.join(' '))) {
    return cloned;
  }
  return null;
}

bool _wasOutOfTurn(String beforeFen, String mover) {
  final parts = beforeFen.split(' ');
  if (parts.length < 2) return false;
  return parts[1] != mover;
}

void _updateRun({
  required String mover,
  required String? lastMover,
  required void Function() onSameSideDouble,
}) {
  if (lastMover == mover) {
    onSameSideDouble();
  }
}

// --- Invariant assertions ---------------------------------------------------

void _assertInvariantsStandalone(
  chess.Chess game, {
  required int seed,
  required int ply,
}) {
  final board = ChessRules.boardPiecesFromFen(game.fen);

  // (a) every occupied square holds a piece of a valid color.
  for (final entry in board.entries) {
    final symbol = entry.value;
    final valid = 'pnbrqkPNBRQK'.contains(symbol);
    expect(
      valid,
      isTrue,
      reason: 'seed=$seed ply=$ply square ${entry.key} has invalid symbol '
          '"$symbol" fen=${game.fen}',
    );
  }

  // (d) exactly one king per side.
  final whiteKings = board.values.where((p) => p == 'K').length;
  final blackKings = board.values.where((p) => p == 'k').length;
  expect(
    whiteKings,
    1,
    reason: 'seed=$seed ply=$ply white king count=$whiteKings fen=${game.fen}',
  );
  expect(
    blackKings,
    1,
    reason: 'seed=$seed ply=$ply black king count=$blackKings fen=${game.fen}',
  );
}

void _assertInvariantsAfterMove({
  required String before,
  required chess.Chess game,
  required String mover,
  required _Move chosen,
  required int seed,
  required int ply,
}) {
  final beforeBoard = ChessRules.boardPiecesFromFen(before);
  final afterBoard = ChessRules.boardPiecesFromFen(game.fen);

  _assertInvariantsStandalone(game, seed: seed, ply: ply);

  // (b) the piece on the destination is owned by the mover (no ownership flip).
  final destSymbol = afterBoard[chosen.to];
  expect(
    destSymbol,
    isNotNull,
    reason: 'seed=$seed ply=$ply mover=$mover ${chosen.from}->${chosen.to} '
        'destination empty after move. before=$before after=${game.fen}',
  );
  final destOwner = ChessRules.pieceColor(destSymbol!);
  expect(
    destOwner,
    mover,
    reason: 'OWNERSHIP FLIP: seed=$seed ply=$ply mover=$mover '
        '${chosen.from}->${chosen.to} landed a $destOwner piece ($destSymbol). '
        'before=$before after=${game.fen}',
  );

  // (c1) piece count non-increasing except promotion keeps it equal.
  final beforeCount = beforeBoard.length;
  final afterCount = afterBoard.length;
  expect(
    afterCount,
    lessThanOrEqualTo(beforeCount),
    reason: 'PHANTOM PIECE: seed=$seed ply=$ply piece count grew '
        '$beforeCount -> $afterCount. mover=$mover '
        '${chosen.from}->${chosen.to} before=$before after=${game.fen}',
  );

  // (c2) source square must have cleared (no duplicate left behind), unless the
  // move was castling (rook+king both move) or en-passant; for those the FEN
  // still cannot leave the original from-square occupied by the same piece.
  final sourceStillOccupied = afterBoard.containsKey(chosen.from);
  if (sourceStillOccupied) {
    // The only legitimate way a from-square is still occupied is if a DIFFERENT
    // piece slid into it in the same ply, which cannot happen in one move. So a
    // still-occupied source with the same piece as before is a duplicate.
    final sameAsBefore = beforeBoard[chosen.from] == afterBoard[chosen.from];
    expect(
      sameAsBefore,
      isFalse,
      reason: 'DUPLICATE PIECE: seed=$seed ply=$ply source ${chosen.from} still '
          'holds its original piece after moving to ${chosen.to}. '
          'before=$before after=${game.fen}',
    );
  }

  // (c3) A non-capture, non-promotion move must preserve exact piece count.
  final wasCapture = (chosen.flags ?? '').contains('c') ||
      (chosen.flags ?? '').contains('e');
  if (!wasCapture && !chosen.isPromotion) {
    expect(
      afterCount,
      beforeCount,
      reason: 'seed=$seed ply=$ply quiet move changed piece count '
          '$beforeCount -> $afterCount. before=$before after=${game.fen}',
    );
  }
}

// --- Value types ------------------------------------------------------------

class _Move {
  const _Move({
    required this.from,
    required this.to,
    this.promotion,
    this.flags,
    this.san,
  });

  final String from;
  final String to;
  final String? promotion;
  final String? flags;
  final String? san;

  bool get isPromotion =>
      (promotion != null && promotion!.isNotEmpty) ||
      (flags != null && flags!.contains('p')) ||
      (san != null && san!.contains('='));
}

class _GameResult {
  const _GameResult({
    required this.finalFen,
    required this.fenSequence,
    required this.appliedPlies,
    required this.outOfTurnMoves,
    required this.sameSideDoubles,
    required this.longSameSideRuns,
    required this.promotions,
    required this.guardReverts,
  });

  final String finalFen;
  final List<String> fenSequence;
  final int appliedPlies;
  final int outOfTurnMoves;
  final int sameSideDoubles;
  final int longSameSideRuns;
  final int promotions;
  final int guardReverts;
}

class _CoverageAggregate {
  int appliedPlies = 0;
  int outOfTurnMoves = 0;
  int sameSideDoubles = 0;
  int longSameSideRuns = 0;
  int promotions = 0;
  int guardReverts = 0;
  int maxPliesInAGame = 0;

  void add(_GameResult r) {
    appliedPlies += r.appliedPlies;
    outOfTurnMoves += r.outOfTurnMoves;
    sameSideDoubles += r.sameSideDoubles;
    longSameSideRuns += r.longSameSideRuns;
    promotions += r.promotions;
    guardReverts += r.guardReverts;
    if (r.appliedPlies > maxPliesInAGame) {
      maxPliesInAGame = r.appliedPlies;
    }
  }
}
