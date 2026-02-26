import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/local_game_controller.dart';
import 'chess_board_view.dart';
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<_GameMode>(
                      segments: const [
                        ButtonSegment<_GameMode>(
                          value: _GameMode.local,
                          label: Text('Local vs Bot'),
                          icon: Icon(Icons.smart_toy_outlined),
                        ),
                        ButtonSegment<_GameMode>(
                          value: _GameMode.online,
                          label: Text('Online Prototype'),
                          icon: Icon(Icons.wifi),
                        ),
                      ],
                      selected: <_GameMode>{_mode},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _mode = selection.first;
                        });
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _mode == _GameMode.local ? 0 : 1,
                    children: [_buildLocalView(), const OnlineGamePanel()],
                  ),
                ),
              ],
            ),
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
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  title: const Text(
                    'Game Menu',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('New game and settings'),
                  trailing: Icon(
                    _isGameMenuOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
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
                            icon: const Icon(Icons.refresh),
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
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _controller.statusText,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_controller.feedback != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _controller.feedback!,
                      style: const TextStyle(
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const barHeight = 34.0;
                  const boardGap = 10.0;
                  final boardSize = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight - (barHeight * 2) - (boardGap * 2),
                  );
                  if (boardSize <= 0) {
                    return const SizedBox.shrink();
                  }

                  final whiteRatio = _cooldownRatio(_controller, 'w');
                  final blackRatio = _cooldownRatio(_controller, 'b');
                  final topColor = _controller.playerColor == 'w' ? 'b' : 'w';
                  final bottomColor = _controller.playerColor;
                  final whiteIsPlayer = _controller.playerColor == 'w';
                  final blackIsPlayer = _controller.playerColor == 'b';
                  final topRatio = topColor == 'w' ? whiteRatio : blackRatio;
                  final bottomRatio = bottomColor == 'w'
                      ? whiteRatio
                      : blackRatio;
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
                          child: _HorizontalCooldownBar(
                            key: const ValueKey('top_bar'),
                            label: topColor == 'w' ? 'W' : 'B',
                            ratio: topRatio,
                            activeColor: topActiveColor,
                            isPlayerSide: topIsPlayer,
                            timerLabel: _controller.hasActiveGame
                                ? _formatDuration(topRemaining)
                                : '--',
                            readyToFlash:
                                _controller.hasActiveGame &&
                                topRemaining.inMilliseconds == 0,
                            flashTint: topFlashTint,
                            flashDuration: const Duration(milliseconds: 1800),
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
                                        icon: const Icon(Icons.play_arrow),
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
                          child: _HorizontalCooldownBar(
                            key: const ValueKey('bottom_bar'),
                            label: bottomColor == 'w' ? 'W' : 'B',
                            ratio: bottomRatio,
                            activeColor: bottomActiveColor,
                            isPlayerSide: bottomIsPlayer,
                            timerLabel: _controller.hasActiveGame
                                ? _formatDuration(bottomRemaining)
                                : '--',
                            readyToFlash:
                                _controller.hasActiveGame &&
                                bottomRemaining.inMilliseconds == 0,
                            flashTint: bottomFlashTint,
                            flashDuration: const Duration(milliseconds: 1800),
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
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
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
    final seconds = duration.inMilliseconds / 1000.0;
    return '${seconds.toStringAsFixed(1)}s';
  }

  static double _cooldownRatio(LocalGameController controller, String color) {
    final totalMs = controller.cooldownDuration.inMilliseconds;
    if (totalMs <= 0) {
      return 0;
    }

    final remainingMs = controller.cooldownRemaining(color).inMilliseconds;
    final ratio = remainingMs / totalMs;
    return ratio.clamp(0.0, 1.0);
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
}

class _HorizontalCooldownBar extends StatefulWidget {
  const _HorizontalCooldownBar({
    required this.label,
    required this.ratio,
    required this.activeColor,
    required this.isPlayerSide,
    required this.timerLabel,
    required this.readyToFlash,
    required this.flashTint,
    required this.flashDuration,
    super.key,
  });

  final String label;
  final double ratio;
  final Color activeColor;
  final bool isPlayerSide;
  final String timerLabel;
  final bool readyToFlash;
  final Color flashTint;
  final Duration flashDuration;

  @override
  State<_HorizontalCooldownBar> createState() => _HorizontalCooldownBarState();
}

class _HorizontalCooldownBarState extends State<_HorizontalCooldownBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: widget.flashDuration);
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _HorizontalCooldownBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flashDuration != widget.flashDuration) {
      _pulse.duration = widget.flashDuration;
    }
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.readyToFlash) {
      if (!_pulse.isAnimating) {
        _pulse.repeat(reverse: true);
      }
      return;
    }
    if (_pulse.isAnimating) {
      _pulse.stop();
    }
    _pulse.value = 0;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.ratio == 0;
    final fillColor = ready ? const Color(0xFF43A047) : widget.activeColor;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFDED6CB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFF9E9489)),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: widget.ratio),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return FractionallySizedBox(
                          heightFactor: 1,
                          widthFactor: value,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  fillColor.withValues(alpha: 0.55),
                                  fillColor.withValues(alpha: 0.95),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.readyToFlash)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final opacity = 0.18 + (0.34 * _pulse.value);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: widget.flashTint.withValues(alpha: opacity),
                      ),
                    );
                  },
                ),
              ),
            ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  if (widget.isPlayerSide) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.person,
                      size: 12,
                      color: Color(0xFF1A1A1A),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    widget.timerLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFF1A1A1A),
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
}
