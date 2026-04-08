import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'chess_rules.dart';
part 'online/online_game_controller_clock_forfeit.dart';
part 'online/online_game_controller_debug.dart';
part 'online/online_game_controller_health.dart';
part 'online/online_game_controller_message_handler.dart';
part 'online/online_game_controller_queue.dart';
part 'online/online_game_controller_session.dart';

class OnlineGameController extends ChangeNotifier {
  static const String _defaultPromotion = ChessRules.defaultPromotion;
  static const String _defaultPieceSkinId = 'chess_classic';
  static const bool _disableQueuedInput = bool.fromEnvironment(
    'CHESS_DISABLE_QUEUED_INPUT',
    defaultValue: false,
  );
  static const Duration _defaultHealthTimeout = Duration(seconds: 5);
  static const Duration _defaultWakeTimeout = Duration(seconds: 15);
  static const int _maxDebugLogEntries = 400;

  OnlineGameController({
    Duration initialCooldownDuration = const Duration(seconds: 3),
    http.Client? httpClient,
    DateTime Function()? nowProvider,
  }) : _cooldownDuration = initialCooldownDuration,
       _now = nowProvider ?? DateTime.now {
    _httpClient = httpClient ?? http.Client();
    _ownsHttpClient = httpClient == null;
    _transportClient = MultiplayerTransportClient(
      httpClient: _httpClient,
      requestTimeout: _defaultHealthTimeout,
    );
    _backendHealthChecker = BackendHealthChecker(
      httpClient: _httpClient,
      defaultTimeout: _defaultHealthTimeout,
      wakeTimeout: _defaultWakeTimeout,
    );
    final now = _now().millisecondsSinceEpoch;
    _whiteReadyAtMs = now;
    _blackReadyAtMs = now;
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
    _sessionLogger.beginSession(
      sessionLabel: 'controller_boot',
      context: <String, Object?>{
        'cooldownSeconds': _cooldownDuration.inSeconds,
      },
    );
    _sessionLogger.logEvent('controller_initialized');
  }

  final chess.Chess _game = chess.Chess();

  late final Timer _ticker;
  late final http.Client _httpClient;
  late final bool _ownsHttpClient;
  late final BackendHealthChecker _backendHealthChecker;
  late final MultiplayerTransportClient _transportClient;
  final DateTime Function() _now;

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
  String? _forfeitBlockedColor;
  String? _forfeitReleaseByColor;
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
  final GameSessionLogger _sessionLogger = GameSessionLogger(
    applicationId: 'bulletholechess',
    gameId: 'chess',
    mode: 'online',
  );

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
    if (_isBlockedByForfeitLock(color, resolveTimeout: false)) {
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
  Set<String> get checkedKingSquares {
    if (!isConnected || (_status != 'active' && _status != 'game_over')) {
      return const <String>{};
    }
    return ChessRules.checkedKingSquares(_game);
  }

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

    if (_isBlockedByForfeitLock(color)) {
      final releaseBy = _forfeitReleaseByColor;
      if (releaseBy != null) {
        final releaseRemaining = cooldownRemaining(releaseBy);
        if (releaseRemaining.inMilliseconds > 0) {
          return 'Overtime turn forfeited. Waiting ${ChessRules.formatDuration(releaseRemaining)}.';
        }
      }
      return 'Overtime turn forfeited. Waiting for opponent.';
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
      'generatedAt=${_now().toIso8601String()}',
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
    _sessionLogger.beginSession(
      sessionLabel: 'find_match',
      context: <String, Object?>{
        'apiBase': apiBaseUrl.trim(),
        'displayName': normalizedName,
        'cooldownSeconds': cooldownSeconds,
      },
    );
    _connectionState = OnlineConnectionState.connecting;
    _feedback = null;
    if (cooldownSeconds != null && cooldownSeconds > 0) {
      _cooldownDuration = Duration(seconds: cooldownSeconds);
    }
    notifyListeners();

    try {
      final joined = await _transportClient.joinMatch(
        apiBaseUrl: apiBaseUrl,
        displayName: normalizedName,
        pieceSkinId: _myPieceSkinId,
        cooldownSeconds: cooldownSeconds,
        gameType: 'chess',
      );
      if (joined.cooldownSeconds != null && joined.cooldownSeconds! > 0) {
        _cooldownDuration = Duration(seconds: joined.cooldownSeconds!);
      }

      await _connectWebSocket(
        baseUri: joined.baseUri,
        wsPath: joined.wsPath,
        matchId: joined.matchId,
        playerId: joined.playerId,
      );
      _sessionLogger.setRoomOrMatchId(joined.matchId);
      _logEvent(
        'matchmaking_success',
        details: <String, Object?>{
          'matchId': joined.matchId,
          'playerId': joined.playerId,
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
    _sessionLogger.beginSession(
      sessionLabel: 'manual_connect',
      context: <String, Object?>{
        'serverUrl': serverUrl.trim(),
        'roomId': roomId.trim(),
        'displayName': displayName.trim(),
      },
    );
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
      await _transportClient.connectToUri(
        uri: uri,
        onMessage: _onMessage,
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
    await _transportClient.disconnect();
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
    final now = _now().millisecondsSinceEpoch;
    _whiteReadyAtMs = now;
    _blackReadyAtMs = now;
    _clearForfeitLock();
    _feedback = null;
    _sessionLogger.closeSession(
      reason: 'disconnect',
      summary: _sessionSnapshot(),
    );
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
      final chosenPromotion =
          legalMove['promotion'] as String? ?? _defaultPromotion;
      final onCooldown = cooldownRemaining(color).inMilliseconds > 0;
      if (onCooldown && !_disableQueuedInput) {
        _logEvent(
          'queue_move',
          details: <String, Object?>{
            'from': from,
            'to': square,
            'reason': 'cooldown',
            'remainingMs': cooldownRemaining(color).inMilliseconds,
          },
        );
        _queuePlayerMove(from: from, to: square, promotion: chosenPromotion);
        _clearSelection();
        _feedback = null;
        notifyListeners();
        return;
      }
      if (onCooldown && _disableQueuedInput) {
        _feedback =
            'Cooling down (${ChessRules.formatDuration(cooldownRemaining(color))}).';
        _clearSelection();
        notifyListeners();
        return;
      }

      final sent = _sendMove(
        from: from,
        to: square,
        promotion: chosenPromotion,
        source: 'manual',
      );
      if (sent) {
        _logEvent(
          'send_move',
          details: <String, Object?>{
            'from': from,
            'to': square,
            'promotion': chosenPromotion,
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
    _applyBackendHealthResult(
      result: result,
      eventName: 'backend_health_check_result',
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
    _applyBackendHealthResult(result: result, eventName: 'backend_wake_result');
    notifyListeners();
    return result.ok;
  }

  Future<int> pullServerDebugLogs({
    required String apiBaseUrl,
    int limit = 120,
  }) {
    return _pullServerDebugLogsImpl(apiBaseUrl: apiBaseUrl, limit: limit);
  }

  @override
  void notifyListeners() {
    // Async transport callbacks can still arrive briefly during teardown.
    // Ignore notifications once disposed to avoid use-after-dispose crashes.
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _sessionLogger.closeSession(
      reason: 'controller_dispose',
      summary: _sessionSnapshot(),
    );
    _disposed = true;
    _ticker.cancel();
    disconnect(notify: false);
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }
}
