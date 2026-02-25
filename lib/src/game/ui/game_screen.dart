import 'package:flutter/material.dart';

import '../engine/local_game_controller.dart';
import 'chess_board_view.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final LocalGameController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LocalGameController();
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
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () {
                            _controller.startNewGame(playerAsWhite: true);
                          },
                          child: const Text('New Game: White'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () {
                            _controller.startNewGame(playerAsWhite: false);
                          },
                          child: const Text('New Game: Black'),
                        ),
                      ),
                    ],
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
                      child: AspectRatio(
                        aspectRatio: 1,
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
