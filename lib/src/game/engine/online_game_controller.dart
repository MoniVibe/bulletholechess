import 'dart:async';
import 'dart:convert';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'chess_rules.dart';

enum OnlineConnectionState { disconnected, connecting, connected }

class OnlineGameController extends ChangeNotifier {
  static const String _defaultPromotion = ChessRules.defaultPromotion;

  OnlineGameController({
    Duration initialCooldownDuration = const Duration(seconds: 3),
  }) : _cooldownDuration = initialCooldownDuration {
    final now = DateTime.now().millisecondsSinceEpoch;
    _whiteReadyAtMs = now;
    _blackReadyAtMs = now;
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
  }

  final chess.Chess _game = chess.Chess();

  late final Timer _ticker;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  OnlineConnectionState _connectionState = OnlineConnectionState.disconnected;
  Duration _cooldownDuration;
  int _sequence = 0;
  int _clockOffsetMs = 0;
  int _whiteReadyAtMs = 0;
  int _blackReadyAtMs = 0;
  bool _disposed = false;
  bool _moveInFlight = false;

  String? _selectedSquare;
  Set<String> _legalTargets = <String>{};
  String? _myLastMoveFrom;
  String? _myLastMoveTo;
  String? _opponentLastMoveFrom;
  String? _opponentLastMoveTo;
  String? _lastMoveFrom;
  String? _lastMoveTo;
  String? _lastMoverColor;
  String? _feedback;
  String? _matchId;
  String? _myColor;
  String _status = 'disconnected';
  String? _whitePlayerName;
  String? _blackPlayerName;
  String? _result;

  String? _queuedMoveFrom;
  String? _queuedMoveTo;
  String _queuedPromotion = _defaultPromotion;

  OnlineConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == OnlineConnectionState.connected;
  String? get roomId => _matchId;
  String? get matchId => _matchId;
  String? get myColor => _myColor;
  bool get hasActiveGame => _status == 'active';
  bool get isWaitingForOpponent => _status == 'waiting';
  bool get isMatchActive => _status == 'active';
  Duration get cooldownDuration => _cooldownDuration;
  String get turnColor => ChessRules.colorCode(_game.turn);
  bool get isMyTurn => _myColor != null && _myColor == turnColor;
  bool get isGameOver => _result != null || _game.game_over;
  String? get resultCode => _result;
  String? get selectedSquare => _selectedSquare;
  Set<String> get legalTargets => _legalTargets;
  String? get playerLastMoveFrom => _myLastMoveFrom;
  String? get playerLastMoveTo => _myLastMoveTo;
  String? get opponentLastMoveFrom => _opponentLastMoveFrom;
  String? get opponentLastMoveTo => _opponentLastMoveTo;
  String? get lastMoveFrom => _lastMoveFrom;
  String? get lastMoveTo => _lastMoveTo;
  bool get isOpponentLastMove =>
      _lastMoverColor != null &&
      _myColor != null &&
      _lastMoverColor != _myColor;
  bool get hasQueuedMove => _queuedMoveFrom != null && _queuedMoveTo != null;
  String? get queuedMoveFrom => _queuedMoveFrom;
  String? get queuedMoveTo => _queuedMoveTo;
  String? get queuedMoveLabel {
    if (!hasQueuedMove) {
      return null;
    }
    return '$_queuedMoveFrom-$_queuedMoveTo';
  }

  bool get canPlayerInteract {
    final color = _myColor;
    if (!isConnected || _status != 'active' || color == null || isGameOver) {
      return false;
    }
    return ChessRules.hasAnyLegalMove(_game, color);
  }

  String? get opponentLastMoveLabel {
    if (_opponentLastMoveFrom == null || _opponentLastMoveTo == null) {
      return null;
    }
    return '$_opponentLastMoveFrom-$_opponentLastMoveTo';
  }

  String? get feedback => _feedback;
  Map<String, String> get boardPieces => ChessRules.boardPiecesFromFen(_game.fen);
  List<String> get history => _game.getHistory().cast<String>();
  String get playerColor => _myColor ?? 'w';
  String? get whitePlayerName => _whitePlayerName;
  String? get blackPlayerName => _blackPlayerName;

