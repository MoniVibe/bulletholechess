import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/online_game_controller.dart';
import 'chess_board_view.dart';

class OnlineGamePanel extends StatefulWidget {
  const OnlineGamePanel({super.key});

  @override
  State<OnlineGamePanel> createState() => _OnlineGamePanelState();
}

class _OnlineGamePanelState extends State<OnlineGamePanel> {
  static const List<int> _cooldownOptionsSeconds = [2, 3, 5, 7, 10];
  static const String _defaultBackendUrl = String.fromEnvironment(
    'DEFAULT_BACKEND_URL',
    defaultValue: 'http://localhost:8080',
  );

  late final OnlineGameController _controller;
  late final TextEditingController _apiBaseController;
  late final TextEditingController _nameController;

  bool _connecting = false;
  bool _isMatchMenuOpen = false;
  int _selectedCooldownSeconds = 3;

  @override
  void initState() {
    super.initState();
    _controller = OnlineGameController();
    _apiBaseController = TextEditingController(text: _defaultBackendUrl);
    _nameController = TextEditingController(text: 'Player');
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
                        'Matchmaking',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('Backend and connection'),
                      trailing: Icon(
                        _isMatchMenuOpen
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                      ),
                      onTap: () {
                        setState(() {
                          _isMatchMenuOpen = !_isMatchMenuOpen;
                        });
                      },
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: canStart ? _findMatch : null,
                                    icon: const Icon(Icons.groups_2_outlined),
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
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: connected
                                    ? () => _controller.requestNewGame(
                                        cooldownSeconds:
                                            _selectedCooldownSeconds,
                                      )
                                    : null,
                                icon: const Icon(Icons.replay, size: 16),
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
                      crossFadeState: _isMatchMenuOpen
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 180),
                      sizeCurve: Curves.easeOutCubic,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
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
                            label: 'N',
                            value: '${_controller.cooldownDuration.inSeconds}s',
                          ),
                          _InfoChip(
                            label: 'Turn',
                            value: _controller.isConnected
                                ? _controller.turnColor == 'w'
                                      ? 'White'
                                      : 'Black'
                                : '-',
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
                          _InfoChip(
                            label: 'Queue',
                            value: _controller.queuedMoveLabel ?? '-',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const sideBarWidth = 40.0;
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
                      final whiteIsPlayer = _controller.myColor == 'w';
                      final blackIsPlayer = _controller.myColor == 'b';

                      return SizedBox(
                        width: boardSize + (sideBarWidth * 2) + (sideGap * 2),
                        height: boardSize,
                        child: Row(
                          children: [
                            SizedBox(
                              width: sideBarWidth,
                              child: _SideStatusBar(
                                label: 'W',
                                ratio: whiteRatio,
                                activeColor: const Color(0xFF42A5F5),
                                isPlayerSide: whiteIsPlayer,
                                statusLabel: _controller.isMatchActive
                                    ? _formatDuration(whiteRemaining)
                                    : '--',
                                statusOnTop: !whiteIsPlayer,
                                readyToFlash:
                                    _controller.isConnected &&
                                    _controller.isMatchActive &&
                                    !_controller.isGameOver &&
                                    whiteRemaining.inMilliseconds == 0,
                                flashTint: const Color(0xFFBBDEFB),
                                flashDuration: const Duration(
                                  milliseconds: 2600,
                                ),
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
                                    lastMoveFrom:
                                        _controller.playerLastMoveFrom,
                                    lastMoveTo: _controller.playerLastMoveTo,
                                    lastMoveHighlightColor: const Color(
                                      0xFFD7CA64,
                                    ),
                                    secondaryMoveFrom:
                                        _controller.opponentLastMoveFrom,
                                    secondaryMoveTo:
                                        _controller.opponentLastMoveTo,
                                    secondaryMoveHighlightColor: const Color(
                                      0xFFE57373,
                                    ),
                                    queuedMoveFrom: _controller.queuedMoveFrom,
                                    queuedMoveTo: _controller.queuedMoveTo,
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
                                            onPressed: canStart
                                                ? _findMatch
                                                : null,
                                            icon: const Icon(
                                              Icons.groups_2_outlined,
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
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: sideGap),
                            SizedBox(
                              width: sideBarWidth,
                              child: _SideStatusBar(
                                label: 'B',
                                ratio: blackRatio,
                                activeColor: const Color(0xFFFF7043),
                                isPlayerSide: blackIsPlayer,
                                statusLabel: _controller.isMatchActive
                                    ? _formatDuration(blackRemaining)
                                    : '--',
                                statusOnTop: !blackIsPlayer,
                                readyToFlash:
                                    _controller.isConnected &&
                                    _controller.isMatchActive &&
                                    !_controller.isGameOver &&
                                    blackRemaining.inMilliseconds == 0,
                                flashTint: const Color(0xFFFFCCBC),
                                flashDuration: const Duration(
                                  milliseconds: 3200,
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
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final seconds = duration.inMilliseconds / 1000.0;
    return '${seconds.toStringAsFixed(1)}s';
  }

  static double _cooldownRatio(OnlineGameController controller, String color) {
    final totalMs = controller.cooldownDuration.inMilliseconds;
    if (totalMs <= 0 || !controller.isMatchActive) {
      return 0;
    }

    final remainingMs = controller.cooldownRemaining(color).inMilliseconds;
    final ratio = remainingMs / totalMs;
    return ratio.clamp(0.0, 1.0);
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

class _SideStatusBar extends StatefulWidget {
  const _SideStatusBar({
    required this.label,
    required this.ratio,
    required this.activeColor,
    required this.isPlayerSide,
    required this.statusLabel,
    required this.statusOnTop,
    required this.readyToFlash,
    required this.flashTint,
    required this.flashDuration,
  });

  final String label;
  final double ratio;
  final Color activeColor;
  final bool isPlayerSide;
  final String statusLabel;
  final bool statusOnTop;
  final bool readyToFlash;
  final Color flashTint;
  final Duration flashDuration;

  @override
  State<_SideStatusBar> createState() => _SideStatusBarState();
}

class _SideStatusBarState extends State<_SideStatusBar>
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
        if (widget.statusOnTop)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.statusLabel,
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
                        decoration: const BoxDecoration(
                          color: Color(0xFF9E9489),
                        ),
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
                              color: widget.flashTint.withValues(
                                alpha: opacity,
                              ),
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
        if (!widget.statusOnTop)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.statusLabel,
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
