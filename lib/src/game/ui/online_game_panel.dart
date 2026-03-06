import 'dart:math' as math;

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../engine/online_game_controller.dart';
import 'app_assets.dart';
import 'chess_board_view.dart';
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

class _OnlineGamePanelState extends State<OnlineGamePanel> {
  static const List<int> _cooldownOptionsSeconds = [2, 3, 5, 7, 10];
  static const String _defaultBackendUrl = String.fromEnvironment(
    'DEFAULT_BACKEND_URL',
    defaultValue: 'http://localhost:8080',
  );
  static const Set<String> _ownedChessPieceSkinIds = <String>{
    'chess_classic',
    'chess_red_pieces',
  };

  late final OnlineGameController _controller;
  late final TextEditingController _apiBaseController;
  late final TextEditingController _nameController;

  bool _connecting = false;
  bool _backendActionInFlight = false;
  bool _isMatchMenuOpen = false;
  int _selectedCooldownSeconds = 3;
  String _selectedChessBoardSkinId = SkinCatalog.defaultChessBoardSkinId;
  TimeBarOrientation _timeBarOrientation = TimeBarOrientation.horizontal;

  @override
  void initState() {
    super.initState();
    _controller = OnlineGameController();
    _apiBaseController = TextEditingController(text: _defaultBackendUrl);
    _nameController = TextEditingController(text: 'Player');
    _checkBackendHealth();
  }

