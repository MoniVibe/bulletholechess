import 'dart:math' as math;

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../engine/chess_ai_game_controller.dart';
import 'app_assets.dart';
import 'chess_board_view.dart';
import 'skin_catalog.dart';

class ChessAiPanel extends StatefulWidget {
  const ChessAiPanel({super.key});

  @override
  State<ChessAiPanel> createState() => _ChessAiPanelState();
}

class _ChessAiPanelState extends State<ChessAiPanel> {
  static const Duration _aiTestingDelay = Duration(seconds: 3);
  static const List<int> _cooldownOptionsSeconds = <int>[2, 3, 5, 7, 10];
  static const Set<String> _ownedChessPieceSkinIds = <String>{
    'chess_classic',
    'chess_red_pieces',
  };

  late final ChessAiGameController _controller;
  bool _menuOpen = true;
  String _selectedBoardSkinId = SkinCatalog.defaultChessBoardSkinId;
  String _selectedPlayerPieceSkinId = SkinCatalog.defaultChessPieceSkinId;
  bool _playerAsWhite = true;
  int _selectedCooldownSeconds = 3;
  TimeBarOrientation _timeBarOrientation = TimeBarOrientation.horizontal;

  @override
  void initState() {
    super.initState();
    _controller = ChessAiGameController(
      aiMoveDelay: _aiTestingDelay,
      initialCooldownDuration: Duration(seconds: _selectedCooldownSeconds),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final boardSkin = SkinCatalog.chessBoardById(_selectedBoardSkinId);
        final playerPieceSkin = SkinCatalog.chessPieceById(
          _selectedPlayerPieceSkinId,
        );
        final aiPieceSkin = SkinCatalog.chessPieceById(
          SkinCatalog.defaultChessPieceSkinId,
        );
        final whitePieceSkin = _controller.playerColor == 'w'
            ? playerPieceSkin
            : aiPieceSkin;
        final blackPieceSkin = _controller.playerColor == 'b'
            ? playerPieceSkin
            : aiPieceSkin;
        final whiteRemaining = _controller.cooldownRemaining('w');
        final blackRemaining = _controller.cooldownRemaining('b');
        final history = _controller.history;
        final tailHistory = history.length > 8
            ? history.sublist(history.length - 8)
            : history;
        final topColor = _controller.playerColor == 'w' ? 'b' : 'w';
        final bottomColor = _controller.playerColor;
        final topRemaining = topColor == 'w' ? whiteRemaining : blackRemaining;
        final bottomRemaining = bottomColor == 'w'
            ? whiteRemaining
            : blackRemaining;
        final topIsPlayer = topColor == _controller.playerColor;
        final bottomIsPlayer = bottomColor == _controller.playerColor;
        final topActiveColor = topColor == 'w'
            ? const Color(0xFF42A5F5)
            : const Color(0xFFFF7043);
        final bottomActiveColor = bottomColor == 'w'
            ? const Color(0xFF42A5F5)
            : const Color(0xFFFF7043);
        final topFlashTint = topColor == 'w'
            ? const Color(0xFFBBDEFB)
            : const Color(0xFFFFCCBC);
        final bottomFlashTint = bottomColor == 'w'
            ? const Color(0xFFBBDEFB)
            : const Color(0xFFFFCCBC);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              CollapsibleSettingsCard(
                title: 'Vs AI',
                isOpen: _menuOpen,
                onToggle: () {
                  setState(() {
                    _menuOpen = !_menuOpen;
                  });
                },
                leading: const AppAssetIcon(
                  AppAssets.settingsIcon,
                  fallbackIcon: Icons.smart_toy_outlined,
                  size: 22,
                ),
                child: Column(
                  children: [
                    DropdownButtonFormField<bool>(
                      initialValue: _playerAsWhite,
                      decoration: const InputDecoration(
                        labelText: 'Play As',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const <DropdownMenuItem<bool>>[
                        DropdownMenuItem<bool>(
                          value: true,
                          child: Text('White'),
                        ),
                        DropdownMenuItem<bool>(
                          value: false,
                          child: Text('Black'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _playerAsWhite = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedCooldownSeconds,
                      decoration: const InputDecoration(
                        labelText: 'Cooldown (seconds)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _cooldownOptionsSeconds
                          .map(
                            (seconds) => DropdownMenuItem<int>(
                              value: seconds,
                              child: Text('$seconds s'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedCooldownSeconds = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TimeBarOrientationSwitch(
                      orientation: _timeBarOrientation,
                      onChanged: (orientation) {
                        setState(() {
                          _timeBarOrientation = orientation;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'chess_ai_board_skin_$_selectedBoardSkinId',
                      ),
                      initialValue: _selectedBoardSkinId,
                      decoration: const InputDecoration(
                        labelText: 'Select Board',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _chessBoardDropdownItems(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedBoardSkinId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'chess_ai_player_skin_$_selectedPlayerPieceSkinId',
                      ),
                      initialValue: _selectedPlayerPieceSkinId,
                      decoration: const InputDecoration(
                        labelText: 'Player Skin',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: SkinCatalog.chessPieceSkins
                          .map(
                            (skin) => DropdownMenuItem<String>(
                              value: skin.id,
                              enabled: _ownedChessPieceSkinIds.contains(
                                skin.id,
                              ),
                              child: Text(
                                _ownedChessPieceSkinIds.contains(skin.id)
                                    ? skin.label
                                    : '${skin.label} (Locked)',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedPlayerPieceSkinId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          _controller.startNewGame(
                            playerAsWhite: _playerAsWhite,
                            cooldownDuration: Duration(
                              seconds: _selectedCooldownSeconds,
                            ),
                          );
                        },
                        icon: const AppAssetIcon(
                          AppAssets.newGameIcon,
                          fallbackIcon: Icons.refresh,
                          size: 18,
                        ),
                        label: const Text('New Game'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const horizontalBarHeight = 58.0;
                      const verticalBarWidth = 64.0;
                      const boardGap = 10.0;

                      Widget buildBoardStack(double boardSize) {
                        return SizedBox(
                          width: boardSize,
                          height: boardSize,
                          child: Stack(
                            children: [
                              ChessBoardView(
                                pieces: _controller.boardPieces,
                                playerColor: _controller.playerColor,
                                boardAssetPath: boardSkin.assetPath,
                                playableInsetRatio:
                                    boardSkin.playableInsetRatio,
                                playableSizeRatio: boardSkin.playableSizeRatio,
                                whitePieceSprites: whitePieceSkin.spriteMap,
                                blackPieceSprites: blackPieceSkin.spriteMap,
                                selectedSquare: _controller.selectedSquare,
                                legalTargets: _controller.legalTargets,
                                lastMoveFrom: _controller.playerLastMoveFrom,
                                lastMoveTo: _controller.playerLastMoveTo,
                                secondaryMoveFrom: _controller.aiLastMoveFrom,
                                secondaryMoveTo: _controller.aiLastMoveTo,
                                queuedMoveFrom: _controller.queuedMoveFrom,
                                queuedMoveTo: _controller.queuedMoveTo,
                                onSquareTap: _controller.tapSquare,
                              ),
                              if (_controller.isGameOver)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    child: Center(
                                      child: FilledButton.icon(
                                        onPressed: () {
                                          _controller.startNewGame(
                                            playerAsWhite: _playerAsWhite,
                                            cooldownDuration: Duration(
                                              seconds: _selectedCooldownSeconds,
                                            ),
                                          );
                                        },
                                        icon: const AppAssetIcon(
                                          AppAssets.newGameIcon,
                                          fallbackIcon: Icons.refresh,
                                          size: 18,
                                        ),
                                        label: const Text('New Game'),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }

                      if (_timeBarOrientation == TimeBarOrientation.vertical) {
                        final boardSize = math.min(
                          constraints.maxHeight,
                          constraints.maxWidth -
                              (verticalBarWidth * 2) -
                              (boardGap * 2),
                        );
                        if (boardSize <= 0) {
                          return const SizedBox.shrink();
                        }

                        return SizedBox(
                          width:
                              boardSize +
                              (verticalBarWidth * 2) +
                              (boardGap * 2),
                          height: boardSize,
                          child: Row(
                            children: [
                              SizedBox(
                                width: verticalBarWidth,
                                child: CooldownMeter(
                                  label: topColor == 'w' ? 'W' : 'B',
                                  remaining: topRemaining,
                                  total: _controller.cooldownDuration,
                                  horizontalPrimaryAssetPath:
                                      AppAssets.horizontalTimeBarAccent,
                                  horizontalFallbackAssetPath:
                                      AppAssets.horizontalTimeBar,
                                  verticalPrimaryAssetPath:
                                      AppAssets.verticalTimeBarAccent,
                                  verticalFallbackAssetPath:
                                      AppAssets.verticalTimeBar,
                                  orientation: TimeBarOrientation.vertical,
                                  activeColor: topActiveColor,
                                  isPlayerSide: topIsPlayer,
                                  timeLabel: _formatDuration(topRemaining),
                                  readyToFlash:
                                      !_controller.isGameOver &&
                                      _controller.turnColor == topColor &&
                                      topRemaining.inMilliseconds == 0,
                                  flashTint: topFlashTint,
                                  flashDuration: const Duration(
                                    milliseconds: 700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: boardGap),
                              buildBoardStack(boardSize),
                              const SizedBox(width: boardGap),
                              SizedBox(
                                width: verticalBarWidth,
                                child: CooldownMeter(
                                  label: bottomColor == 'w' ? 'W' : 'B',
                                  remaining: bottomRemaining,
                                  total: _controller.cooldownDuration,
                                  horizontalPrimaryAssetPath:
                                      AppAssets.horizontalTimeBarAccent,
                                  horizontalFallbackAssetPath:
                                      AppAssets.horizontalTimeBar,
                                  verticalPrimaryAssetPath:
                                      AppAssets.verticalTimeBarAccent,
                                  verticalFallbackAssetPath:
                                      AppAssets.verticalTimeBar,
                                  orientation: TimeBarOrientation.vertical,
                                  activeColor: bottomActiveColor,
                                  isPlayerSide: bottomIsPlayer,
                                  timeLabel: _formatDuration(bottomRemaining),
                                  readyToFlash:
                                      !_controller.isGameOver &&
                                      _controller.turnColor == bottomColor &&
                                      bottomRemaining.inMilliseconds == 0,
                                  flashTint: bottomFlashTint,
                                  flashDuration: const Duration(
                                    milliseconds: 700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final boardSize = math.min(
                        constraints.maxWidth,
                        constraints.maxHeight -
                            (horizontalBarHeight * 2) -
                            (boardGap * 2),
                      );
                      if (boardSize <= 0) {
                        return const SizedBox.shrink();
                      }

                      return SizedBox(
                        width: boardSize,
                        height:
                            boardSize +
                            (horizontalBarHeight * 2) +
                            (boardGap * 2),
                        child: Column(
                          children: [
                            SizedBox(
                              height: horizontalBarHeight,
                              child: CooldownMeter(
                                label: topColor == 'w' ? 'W' : 'B',
                                remaining: topRemaining,
                                total: _controller.cooldownDuration,
                                horizontalPrimaryAssetPath:
                                    AppAssets.horizontalTimeBarAccent,
                                horizontalFallbackAssetPath:
                                    AppAssets.horizontalTimeBar,
                                verticalPrimaryAssetPath:
                                    AppAssets.verticalTimeBarAccent,
                                verticalFallbackAssetPath:
                                    AppAssets.verticalTimeBar,
                                orientation: TimeBarOrientation.horizontal,
                                activeColor: topActiveColor,
                                isPlayerSide: topIsPlayer,
                                timeLabel: _formatDuration(topRemaining),
                                readyToFlash:
                                    !_controller.isGameOver &&
                                    _controller.turnColor == topColor &&
                                    topRemaining.inMilliseconds == 0,
                                flashTint: topFlashTint,
                                flashDuration: const Duration(
                                  milliseconds: 700,
                                ),
                              ),
                            ),
                            const SizedBox(height: boardGap),
                            buildBoardStack(boardSize),
                            const SizedBox(height: boardGap),
                            SizedBox(
                              height: horizontalBarHeight,
                              child: CooldownMeter(
                                label: bottomColor == 'w' ? 'W' : 'B',
                                remaining: bottomRemaining,
                                total: _controller.cooldownDuration,
                                horizontalPrimaryAssetPath:
                                    AppAssets.horizontalTimeBarAccent,
                                horizontalFallbackAssetPath:
                                    AppAssets.horizontalTimeBar,
                                verticalPrimaryAssetPath:
                                    AppAssets.verticalTimeBarAccent,
                                verticalFallbackAssetPath:
                                    AppAssets.verticalTimeBar,
                                orientation: TimeBarOrientation.horizontal,
                                activeColor: bottomActiveColor,
                                isPlayerSide: bottomIsPlayer,
                                timeLabel: _formatDuration(bottomRemaining),
                                readyToFlash:
                                    !_controller.isGameOver &&
                                    _controller.turnColor == bottomColor &&
                                    bottomRemaining.inMilliseconds == 0,
                                flashTint: bottomFlashTint,
                                flashDuration: const Duration(
                                  milliseconds: 700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status:',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_controller.statusText)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                color: const Color(0xFFFFF2F2),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Note:',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _controller.feedback ?? '-',
                          style: const TextStyle(color: Color(0xFF8B2323)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Log:',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tailHistory.isEmpty ? '-' : tailHistory.join('  '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) {
      return '0.0s';
    }
    final halfSteps = (ms / 500).ceil();
    final halfSecondValue = halfSteps / 2;
    return '${halfSecondValue.toStringAsFixed(1)}s';
  }

  List<DropdownMenuItem<String>> _chessBoardDropdownItems() {
    final board = SkinCatalog.chessBoardPearl;
    return <DropdownMenuItem<String>>[
      DropdownMenuItem<String>(value: board.id, child: Text(board.label)),
    ];
  }
}
