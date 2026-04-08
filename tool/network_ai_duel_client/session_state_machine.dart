part of '../network_ai_duel_client.dart';

class _ChessNetworkAiSession {
  _ChessNetworkAiSession({
    required this.config,
    required this.transport,
    required this.logger,
  }) : _ai = DumbAiEngine(random: Random(config.seed));

  final _Config config;
  final MultiplayerTransportClient transport;
  final _JsonlLogger logger;
  final DumbAiEngine _ai;
  final Completer<void> _done = Completer<void>();

  Timer? _ticker;
  Timer? _watchdog;
  String? _myColor;
  String _status = 'disconnected';
  String? _result;
  String? _fen;
  int _sequence = 0;
  int _clockOffsetMs = 0;
  DateTime? _lastStateAt;
  bool _moveInFlight = false;
  int _nextClientMoveId = 1;
  int? _inFlightClientMoveId;
  String? _inFlightFrom;
  String? _inFlightTo;
  int? _lastAttemptSequence;
  final Map<String, int> _cooldownEndsAt = <String, int>{'w': 0, 'b': 0};
  Map<String, dynamic>? _forfeitLock;
  bool _disposed = false;

  Future<void> run() async {
    final joined = await transport.joinMatch(
      apiBaseUrl: config.backendUrl,
      displayName: config.displayName,
      pieceSkinId: 'chess_classic',
      cooldownSeconds: config.cooldownSeconds,
      gameType: 'chess',
      metadata: <String, dynamic>{'client': 'network_ai_duel'},
    );

    await logger.log(<String, Object?>{
      'event': 'match_joined',
      'at': DateTime.now().toIso8601String(),
      'matchId': joined.matchId,
      'playerId': joined.playerId,
      'wsPath': joined.wsPath,
    });

    await transport.connectSocket(
      baseUri: joined.baseUri,
      wsPath: joined.wsPath,
      matchId: joined.matchId,
      playerId: joined.playerId,
      onMessage: _onMessage,
      onError: (Object error) {
        _finishWithError('WebSocket error: $error');
      },
      onDone: () {
        if (_disposed || _done.isCompleted) {
          return;
        }
        _finish();
      },
    );

    _ticker = Timer.periodic(
      Duration(milliseconds: config.pollMs),
      (_) => _onTick(),
    );
    _watchdog = Timer(Duration(seconds: config.maxSeconds), () {
      if (_done.isCompleted || _disposed) {
        return;
      }
      logger.log(<String, Object?>{
        'event': 'game_over',
        'at': DateTime.now().toIso8601String(),
        'result': 'max_seconds_cutoff',
        'sequence': _sequence,
      });
      _finish();
    });
    await _done.future;
  }

  void _onTick() {
    if (_disposed || _done.isCompleted) {
      return;
    }
    _attemptMoveIfReady();
  }

  void _attemptMoveIfReady() {
    if (_done.isCompleted || _disposed) {
      return;
    }
    if (_status != 'active' || _result != null) {
      return;
    }
    if (_moveInFlight) {
      return;
    }
    if (_lastAttemptSequence != null && _lastAttemptSequence == _sequence) {
      return;
    }
    final myColor = _myColor;
    final fen = _fen;
    if (myColor == null || fen == null || fen.trim().isEmpty) {
      return;
    }
    final lastStateAt = _lastStateAt;
    if (lastStateAt == null ||
        DateTime.now().difference(lastStateAt).inMilliseconds <
            config.settleMs) {
      return;
    }
    if (_isBlockedByForfeitLock(myColor)) {
      return;
    }
    if (_cooldownRemainingMs(myColor) > 0) {
      return;
    }

    final game = chess.Chess();
    final loaded = game.load(fen);
    if (!loaded) {
      _lastAttemptSequence = _sequence;
      logger.log(<String, Object?>{
        'event': 'state_load_failed',
        'at': DateTime.now().toIso8601String(),
        'sequence': _sequence,
        'fen': fen,
      });
      return;
    }

    final move = ChessRules.withTurn<EngineMove?>(
      game,
      myColor,
      () => _ai.chooseMove(game),
    );
    if (move == null) {
      logger.log(<String, Object?>{
        'event': 'no_legal_move',
        'at': DateTime.now().toIso8601String(),
        'color': myColor,
      });
      return;
    }

    final clientMoveId = _nextClientMoveId++;
    final sent = transport.sendJson(<String, dynamic>{
      'type': 'move',
      'from': move.from,
      'to': move.to,
      'promotion': move.promotion,
      'source': 'manual',
      'clientMoveId': clientMoveId,
      'expectedSequence': _sequence,
    });
    if (!sent) {
      return;
    }

    _lastAttemptSequence = _sequence;
    _moveInFlight = true;
    _inFlightClientMoveId = clientMoveId;
    _inFlightFrom = move.from;
    _inFlightTo = move.to;
    logger.log(<String, Object?>{
      'event': 'move_sent',
      'at': DateTime.now().toIso8601String(),
      'clientMoveId': clientMoveId,
      'color': myColor,
      'from': move.from,
      'to': move.to,
      'promotion': move.promotion,
    });
  }

  void _finishWithError(String message) {
    logger.log(<String, Object?>{
      'event': 'fatal',
      'at': DateTime.now().toIso8601String(),
      'message': message,
    });
    if (!_done.isCompleted) {
      _done.completeError(StateError(message));
    }
    _dispose();
  }

  void _finish() {
    if (!_done.isCompleted) {
      _done.complete();
    }
    _dispose();
  }

  void _dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _ticker?.cancel();
    _watchdog?.cancel();
  }
}
