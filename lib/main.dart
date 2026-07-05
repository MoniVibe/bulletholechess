import 'package:flutter/material.dart';
import 'package:bullethole_shared/bullethole_shared.dart';

import 'src/game/engine/online_game_controller.dart';
import 'src/game/ui/chess_game_screen.dart';

void main() {
  runApp(const BulletholeChessApp());
}

class BulletholeChessApp extends StatelessWidget {
  const BulletholeChessApp({super.key, this.onlineControllerFactory});

  /// Test-only seam forwarded to [ChessGameScreen] so widget tests can supply a
  /// controller with a stubbed HTTP client. Null in production.
  @visibleForTesting
  final OnlineGameController Function()? onlineControllerFactory;

  @override
  Widget build(BuildContext context) {
    final baseTheme = buildBulletholeGameTheme(
      palette: const BulletholeThemePalette(
        primary: Color(0xFFE04545),
        secondary: Color(0xFFD39B46),
        tertiary: Color(0xFF4F79FF),
      ),
    );

    return MaterialApp(
      title: 'Bullethole Chess',
      debugShowCheckedModeBanner: false,
      theme: baseTheme,
      home: ChessGameScreen(
        onlineControllerFactory: onlineControllerFactory,
      ),
    );
  }
}
