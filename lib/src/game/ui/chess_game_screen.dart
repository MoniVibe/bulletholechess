import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import 'app_assets.dart';
import 'chess_ai_panel.dart';
import 'online_game_panel.dart';

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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _mode == _ChessMode.vsAi
                              ? 'Chess Vs AI'
                              : 'Chess Online',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      CompactModeSwitch(
                        onlineSelected: _mode == _ChessMode.online,
                        onChanged: (online) {
                          setState(() {
                            _mode = online
                                ? _ChessMode.online
                                : _ChessMode.vsAi;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _mode == _ChessMode.vsAi
                      ? const ChessAiPanel()
                      : const OnlineGamePanel(showModeSwitch: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
