import 'package:flutter/material.dart';

import '../engine/online_game_controller.dart';
import 'chess_board_view.dart';

class OnlineGamePanel extends StatefulWidget {
  const OnlineGamePanel({super.key});

  @override
  State<OnlineGamePanel> createState() => _OnlineGamePanelState();
}

class _OnlineGamePanelState extends State<OnlineGamePanel> {
  late final OnlineGameController _controller;
  late final TextEditingController _apiBaseController;
  late final TextEditingController _nameController;
  late final TextEditingController _joinCodeController;

  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _controller = OnlineGameController();
    _apiBaseController = TextEditingController(text: 'http://localhost:8080');
    _nameController = TextEditingController(text: 'Player');
    _joinCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _apiBaseController.dispose();
    _nameController.dispose();
    _joinCodeController.dispose();
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

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: canStart ? _createInvite : null,
                              icon: const Icon(Icons.link),
                              label: const Text('Create Invite'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: connected ? _disconnect : null,
                              child: const Text('Disconnect'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _joinCodeController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Invite Code',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.tonal(
                            onPressed: canStart ? _joinInvite : null,
                            child: const Text('Join Invite'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: connected
                            ? _controller.requestNewGame
                            : null,
                        icon: const Icon(Icons.replay, size: 16),
                        label: const Text('Request New Game'),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            label: 'Invite',
                            value: _controller.joinCode ?? '-',
                          ),
                          _InfoChip(
                            label: 'Match',
                            value: _controller.matchId ?? '-',
                          ),
                          _InfoChip(
                            label: 'You',
                            value: _controller.myColor == null
                                ? '-'
                                : _controller.myColor == 'w'
                                ? 'White'
                                : 'Black',
                          ),
                          _InfoChip(
                            label: 'Turn',
                            value: _controller.turnColor == 'w'
                                ? 'White'
                                : 'Black',
                          ),
                          _InfoChip(
                            label: 'White',
                            value: _controller.whitePlayerName ?? '-',
                          ),
                          _InfoChip(
                            label: 'Black',
                            value: _controller.blackPlayerName ?? '-',
                          ),
                          _InfoChip(
                            label: 'Opp Last',
                            value: _controller.opponentLastMoveLabel ?? '-',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _controller.statusText,
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ChessBoardView(
                      pieces: _controller.boardPieces,
                      playerColor: _controller.playerColor,
                      selectedSquare: _controller.selectedSquare,
                      legalTargets: _controller.legalTargets,
                      lastMoveFrom: _controller.lastMoveFrom,
                      lastMoveTo: _controller.lastMoveTo,
                      lastMoveHighlightColor: _controller.isOpponentLastMove
                          ? const Color(0xFFE57373)
                          : const Color(0xFFD7CA64),
                      onSquareTap: _controller.tapSquare,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: Colors.white,
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
                          _controller.history.isEmpty
                              ? '-'
                              : _controller.history.join('  '),
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

  Future<void> _createInvite() async {
    setState(() {
      _connecting = true;
    });

    try {
      await _controller.createInvite(
        apiBaseUrl: _apiBaseController.text,
        displayName: _nameController.text,
      );
      if (_controller.joinCode != null) {
        _joinCodeController.text = _controller.joinCode!;
      }
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  Future<void> _joinInvite() async {
    setState(() {
      _connecting = true;
    });

    try {
      await _controller.joinInvite(
        apiBaseUrl: _apiBaseController.text,
        joinCode: _joinCodeController.text,
        displayName: _nameController.text,
      );
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    await _controller.disconnect();
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
