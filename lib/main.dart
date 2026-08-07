import 'package:flutter/material.dart';
import 'package:bullethole_shared/bullethole_shared.dart';

import 'src/game/engine/online_game_controller.dart';
import 'src/game/ui/chess_game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BulletholeChessApp());
  // Bullethole Chess's own AdMob production ids (it is its own AdMob app). Only
  // used when built with --dart-define=bullethole.ads.prod=true; default/test
  // builds ignore them. The App ID must match AndroidManifest APPLICATION_ID at
  // go-live.
  AdConfig.configure(
    androidAppId: 'ca-app-pub-4992063355616359~1799160184',
    androidInterstitial: 'ca-app-pub-4992063355616359/6915755495',
  );
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
