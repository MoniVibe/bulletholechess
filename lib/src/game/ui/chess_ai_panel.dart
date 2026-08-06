import 'dart:math' as math;

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../engine/chess_ai_game_controller.dart';
import 'app_assets.dart';
import 'chess_board_view.dart';
import 'collapsible_settings_section.dart';
import 'skin_catalog.dart';

class ChessAiPanel extends StatefulWidget {
  const ChessAiPanel({super.key});

  @override
  State<ChessAiPanel> createState() => _ChessAiPanelState();
}

class _ChessAiPanelState extends State<ChessAiPanel> {
  static const Duration _aiTestingDelay = Duration(seconds: 3);
  static const List<int> _cooldownOptionsSeconds = <int>[2, 3, 5, 7, 10];
  // 0 == Off (classic rules); sentinel below reveals a custom seconds field.
  static const List<int> _checkTimeoutPresetSeconds = <int>[0, 15, 30, 60, 90];
  static const int _checkTimeoutCustomSentinel = -1;
  static const Set<String> _ownedChessPieceSkinIds = <String>{
    'chess_sashite_western',
    'chess_classic',
    'chess_red_pieces',
  };

  late final ChessAiGameController _controller;
  late final ScrollController _settingsScrollController;
  bool _menuOpen = true;
  bool _isBoardSettingsOpen = false;
  String _selectedBoardSkinId = SkinCatalog.defaultChessBoardSkinId;
  String _selectedPlayerPieceSkinId = SkinCatalog.defaultChessPieceSkinId;
  _PlayAsChoice _playAsChoice = _PlayAsChoice.white;
  int _selectedCooldownSeconds = 3;
  // Selected check-timer preset (seconds), or _checkTimeoutCustomSentinel.
  int _selectedCheckTimeoutSeconds = 30;
  int _customCheckTimeoutSeconds = 45;
  late final TextEditingController _customCheckController;
  TimeBarOrientation _timeBarOrientation = TimeBarOrientation.horizontal;
  final math.Random _uiRandom = math.Random();

  int get _effectiveCheckTimeoutSeconds {
    if (_selectedCheckTimeoutSeconds == _checkTimeoutCustomSentinel) {
      return _customCheckTimeoutSeconds;
    }
    return _selectedCheckTimeoutSeconds;
  }

