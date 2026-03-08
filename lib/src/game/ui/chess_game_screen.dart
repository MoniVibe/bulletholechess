import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import 'app_assets.dart';
import 'chess_ai_panel.dart';
import 'online_game_panel.dart';
import 'ui_sfx.dart';

enum _ChessMode { vsAi, online }

/// Chess-only shell with explicit local-vs-AI and online modes.
class ChessGameScreen extends StatefulWidget {
  const ChessGameScreen({super.key});

  @override
  State<ChessGameScreen> createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends State<ChessGameScreen> {
  _ChessMode _mode = _ChessMode.vsAi;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameBackdrop(
        backgroundAssetPath: AppAssets.appBackground,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _buildHeader(context),
              ),
              Expanded(
                child: _mode == _ChessMode.vsAi
                    ? const ChessAiPanel()
                    : const OnlineGamePanel(showModeSwitch: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = _mode == _ChessMode.vsAi
        ? 'Train locally with bullet-hole timing windows.'
        : 'Live multiplayer with synchronized cooldown windows.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.sports_esports_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _mode == _ChessMode.vsAi ? 'Chess Vs AI' : 'Chess Online',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CompactModeSwitch(
              key: const ValueKey<String>('chess_mode_switch'),
              onlineSelected: _mode == _ChessMode.online,
              onChanged: (online) {
                UiSfx.tap();
                setState(() {
                  _mode = online ? _ChessMode.online : _ChessMode.vsAi;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
