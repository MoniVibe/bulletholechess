import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class OnlineMatchFoundOverlay extends StatelessWidget {
  const OnlineMatchFoundOverlay({
    required this.fadeAnimation,
    required this.scaleAnimation,
    required this.topColor,
    required this.bottomColor,
    required this.topPlayerName,
    required this.bottomPlayerName,
    super.key,
  });

  final Animation<double> fadeAnimation;
  final Animation<double> scaleAnimation;
  final String topColor;
  final String bottomColor;
  final String topPlayerName;
  final String bottomPlayerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FadeTransition(
      opacity: fadeAnimation,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 2.8, sigmaY: 2.8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x66121820),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: ScaleTransition(
              scale: scaleAnimation,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0xFF0E1A28),
                        Color(0xFF13273D),
                        Color(0xFF0E1A28),
                      ],
                    ),
                    border: Border.all(color: const Color(0x66A8DBFF)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x551C85C7),
                        blurRadius: 28,
                        spreadRadius: 1,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xFF50E3C2),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Match Found!',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You are now live',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFCFE4F8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _MatchFoundPlayerRow(
                          sideLabel: topColor == 'w' ? 'White' : 'Black',
                          playerName: topPlayerName,
                          accent: topColor == 'w'
                              ? const Color(0xFFA6E3FF)
                              : const Color(0xFFFFC8AA),
                          alignStart: true,
                        ),
                        const SizedBox(height: 8),
                        _MatchFoundPlayerRow(
                          sideLabel: bottomColor == 'w' ? 'White' : 'Black',
                          playerName: bottomPlayerName,
                          accent: bottomColor == 'w'
                              ? const Color(0xFFA6E3FF)
                              : const Color(0xFFFFC8AA),
                          alignStart: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchFoundPlayerRow extends StatelessWidget {
  const _MatchFoundPlayerRow({
    required this.sideLabel,
    required this.playerName,
    required this.accent,
    required this.alignStart,
  });

  final String sideLabel;
  final String playerName;
  final Color accent;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x331D2F45),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0x55FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: 0.8)),
            ),
            child: Text(
              sideLabel,
              style: const TextStyle(
                color: Color(0xFFF0F6FC),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            playerName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      child: content,
    );
  }
}