  double _snapDownToPixel(double value, BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio <= 0) {
      return value;
    }
    // Avoid losing a physical pixel to floating-point noise when a snapped
    // board size is added to the integer timer/gap bands.
    return ((value * ratio) + 1e-6).floorToDouble() / ratio;
  }

  @override
  void initState() {
    super.initState();
    _controller = ChessAiGameController(
      aiMoveDelay: _aiTestingDelay,
      initialCooldownDuration: Duration(seconds: _selectedCooldownSeconds),
      initialCheckTimeoutDuration: Duration(
        seconds: _effectiveCheckTimeoutSeconds,
      ),
    );
    _customCheckController = TextEditingController(
      text: '$_customCheckTimeoutSeconds',
    );
    _settingsScrollController = ScrollController();
  }

  @override
  void dispose() {
    _customCheckController.dispose();
    _settingsScrollController.dispose();
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
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
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
                trailing: DebugLogExportButton(
                  logTextProvider: _controller.exportDebugLog,
                  iconOnly: true,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: Scrollbar(
                        controller: _settingsScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _settingsScrollController,
                          child: Column(
                            children: [
                              DropdownButtonFormField<_PlayAsChoice>(
                                initialValue: _playAsChoice,
                                decoration: const InputDecoration(
                                  labelText: 'Play As',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: const <DropdownMenuItem<_PlayAsChoice>>[
                                  DropdownMenuItem<_PlayAsChoice>(
                                    value: _PlayAsChoice.white,
                                    child: Text('White'),
                                  ),
                                  DropdownMenuItem<_PlayAsChoice>(
                                    value: _PlayAsChoice.black,
                                    child: Text('Black'),
                                  ),
                                  DropdownMenuItem<_PlayAsChoice>(
                                    value: _PlayAsChoice.random,
                                    child: Text('Random'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    _playAsChoice = value;
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
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Bullet-hole play: move when your window is live. If you move during cooldown, the queued squares glow and the move executes when ready.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF6A635A),
                                      ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<int>(
                                initialValue: _selectedCheckTimeoutSeconds,
                                decoration: const InputDecoration(
                                  labelText: 'Check timer',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: <DropdownMenuItem<int>>[
                                  ..._checkTimeoutPresetSeconds.map(
                                    (seconds) => DropdownMenuItem<int>(
                                      value: seconds,
                                      child: Text(
                                        seconds == 0 ? 'Off' : '$seconds s',
                                      ),
                                    ),
                                  ),
                                  const DropdownMenuItem<int>(
                                    value: _checkTimeoutCustomSentinel,
                                    child: Text('Custom…'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    _selectedCheckTimeoutSeconds = value;
                                  });
                                },
                              ),
                              if (_selectedCheckTimeoutSeconds ==
                                  _checkTimeoutCustomSentinel) ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _customCheckController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Custom check seconds',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    helperText:
                                        'Seconds to escape check (5–600).',
                                  ),
                                  onChanged: (text) {
                                    final parsed = int.tryParse(text.trim());
                                    if (parsed == null) {
                                      return;
                                    }
                                    setState(() {
                                      _customCheckTimeoutSeconds = parsed.clamp(
                                        5,
                                        600,
                                      );
                                    });
                                  },
                                ),
                              ],
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Check timer: a side left in check must escape before the clock runs out or it loses. Set Off for classic rules.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF6A635A),
                                      ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              CollapsibleSettingsSection(
                                title: 'Board Settings',
                                isOpen: _isBoardSettingsOpen,
                                onToggle: () {
                                  setState(() {
                                    _isBoardSettingsOpen =
                                        !_isBoardSettingsOpen;
                                  });
                                },
                                child: Column(
                                  children: [
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
                                              enabled: _ownedChessPieceSkinIds
                                                  .contains(skin.id),
                                              child: Text(
                                                _ownedChessPieceSkinIds
                                                        .contains(skin.id)
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
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey<String>('chess_ai_new_game'),
                        onPressed: _startNewGame,
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
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const baseHorizontalBarHeight = 50.0;
                      const baseVerticalBarWidth = 58.0;
                      const boardGap = 8.0;
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
                              if (_controller.isCheckCountdownActive)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  right: 8,
                                  child: IgnorePointer(
                                    child: _buildCheckCountdownBanner(),
                                  ),
                                ),
                              if (_controller.isGameOver)
                                Positioned.fill(
                                  child: _buildVictoryOverlay(
                                    title: _victoryTitle(),
                                    subtitle: _victorySubtitle(),
                                    actionLabel: 'New Game',
                                    onAction: _startNewGame,
                                  ),
                                )
                              else if (!hasActiveGame)
                                Positioned.fill(
                                  child: _buildStartOverlay(
                                    onStart: _startNewGame,
                                  ),
                                ),
                            ],
                          ),
                        );
                      }

                      if (_timeBarOrientation == TimeBarOrientation.vertical) {
                        final rawBoardSize = math.min(
                          constraints.maxHeight,
                          constraints.maxWidth -
                              (verticalBarWidth * 2) -
                              (edgeGap * 2),
                        );
                        final boardSize = _snapDownToPixel(
                          rawBoardSize,
                          context,
                        );
                        if (boardSize <= 0) {
                          return const SizedBox.shrink();
                        }

                        return SizedBox(
                          width: _snapDownToPixel(
                            boardSize + (verticalBarWidth * 2) + (edgeGap * 2),
                            context,
                          ),
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

                      final rawBoardSize = math.min(
                        constraints.maxWidth,
                        constraints.maxHeight -
                            (horizontalBarHeight * 2) -
                            (edgeGap * 2),
                      );
                      final boardSize = _snapDownToPixel(rawBoardSize, context);
                      if (boardSize <= 0) {
                        return const SizedBox.shrink();
                      }

                      return SizedBox(
                        width: boardSize,
                        height: _snapDownToPixel(
                          boardSize + (horizontalBarHeight * 2) + (edgeGap * 2),
                          context,
                        ),
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
              if (_controller.feedback != null) ...[
                const SizedBox(height: 10),
                Card(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.16),
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
                            _controller.feedback!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.88),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (tailHistory.isNotEmpty) ...[
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
                            tailHistory.join('  '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
    if (_controller.isCheckTimeoutLoss) {
      final loser = _controller.checkTimeoutLoserColor == 'w'
          ? 'White'
          : 'Black';
      final winner = _controller.winnerLabel ?? '';
      return '$loser ran out of time in check. $winner takes the game.';
    }
    if (_controller.isDraw) {
      return 'No side could force a win. Start a new game.';
    }
    final winner = _controller.winnerLabel;
    if (winner != null) {
      return 'Checkmate. $winner takes the game.';
    }
    return _controller.statusText;
  }

  void _startNewGame() {
    _controller.startNewGame(
      playerAsWhite: _resolvePlayerAsWhite(),
      cooldownDuration: Duration(seconds: _selectedCooldownSeconds),
      checkTimeoutDuration: Duration(seconds: _effectiveCheckTimeoutSeconds),
    );
    if (_menuOpen) {
      setState(() {
        _menuOpen = false;
      });
    }
  }

  bool _resolvePlayerAsWhite() {
    return switch (_playAsChoice) {
      _PlayAsChoice.white => true,
      _PlayAsChoice.black => false,
      // Resolve random only when starting a game so the dropdown remains stable.
      _PlayAsChoice.random => _uiRandom.nextBool(),
    };
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

  Widget _buildCheckCountdownBanner() {
    final checkColor = _controller.checkTimerColor;
    if (checkColor == null) {
      return const SizedBox.shrink();
    }
    final remaining = _controller.checkTimeRemaining(checkColor);
    final isPlayer = checkColor == _controller.playerColor;
    final sideLabel = checkColor == 'w' ? 'White' : 'Black';
    final label = isPlayer
        ? 'CHECK — escape in ${_formatDuration(remaining)}'
        : '$sideLabel in check — ${_formatDuration(remaining)}';
    final total = _controller.checkTimeoutDuration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (remaining.inMilliseconds / total).clamp(0.0, 1.0);
    final urgent = remaining.inMilliseconds <= 5000;
    final background = isPlayer
        ? (urgent ? const Color(0xF2C62828) : const Color(0xF2B71C1C))
        : const Color(0xF21B5E20);
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPlayer
                        ? Icons.warning_amber_rounded
                        : Icons.gpp_maybe_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 180,
                  height: 5,
                  child: LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: const Color(0x33000000),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      urgent ? const Color(0xFFFFCDD2) : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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

enum _PlayAsChoice { white, black, random }
