import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../../app_assets.dart';
import '../../collapsible_settings_section.dart';
import '../../skin_catalog.dart';
import 'online_backend_health_card.dart';

class OnlineMatchmakingSettingsCard extends StatelessWidget {
  const OnlineMatchmakingSettingsCard({
    required this.isOpen,
    required this.onToggle,
    required this.showModeSwitch,
    required this.isOnlineMode,
    required this.onModeChanged,
    required this.scrollController,
    required this.nameController,
    required this.cooldownOptionsSeconds,
    required this.selectedCooldownSeconds,
    required this.onCooldownChanged,
    required this.isBoardSettingsOpen,
    required this.onBoardSettingsToggle,
    required this.timeBarOrientation,
    required this.onTimeBarOrientationChanged,
    required this.selectedChessBoardSkinId,
    required this.chessBoardDropdownItems,
    required this.onChessBoardSkinChanged,
    required this.myPieceSkinId,
    required this.ownedChessPieceSkinIds,
    required this.onMyPieceSkinChanged,
    required this.canStart,
    required this.connected,
    required this.onFindMatch,
    required this.onDisconnect,
    required this.backendHealthState,
    required this.backendHealthMessage,
    required this.backendHealthCheckedAt,
    required this.backendActionInFlight,
    required this.onCheckBackendHealth,
    required this.onWakeBackend,
    required this.onRequestNewGame,
    required this.hasQueuedMove,
    required this.queuedMoveLabel,
    required this.onClearQueuedMove,
    super.key,
  });

  final bool isOpen;
  final VoidCallback onToggle;
  final bool showModeSwitch;
  final bool isOnlineMode;
  final ValueChanged<bool>? onModeChanged;
  final ScrollController scrollController;
  final TextEditingController nameController;

  final List<int> cooldownOptionsSeconds;
  final int selectedCooldownSeconds;
  final ValueChanged<int> onCooldownChanged;

  final bool isBoardSettingsOpen;
  final VoidCallback onBoardSettingsToggle;
  final TimeBarOrientation timeBarOrientation;
  final ValueChanged<TimeBarOrientation> onTimeBarOrientationChanged;
  final String selectedChessBoardSkinId;
  final List<DropdownMenuItem<String>> chessBoardDropdownItems;
  final ValueChanged<String> onChessBoardSkinChanged;
  final String myPieceSkinId;
  final Set<String> ownedChessPieceSkinIds;
  final ValueChanged<String> onMyPieceSkinChanged;

  final bool canStart;
  final bool connected;
  final VoidCallback onFindMatch;
  final VoidCallback onDisconnect;

  final BackendHealthState backendHealthState;
  final String? backendHealthMessage;
  final DateTime? backendHealthCheckedAt;
  final bool backendActionInFlight;
  final Future<void> Function() onCheckBackendHealth;
  final Future<void> Function() onWakeBackend;

  final VoidCallback onRequestNewGame;
  final bool hasQueuedMove;
  final String? queuedMoveLabel;
  final VoidCallback onClearQueuedMove;

  @override
  Widget build(BuildContext context) {
    return CollapsibleSettingsCard(
      title: 'Matchmaking',
      isOpen: isOpen,
      onToggle: onToggle,
      leading: const AppAssetIcon(
        AppAssets.settingsIcon,
        fallbackIcon: Icons.settings,
        size: 22,
      ),
      trailing: showModeSwitch
          ? CompactModeSwitch(
              onlineSelected: isOnlineMode,
              onChanged: (selected) {
                final callback = onModeChanged;
                if (callback != null) {
                  callback(selected);
                }
              },
            )
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              children: [
                TextField(
                  key: const ValueKey<String>('chess_online_display_name'),
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: selectedCooldownSeconds,
                  decoration: const InputDecoration(
                    labelText: 'Cooldown (seconds)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: cooldownOptionsSeconds
                      .map(
                        (seconds) => DropdownMenuItem<int>(
                          value: seconds,
                          child: Text('$seconds s'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: connected
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          onCooldownChanged(value);
                        },
                ),
                const SizedBox(height: 8),
                CollapsibleSettingsSection(
                  title: 'Board Settings',
                  isOpen: isBoardSettingsOpen,
                  onToggle: onBoardSettingsToggle,
                  child: Column(
                    children: [
                      TimeBarOrientationSwitch(
                        orientation: timeBarOrientation,
                        onChanged: onTimeBarOrientationChanged,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>(
                          'chess_board_skin_$selectedChessBoardSkinId',
                        ),
                        initialValue: selectedChessBoardSkinId,
                        decoration: const InputDecoration(
                          labelText: 'Select Board',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: chessBoardDropdownItems,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          onChessBoardSkinChanged(value);
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>('my_piece_skin_$myPieceSkinId'),
                        initialValue: myPieceSkinId,
                        decoration: const InputDecoration(
                          labelText: 'Player Skin',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: SkinCatalog.chessPieceSkins
                            .map(
                              (skin) => DropdownMenuItem<String>(
                                value: skin.id,
                                enabled: ownedChessPieceSkinIds.contains(
                                  skin.id,
                                ),
                                child: Text(
                                  ownedChessPieceSkinIds.contains(skin.id)
                                      ? skin.label
                                      : '${skin.label} (Locked)',
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          onMyPieceSkinChanged(value);
                        },
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Opponent piece skin is server-driven and read-only on your side. If both players pick the same skin, black auto-inverts for clarity.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF6A635A)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey<String>('chess_online_find_match'),
                        onPressed: canStart ? onFindMatch : null,
                        icon: const AppAssetIcon(
                          AppAssets.newGameIcon,
                          fallbackIcon: Icons.groups_2_outlined,
                          size: 20,
                        ),
                        label: const Text('Find Match'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey<String>('chess_online_disconnect'),
                        onPressed: connected ? onDisconnect : null,
                        child: const Text('Disconnect'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OnlineBackendHealthCard(
                  state: backendHealthState,
                  message: backendHealthMessage,
                  checkedAt: backendHealthCheckedAt,
                  busy: backendActionInFlight,
                  onCheckPressed: onCheckBackendHealth,
                  onWakePressed: onWakeBackend,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('chess_online_new_game'),
                    onPressed: connected ? onRequestNewGame : null,
                    icon: const AppAssetIcon(
                      AppAssets.rematchIcon,
                      fallbackIcon: Icons.replay,
                      size: 18,
                    ),
                    label: const Text('Request New Game'),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: hasQueuedMove ? onClearQueuedMove : null,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: Text(
                      hasQueuedMove
                          ? 'Clear Queue (${queuedMoveLabel ?? ''})'
                          : 'Clear Queue',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
