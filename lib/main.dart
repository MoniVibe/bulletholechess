import 'package:flutter/material.dart';

import 'src/game/ui/game_screen.dart';

void main() {
  runApp(const BulletholeChessApp());
}

class BulletholeChessApp extends StatelessWidget {
  const BulletholeChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    const boardDark = Color(0xFF635B57);
    const surface = Color(0xFFF4F1EC);

    return MaterialApp(
      title: 'Bullethole Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: boardDark,
          secondary: Color(0xFF2F7D32),
          surface: surface,
        ),
        scaffoldBackgroundColor: surface,
        useMaterial3: true,
      ),
      home: const GameScreen(),
    );
  }
}
