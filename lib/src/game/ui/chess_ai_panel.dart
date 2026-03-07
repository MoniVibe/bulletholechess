import 'dart:math' as math;

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../engine/chess_ai_game_controller.dart';
import 'app_assets.dart';
import 'chess_board_view.dart';
import 'skin_catalog.dart';

class ChessAiPanel extends StatefulWidget {
  const ChessAiPanel({super.key});

  @override
  State<ChessAiPanel> createState() => _ChessAiPanelState();
}

class _ChessAiPanelState extends State<ChessAiPanel> {
  static const Duration _aiTestingDelay = Duration(seconds: 3);
  static const List<int> _cooldownOptionsSeconds = <int>[2, 3, 5, 7, 10];
  static const Set<String> _ownedChessPieceSkinIds = <String>{
    'chess_sashite_western',
    'chess_classic',
    'chess_red_pieces',
  };

  late final ChessAiGameController _controller;
  bool _menuOpen = true;
  String _selectedBoardSkinId = SkinCatalog.defaultChessBoardSkinId;
  String _selectedPlayerPieceSkinId = SkinCatalog.defaultChessPieceSkinId;
  bool _playerAsWhite = true;
  int _selectedCooldownSeconds = 3;
  TimeBarOrientation _timeBarOrientation = TimeBarOrientation.horizontal;

