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
  bool _backendActionInFlight = false;
  bool _isMatchMenuOpen = false;
  int _selectedCooldownSeconds = 3;

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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const barHeight = 34.0;
                      const boardGap = 10.0;
                      final boardSize = math.min(
                        constraints.maxWidth,
                        constraints.maxHeight -
                            (barHeight * 2) -
                            (boardGap * 2),
                      );
                      if (boardSize <= 0) {
                        return const SizedBox.shrink();
                      }

                      final whiteRatio = _cooldownRatio(_controller, 'w');
                      final blackRatio = _cooldownRatio(_controller, 'b');
                      final topColor = _controller.playerColor == 'w'
                          ? 'b'
                          : 'w';
                      final bottomColor = _controller.playerColor;
                      final whiteIsPlayer = _controller.myColor == 'w';
                      final blackIsPlayer = _controller.myColor == 'b';
                      final topRatio = topColor == 'w'
                          ? whiteRatio
                          : blackRatio;
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
                              child: _HorizontalStatusBar(
                                label: topColor == 'w' ? 'W' : 'B',
                                ratio: topRatio,
                                activeColor: topActiveColor,
                                isPlayerSide: topIsPlayer,
                                statusLabel: _controller.isMatchActive
                                    ? _formatDuration(topRemaining)
                                    : '--',
                                readyToFlash:
                                    _controller.isConnected &&
                                    _controller.isMatchActive &&
                                    !_controller.isGameOver &&
                                    topRemaining.inMilliseconds == 0,
                                flashTint: topFlashTint,
                                flashDuration: const Duration(
                                  milliseconds: 1800,
                                ),
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
                            const SizedBox(height: boardGap),
                            SizedBox(
                              height: barHeight,
                              child: _HorizontalStatusBar(
                                label: bottomColor == 'w' ? 'W' : 'B',
                                ratio: bottomRatio,
                                activeColor: bottomActiveColor,
                                isPlayerSide: bottomIsPlayer,
                                statusLabel: _controller.isMatchActive
                                    ? _formatDuration(bottomRemaining)
                                    : '--',
                                readyToFlash:
                                    _controller.isConnected &&
                                    _controller.isMatchActive &&
                                    !_controller.isGameOver &&
                                    bottomRemaining.inMilliseconds == 0,
                                flashTint: bottomFlashTint,
                                flashDuration: const Duration(
                                  milliseconds: 1800,
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
      if (!mounted) {
        return;
      }
      setState(() {
        _backendActionInFlight = false;
      });
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
      if (!mounted) {
        return;
      }
      setState(() {
        _backendActionInFlight = false;
      });
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
                    icon: const Icon(Icons.monitor_heart_outlined, size: 16),
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

class _HorizontalStatusBar extends StatefulWidget {
  const _HorizontalStatusBar({
    required this.label,
    required this.ratio,
    required this.activeColor,
    required this.isPlayerSide,
    required this.statusLabel,
    required this.readyToFlash,
    required this.flashTint,
    required this.flashDuration,
  });

  final String label;
  final double ratio;
  final Color activeColor;
  final bool isPlayerSide;
  final String statusLabel;
  final bool readyToFlash;
  final Color flashTint;
  final Duration flashDuration;

  @override
  State<_HorizontalStatusBar> createState() => _HorizontalStatusBarState();
}

class _HorizontalStatusBarState extends State<_HorizontalStatusBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: widget.flashDuration);
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _HorizontalStatusBar oldWidget) {
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
                    widget.statusLabel,
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