  String get statusText {
    if (_connectionState == OnlineConnectionState.disconnected) {
      return 'Not connected.';
    }
    if (_connectionState == OnlineConnectionState.connecting) {
      return 'Connecting...';
    }

    if (_status == 'waiting') {
      return 'Connected. Waiting for another player...';
    }

    if (isGameOver) {
      switch (_result) {
        case 'white_wins_checkmate':
          return 'White wins by checkmate. Request new game to rematch.';
        case 'black_wins_checkmate':
          return 'Black wins by checkmate. Request new game to rematch.';
        case 'draw':
          return 'Draw game. Request new game to rematch.';
      }

      if (_game.in_checkmate) {
        final winner = turnColor == 'w' ? 'Black' : 'White';
        return '$winner wins by checkmate.';
      }
      if (_game.in_draw) {
        return 'Draw game.';
      }

      return 'Game over. Start a new game/rematch.';
    }

    final color = _myColor;
    if (color == null) {
      return 'Waiting for color assignment...';
    }

    if (ChessRules.isInCheckFor(_game, color)) {
      return 'Your king is in check. Play a legal response.';
    }

    if (hasQueuedMove) {
      final remaining = cooldownRemaining(color);
      if (remaining.inMilliseconds > 0) {
        return 'Queued $queuedMoveLabel (${ChessRules.formatDuration(remaining)}).';
      }
      return _moveInFlight
          ? 'Queued $queuedMoveLabel. Sending...'
          : 'Queued $queuedMoveLabel. Executing...';
    }

    if (_moveInFlight) {
      return 'Move sent. Waiting for server...';
    }

    final myRemaining = cooldownRemaining(color);
    if (myRemaining.inMilliseconds > 0) {
      return 'Cooling down (${ChessRules.formatDuration(myRemaining)}).';
    }

    return 'You can move now.';
  }

  Duration cooldownRemaining(String color) {
    final now = _estimatedServerNowMs();
    final readyAt = color == 'w' ? _whiteReadyAtMs : _blackReadyAtMs;
    final remaining = readyAt - now;
    if (remaining <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: remaining);
  }

  void clearQueuedMove() {
    if (!hasQueuedMove) {
      return;
    }
    _clearQueuedMove();
    _feedback = 'Queued move cleared';
    notifyListeners();
  }

  Future<void> findMatch({
    required String apiBaseUrl,
    required String displayName,
    int? cooldownSeconds,
  }) async {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty) {
      _feedback = 'Display name is required.';
      notifyListeners();
      return;
    }

