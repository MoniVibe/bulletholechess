import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/local_game_controller.dart';
import 'app_asset_icon.dart';
import 'app_assets.dart';
import 'chess_board_view.dart';
import 'cooldown_meter.dart';
import 'mode_switch.dart';
import 'online_game_panel.dart';

enum _GameMode { local, online }

enum _NewGameColor { white, black, random }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const List<int> _cooldownOptionsSeconds = [2, 3, 5, 7, 10];

  late final LocalGameController _controller;
  final math.Random _uiRandom = math.Random();
  bool _isGameMenuOpen = false;
  int _selectedCooldownSeconds = 3;
  _GameMode _mode = _GameMode.local;
  bool _didPrecacheVisualAssets = false;

  @override
  void initState() {
    super.initState();
    _controller = LocalGameController(
      initialCooldownDuration: Duration(seconds: _selectedCooldownSeconds),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheVisualAssets) {
      return;
    }
    _didPrecacheVisualAssets = true;
    _precacheVisualAssets();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  AppAssets.appBackground,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) {
                    return const ColoredBox(color: Color(0xFFF2EFEA));
                  },
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.34),
                        Colors.white.withValues(alpha: 0.14),
                        Colors.black.withValues(alpha: 0.03),
                      ],
                      stops: const [0, 0.6, 1],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: IndexedStack(
                        index: _mode == _GameMode.local ? 0 : 1,
                        children: [
                          _buildLocalView(),
                          OnlineGamePanel(
                            isOnlineMode: _mode == _GameMode.online,
                            onModeChanged: (online) {
                              setState(() {
                                _mode = online
                                    ? _GameMode.online
                                    : _GameMode.local;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocalView() {
    final history = _controller.history;
    final tailHistory = history.length > 8
        ? history.sublist(history.length - 8)
        : history;

    final whiteRemaining = _controller.cooldownRemaining('w');
    final blackRemaining = _controller.cooldownRemaining('b');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  title: Row(
                    children: [
                      const AppAssetIcon(
                        AppAssets.settingsIcon,
                        fallbackIcon: Icons.settings,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Game Menu',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      CompactModeSwitch(
                        onlineSelected: false,
                        onChanged: (online) {
                          setState(() {
                            _mode = online ? _GameMode.online : _GameMode.local;
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _isGameMenuOpen
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                      ),
                    ],
                  ),
                  onTap: () {
                    setState(() {
                      _isGameMenuOpen = !_isGameMenuOpen;
                    });
                  },
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
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
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _showNewGamePrompt,
                            icon: const AppAssetIcon(
                              AppAssets.newGameIcon,
                              fallbackIcon: Icons.refresh,
                              size: 20,
                            ),
                            label: const Text('New Game'),
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
                  crossFadeState: _isGameMenuOpen
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                  sizeCurve: Curves.easeOutCubic,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const barHeight = 58.0;
                  const boardGap = 10.0;
                  final boardSize = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight - (barHeight * 2) - (boardGap * 2),
                  );
                  if (boardSize <= 0) {
                    return const SizedBox.shrink();
                  }

                  final topColor = _controller.playerColor == 'w' ? 'b' : 'w';
                  final bottomColor = _controller.playerColor;
                  final whiteIsPlayer = _controller.playerColor == 'w';
                  final blackIsPlayer = _controller.playerColor == 'b';
                  final topRemaining = topColor == 'w'
                      ? whiteRemaining
                      : blackRemaining;
                  final bottomRemaining = bottomColor == 'w'
                      ? whiteRemaining
                      : blackRemaining;
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

                  return SizedBox(
                    width: boardSize,
                    height: boardSize + (barHeight * 2) + (boardGap * 2),
                    child: Column(
                      children: [
                        SizedBox(
                          height: barHeight,
                          child: CooldownMeter(
                            key: const ValueKey('top_bar'),
                            label: topColor == 'w' ? 'W' : 'B',
                            remaining: topRemaining,
                            total: _controller.cooldownDuration,
                            activeColor: topActiveColor,
                            isPlayerSide: topIsPlayer,
                            timeLabel: _controller.hasActiveGame
                                ? _formatDuration(topRemaining)
                                : '--',
                            readyToFlash:
                                _controller.hasActiveGame &&
                                topRemaining.inMilliseconds == 0,
                            flashTint: topFlashTint,
                            flashDuration: const Duration(milliseconds: 700),
                          ),
                        ),
                        const SizedBox(height: boardGap),
                        SizedBox(
                          width: boardSize,
                          height: boardSize,
                          child: Stack(
                            children: [
                              ChessBoardView(
                                pieces: _controller.boardPieces,
                                playerColor: _controller.playerColor,
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
                                onSquareTap: _controller.tapSquare,
                              ),
                              if (!_controller.hasActiveGame)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    child: Center(
                                      child: FilledButton.icon(
                                        onPressed: _showNewGamePrompt,
                                        icon: const AppAssetIcon(
                                          AppAssets.newGameIcon,
                                          fallbackIcon: Icons.play_arrow,
                                          size: 20,
                                        ),
                                        label: const Text('Start New Game'),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: boardGap),
                        SizedBox(
                          height: barHeight,
                          child: CooldownMeter(
                            key: const ValueKey('bottom_bar'),
                            label: bottomColor == 'w' ? 'W' : 'B',
                            remaining: bottomRemaining,
                            total: _controller.cooldownDuration,
                            activeColor: bottomActiveColor,
                            isPlayerSide: bottomIsPlayer,
                            timeLabel: _controller.hasActiveGame
                                ? _formatDuration(bottomRemaining)
                                : '--',
                            readyToFlash:
                                _controller.hasActiveGame &&
                                bottomRemaining.inMilliseconds == 0,
                            flashTint: bottomFlashTint,
                            flashDuration: const Duration(milliseconds: 700),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
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

  Future<void> _showNewGamePrompt() async {
    final choice = await showModalBottomSheet<_NewGameColor>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.circle_outlined),
                title: const Text('Play White'),
                onTap: () => Navigator.of(context).pop(_NewGameColor.white),
              ),
              ListTile(
                leading: const Icon(Icons.circle),
                title: const Text('Play Black'),
                onTap: () => Navigator.of(context).pop(_NewGameColor.black),
              ),
              ListTile(
                leading: const Icon(Icons.shuffle),
                title: const Text('Random'),
                onTap: () => Navigator.of(context).pop(_NewGameColor.random),
              ),
            ],
          ),
        );
      },
    );

    if (choice == null) {
      return;
    }

    final playerAsWhite = switch (choice) {
      _NewGameColor.white => true,
      _NewGameColor.black => false,
      _NewGameColor.random => _uiRandom.nextBool(),
    };
    _startNewGame(playerAsWhite: playerAsWhite);
  }

  void _startNewGame({required bool playerAsWhite}) {
    _controller.startNewGame(
      playerAsWhite: playerAsWhite,
      cooldownDuration: Duration(seconds: _selectedCooldownSeconds),
    );
    setState(() {
      _isGameMenuOpen = false;
    });
  }

  void _precacheVisualAssets() {
    final uniqueAssets = <String>{
      AppAssets.appBackground,
      AppAssets.boardFrame,
      AppAssets.horizontalTimeBar,
      AppAssets.settingsIcon,
      AppAssets.newGameIcon,
      AppAssets.rematchIcon,
      AppAssets.feedbackIcon,
      ...AppAssets.pieceSprites.values,
    };
    for (final assetPath in uniqueAssets) {
      precacheImage(AssetImage(assetPath), context);
    }
  }
}
