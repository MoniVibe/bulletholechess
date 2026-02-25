import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/local_game_controller.dart';
import 'chess_board_view.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const List<int> _cooldownOptionsSeconds = [2, 3, 5, 7, 10];

  late final LocalGameController _controller;
  bool _isGameMenuOpen = false;
  int _selectedCooldownSeconds = 3;

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
        final history = _controller.history;
        final tailHistory = history.length > 8
            ? history.sublist(history.length - 8)
            : history;

        return Scaffold(
          appBar: AppBar(title: const Text('Bullethole Chess MVP')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.tonal(
                                        onPressed: () {
                                          _startNewGame(playerAsWhite: true);
                                        },
                                        child: const Text('New Game: White'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.tonal(
                                        onPressed: () {
                                          _startNewGame(playerAsWhite: false);
                                        },
                                        child: const Text('New Game: Black'),
                                      ),
                                    ),
                                  ],
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
                                const SizedBox(height: 10),
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.tune,
                                      size: 16,
                                      color: Color(0xFF6A625A),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Settings section placeholder (coming soon)',
                                        style: TextStyle(
                                          color: Color(0xFF6A625A),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
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
                                label: 'Ready',
                                value: _controller.readyLabel,
                              ),
                              _InfoChip(
                                label: 'Version',
                                value: _controller.version.toString(),
                              ),
                              _InfoChip(
                                label: 'N',
                                value:
                                    '${_controller.cooldownDuration.inSeconds}s',
                              ),
                              _InfoChip(
                                label: 'Queue',
                                value: _controller.queuedMoveLabel ?? '-',
                              ),
                              _InfoChip(
                                label: 'You',
                                value: _formatDuration(
                                  _controller.cooldownRemaining(
                                    _controller.playerColor,
                                  ),
                                ),
                              ),
                              _InfoChip(
                                label: 'Bot',
                                value: _formatDuration(
                                  _controller.cooldownRemaining(
                                    _controller.aiColor,
                                  ),
                                ),
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
                          const sideBarWidth = 30.0;
                          const sideGap = 10.0;
                          final maxBoardWidth =
                              constraints.maxWidth -
                              (sideBarWidth * 2) -
                              (sideGap * 2);
                          final boardSize = math.min(
                            maxBoardWidth,
                            constraints.maxHeight,
                          );
                          if (boardSize <= 0) {
                            return const SizedBox.shrink();
                          }

                          final whiteRatio = _cooldownRatio(_controller, 'w');
                          final blackRatio = _cooldownRatio(_controller, 'b');

                          return SizedBox(
                            width:
                                boardSize + (sideBarWidth * 2) + (sideGap * 2),
                            height: boardSize,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: sideBarWidth,
                                  child: _SideCooldownBar(
                                    label: 'W',
                                    ratio: whiteRatio,
                                    activeColor: const Color(0xFF42A5F5),
                                    isPlayerSide:
                                        _controller.playerColor == 'w',
                                  ),
                                ),
                                const SizedBox(width: sideGap),
                                SizedBox(
                                  width: boardSize,
                                  height: boardSize,
                                  child: ChessBoardView(
                                    pieces: _controller.boardPieces,
                                    playerColor: _controller.playerColor,
                                    selectedSquare: _controller.selectedSquare,
                                    legalTargets: _controller.legalTargets,
                                    lastMoveFrom: _controller.lastMoveFrom,
                                    lastMoveTo: _controller.lastMoveTo,
                                    onSquareTap: _controller.tapSquare,
                                  ),
                                ),
                                const SizedBox(width: sideGap),
                                SizedBox(
                                  width: sideBarWidth,
                                  child: _SideCooldownBar(
                                    label: 'B',
                                    ratio: blackRatio,
                                    activeColor: const Color(0xFFFF7043),
                                    isPlayerSide:
                                        _controller.playerColor == 'b',
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
                              tailHistory.isEmpty
                                  ? '-'
                                  : tailHistory.join('  '),
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
            ),
          ),
        );
      },
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

class _SideCooldownBar extends StatelessWidget {
  const _SideCooldownBar({
    required this.label,
    required this.ratio,
    required this.activeColor,
    required this.isPlayerSide,
  });

  final String label;
  final double ratio;
  final Color activeColor;
  final bool isPlayerSide;

  @override
  Widget build(BuildContext context) {
    final ready = ratio == 0;
    final fillColor = ready ? const Color(0xFF43A047) : activeColor;

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
                    alignment: Alignment.bottomCenter,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: ratio),
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
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          if (isPlayerSide)
            Positioned(
              bottom: 6,
              left: 0,
              right: 0,
              child: const Icon(
                Icons.person,
                size: 12,
                color: Color(0xFF1A1A1A),
              ),
            ),
        ],
      ),
    );
  }
}