    _connectionState = OnlineConnectionState.connecting;
    _feedback = null;
    if (cooldownSeconds != null && cooldownSeconds > 0) {
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    notifyListeners();

    try {
      final baseUri = _parseBaseUri(apiBaseUrl);
      final payload = <String, dynamic>{'name': normalizedName};
      if (cooldownSeconds != null) {
        payload['cooldownSeconds'] = cooldownSeconds;
      }

      final response = await http.post(
        baseUri.resolve('/api/matches/join'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(payload),
      );

      final body = _decodeResponseMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          body['error'] ?? 'Matchmaking failed (${response.statusCode}).',
        );
      }

      final matchId = body['matchId'] as String?;
      final playerId = body['playerId'] as String?;
      final wsPath = body['wsPath'] as String? ?? '/ws';
      final responseCooldown = _readInt(body['cooldownSeconds']);
      if (responseCooldown != null && responseCooldown > 0) {
        _cooldownDuration = Duration(seconds: responseCooldown);
      }

      if (matchId == null || playerId == null) {
        throw Exception('Invalid match response from server.');
      }

      await _connectWebSocket(
        baseUri: baseUri,
        wsPath: wsPath,
        matchId: matchId,
        playerId: playerId,
      );
    } catch (error) {
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = 'Matchmaking failed: $error';
      notifyListeners();
    }
  }

  Future<void> connectManual({
    required String serverUrl,
    required String roomId,
    required String displayName,
  }) async {
    await disconnect(notify: false);

    final normalizedRoom = roomId.trim().toLowerCase();
    final normalizedName = displayName.trim();

    if (normalizedRoom.isEmpty || normalizedName.isEmpty) {
      _feedback = 'Room id and display name are required.';
      notifyListeners();
      return;
    }

    _connectionState = OnlineConnectionState.connecting;
    _feedback = null;
    _matchId = normalizedRoom;
    notifyListeners();

    try {
      final uri = Uri.parse(serverUrl.trim());
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object error) {
          _feedback = 'Connection error: $error';
          _connectionState = OnlineConnectionState.disconnected;
          notifyListeners();
        },
        onDone: () {
          _connectionState = OnlineConnectionState.disconnected;
          _feedback = 'Disconnected from server.';
          notifyListeners();
        },
        cancelOnError: true,
      );

      _send(<String, dynamic>{
        'type': 'join',
        'roomId': normalizedRoom,
        'name': normalizedName,
      });
    } catch (error) {
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = 'Unable to connect: $error';
      notifyListeners();
    }
  }

  Future<void> disconnect({bool notify = true}) async {
    _moveInFlight = false;
    _clearSelection();
    _clearQueuedMove();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _connectionState = OnlineConnectionState.disconnected;
    _status = 'disconnected';
    _matchId = null;
    _myColor = null;
    _lastMoverColor = null;
    _myLastMoveFrom = null;
    _myLastMoveTo = null;
    _opponentLastMoveFrom = null;
    _opponentLastMoveTo = null;
    _lastMoveFrom = null;
    _lastMoveTo = null;
    _whitePlayerName = null;
    _blackPlayerName = null;
    _result = null;
    _sequence = 0;
    _clockOffsetMs = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    _whiteReadyAtMs = now;
    _blackReadyAtMs = now;
    _feedback = null;
    if (notify) {
      notifyListeners();
    }
  }

  void tapSquare(String square) {
    final color = _myColor;
    if (color == null || !canPlayerInteract || isGameOver) {
      return;
    }

    final pieces = boardPieces;
    final piece = pieces[square];
    final isOwnPiece = piece != null && ChessRules.pieceColor(piece) == color;

    if (_selectedSquare == null) {
      if (isOwnPiece) {
        _selectedSquare = square;
        _legalTargets = ChessRules.legalDestinationsFrom(
          game: _game,
          square: square,
          color: color,
        );
        _feedback = null;
        notifyListeners();
      }
      return;
    }

    if (_selectedSquare == square) {
      _clearSelection();
      notifyListeners();
      return;
    }

    final from = _selectedSquare!;
    final legalMove = ChessRules.findValidatedLegalMove(
      game: _game,
      from: from,
      to: square,
      color: color,
      promotion: _defaultPromotion,
    );
    final legalNow = legalMove != null;

    if (legalNow) {
      final onCooldown = cooldownRemaining(color).inMilliseconds > 0;
      if (onCooldown) {
        _queuePlayerMove(
          from: from,
          to: square,
          promotion: _defaultPromotion,
        );
        _clearSelection();
        _feedback = null;
        notifyListeners();
        return;
      }

      final sent = _sendMove(
        from: from,
        to: square,
        promotion: _defaultPromotion,
      );
      if (sent) {
        _clearQueuedMove();
        _clearSelection();
        _feedback = null;
        notifyListeners();
      }
      return;
    }

    if (isOwnPiece) {
      final onCooldown = cooldownRemaining(color).inMilliseconds > 0;
      if (onCooldown && _selectedSquare != square) {
        // Allow speculative queueing (e.g. predicted recapture) while cooling down.
        _queuePlayerMove(
          from: from,
          to: square,
          promotion: _defaultPromotion,
        );
        _clearSelection();
        _feedback = null;
        notifyListeners();
        return;
      }
      _selectedSquare = square;
      _legalTargets = ChessRules.legalDestinationsFrom(
        game: _game,
        square: square,
        color: color,
      );
      _feedback = null;
      notifyListeners();
      return;
    }

    _feedback = 'Illegal move';
    notifyListeners();
  }

  void requestNewGame({int? cooldownSeconds}) {
    if (!isConnected) {
      return;
    }
    final payload = <String, dynamic>{'type': 'new_game'};
    if (cooldownSeconds != null) {
      payload['cooldownSeconds'] = cooldownSeconds;
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    _send(payload);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.cancel();
    disconnect(notify: false);
    super.dispose();
  }

  void _onTick() {
    if (_disposed || !isConnected) {
      return;
    }

    if (_status == 'active') {
      _tryExecuteQueuedPlayerMove();
    }

    if (_status == 'active' || hasQueuedMove) {
      notifyListeners();
    }
  }

  bool _sendMove({
    required String from,
    required String to,
    required String promotion,
  }) {
    if (!isConnected || _status != 'active' || _moveInFlight) {
      return false;
    }

    _send(<String, dynamic>{
      'type': 'move',
      'from': from,
      'to': to,
      'promotion': promotion,
    });
    _moveInFlight = true;
    return true;
  }

  void _tryExecuteQueuedPlayerMove() {
    final color = _myColor;
    if (color == null || !hasQueuedMove || isGameOver || _moveInFlight) {
      return;
    }
    if (cooldownRemaining(color).inMilliseconds > 0) {
      return;
    }

    final from = _queuedMoveFrom!;
    final to = _queuedMoveTo!;
    final promotion = _queuedPromotion;
    final legalMove = ChessRules.findValidatedLegalMove(
      game: _game,
      from: from,
      to: to,
      color: color,
      promotion: promotion,
    );
    if (legalMove == null) {
      _clearQueuedMove();
      _feedback = null;
      return;
    }

    final sent = _sendMove(from: from, to: to, promotion: promotion);
    if (sent) {
      _feedback = null;
    }
  }

  void _queuePlayerMove({
    required String from,
    required String to,
    required String promotion,
  }) {
    _queuedMoveFrom = from;
    _queuedMoveTo = to;
    _queuedPromotion = promotion;
  }

  void _clearQueuedMove() {
    _queuedMoveFrom = null;
    _queuedMoveTo = null;
    _queuedPromotion = _defaultPromotion;
  }

  Future<void> _connectWebSocket({
    required Uri baseUri,
    required String wsPath,
    required String matchId,
    required String playerId,
  }) async {
    await disconnect(notify: false);

    final wsUri = _wsUriFromBase(baseUri, wsPath, <String, String>{
      'matchId': matchId,
      'playerId': playerId,
    });

    try {
      _matchId = matchId;
      final channel = WebSocketChannel.connect(wsUri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object error) {
          _feedback = 'Connection error: $error';
          _connectionState = OnlineConnectionState.disconnected;
          notifyListeners();
        },
        onDone: () {
          _connectionState = OnlineConnectionState.disconnected;
          _feedback = 'Disconnected from server.';
          notifyListeners();
        },
        cancelOnError: true,
      );

      _connectionState = OnlineConnectionState.connected;
      notifyListeners();
    } catch (error) {
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = 'Unable to connect game socket: $error';
      notifyListeners();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      return;
    }

    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final type = map['type'];
    if (type is! String) {
      return;
    }

    switch (type) {
      case 'welcome':
        _connectionState = OnlineConnectionState.connected;
        _matchId = map['matchId'] as String? ?? _matchId;
        _myColor = map['color'] as String?;

        final welcomeCooldown = _readInt(map['cooldownSeconds']);
        if (welcomeCooldown != null && welcomeCooldown > 0) {
          _cooldownDuration = Duration(seconds: welcomeCooldown);
        }
        final serverNow = _readInt(map['serverNow']);
        if (serverNow != null) {
          _clockOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
        }

        _feedback = null;
        notifyListeners();
        return;
      case 'state':
        _applyState(map);
        return;
      case 'opponent_left':
        _feedback = map['message'] as String? ?? 'Opponent disconnected.';
        notifyListeners();
        return;
      case 'error':
        _moveInFlight = false;
        final errorCode = map['code'] as String?;
        final message = map['message'] as String? ?? 'Server error';
        _feedback = message;
        final serverNow = _readInt(map['serverNow']);
        if (serverNow != null) {
          _clockOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
        }

        final cooldownEndsAt = map['cooldownEndsAt'];
        if (cooldownEndsAt is Map) {
          final w = _readInt(cooldownEndsAt['w']);
          final b = _readInt(cooldownEndsAt['b']);
          if (w != null) {
            _whiteReadyAtMs = w;
          }
          if (b != null) {
            _blackReadyAtMs = b;
          }
        }

        if (hasQueuedMove && !_isRetriableQueueError(errorCode, message)) {
          _clearQueuedMove();
        }
        notifyListeners();
        return;
      case 'pong':
        return;
      default:
        return;
    }
  }

  void _applyState(Map<String, dynamic> state) {
    final nextSequence = state['sequence'] as int? ?? (_sequence + 1);
    if (nextSequence < _sequence) {
      return;
    }
    _sequence = nextSequence;

    final serverNow = _readInt(state['serverNow']);
    if (serverNow != null) {
      _clockOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
    }

    final cooldownSeconds = _readInt(state['cooldownSeconds']);
    if (cooldownSeconds != null && cooldownSeconds > 0) {
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    final cooldownMs = _readInt(state['cooldownMs']);
    if ((cooldownSeconds == null || cooldownSeconds <= 0) &&
        cooldownMs != null &&
        cooldownMs > 0) {
      _cooldownDuration = Duration(milliseconds: cooldownMs);
    }

    final cooldownEndsAt = state['cooldownEndsAt'];
    if (cooldownEndsAt is Map) {
      final w = _readInt(cooldownEndsAt['w']);
      final b = _readInt(cooldownEndsAt['b']);
      if (w != null) {
        _whiteReadyAtMs = w;
      }
      if (b != null) {
        _blackReadyAtMs = b;
      }
    }

    final fen = state['fen'] as String?;
    if (fen != null) {
      final loaded = _game.load(fen);
      if (!loaded) {
        _feedback = 'Received invalid board state from server.';
      }
    }

    _status = state['status'] as String? ?? _status;
    _result = state['result'] as String?;

    final players = state['players'];
    if (players is Map<String, dynamic>) {
      _whitePlayerName = players['w'] as String?;
      _blackPlayerName = players['b'] as String?;
    }

    final lastMove = state['lastMove'];
    if (lastMove is Map<String, dynamic>) {
      _lastMoveFrom = lastMove['from'] as String?;
      _lastMoveTo = lastMove['to'] as String?;
      final turnAfterMove = state['turn'] as String? ?? turnColor;
      final moverColor = ChessRules.oppositeColor(turnAfterMove);
      _lastMoverColor = moverColor;
      if (_myColor != null && moverColor == _myColor) {
        _myLastMoveFrom = _lastMoveFrom;
        _myLastMoveTo = _lastMoveTo;
      } else {
        _opponentLastMoveFrom = _lastMoveFrom;
        _opponentLastMoveTo = _lastMoveTo;
      }

      if (hasQueuedMove &&
          _myColor != null &&
          moverColor == _myColor &&
          _queuedMoveFrom == _lastMoveFrom &&
          _queuedMoveTo == _lastMoveTo) {
        _clearQueuedMove();
      }
    } else {
      final history = state['history'];
      if (history is List && history.isEmpty) {
        _myLastMoveFrom = null;
        _myLastMoveTo = null;
        _opponentLastMoveFrom = null;
        _opponentLastMoveTo = null;
        _lastMoveFrom = null;
        _lastMoveTo = null;
        _lastMoverColor = null;
        _clearQueuedMove();
      }
    }

    _moveInFlight = false;
    _refreshSelectionForCurrentBoard();
    notifyListeners();
  }

  void _clearSelection() {
    _selectedSquare = null;
    _legalTargets = <String>{};
  }

  void _refreshSelectionForCurrentBoard() {
    final color = _myColor;
    if (_selectedSquare == null || color == null) {
      return;
    }

    final piece = boardPieces[_selectedSquare!];
    if (piece == null || ChessRules.pieceColor(piece) != color) {
      _clearSelection();
      return;
    }

    _legalTargets = ChessRules.legalDestinationsFrom(
      game: _game,
      square: _selectedSquare!,
      color: color,
    );
  }

  void _send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  int _estimatedServerNowMs() {
    return DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;
  }

  bool _isRetriableQueueError(String? code, String message) {
    if (code == 'cooldown_active') {
      return true;
    }
    return message.toLowerCase().contains('cooldown');
  }

  static Uri _parseBaseUri(String raw) {
    final uri = Uri.parse(raw.trim());
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw Exception('Use a full URL like https://your-host');
    }
    return uri;
  }

  static Map<String, dynamic> _decodeResponseMap(String body) {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return <String, dynamic>{};
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Uri _wsUriFromBase(
    Uri baseUri,
    String wsPath,
    Map<String, String> query,
  ) {
    final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final normalizedPath = wsPath.startsWith('/') ? wsPath : '/$wsPath';
    return baseUri.replace(
      scheme: scheme,
      path: normalizedPath,
      queryParameters: query,
    );
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

}
