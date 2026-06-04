import 'dart:async';

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../config/app_runtime_config.dart';
import '../engine/online_game_controller.dart';
import 'online/widgets/online_board_timer_stage.dart';
import 'online/widgets/online_match_found_overlay.dart';
import 'online/widgets/online_matchmaking_settings_card.dart';
import 'online/widgets/online_victory_overlay.dart';
import 'skin_catalog.dart';

class OnlineGamePanel extends StatefulWidget {
  const OnlineGamePanel({
    this.isOnlineMode = true,
    this.onModeChanged,
    this.showModeSwitch = true,
    super.key,
  });

  final bool isOnlineMode;
  final ValueChanged<bool>? onModeChanged;
  final bool showModeSwitch;

  @override
  State<OnlineGamePanel> createState() => _OnlineGamePanelState();
}

class _OnlineGamePanelState extends State<OnlineGamePanel>
    with SingleTickerProviderStateMixin {
  static const List<int> _cooldownOptionsSeconds = [2, 3, 5, 7, 10];
  static const Set<String> _ownedChessPieceSkinIds = <String>{
    'chess_sashite_western',
    'chess_classic',
    'chess_red_pieces',
  };

  late final OnlineGameController _controller;
  late final TextEditingController _nameController;
  late final ScrollController _matchSettingsScrollController;
  late final AnimationController _matchFoundOverlayAnimation;
  late final Animation<double> _matchFoundFadeAnimation;
  late final Animation<double> _matchFoundScaleAnimation;
  Timer? _matchFoundDismissTimer;

  bool _connecting = false;
  bool _backendActionInFlight = false;
  bool _isMatchMenuOpen = false;
  bool _isBoardSettingsOpen = false;
  bool _showMatchFoundOverlay = false;
  bool _wasMatchActive = false;
  int _selectedCooldownSeconds = 3;
  String _selectedChessBoardSkinId = SkinCatalog.defaultChessBoardSkinId;
  TimeBarOrientation _timeBarOrientation = TimeBarOrientation.horizontal;

  @override
  void initState() {
    super.initState();
    _controller = OnlineGameController();
    _nameController = TextEditingController(text: 'Player');
    _matchSettingsScrollController = ScrollController();
    _matchFoundOverlayAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 280),
    );
    _matchFoundFadeAnimation = CurvedAnimation(
      parent: _matchFoundOverlayAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _matchFoundScaleAnimation = Tween<double>(begin: 0.965, end: 1.0).animate(
      CurvedAnimation(
        parent: _matchFoundOverlayAnimation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _wasMatchActive = _controller.isMatchActive;
    _controller.addListener(_handleControllerStateChange);
    _checkBackendHealth();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerStateChange);
    _matchFoundDismissTimer?.cancel();
    _matchFoundOverlayAnimation.dispose();
    _matchSettingsScrollController.dispose();
    _nameController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final connected =
            _controller.connectionState == OnlineConnectionState.connected;
        final canStart = !connected && !_connecting;

        final history = _controller.history;
        final tailHistory = history.length > 8
            ? history.sublist(history.length - 8)
            : history;
        final chessBoardSkin = SkinCatalog.chessBoardById(
          _selectedChessBoardSkinId,
        );
        final myPieceSkinId = _controller.myPieceSkinId;
        final whitePieceSkinId = _controller.pieceSkinIdForColor('w');
        final blackPieceSkinId = _controller.pieceSkinIdForColor('b');
        final whiteChessPieceSkin = SkinCatalog.chessPieceById(
          whitePieceSkinId,
        );
        final blackChessPieceSkin = SkinCatalog.chessPieceById(
          blackPieceSkinId,
        );
        final invertBlackPieceColors = _shouldInvertBlackChessPieces(
          whiteSkinId: whitePieceSkinId,
          blackSkinId: blackPieceSkinId,
          whiteSkin: whiteChessPieceSkin,
          blackSkin: blackChessPieceSkin,
        );
        final whiteRemaining = _controller.cooldownRemaining('w');
        final blackRemaining = _controller.cooldownRemaining('b');
        final timerHasStarted =
            _controller.hasActiveGame &&
            (_controller.lastMoveFrom != null &&
                _controller.lastMoveTo != null);

        String? activeWindowColor() {
          if (!_controller.isMatchActive || !timerHasStarted) {
            return null;
          }
          return _controller.turnColor;
        }

        Duration activeWindowRemaining() {
          final active = activeWindowColor();
          if (active == null) {
            return Duration.zero;
          }
          return active == 'w' ? blackRemaining : whiteRemaining;
        }

        Duration displayedRemainingForColor(String color) {
          final active = activeWindowColor();
          if (active == null || color != active) {
            return Duration.zero;
          }
          return activeWindowRemaining();
        }

        final topColor = _controller.playerColor == 'w' ? 'b' : 'w';
        final bottomColor = _controller.playerColor;
        final whiteIsPlayer = _controller.myColor == 'w';
        final blackIsPlayer = _controller.myColor == 'b';
        final topRemaining = displayedRemainingForColor(topColor);
        final bottomRemaining = displayedRemainingForColor(bottomColor);
        final topIsPlayer = topColor == 'w' ? whiteIsPlayer : blackIsPlayer;
        final bottomIsPlayer = bottomColor == 'w'
            ? whiteIsPlayer
            : blackIsPlayer;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              OnlineMatchmakingSettingsCard(
                isOpen: _isMatchMenuOpen,
                onToggle: () {
                  setState(() {
                    _isMatchMenuOpen = !_isMatchMenuOpen;
                  });
                },
                showModeSwitch: widget.showModeSwitch,
                isOnlineMode: widget.isOnlineMode,
                onModeChanged: widget.onModeChanged,
                scrollController: _matchSettingsScrollController,
                nameController: _nameController,
                cooldownOptionsSeconds: _cooldownOptionsSeconds,
                selectedCooldownSeconds: _selectedCooldownSeconds,
                onCooldownChanged: (value) {
                  setState(() {
                    _selectedCooldownSeconds = value;
                  });
                },
                isBoardSettingsOpen: _isBoardSettingsOpen,
                onBoardSettingsToggle: () {
                  setState(() {
                    _isBoardSettingsOpen = !_isBoardSettingsOpen;
                  });
                },
                timeBarOrientation: _timeBarOrientation,
                onTimeBarOrientationChanged: (orientation) {
                  setState(() {
                    _timeBarOrientation = orientation;
                  });
                },
                selectedChessBoardSkinId: _selectedChessBoardSkinId,
                chessBoardDropdownItems: _chessBoardDropdownItems(),
                onChessBoardSkinChanged: (value) {
                  setState(() {
                    _selectedChessBoardSkinId = value;
                  });
                },
                myPieceSkinId: myPieceSkinId,
                ownedChessPieceSkinIds: _ownedChessPieceSkinIds,
                onMyPieceSkinChanged: _controller.setMyPieceSkin,
                canStart: canStart,
                connected: connected,
                onFindMatch: _findMatch,
                onDisconnect: _disconnect,
                backendHealthState: _controller.backendHealthState,
                backendHealthMessage: _controller.backendHealthMessage,
                backendHealthCheckedAt: _controller.backendHealthCheckedAt,
                backendActionInFlight: _backendActionInFlight,
                onCheckBackendHealth: _checkBackendHealth,
                onWakeBackend: _wakeBackend,
                onRequestNewGame: () {
                  _controller.requestNewGame(
                    cooldownSeconds: _selectedCooldownSeconds,
                  );
                },
                hasQueuedMove: _controller.hasQueuedMove,
                queuedMoveLabel: _controller.queuedMoveLabel,
                onClearQueuedMove: _controller.clearQueuedMove,
                debugLogExportButton: DebugLogExportButton(
                  logTextProvider: _controller.exportDebugLog,
                  iconOnly: true,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: OnlineBoardTimerStage(
                  pieces: _controller.boardPieces,
                  playerColor: _controller.playerColor,
                  boardAssetPath: chessBoardSkin.assetPath,
                  playableInsetRatio: chessBoardSkin.playableInsetRatio,
                  playableSizeRatio: chessBoardSkin.playableSizeRatio,
                  whitePieceSprites: whiteChessPieceSkin.spriteMap,
                  blackPieceSprites: blackChessPieceSkin.spriteMap,
                  whitePieceScale: whiteChessPieceSkin.pieceScale,
                  blackPieceScale: blackChessPieceSkin.pieceScale,
                  whitePieceYOffset: whiteChessPieceSkin.pieceYOffset,
                  blackPieceYOffset: blackChessPieceSkin.pieceYOffset,
                  invertBlackPieceColors: invertBlackPieceColors,
                  selectedSquare: _controller.selectedSquare,
                  legalTargets: _controller.legalTargets,
                  playerLastMoveFrom: _controller.playerLastMoveFrom,
                  playerLastMoveTo: _controller.playerLastMoveTo,
                  opponentLastMoveFrom: _controller.opponentLastMoveFrom,
                  opponentLastMoveTo: _controller.opponentLastMoveTo,
                  queuedMoveFrom: _controller.queuedMoveFrom,
                  queuedMoveTo: _controller.queuedMoveTo,
                  checkedKingSquares: _controller.checkedKingSquares,
                  isOnlineCheckmate: _isOnlineCheckmate(),
                  boardMessage: _onlineBoardMessage(),
                  onSquareTap: _controller.tapSquare,
                  isConnected: _controller.isConnected,
                  isWaitingForOpponent: _controller.isWaitingForOpponent,
                  isMatchActive: _controller.isMatchActive,
                  isGameOver: _controller.isGameOver,
                  canStart: canStart,
                  onFindMatch: _findMatch,
                  showMatchFoundOverlay: _showMatchFoundOverlay,
                  matchFoundOverlay: _buildMatchFoundOverlay(
                    topColor: topColor,
                    bottomColor: bottomColor,
                  ),
                  victoryOverlay: OnlineVictoryOverlay(
                    title: _onlineVictoryTitle(),
                    subtitle: _onlineVictorySubtitle(),
                    actionLabel: 'Request New Game',
                    onAction: () {
                      _controller.requestNewGame(
                        cooldownSeconds: _selectedCooldownSeconds,
                      );
                    },
                  ),
                  timeBarOrientation: _timeBarOrientation,
                  topColor: topColor,
                  bottomColor: bottomColor,
                  topRemaining: topRemaining,
                  bottomRemaining: bottomRemaining,
                  cooldownDuration: _controller.cooldownDuration,
                  timerHasStarted: timerHasStarted,
                  topIsActiveWindow: activeWindowColor() == topColor,
                  bottomIsActiveWindow: activeWindowColor() == bottomColor,
                  topIsPlayer: topIsPlayer,
                  bottomIsPlayer: bottomIsPlayer,
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Moves:',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tailHistory.isEmpty ? '-' : tailHistory.join('  '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isOnlineCheckmate() {
    final result = _controller.resultCode;
    return result == 'white_wins_checkmate' || result == 'black_wins_checkmate';
  }

  String? _onlineBoardMessage() {
    final result = _controller.resultCode;
    if (result == 'white_wins_checkmate') {
      return 'Checkmate - White wins';
    }
    if (result == 'black_wins_checkmate') {
      return 'Checkmate - Black wins';
    }
    if (result == 'draw') {
      return 'Draw';
    }
    if (_controller.checkedKingSquares.isNotEmpty) {
      return 'Check';
    }
    return null;
  }

  String _onlineVictoryTitle() {
    final result = _controller.resultCode;
    if (result == 'white_wins_checkmate') {
      return 'White Wins';
    }
    if (result == 'black_wins_checkmate') {
      return 'Black Wins';
    }
    if (result == 'draw') {
      return 'Draw';
    }
    if (result != null && result.isNotEmpty) {
      return _humanizeResultCode(result);
    }
    final status = _controller.statusText.toLowerCase();
    if (status.contains('white wins')) {
      return 'White Wins';
    }
    if (status.contains('black wins')) {
      return 'Black Wins';
    }
    if (status.contains('draw')) {
      return 'Draw';
    }
    return 'Game Over';
  }

  String _onlineVictorySubtitle() {
    final result = _controller.resultCode;
    if (result == 'white_wins_checkmate' || result == 'black_wins_checkmate') {
      return 'Checkmate. Request a new game for a rematch.';
    }
    if (result == 'draw') {
      return 'The match ended in a draw. Request a new game to continue.';
    }
    if (result != null && result.isNotEmpty) {
      return '${_humanizeResultCode(result)}. Request a new game to continue.';
    }
    return _controller.statusText;
  }

  static String _humanizeResultCode(String code) {
    final tokens = code.split('_').where((part) => part.isNotEmpty).toList();
    if (tokens.isEmpty) {
      return 'Game Over';
    }
    return tokens
        .map(
          (token) =>
              '${token[0].toUpperCase()}${token.length > 1 ? token.substring(1) : ''}',
        )
        .join(' ');
  }

  void _handleControllerStateChange() {
    final isMatchActive = _controller.isMatchActive;
    if (!_wasMatchActive && isMatchActive) {
      _showMatchFoundBanner();
    }
    _wasMatchActive = isMatchActive;
  }

  void _showMatchFoundBanner() {
    _matchFoundDismissTimer?.cancel();
    if (mounted) {
      setState(() {
        _showMatchFoundOverlay = true;
      });
    }
    _matchFoundOverlayAnimation.forward(from: 0);
    _matchFoundDismissTimer = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) {
        return;
      }
      _matchFoundOverlayAnimation.reverse().whenComplete(() {
        if (!mounted) {
          return;
        }
        setState(() {
          _showMatchFoundOverlay = false;
        });
      });
    });
  }

  Widget _buildMatchFoundOverlay({
    required String topColor,
    required String bottomColor,
  }) {
    return OnlineMatchFoundOverlay(
      fadeAnimation: _matchFoundFadeAnimation,
      scaleAnimation: _matchFoundScaleAnimation,
      topColor: topColor,
      bottomColor: bottomColor,
      topPlayerName: _displayNameForColor(topColor),
      bottomPlayerName: _displayNameForColor(bottomColor),
    );
  }

  String _displayNameForColor(String color) {
    final name = color == 'w'
        ? _controller.whitePlayerName
        : _controller.blackPlayerName;
    if (name == null || name.trim().isEmpty) {
      return color == 'w' ? 'White Player' : 'Black Player';
    }
    return name.trim();
  }

  bool _shouldInvertBlackChessPieces({
    required String whiteSkinId,
    required String blackSkinId,
    required ChessPieceSkinOption whiteSkin,
    required ChessPieceSkinOption blackSkin,
  }) {
    if (whiteSkinId != blackSkinId) {
      return false;
    }

    const whiteSymbols = <String>['P', 'R', 'N', 'B', 'Q', 'K'];
    const blackSymbols = <String>['p', 'r', 'n', 'b', 'q', 'k'];
    for (var i = 0; i < whiteSymbols.length; i++) {
      final whiteAsset = whiteSkin.spriteMap[whiteSymbols[i]];
      final blackAsset = blackSkin.spriteMap[blackSymbols[i]];
      if (whiteAsset == null ||
          blackAsset == null ||
          whiteAsset != blackAsset) {
        return false;
      }
    }

    return true;
  }

  List<DropdownMenuItem<String>> _chessBoardDropdownItems() {
    return SkinCatalog.chessBoardSkins
        .map(
          (board) => DropdownMenuItem<String>(
            value: board.id,
            child: Text(board.label),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _findMatch() async {
    setState(() {
      _connecting = true;
    });

    try {
      await _controller.findMatch(
        apiBaseUrl: _resolvedApiBaseUrl(),
        displayName: _nameController.text,
        cooldownSeconds: _selectedCooldownSeconds,
      );
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
          _isMatchMenuOpen = false;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    await _controller.disconnect();
  }

  Future<void> _checkBackendHealth() async {
    if (_backendActionInFlight) {
      return;
    }
    setState(() {
      _backendActionInFlight = true;
    });
    try {
      await _controller.checkBackendHealth(apiBaseUrl: _resolvedApiBaseUrl());
    } finally {
      if (mounted) {
        setState(() {
          _backendActionInFlight = false;
        });
      }
    }
  }

  Future<void> _wakeBackend() async {
    if (_backendActionInFlight) {
      return;
    }
    setState(() {
      _backendActionInFlight = true;
    });
    try {
      await _controller.wakeBackend(apiBaseUrl: _resolvedApiBaseUrl());
    } finally {
      if (mounted) {
        setState(() {
          _backendActionInFlight = false;
        });
      }
    }
  }

  String _resolvedApiBaseUrl() {
    // Keep backend selection non-editable in the UI.
    // Source of truth remains runtime configuration.
    return AppRuntimeConfig.defaultBackendUrl;
  }
}
