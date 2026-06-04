import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../../app_assets.dart';

class OnlineBackendHealthCard extends StatelessWidget {
  const OnlineBackendHealthCard({
    required this.state,
    required this.message,
    required this.checkedAt,
    required this.busy,
    required this.onCheckPressed,
    required this.onWakePressed,
    super.key,
  });

  final BackendHealthState state;
  final String? message;
  final DateTime? checkedAt;
  final bool busy;
  final Future<void> Function() onCheckPressed;
  final Future<void> Function() onWakePressed;

  @override
  Widget build(BuildContext context) {
    final colors = _healthColors(state);
    final checkedLabel = checkedAt == null
        ? 'Not checked yet'
        : 'Checked ${TimeOfDay.fromDateTime(checkedAt!).format(context)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6D0C6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(colors.icon, size: 16, color: colors.color),
                const SizedBox(width: 6),
                Text(
                  _healthLabel(state),
                  style: TextStyle(
                    color: colors.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  checkedLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4E4A45),
                  ),
                ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6D3C12)),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onCheckPressed,
                    icon: const AppAssetIcon(
                      AppAssets.feedbackIcon,
                      fallbackIcon: Icons.monitor_heart_outlined,
                      size: 16,
                    ),
                    label: const Text('Check Status'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : onWakePressed,
                    icon: const Icon(Icons.power_settings_new, size: 16),
                    label: const Text('Wake Backend'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _healthLabel(BackendHealthState state) {
    switch (state) {
      case BackendHealthState.unknown:
        return 'Backend status unknown';
      case BackendHealthState.checking:
        return 'Checking backend...';
      case BackendHealthState.healthy:
        return 'Backend is online';
      case BackendHealthState.unhealthy:
        return 'Backend unavailable';
    }
  }

  static ({IconData icon, Color color}) _healthColors(
    BackendHealthState state,
  ) {
    switch (state) {
      case BackendHealthState.unknown:
        return (icon: Icons.help_outline, color: const Color(0xFF546E7A));
      case BackendHealthState.checking:
        return (icon: Icons.autorenew, color: const Color(0xFF1565C0));
      case BackendHealthState.healthy:
        return (icon: Icons.check_circle, color: const Color(0xFF2E7D32));
      case BackendHealthState.unhealthy:
        return (icon: Icons.error_outline, color: const Color(0xFFB71C1C));
    }
  }
}
