import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../../app_assets.dart';

class OnlineVictoryOverlay extends StatelessWidget {
  const OnlineVictoryOverlay({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xEE111821),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x66FFFFFF)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFFD26A),
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: AppAssetIcon(
                        AppAssets.rematchIcon,
                        fallbackIcon: Icons.replay,
                        size: 18,
                      ),
                      label: Text(actionLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
