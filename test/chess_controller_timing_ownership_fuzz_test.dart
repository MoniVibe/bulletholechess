// Seeded CONTROLLER-LEVEL timing fuzz for the cooldown-based out-of-turn chess
// variant.
//
// WHY THIS EXISTS (complements chess_variant_ownership_fuzz_test.dart):
//   The sibling fuzz drives the RULES FACADE directly
//   (findValidatedLegalMove -> applyValidatedLegalMoveForColor) and replicates
//   the controllers' ownership-revert guard by hand. That is evidence-of-absence
//   on the *rules* path, but it never instantiates the real controllers with
//   their cooldown timers, move queue, AI timer and periodic ticker. The
//   director's live-play glitches ("units switching sides", "pieces appearing
//   out of nowhere") happened through the CONTROLLER path, and the ownership
//   revert-guard was installed IN the controllers precisely because that path
//   can, in principle, produce a flip. This test exercises THAT path.
//
// TIME SEAM: no production change needed. Both controllers already accept an
//   injectable `DateTime Function()? nowProvider` (LocalGameController ctor
//   param, threaded into TurnCooldownTracker via nowMsProvider). We drive it
//   with a mutable `now` advanced in lockstep with fakeAsync's `elapse`, exactly
//   as the shipped bughunt_clock_determinism_test.dart does. Under fakeAsync the
//   real periodic ticker, the real AI Timer and the real queued-move execution
//   in `_onTick` all fire deterministically, so the genuine controller code runs
//   -- including _applyMove and its revert guard.
//
// The scheduler deliberately manufactures the exact conditions the guard defends
// against:
//   * same-side double moves  (player taps again after its own cooldown expires
//     while the opponent is still cooling / not yet scheduled)
//   * both-sides-eligible races (both cooldowns elapsed to zero, player taps in
//     the same window the AI Timer fires)
//   * queued-move-then-board-change (player queues under cooldown, the AI mutates
//     the board, then the ticker re-validates and executes the stale queue)
//
// On EVERY observed board transition it asserts:
//   (a) every occupied square holds a piece of a valid color;
//   (b) NO ownership flip -- the piece on a mover's destination is the mover's;
//   (c) no phantom / duplicate -- piece count non-increasing except legal
//       promotion, and the source square is cleared;
//   (d) exactly one king per side.
//
// Coverage counters are printed and asserted non-vacuous: a green run with zero
// races / zero doubles / zero queued-then-changed events proves nothing.

import 'dart:math';

