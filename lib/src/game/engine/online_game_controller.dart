import 'dart:async';
import 'dart:convert';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

enum OnlineConnectionState { disconnected, connecting, connected }

class OnlineGameController extends ChangeNotifier {
  OnlineGameController();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  OnlineConnectionState _connectionState = OnlineConnectionState.disconnected;
  final chess.Chess _game = chess.Chess();
  int _sequence = 0;
  String? _selectedSquare;
  Set<String> _legalTargets = <String>{};
  String? _lastMoveFrom;
  String? _lastMoveTo;
  String? _lastMoverColor;
  String? _feedback;
  String? _matchId;
  String? _joinCode;
  String? _myColor;
  String _status = 'disconnected';
  String? _whitePlayerName;
  String? _blackPlayerName;
  bool _moveInFlight = false;
  String? _result;

  OnlineConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == OnlineConnectionState.connected;
  String? get roomId => _matchId;
  String? get matchId => _matchId;
  String? get joinCode => _joinCode;
  String? get myColor => _myColor;
  String get turnColor => _colorCode(_game.turn);
  bool get isMyTurn => _myColor != null && _myColor == turnColor;
  bool get isGameOver => _result != null || _game.game_over;
  String? get resultCode => _result;
  String? get selectedSquare => _selectedSquare;
  Set<String> get legalTargets => _legalTargets;
  String? get lastMoveFrom => _lastMoveFrom;
  String? get lastMoveTo => _lastMoveTo;
  bool get isOpponentLastMove =>
      _lastMoverColor != null &&
      _myColor != null &&
      _lastMoverColor != _myColor;
  String? get opponentLastMoveLabel {
    if (!isOpponentLastMove || _lastMoveFrom == null || _lastMoveTo == null) {
      return null;
    }
    return '$_lastMoveFrom-$_lastMoveTo';
  }

  String? get feedback => _feedback;
  Map<String, String> get boardPieces => _boardPiecesFromFen(_game.fen);
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
      return 'Connected. Waiting for opponent to join invite ${_joinCode ?? '-'}.';
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

    if (_moveInFlight) {
      return 'Move sent. Waiting for server...';
    }

    if (isMyTurn) {
      if (_game.in_check) {
        return 'Your turn. You are in check.';
      }
      return 'Your turn.';
    }

