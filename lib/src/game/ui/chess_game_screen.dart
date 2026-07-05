import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../engine/online_game_controller.dart';
import 'app_assets.dart';
import 'chess_ai_panel.dart';
import 'online_game_panel.dart';
import 'ui_sfx.dart';

enum _ChessMode { vsAi, online }

/// Chess-only shell with explicit local-vs-AI and online modes.
class ChessGameScreen extends StatefulWidget {
  const ChessGameScreen({super.key, this.onlineControllerFactory});

  /// Test-only seam forwarded to [OnlineGamePanel] so widget tests can supply a
  /// controller with a stubbed HTTP client. Null in production.
  @visibleForTesting
  final OnlineGameController Function()? onlineControllerFactory;

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showNavRail = constraints.maxWidth >= 920;
              return Row(
                children: <Widget>[
                  if (showNavRail)
                    GameNavRail(
                      destinations: <GameNavDestination>[
                        GameNavDestination(
                          icon: Icons.smart_toy_outlined,
                          tooltip: 'Vs AI',
                          isActive: _mode == _ChessMode.vsAi,
                          onTap: () {
                            UiSfx.tap();
                            setState(() {
                              _mode = _ChessMode.vsAi;
                            });
                          },
                        ),
                        GameNavDestination(
                          icon: Icons.wifi_rounded,
                          tooltip: 'Online',
                          isActive: _mode == _ChessMode.online,
                          onTap: () {
                            UiSfx.tap();
                            setState(() {
                              _mode = _ChessMode.online;
                            });
                          },
                        ),
                        const GameNavDestination(
                          icon: Icons.history_rounded,
                          tooltip: 'Recent games',
                        ),
                      ],
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: _buildHeader(context),
                        ),
                        Expanded(
                          child: _mode == _ChessMode.vsAi
                              ? const ChessAiPanel()
                              : OnlineGamePanel(
                                  showModeSwitch: false,
                                  controllerFactory:
                                      widget.onlineControllerFactory,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;
          final titleStyle =
              (isCompact
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.titleLarge)
                  ?.copyWith(fontWeight: FontWeight.w800);

          final modeSwitch = CompactModeSwitch(
            key: const ValueKey<String>('chess_mode_switch'),
            onlineSelected: _mode == _ChessMode.online,
            onChanged: (online) {
              UiSfx.tap();
              setState(() {
                _mode = online ? _ChessMode.online : _ChessMode.vsAi;
              });
            },
          );

          if (isCompact) {
            // Mobile-first compact header: keep mode switching visible while
            // reducing vertical footprint and avoiding long wrapped subtitles.
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _mode == _ChessMode.vsAi ? 'Chess Vs AI' : 'Chess Online',
                      style: titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  modeSwitch,
                ],
              ),
            );
          }

          return Padding(
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
                        _mode == _ChessMode.vsAi
                            ? 'Chess Vs AI'
                            : 'Chess Online',
                        style: titleStyle,
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
                modeSwitch,
              ],
            ),
          );
        },
      ),
    );
  }
}
