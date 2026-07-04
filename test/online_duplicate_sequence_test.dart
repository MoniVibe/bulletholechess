import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bulletholechess/src/game/engine/online_game_controller.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

/// Bug A regression: a duplicate/retransmitted state frame carrying the SAME
/// explicit `sequence` as the last applied frame must be ignored, not
/// re-applied. On a WS reconnect the server can re-send the last frame; the
/// message handler previously dropped only strictly-older frames
/// (`nextSequence < _sequence`), so an equal sequence re-ran the last-move
/// highlight side effects and could produce a "ghost" move.
void main() {
  test('duplicate state frame with equal explicit sequence is ignored',
      () async {
    final now = DateTime.utc(2026, 1, 1, 12);
    final server = await _FakeOnlineServer.start();
    addTearDown(server.dispose);

    final controller = OnlineGameController(nowProvider: () => now);
    addTearDown(controller.dispose);

    await controller.connectManual(
      serverUrl: server.wsUrl,
      roomId: 'room-dup',
      displayName: 'Alice',
    );

    await server.waitForConnection();
    await server.waitForType('join');

    final baseNow = now.millisecondsSinceEpoch;
    server.send(<String, Object?>{
      'type': 'welcome',
      'matchId': 'room-dup',
      'color': 'w',
      'serverNow': baseNow,
    });

    // First frame at sequence 7: opponent (black) played e7->e5.
    final firstGame = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'});
    server.send(<String, Object?>{
      'type': 'state',
      'sequence': 7,
      'status': 'active',
      'fen': firstGame.fen,
      'serverNow': baseNow,
      'cooldownEndsAt': <String, int>{'w': baseNow, 'b': baseNow},
      'turn': 'w',
      'lastMove': <String, Object?>{'from': 'e7', 'to': 'e5'},
    });

    await _waitUntil(() => controller.opponentLastMoveFrom == 'e7');
    expect(controller.opponentLastMoveTo, 'e5');

    // Duplicate frame: SAME explicit sequence 7, but a different lastMove.
    // A correctly-guarded handler must ignore this entirely, so the opponent
    // last-move highlight stays on e7->e5. The buggy handler re-applies it and
    // moves the highlight to d7->d5.
    final dupGame = chess.Chess()
      ..move(<String, String>{'from': 'd2', 'to': 'd4'})
      ..move(<String, String>{'from': 'd7', 'to': 'd5'});
    server.send(<String, Object?>{
      'type': 'state',
      'sequence': 7,
      'status': 'active',
      'fen': dupGame.fen,
      'serverNow': baseNow,
      'cooldownEndsAt': <String, int>{'w': baseNow, 'b': baseNow},
      'turn': 'w',
      'lastMove': <String, Object?>{'from': 'd7', 'to': 'd5'},
    });

    // Give the duplicate a chance to be (wrongly) applied.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      controller.opponentLastMoveFrom,
      'e7',
      reason: 'duplicate equal-sequence frame must not re-apply',
    );
    expect(controller.opponentLastMoveTo, 'e5');
    expect(controller.boardPieces.containsKey('d5'), isFalse);
    expect(controller.boardPieces['e5'], 'p');
  });

  test('legitimately-omitted sequence still applies (guard regression)',
      () async {
    final now = DateTime.utc(2026, 1, 1, 12);
    final server = await _FakeOnlineServer.start();
    addTearDown(server.dispose);

    final controller = OnlineGameController(nowProvider: () => now);
    addTearDown(controller.dispose);

    await controller.connectManual(
      serverUrl: server.wsUrl,
      roomId: 'room-omit',
      displayName: 'Alice',
    );

    await server.waitForConnection();
    await server.waitForType('join');

    final baseNow = now.millisecondsSinceEpoch;
    server.send(<String, Object?>{
      'type': 'welcome',
      'matchId': 'room-omit',
      'color': 'w',
      'serverNow': baseNow,
    });

    // Explicit sequence 3.
    final firstGame = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'});
    server.send(<String, Object?>{
      'type': 'state',
      'sequence': 3,
      'status': 'active',
      'fen': firstGame.fen,
      'serverNow': baseNow,
      'cooldownEndsAt': <String, int>{'w': baseNow, 'b': baseNow},
      'turn': 'w',
      'lastMove': <String, Object?>{'from': 'e7', 'to': 'e5'},
    });

    await _waitUntil(() => controller.opponentLastMoveFrom == 'e7');

    // Sequence OMITTED -> handler defaults it to _sequence + 1 (= 4) and must
    // apply. This proves the equal-drop fix does not break the omitted path.
    final nextGame = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'})
      ..move(<String, String>{'from': 'e7', 'to': 'e5'})
      ..move(<String, String>{'from': 'g1', 'to': 'f3'})
      ..move(<String, String>{'from': 'b8', 'to': 'c6'});
    server.send(<String, Object?>{
      'type': 'state',
      'status': 'active',
      'fen': nextGame.fen,
      'serverNow': baseNow,
      'cooldownEndsAt': <String, int>{'w': baseNow, 'b': baseNow},
      'turn': 'w',
      'lastMove': <String, Object?>{'from': 'b8', 'to': 'c6'},
    });

    await _waitUntil(() => controller.opponentLastMoveFrom == 'b8');
    expect(controller.opponentLastMoveTo, 'c6');
  });
}

class _FakeOnlineServer {
  _FakeOnlineServer(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> _received = <Map<String, dynamic>>[];
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
      _messageStream.add(map);
    });
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  Duration pollEvery = const Duration(milliseconds: 25),
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
