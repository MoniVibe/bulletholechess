import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'chess_rules.dart';

enum OnlineConnectionState { disconnected, connecting, connected }

enum BackendHealthState { unknown, checking, healthy, unhealthy }

class OnlineGameController extends ChangeNotifier {
  static const String _defaultPromotion = ChessRules.defaultPromotion;
  static const String _defaultPieceSkinId = 'chess_classic';
  static const Duration _defaultHealthTimeout = Duration(seconds: 5);
  static const Duration _defaultWakeTimeout = Duration(seconds: 15);
  static const int _maxDebugLogEntries = 400;

  OnlineGameController({
    Duration initialCooldownDuration = const Duration(seconds: 3),
    http.Client? httpClient,
  }) : _cooldownDuration = initialCooldownDuration {
    _httpClient = httpClient ?? http.Client();
    _ownsHttpClient = httpClient == null;
    _backendHealthChecker = BackendHealthChecker(
      httpClient: _httpClient,
      defaultTimeout: _defaultHealthTimeout,
      wakeTimeout: _defaultWakeTimeout,
    );
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
  late final http.Client _httpClient;
  late final bool _ownsHttpClient;
  late final BackendHealthChecker _backendHealthChecker;
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
  BackendHealthState _backendHealthState = BackendHealthState.unknown;
  String? _backendHealthMessage;
  DateTime? _backendHealthCheckedAt;

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
  String _myPieceSkinId = _defaultPieceSkinId;
  Map<String, String> _pieceSkinByColor = <String, String>{
    'w': _defaultPieceSkinId,
    'b': _defaultPieceSkinId,
  };

  String? _queuedMoveFrom;
  String? _queuedMoveTo;
  String _queuedPromotion = _defaultPromotion;
  int _queueToken = 0;
  int _nextClientMoveId = 1;
  int? _inFlightClientMoveId;
  String? _inFlightMoveSource;
  int? _inFlightQueueToken;
  final List<String> _debugLogEntries = <String>[];

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
  List<String> get debugLogEntries =>
      List.unmodifiable(_debugLogEntries.reversed.toList(growable: false));
  BackendHealthState get backendHealthState => _backendHealthState;
  String? get backendHealthMessage => _backendHealthMessage;
  DateTime? get backendHealthCheckedAt => _backendHealthCheckedAt;
  Map<String, String> get boardPieces =>
      ChessRules.boardPiecesFromFen(_game.fen);
  List<String> get history => _game.getHistory().cast<String>();
  String get playerColor => _myColor ?? 'w';
  String? get whitePlayerName => _whitePlayerName;
  String? get blackPlayerName => _blackPlayerName;
  String get myPieceSkinId => _myPieceSkinId;

  String pieceSkinIdForColor(String color) {
    return _pieceSkinByColor[color] ?? _defaultPieceSkinId;
  }

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

  void setMyPieceSkin(String skinId) {
    final normalizedSkinId = MultiplayerClientUtils.sanitizeIdentifier(skinId);
    if (normalizedSkinId == null || normalizedSkinId == _myPieceSkinId) {
      return;
    }

    _myPieceSkinId = normalizedSkinId;
    final myColor = _myColor;
    if (myColor != null) {
      _pieceSkinByColor[myColor] = normalizedSkinId;
    } else {
      _pieceSkinByColor = <String, String>{
        'w': normalizedSkinId,
        'b': normalizedSkinId,
      };
    }

    if (isConnected) {
      _send(<String, dynamic>{
        'type': 'set_piece_skin',
        'pieceSkinId': normalizedSkinId,
      });
      _logEvent(
        'piece_skin_update_sent',
        details: <String, Object?>{
          'pieceSkinId': normalizedSkinId,
          'myColor': _myColor,
        },
      );
    }
    notifyListeners();
  }

  void clearDebugLog() {
    _debugLogEntries.clear();
    notifyListeners();
  }

  String buildDebugReport({int maxEntries = 250}) {
    final header = <String>[
      'Bullethole Chess Debug Report',
      'generatedAt=${DateTime.now().toIso8601String()}',
      'connectionState=${_connectionState.name}',
      'matchId=${_matchId ?? '-'}',
      'status=$_status',
      'myColor=${_myColor ?? '-'}',
      'turn=$turnColor',
      'result=${_result ?? '-'}',
      'cooldownSeconds=${_cooldownDuration.inSeconds}',
      'cooldownRemainingWMs=${cooldownRemaining('w').inMilliseconds}',
      'cooldownRemainingBMs=${cooldownRemaining('b').inMilliseconds}',
      'hasQueuedMove=$hasQueuedMove',
      'queueToken=$_queueToken',
      'queuedMove=${queuedMoveLabel ?? '-'}',
      'inFlightMoveId=${_inFlightClientMoveId?.toString() ?? '-'}',
      'inFlightSource=${_inFlightMoveSource ?? '-'}',
      'inFlightQueueToken=${_inFlightQueueToken?.toString() ?? '-'}',
      'historyLen=${history.length}',
      '--- events ---',
    ];

    final start = _debugLogEntries.length > maxEntries
        ? _debugLogEntries.length - maxEntries
        : 0;
    final lines = _debugLogEntries.sublist(start);
    return <String>[...header, ...lines].join('\n');
  }

  void clearQueuedMove() {
    if (!hasQueuedMove) {
      return;
    }
    if (_moveInFlight && _inFlightMoveSource == 'queued') {
      _logEvent(
        'queue_clear_blocked_in_flight',
        details: <String, Object?>{
          'clientMoveId': _inFlightClientMoveId,
          'queueToken': _inFlightQueueToken,
        },
      );
      _feedback = 'Queued move already sent; cannot cancel now.';
      notifyListeners();
      return;
    }
    _logEvent(
      'queue_cleared_by_user',
      details: <String, Object?>{
        'queueToken': _queueToken,
        'from': _queuedMoveFrom,
        'to': _queuedMoveTo,
      },
    );
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
      _logEvent('matchmaking_missing_name');
      _feedback = 'Display name is required.';
      notifyListeners();
      return;
    }

    _logEvent(
      'matchmaking_start',
      details: <String, Object?>{
        'apiBase': apiBaseUrl.trim(),
        'name': normalizedName,
        'cooldownSeconds': cooldownSeconds,
        'pieceSkinId': _myPieceSkinId,
      },
    );
    _connectionState = OnlineConnectionState.connecting;
    _feedback = null;
    if (cooldownSeconds != null && cooldownSeconds > 0) {
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    notifyListeners();

    try {
      final baseUri = MultiplayerClientUtils.parseApiBaseUri(apiBaseUrl);
      final payload = <String, dynamic>{
        'name': normalizedName,
        'pieceSkinId': _myPieceSkinId,
      };
      if (cooldownSeconds != null) {
        payload['cooldownSeconds'] = cooldownSeconds;
      }

      final response = await http.post(
        baseUri.resolve('/api/matches/join'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(payload),
      );

      final body = MultiplayerClientUtils.decodeJsonMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logEvent(
          'matchmaking_http_error',
          details: <String, Object?>{
            'status': response.statusCode,
            'body': response.body,
          },
        );
        throw Exception(
          body['error'] ?? 'Matchmaking failed (${response.statusCode}).',
        );
      }

      final matchId = body['matchId'] as String?;
      final playerId = body['playerId'] as String?;
      final wsPath = body['wsPath'] as String? ?? '/ws';
      final responseCooldown = MultiplayerClientUtils.readInt(
        body['cooldownSeconds'],
      );
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
      _logEvent(
        'matchmaking_success',
        details: <String, Object?>{
          'matchId': matchId,
          'playerId': playerId,
          'cooldownSeconds': _cooldownDuration.inSeconds,
        },
      );
    } catch (error) {
      _logEvent(
        'matchmaking_failed',
        details: <String, Object?>{'error': error.toString()},
      );
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = _friendlyNetworkError(
        error,
        fallback: 'Matchmaking failed: $error',
      );
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
          _feedback = _friendlyNetworkError(
            error,
            fallback: 'Connection error: $error',
          );
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
        'pieceSkinId': _myPieceSkinId,
      });
    } catch (error) {
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = _friendlyNetworkError(
        error,
        fallback: 'Unable to connect: $error',
      );
      notifyListeners();
    }
  }

  Future<void> disconnect({bool notify = true}) async {
    _logEvent(
      'disconnect',
      details: <String, Object?>{
        'matchId': _matchId,
        'connectionState': _connectionState.name,
      },
    );
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
    _pieceSkinByColor = <String, String>{
      'w': _myPieceSkinId,
      'b': _myPieceSkinId,
    };
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
    _inFlightClientMoveId = null;
    _inFlightMoveSource = null;
    _inFlightQueueToken = null;
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
      _logEvent(
        'tap_ignored',
        details: <String, Object?>{
          'square': square,
          'color': color,
          'canInteract': canPlayerInteract,
          'isGameOver': isGameOver,
          'status': _status,
        },
      );
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
        _logEvent(
          'queue_move',
          details: <String, Object?>{
            'from': from,
            'to': square,
            'reason': 'cooldown',
            'remainingMs': cooldownRemaining(color).inMilliseconds,
          },
        );
        _queuePlayerMove(from: from, to: square, promotion: _defaultPromotion);
        _clearSelection();
        _feedback = null;
        notifyListeners();
        return;
      }

      final sent = _sendMove(
        from: from,
        to: square,
        promotion: _defaultPromotion,
        source: 'manual',
      );
      if (sent) {
        _logEvent(
          'send_move',
          details: <String, Object?>{
            'from': from,
            'to': square,
            'promotion': _defaultPromotion,
            'source': 'manual',
            'clientMoveId': _inFlightClientMoveId,
          },
        );
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
        _logEvent(
          'queue_move',
          details: <String, Object?>{
            'from': from,
            'to': square,
            'reason': 'speculative_recapture',
            'remainingMs': cooldownRemaining(color).inMilliseconds,
          },
        );
        _queuePlayerMove(from: from, to: square, promotion: _defaultPromotion);
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
    _logEvent(
      'illegal_move_tap',
      details: <String, Object?>{'selectedFrom': _selectedSquare, 'to': square},
    );
    notifyListeners();
  }

  void requestNewGame({int? cooldownSeconds}) {
    if (!isConnected) {
      _logEvent('new_game_ignored_disconnected');
      return;
    }
    final payload = <String, dynamic>{'type': 'new_game'};
    if (cooldownSeconds != null) {
      payload['cooldownSeconds'] = cooldownSeconds;
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    _logEvent(
      'new_game_requested',
      details: <String, Object?>{
        'cooldownSeconds': cooldownSeconds ?? _cooldownDuration.inSeconds,
      },
    );
    _send(payload);
    notifyListeners();
  }

  Future<bool> checkBackendHealth({
    required String apiBaseUrl,
    Duration timeout = _defaultHealthTimeout,
  }) async {
    _logEvent(
      'backend_health_check_start',
      details: <String, Object?>{'apiBase': apiBaseUrl.trim()},
    );
    _backendHealthState = BackendHealthState.checking;
    _backendHealthMessage = null;
    notifyListeners();

    final result = await _backendHealthChecker.check(
      apiBaseUrl: apiBaseUrl,
      timeout: timeout,
    );
    _backendHealthState = result.ok
        ? BackendHealthState.healthy
        : BackendHealthState.unhealthy;
    _backendHealthMessage = result.ok ? null : result.message;
    _backendHealthCheckedAt = result.checkedAt;
    _logEvent(
      'backend_health_check_result',
      details: <String, Object?>{
        'ok': result.ok,
        'statusCode': result.statusCode,
        'message': _backendHealthMessage,
      },
    );
    notifyListeners();
    return result.ok;
  }

  Future<bool> wakeBackend({required String apiBaseUrl}) async {
    // Some hosts scale containers to zero. A direct request can trigger wake-up.
    _logEvent(
      'backend_wake_start',
      details: <String, Object?>{'apiBase': apiBaseUrl.trim()},
    );
    _backendHealthState = BackendHealthState.checking;
    _backendHealthMessage = 'Requesting backend wake-up...';
    notifyListeners();

    final result = await _backendHealthChecker.wake(apiBaseUrl: apiBaseUrl);
    _backendHealthState = result.ok
        ? BackendHealthState.healthy
        : BackendHealthState.unhealthy;
    _backendHealthMessage = result.ok ? null : result.message;
    _backendHealthCheckedAt = result.checkedAt;
    _logEvent(
      'backend_wake_result',
      details: <String, Object?>{
        'ok': result.ok,
        'statusCode': result.statusCode,
        'message': _backendHealthMessage,
      },
    );
    notifyListeners();
    return result.ok;
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.cancel();
    disconnect(notify: false);
    if (_ownsHttpClient) {
      _httpClient.close();
    }
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
    required String source,
    int? queueToken,
  }) {
    if (!isConnected || _status != 'active' || _moveInFlight) {
      _logEvent(
        'send_move_blocked',
        details: <String, Object?>{
          'from': from,
          'to': to,
          'status': _status,
          'isConnected': isConnected,
          'moveInFlight': _moveInFlight,
        },
      );
      return false;
    }

    final moveId = _nextClientMoveId++;
    final payload = <String, dynamic>{
      'type': 'move',
      'from': from,
      'to': to,
      'promotion': promotion,
      'clientMoveId': moveId,
      'source': source,
      'queueToken': queueToken,
    };
    if (queueToken == null) {
      payload.remove('queueToken');
    }
    _send(payload);
    _moveInFlight = true;
    _inFlightClientMoveId = moveId;
    _inFlightMoveSource = source;
    _inFlightQueueToken = queueToken;
    _logEvent(
      'send_move_payload',
      details: <String, Object?>{
        'clientMoveId': moveId,
        'source': source,
        'queueToken': queueToken,
        'from': from,
        'to': to,
        'promotion': promotion,
      },
    );
    return true;
  }

  Future<int> pullServerDebugLogs({
    required String apiBaseUrl,
    int limit = 120,
  }) async {
    final normalizedLimit = limit.clamp(1, 500);
    _logEvent(
      'server_logs_pull_start',
      details: <String, Object?>{
        'apiBase': apiBaseUrl.trim(),
        'limit': normalizedLimit,
        'matchId': _matchId,
      },
    );

    try {
      final baseUri = MultiplayerClientUtils.parseApiBaseUri(apiBaseUrl);
      final query = <String, String>{'limit': '$normalizedLimit'};
      if (_matchId?.isNotEmpty ?? false) {
        query['matchId'] = _matchId!;
      }
      final response = await _httpClient
          .get(baseUri.resolve('/debug/logs').replace(queryParameters: query))
          .timeout(_defaultHealthTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Server debug logs failed (${response.statusCode})');
      }

      final body = MultiplayerClientUtils.decodeJsonMap(response.body);
      final items = body['items'];
      if (items is! List) {
        _logEvent('server_logs_pull_empty');
        return 0;
      }

      var appended = 0;
      for (final raw in items) {
        if (raw is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(raw);
        _appendServerLogLine(map);
        appended += 1;
      }

      _logEvent(
        'server_logs_pull_success',
        details: <String, Object?>{'appended': appended},
      );
      notifyListeners();
      return appended;
    } catch (error) {
      _logEvent(
        'server_logs_pull_failed',
        details: <String, Object?>{'error': error.toString()},
      );
      notifyListeners();
      return 0;
    }
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
    final queueToken = _queueToken;
    final legalMove = ChessRules.findValidatedLegalMove(
      game: _game,
      from: from,
      to: to,
      color: color,
      promotion: promotion,
    );
    if (legalMove == null) {
      _logEvent(
        'queued_move_cleared_illegal',
        details: <String, Object?>{'from': from, 'to': to},
      );
      _clearQueuedMove();
      _feedback = null;
      return;
    }

    final sent = _sendMove(
      from: from,
      to: to,
      promotion: promotion,
      source: 'queued',
      queueToken: queueToken,
    );
    if (sent) {
      _logEvent(
        'queued_move_executing',
        details: <String, Object?>{
          'queueToken': queueToken,
          'from': from,
          'to': to,
          'promotion': promotion,
        },
      );
      _feedback = null;
    }
  }

  void _queuePlayerMove({
    required String from,
    required String to,
    required String promotion,
  }) {
    _queueToken += 1;
    _queuedMoveFrom = from;
    _queuedMoveTo = to;
    _queuedPromotion = promotion;
    _logEvent(
      'queue_set',
      details: <String, Object?>{
        'queueToken': _queueToken,
        'from': from,
        'to': to,
        'promotion': promotion,
      },
    );
  }

  void _clearQueuedMove() {
    if (_queuedMoveFrom != null && _queuedMoveTo != null) {
      _logEvent(
        'queue_cleared',
        details: <String, Object?>{
          'queueToken': _queueToken,
          'from': _queuedMoveFrom,
          'to': _queuedMoveTo,
        },
      );
    }
    _queueToken += 1;
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
    _logEvent(
      'ws_connect_start',
      details: <String, Object?>{
        'matchId': matchId,
        'playerId': playerId,
        'wsPath': wsPath,
      },
    );
    await disconnect(notify: false);

    final wsUri = MultiplayerClientUtils.websocketUriFromBase(
      baseUri: baseUri,
      wsPath: wsPath,
      queryParameters: <String, String>{
        'matchId': matchId,
        'playerId': playerId,
      },
    );

    try {
      _matchId = matchId;
      final channel = WebSocketChannel.connect(wsUri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object error) {
          _logEvent(
            'ws_stream_error',
            details: <String, Object?>{'error': error.toString()},
          );
          _feedback = _friendlyNetworkError(
            error,
            fallback: 'Connection error: $error',
          );
          _connectionState = OnlineConnectionState.disconnected;
          notifyListeners();
        },
        onDone: () {
          _logEvent('ws_stream_done');
          _connectionState = OnlineConnectionState.disconnected;
          _feedback = 'Disconnected from server.';
          notifyListeners();
        },
        cancelOnError: true,
      );

      _connectionState = OnlineConnectionState.connected;
      _logEvent('ws_connected', details: <String, Object?>{'matchId': matchId});
      notifyListeners();
    } catch (error) {
      _logEvent(
        'ws_connect_failed',
        details: <String, Object?>{'error': error.toString()},
      );
      _connectionState = OnlineConnectionState.disconnected;
      _feedback = _friendlyNetworkError(
        error,
        fallback: 'Unable to connect game socket: $error',
      );
      notifyListeners();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      _logEvent('ws_message_ignored_non_string');
      return;
    }

    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _logEvent('ws_message_ignored_non_map');
        return;
      }
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      _logEvent('ws_message_parse_failed');
      return;
    }

    final type = map['type'];
    if (type is! String) {
      _logEvent('ws_message_missing_type');
      return;
    }

    switch (type) {
      case 'welcome':
        _connectionState = OnlineConnectionState.connected;
        _matchId = map['matchId'] as String? ?? _matchId;
        _myColor = map['color'] as String?;
        final welcomePieceSkinId = MultiplayerClientUtils.sanitizeIdentifier(
          map['pieceSkinId'],
        );
        if (welcomePieceSkinId != null) {
          _myPieceSkinId = welcomePieceSkinId;
          if (_myColor != null) {
            _pieceSkinByColor[_myColor!] = welcomePieceSkinId;
          }
        }

        final welcomeCooldown = MultiplayerClientUtils.readInt(
          map['cooldownSeconds'],
        );
        if (welcomeCooldown != null && welcomeCooldown > 0) {
          _cooldownDuration = Duration(seconds: welcomeCooldown);
        }
        final serverNow = MultiplayerClientUtils.readInt(map['serverNow']);
        if (serverNow != null) {
          _clockOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
        }

        _feedback = null;
        _logEvent(
          'ws_welcome',
          details: <String, Object?>{
            'matchId': _matchId,
            'myColor': _myColor,
            'pieceSkinId': _myPieceSkinId,
            'cooldownSeconds': _cooldownDuration.inSeconds,
          },
        );
        notifyListeners();
        return;
      case 'state':
        _applyState(map);
        return;
      case 'opponent_left':
        _logEvent(
          'ws_opponent_left',
          details: <String, Object?>{'message': map['message']},
        );
        _feedback = map['message'] as String? ?? 'Opponent disconnected.';
        notifyListeners();
        return;
      case 'error':
        _moveInFlight = false;
        _inFlightClientMoveId = null;
        _inFlightMoveSource = null;
        _inFlightQueueToken = null;
        final errorCode = map['code'] as String?;
        final message = map['message'] as String? ?? 'Server error';
        _feedback = message;
        final serverNow = MultiplayerClientUtils.readInt(map['serverNow']);
        if (serverNow != null) {
          _clockOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
        }

        var receivedCooldownSnapshot = false;
        final cooldownEndsAt = map['cooldownEndsAt'];
        if (cooldownEndsAt is Map) {
          final w = MultiplayerClientUtils.readInt(cooldownEndsAt['w']);
          final b = MultiplayerClientUtils.readInt(cooldownEndsAt['b']);
          if (w != null) {
            _whiteReadyAtMs = w;
            receivedCooldownSnapshot = true;
          }
          if (b != null) {
            _blackReadyAtMs = b;
            receivedCooldownSnapshot = true;
          }
        }

        if (!receivedCooldownSnapshot && errorCode == 'cooldown_active') {
          final remainingMs = MultiplayerClientUtils.readInt(
            map['remainingMs'],
          );
          final color = _myColor;
          if (color != null && remainingMs != null && remainingMs > 0) {
            final baseNow = serverNow ?? _estimatedServerNowMs();
            _setReadyAtForColor(color, baseNow + remainingMs);
          }
        }

        if (hasQueuedMove && !_isRetriableQueueError(errorCode, message)) {
          _logEvent(
            'queued_move_cleared_on_error',
            details: <String, Object?>{'code': errorCode, 'message': message},
          );
          _clearQueuedMove();
        }
        _logEvent(
          'ws_error',
          details: <String, Object?>{
            'code': errorCode,
            'message': message,
            'matchId': _matchId,
          },
        );
        notifyListeners();
        return;
      case 'pong':
        _logEvent('ws_pong');
        return;
      default:
        _logEvent(
          'ws_message_unknown_type',
          details: <String, Object?>{'type': type},
        );
        return;
    }
  }

  void _applyState(Map<String, dynamic> state) {
    final nextSequence = state['sequence'] as int? ?? (_sequence + 1);
    if (nextSequence < _sequence) {
      _logEvent(
        'state_ignored_outdated',
        details: <String, Object?>{
          'nextSequence': nextSequence,
          'currentSequence': _sequence,
        },
      );
      return;
    }
    _sequence = nextSequence;

    final serverNow = MultiplayerClientUtils.readInt(state['serverNow']);
    if (serverNow != null) {
      _clockOffsetMs = serverNow - DateTime.now().millisecondsSinceEpoch;
    }

    final cooldownSeconds = MultiplayerClientUtils.readInt(
      state['cooldownSeconds'],
    );
    if (cooldownSeconds != null && cooldownSeconds > 0) {
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    final cooldownMs = MultiplayerClientUtils.readInt(state['cooldownMs']);
    if ((cooldownSeconds == null || cooldownSeconds <= 0) &&
        cooldownMs != null &&
        cooldownMs > 0) {
      _cooldownDuration = Duration(milliseconds: cooldownMs);
    }

    var receivedCooldownSnapshot = false;
    final cooldownEndsAt = state['cooldownEndsAt'];
    if (cooldownEndsAt is Map) {
      final w = MultiplayerClientUtils.readInt(cooldownEndsAt['w']);
      final b = MultiplayerClientUtils.readInt(cooldownEndsAt['b']);
      if (w != null) {
        _whiteReadyAtMs = w;
        receivedCooldownSnapshot = true;
      }
      if (b != null) {
        _blackReadyAtMs = b;
        receivedCooldownSnapshot = true;
      }
    }

    final fen = state['fen'] as String?;
    if (fen != null) {
      final loaded = _game.load(fen);
      if (!loaded) {
        _logEvent('state_invalid_fen', details: <String, Object?>{'fen': fen});
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

    final pieceSkins = state['pieceSkins'];
    if (pieceSkins is Map) {
      final whiteSkin = MultiplayerClientUtils.sanitizeIdentifier(
        pieceSkins['w'],
      );
      final blackSkin = MultiplayerClientUtils.sanitizeIdentifier(
        pieceSkins['b'],
      );
      if (whiteSkin != null) {
        _pieceSkinByColor['w'] = whiteSkin;
      }
      if (blackSkin != null) {
        _pieceSkinByColor['b'] = blackSkin;
      }
      final myColor = _myColor;
      if (myColor != null) {
        final mySkin = _pieceSkinByColor[myColor];
        if (mySkin != null) {
          _myPieceSkinId = mySkin;
        }
      }
    }

    final lastMove = state['lastMove'];
    if (lastMove is Map<String, dynamic>) {
      _lastMoveFrom = lastMove['from'] as String?;
      _lastMoveTo = lastMove['to'] as String?;
      final lastMoveId = MultiplayerClientUtils.readInt(
        lastMove['clientMoveId'],
      );
      final lastMoveSource = lastMove['source'] as String?;
      final lastMoveQueueToken = MultiplayerClientUtils.readInt(
        lastMove['queueToken'],
      );
      final turnAfterMove = state['turn'] as String? ?? turnColor;
      final moverColor = ChessRules.oppositeColor(turnAfterMove);
      _lastMoverColor = moverColor;
      if (!receivedCooldownSnapshot) {
        // Compatibility fallback for older/custom backends that don't emit
        // `cooldownEndsAt` in state payloads. This keeps local timer HUD and
        // queue behavior functional after a confirmed move.
        final fallbackNow = serverNow ?? _estimatedServerNowMs();
        _applyCooldownForMover(moverColor, fallbackNow);
      }
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
        _logEvent(
          'queued_move_confirmed',
          details: <String, Object?>{'from': _lastMoveFrom, 'to': _lastMoveTo},
        );
        _clearQueuedMove();
      }
      if (_myColor != null &&
          moverColor == _myColor &&
          _inFlightClientMoveId != null &&
          lastMoveId != null &&
          _inFlightClientMoveId == lastMoveId) {
        _logEvent(
          'in_flight_move_confirmed',
          details: <String, Object?>{
            'clientMoveId': lastMoveId,
            'source': lastMoveSource,
            'queueToken': lastMoveQueueToken,
          },
        );
        _inFlightClientMoveId = null;
        _inFlightMoveSource = null;
        _inFlightQueueToken = null;
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
    _logEvent(
      'state_applied',
      details: <String, Object?>{
        'sequence': _sequence,
        'status': _status,
        'turn': turnColor,
        'result': _result,
        'historyLen': history.length,
      },
    );
    _refreshSelectionForCurrentBoard();
    notifyListeners();
  }

  void _applyCooldownForMover(String moverColor, int atMs) {
    final nextReady = atMs + _cooldownDuration.inMilliseconds;
    if (moverColor == 'w') {
      _whiteReadyAtMs = nextReady;
      _blackReadyAtMs = atMs;
      return;
    }
    _blackReadyAtMs = nextReady;
    _whiteReadyAtMs = atMs;
  }

  void _setReadyAtForColor(String color, int readyAtMs) {
    if (color == 'w') {
      _whiteReadyAtMs = readyAtMs;
      return;
    }
    _blackReadyAtMs = readyAtMs;
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

  void _logEvent(
    String event, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final ts = DateTime.now().toIso8601String();
    final detailText = details.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    final line = detailText.isEmpty
        ? '[$ts] $event'
        : '[$ts] $event | $detailText';
    _debugLogEntries.add(line);
    while (_debugLogEntries.length > _maxDebugLogEntries) {
      _debugLogEntries.removeAt(0);
    }
    if (kDebugMode) {
      debugPrint('[online] $line');
    }
  }

  void _appendServerLogLine(Map<String, dynamic> entry) {
    final at = entry['at']?.toString() ?? '-';
    final event = entry['event']?.toString() ?? 'unknown';
    final level = entry['level']?.toString() ?? 'info';
    final excluded = <String>{'id', 'at', 'event', 'level'};
    final details = entry.entries
        .where((e) => !excluded.contains(e.key) && e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .join(', ');
    final line = details.isEmpty
        ? '[server $at] $event | level=$level'
        : '[server $at] $event | level=$level, $details';
    _debugLogEntries.add(line);
    while (_debugLogEntries.length > _maxDebugLogEntries) {
      _debugLogEntries.removeAt(0);
    }
    if (kDebugMode) {
      debugPrint('[online] $line');
    }
  }

  static String _friendlyNetworkError(
    Object error, {
    required String fallback,
  }) {
    if (error is SocketException) {
      return 'Cannot reach backend (connection refused). Check Backend URL or start the server.';
    }

    final raw = error.toString().toLowerCase();
    if (raw.contains('connection refused')) {
      return 'Cannot reach backend (connection refused). Check Backend URL or start the server.';
    }
    if (raw.contains('failed host lookup')) {
      return 'Backend host lookup failed. Check the Backend URL.';
    }
    return fallback;
  }
}