    return 'Opponent turn.';
  }

  Future<void> createInvite({
    required String apiBaseUrl,
    required String displayName,
  }) async {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty) {
      _feedback = 'Display name is required.';
      notifyListeners();
      return;
    }

    _connectionState = OnlineConnectionState.connecting;
    _feedback = null;
    notifyListeners();

    try {
      final baseUri = _parseBaseUri(apiBaseUrl);
      final response = await http.post(
        baseUri.resolve('/api/matches/create'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(<String, dynamic>{'name': normalizedName}),
      );

      final body = _decodeResponseMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          body['error'] ?? 'Create invite failed (${response.statusCode}).',
        );
      }

      final matchId = body['matchId'] as String?;
      final playerId = body['playerId'] as String?;
      final wsPath = body['wsPath'] as String? ?? '/ws';
      final joinCode = body['joinCode'] as String?;
      if (matchId == null || playerId == null) {
        throw Exception('Invalid create-match response from server.');
      }

      _joinCode = joinCode;
      await _connectWebSocket(
        baseUri: baseUri,
        wsPath: wsPath,
        matchId: matchId,
        playerId: playerId,
      );
    } catch (error) {
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = 'Create invite failed: $error';
      notifyListeners();
    }
  }

  Future<void> joinInvite({
    required String apiBaseUrl,
    required String joinCode,
    required String displayName,
  }) async {
    final normalizedJoinCode = joinCode.trim().toUpperCase();
    final normalizedName = displayName.trim();

    if (normalizedJoinCode.isEmpty || normalizedName.isEmpty) {
      _feedback = 'Invite code and display name are required.';
      notifyListeners();
      return;
    }

    _connectionState = OnlineConnectionState.connecting;
    _feedback = null;
    notifyListeners();

    try {
      final baseUri = _parseBaseUri(apiBaseUrl);
      final response = await http.post(
        baseUri.resolve('/api/matches/join'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'joinCode': normalizedJoinCode,
          'name': normalizedName,
        }),
      );

      final body = _decodeResponseMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          body['error'] ?? 'Join invite failed (${response.statusCode}).',
        );
      }

      final matchId = body['matchId'] as String?;
      final playerId = body['playerId'] as String?;
      final wsPath = body['wsPath'] as String? ?? '/ws';
      final joinedCode = body['joinCode'] as String?;
      if (matchId == null || playerId == null) {
        throw Exception('Invalid join-match response from server.');
      }

      _joinCode = joinedCode ?? normalizedJoinCode;
      await _connectWebSocket(
        baseUri: baseUri,
        wsPath: wsPath,
        matchId: matchId,
        playerId: playerId,
      );
    } catch (error) {
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = 'Join invite failed: $error';
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
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _connectionState = OnlineConnectionState.disconnected;
    _status = 'disconnected';
    _matchId = null;
    _myColor = null;
    _lastMoverColor = null;
    _result = null;
    if (notify) {
      notifyListeners();
    }
  }

  void tapSquare(String square) {
    if (!isConnected || _status != 'active' || isGameOver || !isMyTurn) {
      return;
    }

    final pieces = boardPieces;
    final piece = pieces[square];
    final ownPiece = piece != null && _pieceColor(piece) == (_myColor ?? '');

    if (_selectedSquare == null) {
      if (ownPiece) {
        _selectedSquare = square;
        _legalTargets = _legalDestinationsFrom(square);
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
    if (_isMoveLegal(from: from, to: square, promotion: 'q')) {
      _send(<String, dynamic>{
        'type': 'move',
        'from': from,
        'to': square,
        'promotion': 'q',
      });
      _moveInFlight = true;
      _clearSelection();
      _feedback = null;
      notifyListeners();
      return;
    }

    if (ownPiece) {
      _selectedSquare = square;
      _legalTargets = _legalDestinationsFrom(square);
      notifyListeners();
      return;
    }

    _feedback = 'Illegal move';
    notifyListeners();
  }

  void requestNewGame() {
    if (!isConnected) {
      return;
    }
    _send(<String, dynamic>{'type': 'new_game'});
  }

  @override
  void dispose() {
    disconnect(notify: false);
    super.dispose();
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

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return;
    }
    final map = Map<String, dynamic>.from(decoded);

    final type = map['type'];
    if (type is! String) {
      return;
    }

    switch (type) {
      case 'welcome':
        _connectionState = OnlineConnectionState.connected;
        _matchId = map['matchId'] as String? ?? _matchId;
        _joinCode = map['joinCode'] as String? ?? _joinCode;
        _myColor = map['color'] as String?;
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
        _feedback = map['message'] as String? ?? 'Server error';
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

    final fen = state['fen'] as String?;
    if (fen != null) {
      final loaded = _game.load(fen);
      if (!loaded) {
        _feedback = 'Received invalid board state from server.';
      }
    }

    _status = state['status'] as String? ?? _status;
    _result = state['result'] as String?;
    _joinCode = state['joinCode'] as String? ?? _joinCode;

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
      _lastMoverColor = _oppositeColor(turnAfterMove);
    } else {
      final history = state['history'];
      if (history is List && history.isEmpty) {
        _lastMoveFrom = null;
        _lastMoveTo = null;
        _lastMoverColor = null;
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
    if (_selectedSquare == null || _myColor == null) {
      return;
    }

    final piece = boardPieces[_selectedSquare!];
    if (piece == null || _pieceColor(piece) != _myColor) {
      _clearSelection();
      return;
    }

    _legalTargets = _legalDestinationsFrom(_selectedSquare!);
  }

  Set<String> _legalDestinationsFrom(String square) {
    return _game
        .moves(<String, dynamic>{'verbose': true})
        .map((dynamic item) => Map<String, dynamic>.from(item as Map))
        .where((move) => move['from'] == square)
        .map((move) => move['to'] as String)
        .toSet();
  }

  bool _isMoveLegal({
    required String from,
    required String to,
    required String promotion,
  }) {
    final legalMoves = _game
        .moves(<String, dynamic>{'verbose': true})
        .map((dynamic item) => Map<String, dynamic>.from(item as Map));

    return legalMoves.any((move) {
      if (move['from'] != from || move['to'] != to) {
        return false;
      }
      final movePromotion = move['promotion'] as String?;
      if (movePromotion == null) {
        return true;
      }
      return movePromotion == promotion;
    });
  }

  void _send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
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

  static String _pieceColor(String piece) {
    return piece == piece.toUpperCase() ? 'w' : 'b';
  }

  static String _colorCode(chess.Color color) {
    return color == chess.Color.WHITE ? 'w' : 'b';
  }

  static String _oppositeColor(String color) {
    return color == 'w' ? 'b' : 'w';
  }

  static Map<String, String> _boardPiecesFromFen(String fen) {
    const files = 'abcdefgh';
    final rows = fen.split(' ').first.split('/');
    final board = <String, String>{};

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      var fileIndex = 0;

      for (final symbol in row.split('')) {
        final emptyCount = int.tryParse(symbol);
        if (emptyCount != null) {
          fileIndex += emptyCount;
          continue;
        }

        final square = '${files[fileIndex]}${8 - rowIndex}';
        board[square] = symbol;
        fileIndex += 1;
      }
    }

    return board;
  }
}
