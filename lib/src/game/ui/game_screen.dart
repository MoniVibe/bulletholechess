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
          appBar: AppBar(title: const Text('Bullethole Chess MVP')),
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
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        label: 'Version',
                        value: _controller.version.toString(),
                      ),
                      _InfoChip(
                        label: 'N',
                        value: '${_controller.cooldownDuration.inSeconds}s',
                      ),
                      _InfoChip(
                        label: 'Opp Last',
                        value: _controller.opponentLastMoveLabel ?? '-',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const sideBarWidth = 40.0;
                  const sideGap = 10.0;
                  final maxBoardWidth =
                      constraints.maxWidth - (sideBarWidth * 2) - (sideGap * 2);
                  final boardSize = math.min(
                    maxBoardWidth,
                    constraints.maxHeight,
                  );
                  if (boardSize <= 0) {
                    return const SizedBox.shrink();
                  }

                  final whiteRatio = _cooldownRatio(_controller, 'w');
                  final blackRatio = _cooldownRatio(_controller, 'b');
                  final whiteIsPlayer = _controller.playerColor == 'w';
                  final blackIsPlayer = _controller.playerColor == 'b';

                  return SizedBox(
                    width: boardSize + (sideBarWidth * 2) + (sideGap * 2),
                    height: boardSize,
                    child: Row(
                      children: [
                        SizedBox(
                          width: sideBarWidth,
                          child: _SideCooldownBar(
                            key: const ValueKey('w_bar'),
                            label: 'W',
                            ratio: whiteRatio,
                            activeColor: const Color(0xFF42A5F5),
                            isPlayerSide: whiteIsPlayer,
                            timerLabel: _controller.hasActiveGame
                                ? _formatDuration(whiteRemaining)
                                : '--',
                            timerOnTop: !whiteIsPlayer,
                            readyToFlash:
                                _controller.hasActiveGame &&
                                whiteRemaining.inMilliseconds == 0,
                            flashTint: const Color(0xFFBBDEFB),
                            flashDuration: const Duration(milliseconds: 2600),
                          ),
                        ),
                        const SizedBox(width: sideGap),
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
                                      color: Colors.black.withValues(alpha: 0.2),
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
                        const SizedBox(width: sideGap),
                        SizedBox(
                          width: sideBarWidth,
                          child: _SideCooldownBar(
                            key: const ValueKey('b_bar'),
                            label: 'B',
                            ratio: blackRatio,
                            activeColor: const Color(0xFFFF7043),
                            isPlayerSide: blackIsPlayer,
                            timerLabel: _controller.hasActiveGame
                                ? _formatDuration(blackRemaining)
                                : '--',
                            timerOnTop: !blackIsPlayer,
                            readyToFlash:
                                _controller.hasActiveGame &&
                                blackRemaining.inMilliseconds == 0,
                            flashTint: const Color(0xFFFFCCBC),
                            flashDuration: const Duration(milliseconds: 3200),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFE7DD),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '$label: $value',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SideCooldownBar extends StatefulWidget {
  const _SideCooldownBar({
    required this.label,
    required this.ratio,
    required this.activeColor,
    required this.isPlayerSide,
    required this.timerLabel,
    required this.timerOnTop,
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
  final bool timerOnTop;
  final bool readyToFlash;
  final Color flashTint;
  final Duration flashDuration;

  @override
  State<_SideCooldownBar> createState() => _SideCooldownBarState();
}

class _SideCooldownBarState extends State<_SideCooldownBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: widget.flashDuration)
      ..repeat(reverse: true);
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

    return Column(
      children: [
        if (widget.timerOnTop)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.timerLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        Expanded(
          child: DecoratedBox(
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
                          alignment: Alignment.bottomCenter,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: widget.ratio),
                            duration: const Duration(milliseconds: 160),
                            builder: (context, value, _) {
                              return FractionallySizedBox(
                                heightFactor: value,
                                widthFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        fillColor.withValues(alpha: 0.95),
                                        fillColor.withValues(alpha: 0.55),
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
                          final opacity = 0.08 + (0.2 * _pulse.value);
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
                Positioned(
                  top: 6,
                  left: 0,
                  right: 0,
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                if (widget.isPlayerSide)
                  const Positioned(
                    bottom: 6,
                    left: 0,
                    right: 0,
                    child: Icon(
                      Icons.person,
                      size: 12,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!widget.timerOnTop)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.timerLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
      ],
    );
  }
}