  @override
  void initState() {
    super.initState();
    _controller = ChessAiGameController(
      aiMoveDelay: _aiTestingDelay,
      initialCooldownDuration: Duration(seconds: _selectedCooldownSeconds),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final boardSkin = SkinCatalog.chessBoardById(_selectedBoardSkinId);
        final playerPieceSkin = SkinCatalog.chessPieceById(
          _selectedPlayerPieceSkinId,
        );
        final aiPieceSkin = SkinCatalog.chessPieceById(
          SkinCatalog.defaultChessPieceSkinId,
        );
        final whitePieceSkin = _controller.playerColor == 'w'
            ? playerPieceSkin
            : aiPieceSkin;
        final blackPieceSkin = _controller.playerColor == 'b'
            ? playerPieceSkin
            : aiPieceSkin;
        final whiteRemaining = _controller.cooldownRemaining('w');
        final blackRemaining = _controller.cooldownRemaining('b');
        final hasActiveGame = _controller.hasActiveGame;
        final timerHasStarted =
            hasActiveGame &&
            (_controller.playerLastMoveFrom != null ||
                _controller.aiLastMoveFrom != null);

        String? activeWindowColor() {
          if (!hasActiveGame || !timerHasStarted) {
            return null;
          }
          // After a move, chess turn flips to the other side.
          // That side owns the currently open move window.
          return _controller.turnColor;
        }

        Duration activeWindowRemaining() {
          final active = activeWindowColor();
          if (active == null) {
            return Duration.zero;
          }
          // Move window for side X is represented by the opposite mover cooldown.
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

        final history = _controller.history;
        final tailHistory = history.length > 8
            ? history.sublist(history.length - 8)
            : history;
        final topColor = _controller.playerColor == 'w' ? 'b' : 'w';
        final bottomColor = _controller.playerColor;
        final topRemaining = displayedRemainingForColor(topColor);
        final bottomRemaining = displayedRemainingForColor(bottomColor);
        final topIsPlayer = topColor == _controller.playerColor;
        final bottomIsPlayer = bottomColor == _controller.playerColor;
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              CollapsibleSettingsCard(
                title: 'Vs AI',
                isOpen: _menuOpen,
                onToggle: () {
                  setState(() {
                    _menuOpen = !_menuOpen;
                  });
                },
                leading: const AppAssetIcon(
                  AppAssets.settingsIcon,
                  fallbackIcon: Icons.smart_toy_outlined,
                  size: 22,
                ),
                child: Column(
                  children: [
                    DropdownButtonFormField<bool>(
                      initialValue: _playerAsWhite,
                      decoration: const InputDecoration(
                        labelText: 'Play As',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const <DropdownMenuItem<bool>>[
                        DropdownMenuItem<bool>(
                          value: true,
                          child: Text('White'),
                        ),
                        DropdownMenuItem<bool>(
                          value: false,
                          child: Text('Black'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _playerAsWhite = value;
                        });
                      },
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
                      onChanged: (value) {
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
                        'chess_ai_board_skin_$_selectedBoardSkinId',
                      ),
                      initialValue: _selectedBoardSkinId,
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
                          _selectedBoardSkinId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'chess_ai_player_skin_$_selectedPlayerPieceSkinId',
                      ),
                      initialValue: _selectedPlayerPieceSkinId,
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
                        setState(() {
                          _selectedPlayerPieceSkinId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey<String>('chess_ai_new_game'),
                        onPressed: () {
                          _controller.startNewGame(
                            playerAsWhite: _playerAsWhite,
                            cooldownDuration: Duration(
                              seconds: _selectedCooldownSeconds,
                            ),
                          );
                        },
                        icon: const AppAssetIcon(
                          AppAssets.newGameIcon,
                          fallbackIcon: Icons.refresh,
                          size: 18,
                        ),
                        label: const Text('New Game'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildTimingHud(
                hasActiveGame: hasActiveGame,
                timerHasStarted: timerHasStarted,
                activeWindowColor: activeWindowColor(),
                isPlayerWindow:
                    activeWindowColor() != null &&
                    activeWindowColor() == _controller.playerColor,
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
                      final horizontalBarHeight = hasActiveGame
                          ? baseHorizontalBarHeight
                          : 0.0;
                      final verticalBarWidth = hasActiveGame
                          ? baseVerticalBarWidth
                          : 0.0;
                      final edgeGap = hasActiveGame ? boardGap : 0.0;

                      Widget buildBoardStack(double boardSize) {
                        return SizedBox(
                          width: boardSize,
                          height: boardSize,
                          child: Stack(
                            children: [
                              ChessBoardView(
                                pieces: _controller.boardPieces,
                                playerColor: _controller.playerColor,
                                boardAssetPath: boardSkin.assetPath,
                                playableInsetRatio:
                                    boardSkin.playableInsetRatio,
                                playableSizeRatio: boardSkin.playableSizeRatio,
                                whitePieceSprites: whitePieceSkin.spriteMap,
                                blackPieceSprites: blackPieceSkin.spriteMap,
                                whitePieceScale: whitePieceSkin.pieceScale,
                                blackPieceScale: blackPieceSkin.pieceScale,
                                whitePieceYOffset: whitePieceSkin.pieceYOffset,
                                blackPieceYOffset: blackPieceSkin.pieceYOffset,
                                selectedSquare: _controller.selectedSquare,
                                legalTargets: _controller.legalTargets,
                                lastMoveFrom: _controller.playerLastMoveFrom,
                                lastMoveTo: _controller.playerLastMoveTo,
                                secondaryMoveFrom: _controller.aiLastMoveFrom,
                                secondaryMoveTo: _controller.aiLastMoveTo,
                                queuedMoveFrom: _controller.queuedMoveFrom,
                                queuedMoveTo: _controller.queuedMoveTo,
                                onSquareTap: _controller.tapSquare,
                              ),
                              if (_controller.isGameOver)
                                Positioned.fill(
                                  child: _buildVictoryOverlay(
                                    title: _victoryTitle(),
                                    subtitle: _victorySubtitle(),
                                    actionLabel: 'New Game',
                                    onAction: () {
                                      _controller.startNewGame(
                                        playerAsWhite: _playerAsWhite,
                                        cooldownDuration: Duration(
                                          seconds: _selectedCooldownSeconds,
                                        ),
                                      );
                                    },
                                  ),
                                )
                              else if (!hasActiveGame)
                                Positioned.fill(
                                  child: _buildStartOverlay(
                                    onStart: () {
                                      _controller.startNewGame(
                                        playerAsWhite: _playerAsWhite,
                                        cooldownDuration: Duration(
                                          seconds: _selectedCooldownSeconds,
                                        ),
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
                              if (hasActiveGame)
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
                                        hasActiveGame &&
                                        timerHasStarted &&
                                        isActiveWindowForColor(topColor) &&
                                        !_controller.isGameOver &&
                                        _controller.turnColor == topColor &&
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
                              if (hasActiveGame)
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
                                        hasActiveGame &&
                                        timerHasStarted &&
                                        isActiveWindowForColor(bottomColor) &&
                                        !_controller.isGameOver &&
                                        _controller.turnColor == bottomColor &&
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
                            if (hasActiveGame)
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
                                      hasActiveGame &&
                                      timerHasStarted &&
                                      isActiveWindowForColor(topColor) &&
                                      !_controller.isGameOver &&
                                      _controller.turnColor == topColor &&
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
                            if (hasActiveGame)
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
                                      hasActiveGame &&
                                      timerHasStarted &&
                                      isActiveWindowForColor(bottomColor) &&
                                      !_controller.isGameOver &&
                                      _controller.turnColor == bottomColor &&
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
                        'Status:',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_controller.statusText)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                color: const Color(0xFFFFF2F2),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Note:',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _controller.feedback ?? '-',
                          style: const TextStyle(color: Color(0xFF8B2323)),
                        ),
                      ),
                    ],
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
                        'Log:',
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

  String _victoryTitle() {
    if (_controller.isDraw) {
      return 'Draw';
    }
    final winner = _controller.winnerLabel;
    if (winner != null) {
      return '$winner Wins';
    }
    return 'Game Over';
  }

  String _victorySubtitle() {
    if (_controller.isDraw) {
      return 'No side could force a win. Start a new game.';
    }
    final winner = _controller.winnerLabel;
    if (winner != null) {
      return 'Checkmate. $winner takes the game.';
    }
    return _controller.statusText;
  }

  Widget _buildTimingHud({
    required bool hasActiveGame,
    required bool timerHasStarted,
    required String? activeWindowColor,
    required bool isPlayerWindow,
    required Duration remaining,
  }) {
    if (!hasActiveGame) {
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 120 || constraints.maxHeight < 120) {
            return const SizedBox.shrink();
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
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
                              AppAssets.newGameIcon,
                              fallbackIcon: Icons.refresh,
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
        },
      ),
    );
  }

  Widget _buildStartOverlay({required VoidCallback onStart}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 110 || constraints.maxHeight < 90) {
            return const SizedBox.shrink();
          }
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: FilledButton.icon(
                key: const ValueKey<String>('chess_ai_start_new_game'),
                onPressed: onStart,
                icon: const AppAssetIcon(
                  AppAssets.newGameIcon,
                  fallbackIcon: Icons.play_arrow,
                  size: 18,
                ),
                label: const Text('Start New Game'),
              ),
            ),
          );
        },
      ),
    );
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
}
