import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bulletholechess/src/game/engine/online_game_controller.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

/// Online desync / out-of-order / idempotency suite for the cooldown-based
/// simultaneous-move variant.
///
/// These tests drive the real message handler (`_applyState` via `_onMessage`)
/// over a loopback `_FakeOnlineServer` -- no mocked internals, no real backend.
/// Each scenario crafts explicit state frames and asserts the client's applied
/// board / metadata / queue state.
///
/// INTENDED SEQUENCE SEMANTICS (documented here as the contract these tests
/// pin):
///   * Every `state` frame is a FULL snapshot (complete FEN + status + result +
///     lastMove + cooldowns). There is no delta encoding.
///   * The client applies a frame iff its (explicit or inferred) `sequence` is
///     strictly greater than the last applied sequence -- last-writer-wins.
///   * A sequence GAP (dropped frames) is therefore harmless: the newer full
///     snapshot subsumes everything skipped.
///   * A REORDERED older frame (sequence <= current) is dropped, so the board
///     never regresses to a stale position.
///   * A duplicate/equal sequence is dropped (WS reconnect retransmit guard).
void main() {
  // ---------------------------------------------------------------------------
  // Scenario 1: DROPPED frame / sequence GAP (5 -> 8, skipping 6,7).
  // ---------------------------------------------------------------------------
  test('sequence gap (5 -> 8) applies the newer full snapshot and does not wedge',
      () async {
    final h = await _Harness.connected(myColor: 'w');
    addTearDown(h.dispose);

    // Frame at sequence 5: opponent (black) played e7-e5 after white e2-e4.
    final g5 = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'});
    h.sendState(sequence: 5, fen: g5.fen, turn: 'w', lastMove: {'from': 'e7', 'to': 'e5'});
    await _waitUntil(() => h.c.opponentLastMoveFrom == 'e7');

    // Server jumps to sequence 8 (6,7 dropped in transit). A full new snapshot:
    // white Nf3, black Nc6 now on the board.
    final g8 = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'})
      ..move(<String, String>{'from': 'g1', 'to': 'f3'})
      ..move(<String, String>{'from': 'b8', 'to': 'c6'});
    h.sendState(sequence: 8, fen: g8.fen, turn: 'w', lastMove: {'from': 'b8', 'to': 'c6'});

    await _waitUntil(() => h.c.opponentLastMoveFrom == 'b8');
    expect(h.c.opponentLastMoveTo, 'c6');
    // Board reflects the sequence-8 snapshot exactly (last-writer-wins).
    expect(h.c.boardPieces['f3'], 'N', reason: 'white knight applied from gap frame');
    expect(h.c.boardPieces['c6'], 'n', reason: 'black knight applied from gap frame');
    expect(h.c.boardPieces.containsKey('g1'), isFalse);
    expect(h.c.boardPieces.containsKey('b8'), isFalse);

    // A subsequent legitimate frame at sequence 9 still applies (not wedged).
    final g9 = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'})
      ..move(<String, String>{'from': 'g1', 'to': 'f3'})
      ..move(<String, String>{'from': 'b8', 'to': 'c6'})
      ..move(<String, String>{'from': 'f1', 'to': 'b5'});
    h.sendState(sequence: 9, fen: g9.fen, turn: 'b', lastMove: {'from': 'f1', 'to': 'b5'});
    await _waitUntil(() => h.c.boardPieces['b5'] == 'B');
    expect(h.c.boardPieces.containsKey('f1'), isFalse);
  });

  // ---------------------------------------------------------------------------
  // Scenario 2: REORDERED / out-of-order frames (5 then 4 then 6).
  // ---------------------------------------------------------------------------
  test('out-of-order frame (5,4,6): stale 4 dropped, board never regresses',
      () async {
    final h = await _Harness.connected(myColor: 'w');
    addTearDown(h.dispose);

    // Sequence 5: black played e7-e5.
    final g5 = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'});
    h.sendState(sequence: 5, fen: g5.fen, turn: 'w', lastMove: {'from': 'e7', 'to': 'e5'});
    await _waitUntil(() => h.c.opponentLastMoveFrom == 'e7');
    expect(h.c.boardPieces['e5'], 'p');

    // Sequence 4 arrives LATE (older): a DIFFERENT, earlier position (black
    // d7-d5). Must be dropped -- board must NOT regress to d5.
    final g4 = chess.Chess()
      ..move(<String, String>{'from': 'd2', 'to': 'd4'})
      ..move(<String, String>{'from': 'd7', 'to': 'd5'});
    h.sendState(sequence: 4, fen: g4.fen, turn: 'w', lastMove: {'from': 'd7', 'to': 'd5'});
    // Give the stale frame time to (wrongly) apply.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(h.c.opponentLastMoveFrom, 'e7',
        reason: 'stale sequence-4 frame must be dropped');
    expect(h.c.boardPieces['e5'], 'p', reason: 'board must not regress to d5 position');
    expect(h.c.boardPieces.containsKey('d5'), isFalse);

    // Sequence 6: legitimate newer frame (white Nf3) still applies.
    final g6 = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'})
      ..move(<String, String>{'from': 'g1', 'to': 'f3'});
    h.sendState(sequence: 6, fen: g6.fen, turn: 'b', lastMove: {'from': 'g1', 'to': 'f3'});
    await _waitUntil(() => h.c.boardPieces['f3'] == 'N');
    expect(h.c.boardPieces.containsKey('g1'), isFalse);
  });

  // ---------------------------------------------------------------------------
  // Scenario 3a: QUEUE IDEMPOTENCY -- duplicate confirm of an in-flight
  // (manual) move keyed by clientMoveId must not double-apply.
  // ---------------------------------------------------------------------------
  test('duplicate confirm of in-flight move (same clientMoveId) is idempotent',
      () async {
    final h = await _Harness.connected(myColor: 'w');
    addTearDown(h.dispose);

    // Establish an active game at sequence 2 (start position, white to move,
    // no cooldown so a manual move sends immediately and goes in-flight).
    h.sendState(
      sequence: 2,
      fen: chess.Chess.DEFAULT_POSITION,
      turn: 'w',
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.turnColor == 'w' && h.c.isMatchActive);

    // Real UI entry: select e2, target e4. With zero cooldown this sends the
    // move immediately, setting an in-flight clientMoveId.
    h.c.tapSquare('e2');
    h.c.tapSquare('e4');
    final clientMoveId = await h.waitForMovePayloadClientMoveId();
    expect(h.c.hasQueuedMove, isFalse, reason: 'manual send should not queue');

    // Server confirms the move at sequence 3, echoing the clientMoveId.
    final gConfirm = chess.Chess()..move(<String, String>{'from': 'e2', 'to': 'e4'});
    h.sendState(
      sequence: 3,
      fen: gConfirm.fen,
      turn: 'b',
      lastMove: {'from': 'e2', 'to': 'e4', 'clientMoveId': clientMoveId, 'source': 'manual'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.playerLastMoveTo == 'e4');
    expect(h.c.boardPieces['e4'], 'P');
    expect(h.c.boardPieces.containsKey('e2'), isFalse);

    // DUPLICATE confirm: same clientMoveId, next sequence 4 (a retransmit that
    // got a fresh sequence). It must be inert: no second advance, no phantom,
    // no re-confirm side effects. Board identical.
    final boardBefore = Map<String, String>.from(h.c.boardPieces);
    h.sendState(
      sequence: 4,
      fen: gConfirm.fen,
      turn: 'b',
      lastMove: {'from': 'e2', 'to': 'e4', 'clientMoveId': clientMoveId, 'source': 'manual'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(h.c.boardPieces, boardBefore, reason: 'duplicate confirm must not mutate board');
    expect(h.c.boardPieces['e4'], 'P');
    expect(h.c.boardPieces.values.where((p) => p == 'P').length, 8,
        reason: 'exactly 8 white pawns -- no phantom from double-apply');
    expect(h.c.hasQueuedMove, isFalse);
  });

  // ---------------------------------------------------------------------------
  // Scenario 3b: QUEUE IDEMPOTENCY -- a queued move (under cooldown) confirmed
  // by the server, then a DUPLICATE confirm for the same clientMoveId/queueToken.
  // Drives the real ticker + cooldown expiry so the queued move genuinely
  // executes through _tryExecuteQueuedPlayerMove.
  // ---------------------------------------------------------------------------
  test('duplicate confirm of queued move (same queueToken) is idempotent',
      () async {
    final h = await _Harness.connected(myColor: 'w', cooldown: const Duration(milliseconds: 300));
    addTearDown(h.dispose);

    // Active, white to move, but white is ON COOLDOWN (ready 400ms in the
    // future) so a tap QUEUES rather than sends.
    h.sendState(
      sequence: 2,
      fen: chess.Chess.DEFAULT_POSITION,
      turn: 'w',
      cooldownEndsAt: {'w': h.baseNow + 400, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.isMatchActive);

    h.c.tapSquare('e2');
    h.c.tapSquare('e4');
    expect(h.c.hasQueuedMove, isTrue, reason: 'move should queue under cooldown');

    // Advance the clock past the cooldown so the periodic ticker executes the
    // queued move (which calls _sendMove with a queueToken and goes in-flight).
    h.advanceClock(const Duration(milliseconds: 600));
    final clientMoveId = await h.waitForMovePayloadClientMoveId();
    await _waitUntil(() => !h.c.hasQueuedMove || h.movePayloads.isNotEmpty);

    // Server confirms the queued move at sequence 3.
    final gConfirm = chess.Chess()..move(<String, String>{'from': 'e2', 'to': 'e4'});
    h.sendState(
      sequence: 3,
      fen: gConfirm.fen,
      turn: 'b',
      lastMove: {'from': 'e2', 'to': 'e4', 'clientMoveId': clientMoveId, 'source': 'queued'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await _waitUntil(() => h.c.playerLastMoveTo == 'e4');
    expect(h.c.hasQueuedMove, isFalse, reason: 'queued move cleared on confirm');
    expect(h.c.boardPieces['e4'], 'P');

    // DUPLICATE confirm of the same queued move at sequence 4. Must be inert.
    final boardBefore = Map<String, String>.from(h.c.boardPieces);
    h.sendState(
      sequence: 4,
      fen: gConfirm.fen,
      turn: 'b',
      lastMove: {'from': 'e2', 'to': 'e4', 'clientMoveId': clientMoveId, 'source': 'queued'},
      cooldownEndsAt: {'w': h.baseNow, 'b': h.baseNow},
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(h.c.hasQueuedMove, isFalse, reason: 'duplicate confirm must not resurrect a queued move');
    expect(h.c.boardPieces, boardBefore);
    expect(h.c.boardPieces.values.where((p) => p == 'P').length, 8);
  });

  // ---------------------------------------------------------------------------
  // Scenario 4: state_invalid_fen must NOT partial-apply metadata off a
  // rejected board. After the fix, the whole frame short-circuits: board,
  // status, result, lastMove all stay on the last good frame.
  // ---------------------------------------------------------------------------
  test('invalid-FEN frame is fully rejected -- no partial metadata apply',
      () async {
    final h = await _Harness.connected(myColor: 'w');
    addTearDown(h.dispose);

    // Good frame at sequence 5: black e7-e5, game active.
    final g5 = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'});
    h.sendState(sequence: 5, fen: g5.fen, turn: 'w', status: 'active',
        lastMove: {'from': 'e7', 'to': 'e5'});
    await _waitUntil(() => h.c.opponentLastMoveFrom == 'e7');
    final goodBoard = Map<String, String>.from(h.c.boardPieces);
    expect(h.c.isMatchActive, isTrue);
    expect(h.c.resultCode, isNull);

    // Malformed frame at sequence 6: a broken FEN (too few ranks) PLUS metadata
    // that, if partial-applied, would corrupt client state: status 'game_over',
    // a result, and a bogus lastMove. The whole frame must be rejected.
    h.sendState(
      sequence: 6,
      fen: 'not/a/valid/fen w - - 0 1',
      turn: 'b',
      status: 'game_over',
      result: 'white_win',
      lastMove: {'from': 'a1', 'to': 'a8'},
    );
    await _waitUntil(() => h.c.feedback == 'Received invalid board state from server.');

    // Board unchanged (still the sequence-5 position).
    expect(h.c.boardPieces, goodBoard, reason: 'board must stay on last good frame');
    // Metadata did NOT advance off the rejected board.
    expect(h.c.isMatchActive, isTrue, reason: 'status must not flip to game_over');
    expect(h.c.resultCode, isNull, reason: 'result must not be set from rejected frame');
    expect(h.c.opponentLastMoveFrom, 'e7',
        reason: 'lastMove highlight must not move to bogus a1-a8');
    expect(h.c.opponentLastMoveTo, 'e5');

    // A subsequent VALID frame at sequence 6 (corrected retransmit at the SAME
    // sequence) still applies -- the rejected frame did not advance _sequence
    // and thus did not swallow the correction.
    final g6 = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'})
      ..move(<String, String>{'from': 'g1', 'to': 'f3'});
    h.sendState(sequence: 6, fen: g6.fen, turn: 'b', status: 'active',
        lastMove: {'from': 'g1', 'to': 'f3'});
    await _waitUntil(() => h.c.boardPieces['f3'] == 'N');
    expect(h.c.boardPieces.containsKey('g1'), isFalse);
  });
}

// =============================================================================
// Harness: wraps OnlineGameController + a loopback fake server, with a mutable
// clock and convenience state-frame builders.
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
      roomId: 'room-desync',
      displayName: 'Alice',
    );
    await server.waitForConnection();
    await server.waitForType('join');

    final baseNow = clock.now().millisecondsSinceEpoch;
    server.send(<String, Object?>{
      'type': 'welcome',
      'matchId': 'room-desync',
      'color': myColor,
      'serverNow': baseNow,
    });
    await _waitUntil(() => controller.myColor == myColor);
    return _Harness(controller, server, clock, baseNow);
  }

  void advanceClock(Duration d) => _nowRef.advance(d);

  void sendState({
    required int sequence,
    String? fen,
    String turn = 'w',
    String status = 'active',
    String? result,
    Map<String, Object?>? lastMove,
    Map<String, int>? cooldownEndsAt,
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
    payload['cooldownEndsAt'] =
        cooldownEndsAt ?? <String, int>{'w': baseNow, 'b': baseNow};
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
