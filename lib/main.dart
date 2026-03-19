import 'package:flutter/material.dart';
import 'package:bullethole_shared/bullethole_shared.dart';

import 'src/game/ui/chess_game_screen.dart';

void main() {
  runApp(const BulletholeChessApp());
}

class BulletholeChessApp extends StatelessWidget {
  const BulletholeChessApp({super.key});

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
      home: const ChessGameScreen(),
    );
  }
}
