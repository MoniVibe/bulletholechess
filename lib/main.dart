import 'package:flutter/material.dart';
import 'package:bullethole_shared/bullethole_shared.dart';

import 'src/game/engine/online_game_controller.dart';
import 'src/game/ui/chess_game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BulletholeChessApp());
  // Additive, non-blocking: gather GDPR/UMP consent then initialise the ads SDK
  // (mobile only; a no-op on web/desktop). Fire-and-forget and never throws into
  // the app, so the game loop is unaffected.
  AdsBootstrap.instance.initialize();
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
        primary: Color(0xFFEBA23C),
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
