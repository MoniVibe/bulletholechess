import 'package:flutter/material.dart';

import 'src/game/ui/chess_game_screen.dart';

void main() {
  runApp(const BulletholeChessApp());
}

class BulletholeChessApp extends StatelessWidget {
  const BulletholeChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2B7FFF);
    const secondary = Color(0xFFE2A84A);
    const tertiary = Color(0xFF34C9A5);
    const surface = Color(0xFFF5F7FB);
    const onSurface = Color(0xFF122033);

    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        tertiary: tertiary,
        surface: surface,
        onSurface: onSurface,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );

    return MaterialApp(
      title: 'Bullethole Chess',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme
            .apply(
              fontFamily: 'Sora',
              bodyColor: onSurface,
              displayColor: onSurface,
            )
            .copyWith(
              titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
                fontFamily: 'Orbitron',
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
              headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'Orbitron',
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
        cardTheme: CardThemeData(
          color: const Color(0xD9FFFFFF),
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.58),
              width: 1,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: onSurface,
            side: BorderSide(color: primary.withValues(alpha: 0.34)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xF0FFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary.withValues(alpha: 0.25)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary.withValues(alpha: 0.18)),
          ),
        ),
      ),
      home: const ChessGameScreen(),
    );
  }
}
