import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bulletholechess/src/game/engine/online_game_controller.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queued move executes after cooldown expires', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final server = await _FakeOnlineServer.start();
    addTearDown(server.dispose);

    final controller = OnlineGameController(nowProvider: () => now);
    addTearDown(controller.dispose);

    await controller.connectManual(
      serverUrl: server.wsUrl,
      roomId: 'room-one',
      displayName: 'Alice',
    );

    await server.waitForConnection();
    await server.waitForType('join');

    final baseNow = now.millisecondsSinceEpoch;
    server.send(<String, Object?>{
      'type': 'welcome',
      'matchId': 'room-one',
      'color': 'w',
      'cooldownSeconds': 1,
      'serverNow': baseNow,
    });
    server.send(
      _statePayload(
        sequence: 1,
        status: 'active',
        fen: chess.Chess.DEFAULT_POSITION,
        serverNow: baseNow,
        cooldownEndsAt: <String, int>{'w': baseNow + 350, 'b': baseNow},
        turn: 'w',
      ),
    );

    await _waitUntil(
      () => controller.isMatchActive && controller.myColor == 'w',
    );

    controller.tapSquare('d2');
    controller.tapSquare('d4');
    expect(controller.hasQueuedMove, isTrue);

    now = now.add(const Duration(milliseconds: 450));

    final moveMessage = await server.waitForType('move');
    expect(moveMessage['source'], 'queued');
    expect(moveMessage['from'], 'd2');
    expect(moveMessage['to'], 'd4');
  });

  test('outdated state sequence is ignored', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final server = await _FakeOnlineServer.start();
    addTearDown(server.dispose);

    final controller = OnlineGameController(nowProvider: () => now);
    addTearDown(controller.dispose);

    await controller.connectManual(
      serverUrl: server.wsUrl,
      roomId: 'room-two',
      displayName: 'Alice',
    );

    await server.waitForConnection();
    await server.waitForType('join');

    final firstGame = chess.Chess()
      ..move(<String, String>{'from': 'e2', 'to': 'e4'});
    final firstFen = firstGame.fen;

    final baseNow = now.millisecondsSinceEpoch;
    server.send(<String, Object?>{
      'type': 'welcome',
      'matchId': 'room-two',
      'color': 'w',
      'serverNow': baseNow,
    });
    server.send(
      _statePayload(
        sequence: 5,
        status: 'active',
        fen: firstFen,
        serverNow: baseNow,
        cooldownEndsAt: <String, int>{'w': baseNow, 'b': baseNow},
        turn: 'b',
      ),
    );

    await _waitUntil(
      () => controller.isMatchActive && controller.boardPieces['e4'] == 'P',
    );

    final staleNow = baseNow + 50;
    server.send(
      _statePayload(
        sequence: 4,
        status: 'waiting',
        fen: chess.Chess.DEFAULT_POSITION,
        serverNow: staleNow,
        cooldownEndsAt: <String, int>{'w': staleNow, 'b': staleNow},
        turn: 'w',
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(controller.isMatchActive, isTrue);
    expect(controller.boardPieces.containsKey('e2'), isFalse);
    expect(controller.boardPieces['e4'], 'P');
  });

  test('disconnect clears transient online state', () async {
    final now = DateTime.utc(2026, 1, 1, 12);
    final server = await _FakeOnlineServer.start();
    addTearDown(server.dispose);

    final controller = OnlineGameController(nowProvider: () => now);
    addTearDown(controller.dispose);

    await controller.connectManual(
      serverUrl: server.wsUrl,
      roomId: 'room-three',
      displayName: 'Alice',
    );

    await server.waitForConnection();
    await server.waitForType('join');

    final baseNow = now.millisecondsSinceEpoch;
    server.send(<String, Object?>{
      'type': 'welcome',
      'matchId': 'room-three',
      'color': 'w',
      'serverNow': baseNow,
    });
    server.send(
      _statePayload(
        sequence: 1,
        status: 'active',
        fen: chess.Chess.DEFAULT_POSITION,
        serverNow: baseNow,
        cooldownEndsAt: <String, int>{'w': baseNow + 500, 'b': baseNow},
        turn: 'w',
      ),
    );

    await _waitUntil(() => controller.isMatchActive);
    controller.tapSquare('d2');
    controller.tapSquare('d4');
    expect(controller.hasQueuedMove, isTrue);

    await controller.disconnect();

    expect(controller.isConnected, isFalse);
    expect(controller.matchId, isNull);
    expect(controller.myColor, isNull);
    expect(controller.feedback, isNull);
    expect(controller.hasQueuedMove, isFalse);
    expect(controller.resultCode, isNull);
    expect(controller.playerLastMoveFrom, isNull);
    expect(controller.opponentLastMoveFrom, isNull);
  });

  test('forfeit lock is released when release cooldown elapses', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final server = await _FakeOnlineServer.start();
    addTearDown(server.dispose);

    final controller = OnlineGameController(nowProvider: () => now);
    addTearDown(controller.dispose);

    await controller.connectManual(
      serverUrl: server.wsUrl,
      roomId: 'room-four',
      displayName: 'Alice',
    );

    await server.waitForConnection();
    await server.waitForType('join');

    final baseNow = now.millisecondsSinceEpoch;
    server.send(<String, Object?>{
      'type': 'welcome',
      'matchId': 'room-four',
      'color': 'w',
      'serverNow': baseNow,
      'forfeitLock': <String, String>{
        'blockedColor': 'w',
        'releaseByColor': 'b',
      },
    });
    server.send(
      _statePayload(
        sequence: 1,
        status: 'active',
        fen: chess.Chess.DEFAULT_POSITION,
        serverNow: baseNow,
        cooldownEndsAt: <String, int>{'w': baseNow, 'b': baseNow + 350},
        turn: 'w',
        forfeitLock: <String, String>{
          'blockedColor': 'w',
          'releaseByColor': 'b',
        },
      ),
    );

    await _waitUntil(() => controller.isMatchActive);
    expect(controller.canPlayerInteract, isFalse);
    expect(controller.statusText, contains('Overtime turn forfeited'));

    now = now.add(const Duration(milliseconds: 450));
    await _waitUntil(() => controller.canPlayerInteract);
    expect(controller.statusText, isNot(contains('Overtime turn forfeited')));
  });
}

Map<String, Object?> _statePayload({
  required int sequence,
  required String status,
  required String fen,
  required int serverNow,
  required Map<String, int> cooldownEndsAt,
  required String turn,
  Map<String, String>? forfeitLock,
}) {
  return <String, Object?>{
    'type': 'state',
    'sequence': sequence,
    'status': status,
    'fen': fen,
    'serverNow': serverNow,
    'cooldownEndsAt': cooldownEndsAt,
    'turn': turn,
    ...?forfeitLock == null
        ? null
        : <String, Object?>{'forfeitLock': forfeitLock},
  };
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
