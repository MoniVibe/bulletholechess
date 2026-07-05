import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bulletholechess/src/game/engine/online_game_controller.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

/// In-flight / forfeit-lock regression suite for the cooldown-based
/// simultaneous-move online variant.
///
/// These tests drive the REAL message handler over a loopback fake server (the
/// same pattern as `online_desync_suite_test.dart`) and pin:
///   * F2: `_moveInFlight` is cleared ONLY when a frame confirms MY move
///     (clientMoveId echo OR no-echo from/to fallback) or the game is terminal
///     -- NOT on an unrelated opponent frame arriving first.
///   * F2 liveness: a silently dropped move (no echo, no error) is unwedged by
///     the bounded in-flight timeout on the ticker.
///   * F3: an unrelated server `error` frame does NOT clear in-flight tracking;
///     a move-related error does.
///   * F7: a `cooldown_active` rejection at cooldown==0-with-clock-skew is
///     retriable and self-heals (queued move retried, not cleared).
///   * F5 (app-side): the prod oscillating forfeit-lock sequence does NOT
///     permanently wedge the app controller -- interaction recovers on the
///     cleared frames.
void main() {
  // ===========================================================================
  // F2 -- Item 1: opponent frame arriving first must NOT clear my in-flight.
  // ===========================================================================
  test('opponent frame first: in-flight stays set until MY move is confirmed',
      () async {
    final h = await _Harness.connected(myColor: 'w');
    addTearDown(h.dispose);

    // Active, white to move, zero cooldown -> a manual tap sends immediately.
    h.sendState(
      sequence: 2,
      fen: chess.Chess.DEFAULT_POSITION,
      turn: 'w',
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.isMatchActive && h.c.turnColor == 'w');

    h.c.tapSquare('e2');
    h.c.tapSquare('e4');
    final myMoveId = await h.waitForMovePayloadClientMoveId();
    expect(h.c.debugMoveInFlight, isTrue, reason: 'manual move is in flight');
    expect(h.movePayloads.length, 1);

    // OPPONENT's move arrives first (simultaneous variant): black e7-e5 at
    // sequence 3, carrying a DIFFERENT clientMoveId that is not ours. This is
    // NOT a confirmation of our move.
    final gOpp = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'});
    h.sendState(
      sequence: 3,
      fen: gOpp.fen,
      turn: 'w',
      lastMove: {'from': 'e7', 'to': 'e5', 'clientMoveId': 999, 'source': 'manual'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.opponentLastMoveFrom == 'e7');

    // The opponent frame must NOT have cleared our in-flight move.
    expect(h.c.debugMoveInFlight, isTrue,
        reason: 'opponent frame must not clear my in-flight move');
    expect(h.c.debugInFlightClientMoveId, myMoveId);

    // Because in-flight is still set, a second manual attempt must be blocked
    // (guard defended): no second move payload is emitted.
    h.c.tapSquare('d2');
    h.c.tapSquare('d4');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(h.movePayloads.length, 1,
        reason: 'no premature second move while first is unacked');

    // Now MY move is confirmed at sequence 4 (echoes my clientMoveId).
    h.sendState(
      sequence: 4,
      fen: gOpp.fen,
      turn: 'b',
      lastMove: {'from': 'e2', 'to': 'e4', 'clientMoveId': myMoveId, 'source': 'manual'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => !h.c.debugMoveInFlight);
    expect(h.c.debugInFlightClientMoveId, isNull);
  });

  // ===========================================================================
  // F2 -- no-echo confirm fallback: my move confirmed by from/to when the
  // backend omits clientMoveId in lastMove.
  // ===========================================================================
  test('no-echo confirm: my move cleared by from/to match without clientMoveId',
      () async {
    final h = await _Harness.connected(myColor: 'w');
    addTearDown(h.dispose);

    h.sendState(
      sequence: 2,
      fen: chess.Chess.DEFAULT_POSITION,
      turn: 'w',
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.isMatchActive);

    h.c.tapSquare('e2');
    h.c.tapSquare('e4');
    await h.waitForMovePayloadClientMoveId();
    expect(h.c.debugMoveInFlight, isTrue);

    // Confirm frame with NO clientMoveId echo, but my color as mover and my
    // exact from/to. The no-echo fallback must clear the in-flight flag.
    final gConfirm = chess.Chess()..move(<String, String>{'from': 'e2', 'to': 'e4'});
    h.sendState(
      sequence: 3,
      fen: gConfirm.fen,
      turn: 'b',
      lastMove: {'from': 'e2', 'to': 'e4'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => !h.c.debugMoveInFlight);
    expect(h.c.debugInFlightClientMoveId, isNull);
  });

  // ===========================================================================
  // F2 -- liveness timeout: a silently dropped move (no confirm, no error) is
  // unwedged by the ticker's bounded in-flight timeout.
  // ===========================================================================
  test('silently dropped move: in-flight timeout unwedges via the ticker',
      () async {
    final h = await _Harness.connected(myColor: 'w');
    addTearDown(h.dispose);

    h.sendState(
      sequence: 2,
      fen: chess.Chess.DEFAULT_POSITION,
      turn: 'w',
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.isMatchActive);

    h.c.tapSquare('e2');
    h.c.tapSquare('e4');
    await h.waitForMovePayloadClientMoveId();
    expect(h.c.debugMoveInFlight, isTrue);

    // No confirm and no error ever arrive. Advance the injected clock past the
    // in-flight timeout; the periodic ticker must force-clear the flag.
    h.advanceClock(const Duration(seconds: 6));
    await _waitUntil(() => !h.c.debugMoveInFlight, timeout: const Duration(seconds: 3));
    expect(h.c.debugInFlightClientMoveId, isNull);
  });

  // ===========================================================================
  // F3 -- Item 2: unrelated error must NOT clear in-flight; move error must.
  // ===========================================================================
  test('unrelated error frame does not clear in-flight; move error does',
      () async {
    final h = await _Harness.connected(myColor: 'w');
    addTearDown(h.dispose);

    h.sendState(
      sequence: 2,
      fen: chess.Chess.DEFAULT_POSITION,
      turn: 'w',
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.isMatchActive);

    h.c.tapSquare('e2');
    h.c.tapSquare('e4');
    final myMoveId = await h.waitForMovePayloadClientMoveId();
    expect(h.c.debugMoveInFlight, isTrue);

    // An UNRELATED error (invalid piece skin id -- no code, not move-related).
    h.sendError(message: 'Invalid piece skin id.');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(h.c.debugMoveInFlight, isTrue,
        reason: 'unrelated error must not clear the in-flight move');
    expect(h.c.debugInFlightClientMoveId, myMoveId);

    // A MOVE-related error (cooldown_active) must end the in-flight attempt.
    h.sendError(code: 'cooldown_active', message: 'Cooldown active for 500ms.');
    await _waitUntil(() => !h.c.debugMoveInFlight);
    expect(h.c.debugInFlightClientMoveId, isNull);
  });

  // ===========================================================================
  // F7 -- cooldown_active self-heal (test-only pin): queued move retried after
  // a cooldown_active rejection at cooldown==0-with-clock-skew, not cleared.
  // ===========================================================================
  test('cooldown_active rejection is retriable: queued move self-heals',
      () async {
    final h = await _Harness.connected(
      myColor: 'w',
      cooldown: const Duration(milliseconds: 300),
    );
    addTearDown(h.dispose);

    // White ON cooldown so a tap queues.
    h.sendState(
      sequence: 2,
      fen: chess.Chess.DEFAULT_POSITION,
      turn: 'w',
      cooldownEndsAt: {'w': h.baseNow + 400, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.isMatchActive);

    h.c.tapSquare('e2');
    h.c.tapSquare('e4');
    expect(h.c.hasQueuedMove, isTrue);

    // Advance past the local cooldown so the ticker fires the queued move.
    h.advanceClock(const Duration(milliseconds: 600));
    final firstMoveId = await h.waitForMovePayloadClientMoveId();
    expect(h.c.hasQueuedMove, isTrue, reason: 'queued move stays queued until confirmed');
    final sentCountAfterFirst = h.movePayloads.length;

    // Server still enforces cooldown (client's clock skew made it think 0):
    // reply cooldown_active with a fresh ready-at ~250ms out. This is retriable.
    final retryReadyAt = h.currentClockMs() + 250;
    h.sendError(
      code: 'cooldown_active',
      message: 'Cooldown active for 250ms.',
      cooldownEndsAt: {'w': retryReadyAt, 'b': h.baseNow},
    );
    await _waitUntil(() => !h.c.debugMoveInFlight);
    // The queued move must survive the retriable rejection.
    expect(h.c.hasQueuedMove, isTrue,
        reason: 'cooldown_active is retriable -- queued move must NOT be cleared');

    // Advance past the refreshed ready-at; the ticker must retry the SAME queued
    // move (a new move payload, still in flight).
    h.advanceClock(const Duration(milliseconds: 400));
    await _waitUntil(() => h.movePayloads.length > sentCountAfterFirst,
        timeout: const Duration(seconds: 3));
    expect(h.movePayloads.last['from'], 'e2');
    expect(h.movePayloads.last['to'], 'e4');
    expect(h.movePayloads.last['clientMoveId'], isNot(firstMoveId),
        reason: 'retry is a fresh send, not a duplicate of the first');
  });

  // ===========================================================================
  // F5 (app-side regression guard): the prod oscillating forfeit-lock sequence
  // does NOT permanently wedge the app controller. On the CLEARED frames the
  // player can interact; a move queued during a cleared window survives the
  // next SET frame and executes.
  //
  // Reproduces network-ai-chess-qa-prod-a: white blocked by forfeit lock after
  // losing the first-move race; server lock oscillates SET/CLEARED across the
  // opponent's successive moves.
  // ===========================================================================
  test('prod oscillating forfeit lock: app recovers, does not permanently wedge',
      () async {
    final h = await _Harness.connected(
      myColor: 'w',
      cooldown: const Duration(milliseconds: 1000),
    );
    addTearDown(h.dispose);

    // Active game, white to move.
    h.sendState(
      sequence: 2,
      fen: chess.Chess.DEFAULT_POSITION,
      turn: 'w',
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.isMatchActive);

    // Forfeit rejection error carrying the SET lock (white blocked, black
    // releases). Mirrors the prod `forfeit_waiting_release` error frame.
    h.sendError(
      code: 'forfeit_waiting_release',
      message: 'You forfeited the overdue turn. Wait for the opponent move or timeout.',
      forfeitLock: {'blockedColor': 'w', 'releaseByColor': 'b'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow + 1000},
    );
    await _waitUntil(() => h.c.debugForfeitBlockedColor == 'w');
    expect(h.c.canPlayerInteract, isFalse, reason: 'white blocked while lock is SET');

    // Black's move #1 (seq 3): server SET lock (nominalTurn=w != color=b).
    h.sendState(
      sequence: 3,
      fen: g3Fen(),
      turn: 'w',
      lastMove: {'from': 'e7', 'to': 'e5'},
      forfeitLock: {'blockedColor': 'w', 'releaseByColor': 'b'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow + 1000},
    );
    await _waitUntil(() => h.c.opponentLastMoveFrom == 'e7');
    expect(h.c.debugForfeitBlockedColor, 'w');
    expect(h.c.canPlayerInteract, isFalse, reason: 'still blocked on SET frame');

    // Black's move #2 (seq 4): server CLEARS the lock (payload nulls). White is
    // now free to interact -- the key anti-wedge assertion.
    h.sendState(
      sequence: 4,
      fen: g4Fen(),
      turn: 'w',
      lastMove: {'from': 'd8', 'to': 'h4'},
      forfeitLock: {'blockedColor': null, 'releaseByColor': null},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow + 2000},
    );
    await _waitUntil(() => h.c.debugForfeitBlockedColor == null);
    expect(h.c.canPlayerInteract, isTrue,
        reason: 'app must recover interactivity on the CLEARED frame (no wedge)');

    // A queued move made during the cleared window must survive a subsequent SET
    // frame (server re-sets lock on black move #3) and eventually execute.
    h.c.tapSquare('g1');
    h.c.tapSquare('f3');

    // Black move #3 (seq 5): lock re-SET.
    h.sendState(
      sequence: 5,
      fen: g5Fen(),
      turn: 'w',
      lastMove: {'from': 'd7', 'to': 'd5'},
      forfeitLock: {'blockedColor': 'w', 'releaseByColor': 'b'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow + 3000},
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    // Black move #4 (seq 6): lock CLEARED again -> the app must not be wedged;
    // interaction recovers again.
    h.sendState(
      sequence: 6,
      fen: g6Fen(),
      turn: 'w',
      lastMove: {'from': 'f8', 'to': 'b4'},
      forfeitLock: {'blockedColor': null, 'releaseByColor': null},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow + 4000},
    );
    await _waitUntil(() => h.c.debugForfeitBlockedColor == null);
    expect(h.c.canPlayerInteract, isTrue,
        reason: 'app recovers again on the second CLEARED frame');
  });
}

// Real prod FENs (from network-ai-chess-qa-prod-a-20260705). All report white
// to move: in the simultaneous variant white never flips the turn.
String g3Fen() => 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';
String g4Fen() => 'rnb1kbnr/pppp1ppp/8/4p3/7q/8/PPPPPPPP/RNBQKBNR w KQkq - 1 3';
String g5Fen() => 'rnb1kbnr/ppp2ppp/8/3pp3/7q/8/PPPPPPPP/RNBQKBNR w KQkq - 0 4';
String g6Fen() => 'rnb1k1nr/ppp2ppp/8/3pp3/1b5q/8/PPPPPPPP/RNBQKBNR w KQkq - 1 5';

// =============================================================================
// Harness: OnlineGameController + loopback fake server + mutable clock.
// Mirrors the proven pattern in online_desync_suite_test.dart, extended with
// forfeitLock on state frames and an error-frame sender.
// =============================================================================
class _Harness {
  _Harness(this.c, this.server, this._nowRef, this.baseNow);

  final OnlineGameController c;
  final _FakeOnlineServer server;
  final _MutableClock _nowRef;
  final int baseNow;

  List<Map<String, dynamic>> get movePayloads => server.movePayloads;

  static Future<_Harness> connected({
    required String myColor,
    Duration cooldown = const Duration(seconds: 3),
  }) async {
    final clock = _MutableClock(DateTime.utc(2026, 1, 1, 12));
    final server = await _FakeOnlineServer.start();
    final controller = OnlineGameController(
      nowProvider: clock.now,
      initialCooldownDuration: cooldown,
    );
    await controller.connectManual(
      serverUrl: server.wsUrl,
      roomId: 'room-inflight',
      displayName: 'Alice',
    );
    await server.waitForConnection();
    await server.waitForType('join');

    final baseNow = clock.now().millisecondsSinceEpoch;
    server.send(<String, Object?>{
      'type': 'welcome',
      'matchId': 'room-inflight',
      'color': myColor,
      'serverNow': baseNow,
    });
    await _waitUntil(() => controller.myColor == myColor);
    return _Harness(controller, server, clock, baseNow);
  }

  void advanceClock(Duration d) => _nowRef.advance(d);
  int currentClockMs() => _nowRef.now().millisecondsSinceEpoch;

  void sendState({
    required int sequence,
    String? fen,
    String turn = 'w',
    String status = 'active',
    String? result,
    Map<String, Object?>? lastMove,
    Map<String, int>? cooldownEndsAt,
    Map<String, Object?>? forfeitLock,
  }) {
    final payload = <String, Object?>{
      'type': 'state',
      'sequence': sequence,
      'status': status,
      'turn': turn,
      'serverNow': baseNow,
    };
    if (fen != null) payload['fen'] = fen;
    if (result != null) payload['result'] = result;
    if (lastMove != null) payload['lastMove'] = lastMove;
    if (forfeitLock != null) payload['forfeitLock'] = forfeitLock;
    payload['cooldownEndsAt'] =
        cooldownEndsAt ?? <String, int>{'w': baseNow, 'b': baseNow};
    server.send(payload);
  }

  void sendError({
    String? code,
    required String message,
    Map<String, int>? cooldownEndsAt,
    Map<String, Object?>? forfeitLock,
    int? remainingMs,
  }) {
    final payload = <String, Object?>{
      'type': 'error',
      'message': message,
      'serverNow': currentClockMs(),
    };
    if (code != null) payload['code'] = code;
    if (cooldownEndsAt != null) payload['cooldownEndsAt'] = cooldownEndsAt;
    if (forfeitLock != null) payload['forfeitLock'] = forfeitLock;
    if (remainingMs != null) payload['remainingMs'] = remainingMs;
    server.send(payload);
  }

  Future<int> waitForMovePayloadClientMoveId() async {
    await _waitUntil(() => server.movePayloads.isNotEmpty);
    final payload = server.movePayloads.last;
    return (payload['clientMoveId'] as num).toInt();
  }

  Future<void> dispose() async {
    c.dispose();
    await server.dispose();
  }
}

class _MutableClock {
  _MutableClock(this._now);
  DateTime _now;
  DateTime now() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

class _FakeOnlineServer {
  _FakeOnlineServer(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> _received = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> movePayloads = <Map<String, dynamic>>[];
  final StreamController<Map<String, dynamic>> _messageStream =
      StreamController<Map<String, dynamic>>.broadcast();
  final Completer<void> _connected = Completer<void>();
  WebSocket? _socket;

  String get wsUrl => 'ws://127.0.0.1:${_server.port}/ws';

  static Future<_FakeOnlineServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeOnlineServer(server);
    server.listen(fake._handleRequest);
    return fake;
  }

  Future<void> waitForConnection() =>
      _connected.future.timeout(const Duration(seconds: 2));

  Future<Map<String, dynamic>> waitForType(String type) {
    for (final message in _received) {
      if (message['type'] == type) {
        return Future<Map<String, dynamic>>.value(message);
      }
    }
    return _messageStream.stream
        .firstWhere((message) => message['type'] == type)
        .timeout(const Duration(seconds: 3));
  }

  void send(Map<String, Object?> payload) {
    final socket = _socket;
    if (socket == null) {
      throw StateError('No client connected yet.');
    }
    socket.add(jsonEncode(payload));
  }

  Future<void> dispose() async {
    await _socket?.close();
    await _messageStream.close();
    await _server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/ws') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    _socket = socket;
    if (!_connected.isCompleted) {
      _connected.complete();
    }

    socket.listen((dynamic raw) {
      if (raw is! String) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      final map = Map<String, dynamic>.from(decoded);
      _received.add(map);
      if (map['type'] == 'move') {
        movePayloads.add(map);
      }
      _messageStream.add(map);
    });
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  Duration pollEvery = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(pollEvery);
  }
  fail('Timed out waiting for condition.');
}