  @override
  void dispose() {
    _apiBaseController.dispose();
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

        bool isActiveWindowForColor(String color) =>
            activeWindowColor() == color;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              CollapsibleSettingsCard(
                title: 'Matchmaking',
                isOpen: _isMatchMenuOpen,
                onToggle: () {
                  setState(() {
                    _isMatchMenuOpen = !_isMatchMenuOpen;
                  });
                },
                leading: const AppAssetIcon(
                  AppAssets.settingsIcon,
                  fallbackIcon: Icons.settings,
                  size: 22,
                ),
                trailing: widget.showModeSwitch
                    ? CompactModeSwitch(
                        onlineSelected: widget.isOnlineMode,
                        onChanged: (selected) {
                          final onModeChanged = widget.onModeChanged;
                          if (onModeChanged != null) {
                            onModeChanged(selected);
                          }
                        },
                      )
                    : null,
                child: Column(
                  children: [
                    TextField(
                      controller: _apiBaseController,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        hintText: 'https://your-backend.example.com',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedCooldownSeconds,
                      decoration: const InputDecoration(
                        labelText: 'Cooldown (seconds)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _cooldownOptionsSeconds
                          .map(
                            (seconds) => DropdownMenuItem<int>(
                              value: seconds,
                              child: Text('$seconds s'),
                            ),
                          )
                          .toList(),
                      onChanged: connected
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedCooldownSeconds = value;
                              });
                            },
                    ),
                    const SizedBox(height: 8),
                    TimeBarOrientationSwitch(
                      orientation: _timeBarOrientation,
                      onChanged: (orientation) {
                        setState(() {
                          _timeBarOrientation = orientation;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'chess_board_skin_$_selectedChessBoardSkinId',
                      ),
                      initialValue: _selectedChessBoardSkinId,
                      decoration: const InputDecoration(
                        labelText: 'Select Board',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _chessBoardDropdownItems(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedChessBoardSkinId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>('my_piece_skin_$myPieceSkinId'),
                      initialValue: myPieceSkinId,
                      decoration: const InputDecoration(
                        labelText: 'Player Skin',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: SkinCatalog.chessPieceSkins
                          .map(
                            (skin) => DropdownMenuItem<String>(
                              value: skin.id,
                              enabled: _ownedChessPieceSkinIds.contains(
                                skin.id,
                              ),
                              child: Text(
                                _ownedChessPieceSkinIds.contains(skin.id)
                                    ? skin.label
                                    : '${skin.label} (Locked)',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        _controller.setMyPieceSkin(value);
                      },
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Opponent piece skin is server-driven and read-only on your side. If both players pick the same skin, black auto-inverts for clarity.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6A635A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: canStart ? _findMatch : null,
                            icon: const AppAssetIcon(
                              AppAssets.newGameIcon,
                              fallbackIcon: Icons.groups_2_outlined,
                              size: 20,
                            ),
                            label: const Text('Find Match'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: connected ? _disconnect : null,
                            child: const Text('Disconnect'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _BackendHealthCard(
                      state: _controller.backendHealthState,
                      message: _controller.backendHealthMessage,
                      checkedAt: _controller.backendHealthCheckedAt,
                      busy: _backendActionInFlight,
                      onCheckPressed: _checkBackendHealth,
                      onWakePressed: _wakeBackend,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: connected
                            ? () => _controller.requestNewGame(
                                cooldownSeconds: _selectedCooldownSeconds,
                              )
                            : null,
                        icon: const AppAssetIcon(
                          AppAssets.rematchIcon,
                          fallbackIcon: Icons.replay,
                          size: 18,
                        ),
                        label: const Text('Request New Game'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _controller.hasQueuedMove
                            ? _controller.clearQueuedMove
                            : null,
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: Text(
                          _controller.hasQueuedMove
                              ? 'Clear Queue (${_controller.queuedMoveLabel})'
                              : 'Clear Queue',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildTimingHud(
                isMatchActive: _controller.isMatchActive,
                timerHasStarted: timerHasStarted,
                activeWindowColor: activeWindowColor(),
                isPlayerWindow:
                    activeWindowColor() != null &&
                    activeWindowColor() == _controller.myColor,
                remaining: activeWindowRemaining(),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const baseHorizontalBarHeight = 58.0;
                      const baseVerticalBarWidth = 64.0;
                      const boardGap = 10.0;
                      final showTimeBars = _controller.isMatchActive;
                      final horizontalBarHeight = showTimeBars
                          ? baseHorizontalBarHeight
                          : 0.0;
                      final verticalBarWidth = showTimeBars
                          ? baseVerticalBarWidth
                          : 0.0;
                      final edgeGap = showTimeBars ? boardGap : 0.0;
                      final topColor = _controller.playerColor == 'w'
                          ? 'b'
                          : 'w';
                      final bottomColor = _controller.playerColor;
                      final whiteIsPlayer = _controller.myColor == 'w';
                      final blackIsPlayer = _controller.myColor == 'b';
                      final topRemaining = displayedRemainingForColor(topColor);
                      final bottomRemaining = displayedRemainingForColor(
                        bottomColor,
                      );
                      final topIsPlayer = topColor == 'w'
                          ? whiteIsPlayer
                          : blackIsPlayer;
                      final bottomIsPlayer = bottomColor == 'w'
                          ? whiteIsPlayer
                          : blackIsPlayer;
                      final topActiveColor = topColor == 'w'
                          ? const Color(0xFF42A5F5)
                          : const Color(0xFFFF7043);
                      final bottomActiveColor = bottomColor == 'w'
                          ? const Color(0xFF42A5F5)
                          : const Color(0xFFFF7043);
                      final topFlashTint = topColor == 'w'
                          ? const Color(0xFFBBDEFB)
                          : const Color(0xFFFFCCBC);
                      final bottomFlashTint = bottomColor == 'w'
                          ? const Color(0xFFBBDEFB)
                          : const Color(0xFFFFCCBC);

                      Widget buildBoardStack(double boardSize) {
                        return SizedBox(
                          width: boardSize,
                          height: boardSize,
                          child: Stack(
                            children: [
                              ChessBoardView(
                                pieces: _controller.boardPieces,
                                playerColor: _controller.playerColor,
                                boardAssetPath: chessBoardSkin.assetPath,
                                playableInsetRatio:
                                    chessBoardSkin.playableInsetRatio,
                                playableSizeRatio:
                                    chessBoardSkin.playableSizeRatio,
                                whitePieceSprites:
                                    whiteChessPieceSkin.spriteMap,
                                blackPieceSprites:
                                    blackChessPieceSkin.spriteMap,
                                invertBlackPieceColors: invertBlackPieceColors,
                                selectedSquare: _controller.selectedSquare,
                                legalTargets: _controller.legalTargets,
                                lastMoveFrom: _controller.playerLastMoveFrom,
                                lastMoveTo: _controller.playerLastMoveTo,
                                lastMoveHighlightColor: const Color(0xFFD7CA64),
                                secondaryMoveFrom:
                                    _controller.opponentLastMoveFrom,
                                secondaryMoveTo: _controller.opponentLastMoveTo,
                                secondaryMoveHighlightColor: const Color(
                                  0xFFE57373,
                                ),
                                queuedMoveFrom: _controller.queuedMoveFrom,
                                queuedMoveTo: _controller.queuedMoveTo,
                                checkedKingSquares:
                                    _controller.checkedKingSquares,
                                isCheckmate: _isOnlineCheckmate(),
                                boardMessage: _onlineBoardMessage(),
                                onSquareTap: _controller.tapSquare,
                              ),
                              if (!_controller.isConnected)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    child: Center(
                                      child: FilledButton.icon(
                                        onPressed: canStart ? _findMatch : null,
                                        icon: const AppAssetIcon(
                                          AppAssets.newGameIcon,
                                          fallbackIcon: Icons.groups_2_outlined,
                                          size: 20,
                                        ),
                                        label: const Text('Find Match'),
                                      ),
                                    ),
                                  ),
                                )
                              else if (_controller.isWaitingForOpponent)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 12),
                                          Text(
                                            'Waiting for opponent...',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1A1A1A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              else if (_controller.isGameOver)
                                Positioned.fill(
                                  child: _buildVictoryOverlay(
                                    title: _onlineVictoryTitle(),
                                    subtitle: _onlineVictorySubtitle(),
                                    actionLabel: 'Request New Game',
                                    onAction: () {
                                      _controller.requestNewGame(
                                        cooldownSeconds:
                                            _selectedCooldownSeconds,
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        );
                      }

                      if (_timeBarOrientation == TimeBarOrientation.vertical) {
                        final boardSize = math.min(
                          constraints.maxHeight,
                          constraints.maxWidth -
                              (verticalBarWidth * 2) -
                              (edgeGap * 2),
                        );
                        if (boardSize <= 0) {
                          return const SizedBox.shrink();
                        }

                        return SizedBox(
                          width:
                              boardSize +
                              (verticalBarWidth * 2) +
                              (edgeGap * 2),
                          height: boardSize,
                          child: Row(
                            children: [
                              if (showTimeBars)
                                SizedBox(
                                  width: verticalBarWidth,
                                  child: CooldownMeter(
                                    label: topColor == 'w' ? 'W' : 'B',
                                    remaining: topRemaining,
                                    total: _controller.cooldownDuration,
                                    horizontalPrimaryAssetPath:
                                        AppAssets.horizontalTimeBarAccent,
                                    horizontalFallbackAssetPath:
                                        AppAssets.horizontalTimeBar,
                                    verticalPrimaryAssetPath:
                                        AppAssets.verticalTimeBarAccent,
                                    verticalFallbackAssetPath:
                                        AppAssets.verticalTimeBar,
                                    orientation: TimeBarOrientation.vertical,
                                    activeColor: topActiveColor,
                                    isPlayerSide: topIsPlayer,
                                    timeLabel: _formatDuration(topRemaining),
                                    readyToFlash:
                                        _controller.isConnected &&
                                        showTimeBars &&
                                        timerHasStarted &&
                                        isActiveWindowForColor(topColor) &&
                                        !_controller.isGameOver &&
                                        topRemaining.inMilliseconds == 0,
                                    flashTint: topFlashTint,
                                    flashDuration: const Duration(
                                      milliseconds: 700,
                                    ),
                                  ),
                                ),
                              if (edgeGap > 0) SizedBox(width: edgeGap),
                              buildBoardStack(boardSize),
                              if (edgeGap > 0) SizedBox(width: edgeGap),
                              if (showTimeBars)
                                SizedBox(
                                  width: verticalBarWidth,
                                  child: CooldownMeter(
                                    label: bottomColor == 'w' ? 'W' : 'B',
                                    remaining: bottomRemaining,
                                    total: _controller.cooldownDuration,
                                    horizontalPrimaryAssetPath:
                                        AppAssets.horizontalTimeBarAccent,
                                    horizontalFallbackAssetPath:
                                        AppAssets.horizontalTimeBar,
                                    verticalPrimaryAssetPath:
                                        AppAssets.verticalTimeBarAccent,
                                    verticalFallbackAssetPath:
                                        AppAssets.verticalTimeBar,
                                    orientation: TimeBarOrientation.vertical,
                                    activeColor: bottomActiveColor,
                                    isPlayerSide: bottomIsPlayer,
                                    timeLabel: _formatDuration(bottomRemaining),
                                    readyToFlash:
                                        _controller.isConnected &&
                                        showTimeBars &&
                                        timerHasStarted &&
                                        isActiveWindowForColor(bottomColor) &&
                                        !_controller.isGameOver &&
                                        bottomRemaining.inMilliseconds == 0,
                                    flashTint: bottomFlashTint,
                                    flashDuration: const Duration(
                                      milliseconds: 700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }

                      final boardSize = math.min(
                        constraints.maxWidth,
                        constraints.maxHeight -
                            (horizontalBarHeight * 2) -
                            (edgeGap * 2),
                      );
                      if (boardSize <= 0) {
                        return const SizedBox.shrink();
                      }

                      return SizedBox(
                        width: boardSize,
                        height:
                            boardSize +
                            (horizontalBarHeight * 2) +
                            (edgeGap * 2),
                        child: Column(
                          children: [
                            if (showTimeBars)
                              SizedBox(
                                height: horizontalBarHeight,
                                child: CooldownMeter(
                                  label: topColor == 'w' ? 'W' : 'B',
                                  remaining: topRemaining,
                                  total: _controller.cooldownDuration,
                                  horizontalPrimaryAssetPath:
                                      AppAssets.horizontalTimeBarAccent,
                                  horizontalFallbackAssetPath:
                                      AppAssets.horizontalTimeBar,
                                  verticalPrimaryAssetPath:
                                      AppAssets.verticalTimeBarAccent,
                                  verticalFallbackAssetPath:
                                      AppAssets.verticalTimeBar,
                                  orientation: TimeBarOrientation.horizontal,
                                  activeColor: topActiveColor,
                                  isPlayerSide: topIsPlayer,
                                  timeLabel: _formatDuration(topRemaining),
                                  readyToFlash:
                                      _controller.isConnected &&
                                      showTimeBars &&
                                      timerHasStarted &&
                                      isActiveWindowForColor(topColor) &&
                                      !_controller.isGameOver &&
                                      topRemaining.inMilliseconds == 0,
                                  flashTint: topFlashTint,
                                  flashDuration: const Duration(
                                    milliseconds: 700,
                                  ),
                                ),
                              ),
                            if (edgeGap > 0) SizedBox(height: edgeGap),
                            buildBoardStack(boardSize),
                            if (edgeGap > 0) SizedBox(height: edgeGap),
                            if (showTimeBars)
                              SizedBox(
                                height: horizontalBarHeight,
                                child: CooldownMeter(
                                  label: bottomColor == 'w' ? 'W' : 'B',
                                  remaining: bottomRemaining,
                                  total: _controller.cooldownDuration,
                                  horizontalPrimaryAssetPath:
                                      AppAssets.horizontalTimeBarAccent,
                                  horizontalFallbackAssetPath:
                                      AppAssets.horizontalTimeBar,
                                  verticalPrimaryAssetPath:
                                      AppAssets.verticalTimeBarAccent,
                                  verticalFallbackAssetPath:
                                      AppAssets.verticalTimeBar,
                                  orientation: TimeBarOrientation.horizontal,
                                  activeColor: bottomActiveColor,
                                  isPlayerSide: bottomIsPlayer,
                                  timeLabel: _formatDuration(bottomRemaining),
                                  readyToFlash:
                                      _controller.isConnected &&
                                      showTimeBars &&
                                      timerHasStarted &&
                                      isActiveWindowForColor(bottomColor) &&
                                      !_controller.isGameOver &&
                                      bottomRemaining.inMilliseconds == 0,
                                  flashTint: bottomFlashTint,
                                  flashDuration: const Duration(
                                    milliseconds: 700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
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

  static String _formatDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) {
      return '0.0s';
    }
    final halfSteps = (ms / 500).ceil();
    final halfSecondValue = halfSteps / 2;
    return '${halfSecondValue.toStringAsFixed(1)}s';
  }

  Widget _buildTimingHud({
    required bool isMatchActive,
    required bool timerHasStarted,
    required String? activeWindowColor,
    required bool isPlayerWindow,
    required Duration remaining,
  }) {
    if (!isMatchActive) {
      return const SizedBox.shrink();
    }

    final title = !timerHasStarted
        ? 'Opening: White moves with no timer'
        : (activeWindowColor == null
              ? 'Both sides unlocked'
              : (isPlayerWindow
                    ? 'Your timer is running'
                    : '${activeWindowColor == 'w' ? 'White' : 'Black'} timer is running'));
    final subtitle = !timerHasStarted
        ? 'After White moves, Black timer starts.'
        : (activeWindowColor == null
              ? 'First mover takes initiative.'
              : '${_formatDuration(remaining)} remaining');
    final accent = !timerHasStarted
        ? const Color(0xFF607D8B)
        : (isPlayerWindow ? const Color(0xFF2E7D32) : const Color(0xFF546E7A));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xF2FFFFFF),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

  Widget _buildVictoryOverlay({
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xEE111821),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x66FFFFFF)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFFD26A),
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: const AppAssetIcon(
                        AppAssets.rematchIcon,
                        fallbackIcon: Icons.replay,
                        size: 18,
                      ),
                      label: Text(actionLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
        apiBaseUrl: _apiBaseController.text,
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
      await _controller.checkBackendHealth(apiBaseUrl: _apiBaseController.text);
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
      await _controller.wakeBackend(apiBaseUrl: _apiBaseController.text);
    } finally {
      if (mounted) {
        setState(() {
          _backendActionInFlight = false;
        });
      }
    }
  }
}

class _BackendHealthCard extends StatelessWidget {
  const _BackendHealthCard({
    required this.state,
    required this.message,
    required this.checkedAt,
    required this.busy,
    required this.onCheckPressed,
    required this.onWakePressed,
  });

  final BackendHealthState state;
  final String? message;
  final DateTime? checkedAt;
  final bool busy;
  final Future<void> Function() onCheckPressed;
  final Future<void> Function() onWakePressed;

  @override
  Widget build(BuildContext context) {
    final colors = _healthColors(state);
    final checkedLabel = checkedAt == null
        ? 'Not checked yet'
        : 'Checked ${TimeOfDay.fromDateTime(checkedAt!).format(context)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6D0C6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(colors.icon, size: 16, color: colors.color),
                const SizedBox(width: 6),
                Text(
                  _healthLabel(state),
                  style: TextStyle(
                    color: colors.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  checkedLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4E4A45),
                  ),
                ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6D3C12)),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onCheckPressed,
                    icon: const AppAssetIcon(
                      AppAssets.feedbackIcon,
                      fallbackIcon: Icons.monitor_heart_outlined,
                      size: 16,
                    ),
                    label: const Text('Check Status'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : onWakePressed,
                    icon: const Icon(Icons.power_settings_new, size: 16),
                    label: const Text('Wake Backend'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _healthLabel(BackendHealthState state) {
    switch (state) {
      case BackendHealthState.unknown:
        return 'Backend status unknown';
      case BackendHealthState.checking:
        return 'Checking backend...';
      case BackendHealthState.healthy:
        return 'Backend is online';
      case BackendHealthState.unhealthy:
        return 'Backend unavailable';
    }
  }

  static ({IconData icon, Color color}) _healthColors(
    BackendHealthState state,
  ) {
    switch (state) {
      case BackendHealthState.unknown:
        return (icon: Icons.help_outline, color: const Color(0xFF546E7A));
      case BackendHealthState.checking:
        return (icon: Icons.autorenew, color: const Color(0xFF1565C0));
      case BackendHealthState.healthy:
        return (icon: Icons.check_circle, color: const Color(0xFF2E7D32));
      case BackendHealthState.unhealthy:
        return (icon: Icons.error_outline, color: const Color(0xFFB71C1C));
    }
  }
}