import 'package:bulletholechess/src/game/engine/chess_ai_game_controller.dart';
import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';
import 'package:bulletholechess/src/game/engine/local_game_controller.dart';
import 'package:chess/chess.dart' as chess;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'LocalGameController timing path holds ownership/phantom invariants under '
    'seeded cooldown races',
    () {
      final seeds = List<int>.generate(30, (i) => i + 1);
      final agg = _Coverage();

      for (final seed in seeds) {
        _runLocalControllerSeed(seed: seed, agg: agg);
      }

      _printAndAssertCoverage('local-controller', agg);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'ChessAiGameController timing path holds ownership/phantom invariants under '
    'seeded cooldown races',
    () {
      final seeds = List<int>.generate(30, (i) => i + 1001);
      final agg = _Coverage();

      for (final seed in seeds) {
        _runAiControllerSeed(seed: seed, agg: agg);
      }

      _printAndAssertCoverage('ai-controller', agg);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // Deterministic regression pin for the en-passant / forced-turn phantom.
  //
  // Before the fix (ChessRules.withTurn clearing the stale en-passant target
  // while the side-to-move is force-flipped), AI-controller seed=1008 spawned a
  // phantom WHITE pawn on b7 at ply 23 (SAN Bc5): after black pushed b7-b5 out of
  // turn, the live game's ep_square=b6 became bogus, and forcing black's turn for
  // move enumeration made the `chess` engine synthesize an illegal en-passant
  // capture whose make/undo (inside move->SAN) resurrected a white pawn on b7.
  // This pins that exact scenario so a regression is caught in <1s.
  test('regression: seed=1008 no en-passant forced-turn phantom pawn', () {
    var maxPieces = 0;
    var sawPhantomWhitePawn = false;
    _runAiControllerSeed(
      seed: 1008,
      agg: _Coverage(),
      onBoard: (board) {
        if (board.length > maxPieces) {
          maxPieces = board.length;
        }
        final whitePawns = board.values.where((p) => p == 'P').length;
        final blackPawns = board.values.where((p) => p == 'p').length;
        if (whitePawns > 8 || blackPawns > 8) {
          sawPhantomWhitePawn = true;
        }
      },
    );
    expect(maxPieces, lessThanOrEqualTo(32),
        reason: 'piece count must never exceed 32 (phantom pawn regression)');
    expect(sawPhantomWhitePawn, isFalse,
        reason: 'no side may ever exceed 8 pawns (phantom pawn regression)');
  }, timeout: const Timeout(Duration(seconds: 60)));
}

void _printAndAssertCoverage(String label, _Coverage agg) {
  // ignore: avoid_print
  print(
    '$label timing-fuzz coverage: '
    'boardTransitions=${agg.transitions} '
    'sameSideDoubles=${agg.sameSideDoubles} '
    'bothEligibleRaces=${agg.bothEligibleRaces} '
    'queuedThenBoardChanged=${agg.queuedThenBoardChanged} '
    'queuedCoexist=${agg.queuedCoexist}',
  );

  // Non-vacuity: the whole point is to reach the race conditions the guard
  // defends against. If these are zero a green run is meaningless.
  expect(
    agg.sameSideDoubles,
    greaterThan(50),
    reason: 'Must manufacture same-side double moves to be meaningful.',
  );
  expect(
    agg.bothEligibleRaces,
    greaterThan(50),
    reason: 'Must manufacture both-sides-eligible windows to be meaningful.',
  );
  expect(
    agg.queuedThenBoardChanged,
    greaterThan(10),
    reason: 'Must manufacture queued-move-then-board-change events.',
  );
}

// ---------------------------------------------------------------------------
// LocalGameController driver
// ---------------------------------------------------------------------------

void _runLocalControllerSeed({required int seed, required _Coverage agg}) {
  fakeAsync((async) {
    final random = Random(seed);
    // Player is white half the time, black the other half, so both the tap path
    // and the AI path exercise both colors across the corpus.
    final playerAsWhite = seed.isEven;

    var now = DateTime.utc(2026, 7, 4, 9, 0, 0);
    // Short cooldown so a side becomes re-eligible quickly (same-side doubles),
    // and the two cooldowns drift in and out of overlap (races).
    final cooldown = Duration(milliseconds: 200 + random.nextInt(400));

    final aiEngine = _RandomLegalEngine(Random(seed ^ 0x5bd1e995));
    final controller = LocalGameController(
      initialCooldownDuration: cooldown,
      // Randomised, sometimes-tiny AI think delay so the AI Timer lands in
      // overlapping / non-overlapping windows relative to the player taps.
      aiThinkDelayMin: Duration(milliseconds: 10 + random.nextInt(60)),
      aiThinkDelayMax: Duration(milliseconds: 80 + random.nextInt(200)),
      aiEngine: aiEngine,
      random: Random(seed ^ 0x9e3779b9),
      nowProvider: () => now,
    );

    final monitor = _BoardMonitor(
      label: 'local seed=$seed',
      agg: agg,
      boardOf: () => controller.boardPieces,
      hasQueuedMove: () => controller.hasQueuedMove,
    );

    controller.startNewGame(playerAsWhite: playerAsWhite);
    monitor.sync(); // baseline

    final playerColor = controller.playerColor;

    // Drive a bounded number of "rounds". Each round: maybe tap a player move,
    // then elapse a randomised slice of time (which fires the ticker, the AI
    // timer and any queued-move execution), sampling the board after each step.
    const rounds = 55;
    for (var r = 0; r < rounds; r += 1) {
      if (controller.isGameOver) {
        break;
      }

      // With some probability, attempt a player move through the real tap path.
      // This either applies immediately (if eligible) or queues (if cooling /
      // forfeit-locked) -- both are genuine controller behaviour.
      if (random.nextInt(100) < 75) {
        final playerEligibleBefore =
            controller.cooldownRemaining(playerColor).inMilliseconds == 0;
        final aiEligibleBefore =
            controller.cooldownRemaining(controller.aiColor).inMilliseconds ==
                0;
        if (playerEligibleBefore && aiEligibleBefore) {
          agg.bothEligibleRaces += 1;
        }

        final hadQueueBefore = controller.hasQueuedMove;
        _attemptPlayerTapMove(
          controller: controller,
          color: playerColor,
          random: random,
        );
        monitor.sync();
        // If we just queued (didn't move) while a queue also existed, note it;
        // queued-then-changed is detected in the monitor via version deltas.
        if (hadQueueBefore && controller.hasQueuedMove) {
          agg.queuedCoexist += 1;
        }
      }

      // Elapse a randomised time slice. Small slices keep both cooldowns near
      // zero to force overlap; larger slices let the AI timer fire and queued
      // moves execute. Sample the board between micro-steps so no transition is
      // missed.
      final sliceMs = 20 + random.nextInt(260);
      _elapseSampling(
        async: async,
        totalMs: sliceMs,
        stepMs: 20,
        advanceNow: (d) => now = now.add(d),
        monitor: monitor,
      );
    }

    controller.dispose();
    async.elapse(const Duration(seconds: 1));
  });
}

void _attemptPlayerTapMove({
  required LocalGameController controller,
  required String color,
  required Random random,
}) {
  final candidate = _pickLegalMove(
    fen: _fenOf(controller.boardPieces, controller.turnColor),
    color: color,
    random: random,
  );
  if (candidate == null) {
    return;
  }
  // Real UI entry: select then target. tapSquare gates on canPlayerInteract /
  // cooldown internally and will queue when appropriate.
  controller.tapSquare(candidate.from);
  controller.tapSquare(candidate.to);
}

// ---------------------------------------------------------------------------
// ChessAiGameController driver
// ---------------------------------------------------------------------------

void _runAiControllerSeed({
  required int seed,
  required _Coverage agg,
  void Function(Map<String, String> board)? onBoard,
}) {
  fakeAsync((async) {
    final random = Random(seed);
    final playerAsWhite = seed.isEven;

    var now = DateTime.utc(2026, 7, 4, 10, 0, 0);
    final cooldown = Duration(milliseconds: 150 + random.nextInt(400));

    final aiEngine = _RandomLegalEngine(Random(seed ^ 0x27d4eb2f));
    final controller = ChessAiGameController(
      aiMoveDelay: Duration(milliseconds: 10 + random.nextInt(120)),
      initialCooldownDuration: cooldown,
      aiEngine: aiEngine,
      nowProvider: () => now,
    );

    final monitor = _BoardMonitor(
      label: 'ai seed=$seed',
      agg: agg,
      boardOf: () => controller.boardPieces,
      hasQueuedMove: () => controller.hasQueuedMove,
      onBoard: onBoard,
    );

    controller.startNewGame(playerAsWhite: playerAsWhite);
    monitor.sync();

    final playerColor = controller.playerColor;

    const rounds = 55;
    for (var r = 0; r < rounds; r += 1) {
      if (controller.isGameOver) {
        break;
      }

      if (random.nextInt(100) < 75) {
        final playerEligibleBefore =
            controller.cooldownRemaining(playerColor).inMilliseconds == 0;
        final aiEligibleBefore =
            controller.cooldownRemaining(controller.aiColor).inMilliseconds ==
                0;
        if (playerEligibleBefore && aiEligibleBefore) {
          agg.bothEligibleRaces += 1;
        }

        final candidate = _pickLegalMove(
          fen: _fenOf(controller.boardPieces, controller.turnColor),
          color: playerColor,
          random: random,
        );
        if (candidate != null) {
          controller.tapSquare(candidate.from);
          controller.tapSquare(candidate.to);
          monitor.sync();
        }
      }

      final sliceMs = 20 + random.nextInt(260);
      _elapseSampling(
        async: async,
        totalMs: sliceMs,
        stepMs: 20,
        advanceNow: (d) => now = now.add(d),
        monitor: monitor,
      );
    }

    controller.dispose();
    async.elapse(const Duration(seconds: 1));
  });
}

// ---------------------------------------------------------------------------
// Time stepping
// ---------------------------------------------------------------------------

void _elapseSampling({
  required FakeAsync async,
  required int totalMs,
  required int stepMs,
  required void Function(Duration) advanceNow,
  required _BoardMonitor monitor,
}) {
  var remaining = totalMs;
  while (remaining > 0) {
    final step = remaining < stepMs ? remaining : stepMs;
    final d = Duration(milliseconds: step);
    advanceNow(d);
    async.elapse(d);
    monitor.sync();
    remaining -= step;
  }
}

// ---------------------------------------------------------------------------
// Board transition monitor + invariants
// ---------------------------------------------------------------------------

class _BoardMonitor {
  _BoardMonitor({
    required this.label,
    required this.agg,
    required this.boardOf,
    required this.hasQueuedMove,
    this.onBoard,
  });

  final String label;
  final _Coverage agg;
  final Map<String, String> Function() boardOf;
  final bool Function() hasQueuedMove;
  final void Function(Map<String, String> board)? onBoard;

  Map<String, String>? _prev;
  String? _lastMover;

  /// Sample the current board. If it changed since the last sample, validate the
  /// transition and attribute it to the mover implied by the delta.
  void sync() {
    final current = Map<String, String>.from(boardOf());
    onBoard?.call(current);
    _assertStandalone(current);

    final prev = _prev;
    if (prev == null) {
      _prev = current;
      return;
    }
    if (_boardsEqual(prev, current)) {
      return; // no transition
    }

    agg.transitions += 1;
    // Queued-then-board-changed: a player move is queued AND the board just
    // mutated underneath it (the opponent, or the queued move's own execution,
    // changed the board while a queue was/had-been standing). This is the exact
    // interleaving the queued-move re-validation guards against.
    if (hasQueuedMove()) {
      agg.queuedThenBoardChanged += 1;
    }
    final mover = _inferMoverAndValidate(prev, current);
    if (mover != null) {
      if (_lastMover == mover) {
        agg.sameSideDoubles += 1;
      }
      if (mover == 'w' || mover == 'b') {
        _lastMover = mover;
      }
    }
    _prev = current;
  }

  /// Infer which side moved from the board delta and assert the ownership /
  /// phantom invariants for that transition. Returns the mover color, or null if
  /// the delta was not attributable to a single side (should not happen for a
  /// single legal ply, but we do not fail on attribution ambiguity -- only on
  /// true invariant violations).
  String? _inferMoverAndValidate(
    Map<String, String> before,
    Map<String, String> after,
  ) {
    // Squares that gained a piece or changed occupant.
    final appeared = <String>[];
    final vacated = <String>[];
    for (final sq in {...before.keys, ...after.keys}) {
      final b = before[sq];
      final a = after[sq];
      if (b == a) {
        continue;
      }
      if (a != null) {
        appeared.add(sq);
      }
      if (b != null && a == null) {
        vacated.add(sq);
      }
    }

    // (c) piece count non-increasing except promotion (which keeps it equal:
    // a pawn is removed and a promoted piece added on the same ply).
    final beforeCount = before.length;
    final afterCount = after.length;
    expect(
      afterCount,
      lessThanOrEqualTo(beforeCount),
      reason: 'PHANTOM PIECE ($label): piece count grew '
          '$beforeCount -> $afterCount. before=$before after=$after',
    );

    // Determine mover: the destination square is one that gained the moving
    // side's piece. For a normal ply exactly one non-capture destination gains a
    // piece (or a capture replaces an enemy piece). Castling moves two of the
    // mover's pieces. We identify the mover as the owner of the piece on the
    // "primary" destination -- the appeared square whose new occupant differs in
    // color from any vacated-square owner, falling back to majority color of
    // appeared squares.
    if (appeared.isEmpty) {
      // Pure removal with no arrival cannot come from a legal move.
      fail('ILLEGAL TRANSITION ($label): pieces vanished with no arrival. '
          'before=$before after=$after');
    }

    // Collect owner colors of appeared squares.
    final appearedOwners =
        appeared.map((sq) => ChessRules.pieceColor(after[sq]!)).toSet();

    // (b) A single ply must be by ONE color: every square that gained a piece in
    // this transition must be owned by the same side (castling moves king+rook,
    // both the mover's; a capture leaves the mover's piece on the dest). If two
    // different colors "appeared" in one sampled transition, the board advanced
    // by more than one ply between samples -- still fine as long as each square
    // is a valid color, but then ownership attribution is skipped. We only hard-
    // assert the single-mover ownership rule when attribution is unambiguous.
    String? mover;
    if (appearedOwners.length == 1) {
      mover = appearedOwners.first;

      // (b) ownership: no vacated square implies a flip. For every square the
      // mover now occupies that was previously occupied, the previous occupant
      // must not be "the same piece that simply changed color" -- i.e. a square
      // that kept its identity but flipped owner is the exact bug.
      for (final sq in appeared) {
        final newOwner = ChessRules.pieceColor(after[sq]!);
        expect(
          newOwner,
          mover,
          reason: 'OWNERSHIP FLIP ($label): square $sq now $newOwner but '
              'transition attributed to $mover. before=$before after=$after',
        );
      }

      // (c2) at least one of the mover's source squares must have cleared.
      // A move that adds an owner-piece without vacating any owner square is a
      // duplicate/phantom.
      final moverVacated = vacated
          .where((sq) => ChessRules.pieceColor(before[sq]!) == mover)
          .isNotEmpty;
      final moverGainedNet = appeared
          .where((sq) =>
              before[sq] == null ||
              ChessRules.pieceColor(before[sq]!) != mover)
          .isNotEmpty;
      if (moverGainedNet && !moverVacated) {
        fail('DUPLICATE PIECE ($label): $mover gained a piece on '
            '$appeared without vacating any of its own squares. '
            'before=$before after=$after');
      }
    }

    return mover;
  }

  void _assertStandalone(Map<String, String> board) {
    for (final entry in board.entries) {
      final ok = 'pnbrqkPNBRQK'.contains(entry.value);
      expect(
        ok,
        isTrue,
        reason: 'INVALID SYMBOL ($label): ${entry.key}="${entry.value}" '
            'board=$board',
      );
    }
    final whiteKings = board.values.where((p) => p == 'K').length;
    final blackKings = board.values.where((p) => p == 'k').length;
    expect(
      whiteKings,
      1,
      reason: 'WHITE KING COUNT ($label)=$whiteKings board=$board',
    );
    expect(
      blackKings,
      1,
      reason: 'BLACK KING COUNT ($label)=$blackKings board=$board',
    );
  }
}

bool _boardsEqual(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final e in a.entries) {
    if (b[e.key] != e.value) {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// Move picking (legal for an out-of-turn color) via the real rules facade
// ---------------------------------------------------------------------------

class _Candidate {
  const _Candidate({required this.from, required this.to, this.promotion});
  final String from;
  final String to;
  final String? promotion;
}

/// Build a FEN from the board map for a given side-to-move. We only need the
/// piece placement + active color fields to be correct for move enumeration; the
/// controllers' rules facade rewrites the turn field itself when cloning for a
/// color, so castling/en-passant richness is not required for candidate picking.
String _fenOf(Map<String, String> board, String turnColor) {
  final rows = <String>[];
  for (var rank = 8; rank >= 1; rank -= 1) {
    final sb = StringBuffer();
    var empty = 0;
    for (var file = 0; file < 8; file += 1) {
      final sq = '${'abcdefgh'[file]}$rank';
      final piece = board[sq];
      if (piece == null) {
        empty += 1;
      } else {
        if (empty > 0) {
          sb.write(empty);
          empty = 0;
        }
        sb.write(piece);
      }
    }
    if (empty > 0) {
      sb.write(empty);
    }
    rows.add(sb.toString());
  }
  final placement = rows.join('/');
  final active = turnColor == 'w' ? 'w' : 'b';
  // Neutral castling/en-passant/clock fields; move enumeration for a color is
  // done by the facade against the live game, this FEN is only for our own
  // candidate list.
  return '$placement $active - - 0 1';
}

_Candidate? _pickLegalMove({
  required String fen,
  required String color,
  required Random random,
}) {
  final game = chess.Chess();
  if (!_safeLoad(game, fen)) {
    return null;
  }
  // Force the color's turn for enumeration (mirrors the variant's out-of-turn
  // move generation).
  final parts = game.fen.split(' ');
  parts[1] = color == 'w' ? 'w' : 'b';
  parts[3] = '-';
  final enumGame = chess.Chess();
  if (!_safeLoad(enumGame, parts.join(' '))) {
    return null;
  }
  final moves = enumGame
      .moves(<String, dynamic>{'verbose': true})
      .map((dynamic m) => Map<String, dynamic>.from(m as Map))
      .toList();
  if (moves.isEmpty) {
    return null;
  }
  final chosen = moves[random.nextInt(moves.length)];
  return _Candidate(
    from: chosen['from'] as String,
    to: chosen['to'] as String,
    promotion: chosen['promotion'] as String?,
  );
}

bool _safeLoad(chess.Chess game, String fen) {
  try {
    return game.load(fen);
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Random legal engine for the AI color (drives the AI side through the real
// controller apply path + timers).
// ---------------------------------------------------------------------------

class _RandomLegalEngine extends DumbAiEngine {
  _RandomLegalEngine(this._rng);

  final Random _rng;

  @override
  EngineMove? chooseMove(chess.Chess game) {
    final raw = game.moves(const <String, dynamic>{'verbose': true});
    if (raw.isEmpty) {
      return null;
    }
    final moves = raw
        .map((dynamic m) => Map<String, dynamic>.from(m as Map))
        .toList();
    final m = moves[_rng.nextInt(moves.length)];
    return EngineMove(
      from: m['from'] as String,
      to: m['to'] as String,
      promotion: (m['promotion'] as String?) ?? 'q',
    );
  }
}

// ---------------------------------------------------------------------------
// Coverage aggregate
// ---------------------------------------------------------------------------

class _Coverage {
  int transitions = 0;
  int sameSideDoubles = 0;
  int bothEligibleRaces = 0;
  int queuedThenBoardChanged = 0;
  int queuedCoexist = 0;
}
