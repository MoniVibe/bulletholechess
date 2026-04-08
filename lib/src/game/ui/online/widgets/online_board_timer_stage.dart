import 'dart:math' as math;

import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import '../../app_assets.dart';
import '../../chess_board_view.dart';

class OnlineBoardTimerStage extends StatelessWidget {
  const OnlineBoardTimerStage({
    required this.pieces,
    required this.playerColor,
    required this.boardAssetPath,
    required this.playableInsetRatio,
    required this.playableSizeRatio,
    required this.whitePieceSprites,
    required this.blackPieceSprites,
    required this.whitePieceScale,
    required this.blackPieceScale,
    required this.whitePieceYOffset,
    required this.blackPieceYOffset,
    required this.invertBlackPieceColors,
    required this.selectedSquare,
    required this.legalTargets,
    required this.playerLastMoveFrom,
    required this.playerLastMoveTo,
    required this.opponentLastMoveFrom,
    required this.opponentLastMoveTo,
    required this.queuedMoveFrom,
    required this.queuedMoveTo,
    required this.checkedKingSquares,
    required this.isOnlineCheckmate,
    required this.boardMessage,
    required this.onSquareTap,
    required this.isConnected,
    required this.isWaitingForOpponent,
    required this.isMatchActive,
    required this.isGameOver,
    required this.canStart,
    required this.onFindMatch,
    required this.showMatchFoundOverlay,
    required this.matchFoundOverlay,
    required this.victoryOverlay,
    required this.timeBarOrientation,
    required this.topColor,
    required this.bottomColor,
    required this.topRemaining,
    required this.bottomRemaining,
    required this.cooldownDuration,
    required this.timerHasStarted,
    required this.topIsActiveWindow,
    required this.bottomIsActiveWindow,
    required this.topIsPlayer,
    required this.bottomIsPlayer,
    super.key,
  });

  final Map<String, String> pieces;
  final String playerColor;
  final String boardAssetPath;
  final double playableInsetRatio;
  final double playableSizeRatio;
  final Map<String, String> whitePieceSprites;
  final Map<String, String> blackPieceSprites;
  final double whitePieceScale;
  final double blackPieceScale;
  final double whitePieceYOffset;
  final double blackPieceYOffset;
  final bool invertBlackPieceColors;
  final String? selectedSquare;
  final Set<String> legalTargets;
  final String? playerLastMoveFrom;
  final String? playerLastMoveTo;
  final String? opponentLastMoveFrom;
  final String? opponentLastMoveTo;
  final String? queuedMoveFrom;
  final String? queuedMoveTo;
  final Set<String> checkedKingSquares;
  final bool isOnlineCheckmate;
  final String? boardMessage;
  final ValueChanged<String> onSquareTap;

  final bool isConnected;
  final bool isWaitingForOpponent;
  final bool isMatchActive;
  final bool isGameOver;
  final bool canStart;
  final VoidCallback onFindMatch;
  final bool showMatchFoundOverlay;
  final Widget matchFoundOverlay;
  final Widget victoryOverlay;

  final TimeBarOrientation timeBarOrientation;
  final String topColor;
  final String bottomColor;
  final Duration topRemaining;
  final Duration bottomRemaining;
  final Duration cooldownDuration;
  final bool timerHasStarted;
  final bool topIsActiveWindow;
  final bool bottomIsActiveWindow;
  final bool topIsPlayer;
  final bool bottomIsPlayer;

  @override
  Widget build(BuildContext context) {
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

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const baseHorizontalBarHeight = 58.0;
          const baseVerticalBarWidth = 64.0;
          const boardGap = 10.0;
          final showTimeBars = isMatchActive;
          final horizontalBarHeight = showTimeBars
              ? baseHorizontalBarHeight
              : 0.0;
          final verticalBarWidth = showTimeBars ? baseVerticalBarWidth : 0.0;
          final edgeGap = showTimeBars ? boardGap : 0.0;

          Widget buildBoardStack(double boardSize) {
            return SizedBox(
              width: boardSize,
              height: boardSize,
              child: Stack(
                children: [
                  ChessBoardView(
                    pieces: pieces,
                    playerColor: playerColor,
                    boardAssetPath: boardAssetPath,
                    playableInsetRatio: playableInsetRatio,
                    playableSizeRatio: playableSizeRatio,
                    whitePieceSprites: whitePieceSprites,
                    blackPieceSprites: blackPieceSprites,
                    whitePieceScale: whitePieceScale,
                    blackPieceScale: blackPieceScale,
                    whitePieceYOffset: whitePieceYOffset,
                    blackPieceYOffset: blackPieceYOffset,
                    invertBlackPieceColors: invertBlackPieceColors,
                    selectedSquare: selectedSquare,
                    legalTargets: legalTargets,
                    lastMoveFrom: playerLastMoveFrom,
                    lastMoveTo: playerLastMoveTo,
                    lastMoveHighlightColor: const Color(0xFFD7CA64),
                    secondaryMoveFrom: opponentLastMoveFrom,
                    secondaryMoveTo: opponentLastMoveTo,
                    secondaryMoveHighlightColor: const Color(0xFFE57373),
                    queuedMoveFrom: queuedMoveFrom,
                    queuedMoveTo: queuedMoveTo,
                    checkedKingSquares: checkedKingSquares,
                    isCheckmate: isOnlineCheckmate,
                    boardMessage: boardMessage,
                    onSquareTap: onSquareTap,
                  ),
                  if (!isConnected)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                        child: Center(
                          child: FilledButton.icon(
                            key: const ValueKey<String>(
                              'chess_online_find_match_overlay',
                            ),
                            onPressed: canStart ? onFindMatch : null,
                            icon: const AppAssetIcon(
                              AppAssets.newGameIcon,
                              fallbackIcon: Icons.groups_2_outlined,
                              size: 20,
                            ),
                            label: const Text('Find Match'),
                          ),
                        ),
                      ),
                    )
                  else if (isWaitingForOpponent)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text(
                                'Waiting for opponent...',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (showMatchFoundOverlay &&
                      isMatchActive &&
                      !isGameOver)
                    Positioned.fill(child: matchFoundOverlay)
                  else if (isGameOver)
                    Positioned.fill(child: victoryOverlay),
                ],
              ),
            );
          }

          if (timeBarOrientation == TimeBarOrientation.vertical) {
            final boardSize = math.min(
              constraints.maxHeight,
              constraints.maxWidth - (verticalBarWidth * 2) - (edgeGap * 2),
            );
            if (boardSize <= 0) {
              return const SizedBox.shrink();
            }

            return SizedBox(
              width: boardSize + (verticalBarWidth * 2) + (edgeGap * 2),
              height: boardSize,
              child: Row(
                children: [
                  if (showTimeBars)
                    SizedBox(
                      width: verticalBarWidth,
                      child: CooldownMeter(
                        label: topColor == 'w' ? 'W' : 'B',
                        remaining: topRemaining,
                        total: cooldownDuration,
                        horizontalPrimaryAssetPath:
                            AppAssets.horizontalTimeBarAccent,
                        horizontalFallbackAssetPath:
                            AppAssets.horizontalTimeBar,
                        verticalPrimaryAssetPath:
                            AppAssets.verticalTimeBarAccent,
                        verticalFallbackAssetPath: AppAssets.verticalTimeBar,
                        orientation: TimeBarOrientation.vertical,
                        activeColor: topActiveColor,
                        isPlayerSide: topIsPlayer,
                        timeLabel: formatDuration(topRemaining),
                        readyToFlash:
                            isConnected &&
                            showTimeBars &&
                            timerHasStarted &&
                            topIsActiveWindow &&
                            !isGameOver &&
                            topRemaining.inMilliseconds == 0,
                        flashTint: topFlashTint,
                        flashDuration: const Duration(milliseconds: 700),
                      ),
                    ),
                  if (edgeGap > 0) SizedBox(width: edgeGap),
                  buildBoardStack(boardSize),
                  if (edgeGap > 0) SizedBox(width: edgeGap),
                  if (showTimeBars)
                    SizedBox(
                      width: verticalBarWidth,
                      child: CooldownMeter(
                        label: bottomColor == 'w' ? 'W' : 'B',
                        remaining: bottomRemaining,
                        total: cooldownDuration,
                        horizontalPrimaryAssetPath:
                            AppAssets.horizontalTimeBarAccent,
                        horizontalFallbackAssetPath:
                            AppAssets.horizontalTimeBar,
                        verticalPrimaryAssetPath:
                            AppAssets.verticalTimeBarAccent,
                        verticalFallbackAssetPath: AppAssets.verticalTimeBar,
                        orientation: TimeBarOrientation.vertical,
                        activeColor: bottomActiveColor,
                        isPlayerSide: bottomIsPlayer,
                        timeLabel: formatDuration(bottomRemaining),
                        readyToFlash:
                            isConnected &&
                            showTimeBars &&
                            timerHasStarted &&
                            bottomIsActiveWindow &&
                            !isGameOver &&
                            bottomRemaining.inMilliseconds == 0,
                        flashTint: bottomFlashTint,
                        flashDuration: const Duration(milliseconds: 700),
                      ),
                    ),
                ],
              ),
            );
          }

          final boardSize = math.min(
            constraints.maxWidth,
            constraints.maxHeight - (horizontalBarHeight * 2) - (edgeGap * 2),
          );
          if (boardSize <= 0) {
            return const SizedBox.shrink();
          }

          return SizedBox(
            width: boardSize,
            height: boardSize + (horizontalBarHeight * 2) + (edgeGap * 2),
            child: Column(
              children: [
                if (showTimeBars)
                  SizedBox(
                    height: horizontalBarHeight,
                    child: CooldownMeter(
                      label: topColor == 'w' ? 'W' : 'B',
                      remaining: topRemaining,
                      total: cooldownDuration,
                      horizontalPrimaryAssetPath:
                          AppAssets.horizontalTimeBarAccent,
                      horizontalFallbackAssetPath: AppAssets.horizontalTimeBar,
                      verticalPrimaryAssetPath: AppAssets.verticalTimeBarAccent,
                      verticalFallbackAssetPath: AppAssets.verticalTimeBar,
                      orientation: TimeBarOrientation.horizontal,
                      activeColor: topActiveColor,
                      isPlayerSide: topIsPlayer,
                      timeLabel: formatDuration(topRemaining),
                      readyToFlash:
                          isConnected &&
                          showTimeBars &&
                          timerHasStarted &&
                          topIsActiveWindow &&
                          !isGameOver &&
                          topRemaining.inMilliseconds == 0,
                      flashTint: topFlashTint,
                      flashDuration: const Duration(milliseconds: 700),
                    ),
                  ),
                if (edgeGap > 0) SizedBox(height: edgeGap),
                buildBoardStack(boardSize),
                if (edgeGap > 0) SizedBox(height: edgeGap),
                if (showTimeBars)
                  SizedBox(
                    height: horizontalBarHeight,
                    child: CooldownMeter(
                      label: bottomColor == 'w' ? 'W' : 'B',
                      remaining: bottomRemaining,
                      total: cooldownDuration,
                      horizontalPrimaryAssetPath:
                          AppAssets.horizontalTimeBarAccent,
                      horizontalFallbackAssetPath: AppAssets.horizontalTimeBar,
                      verticalPrimaryAssetPath: AppAssets.verticalTimeBarAccent,
                      verticalFallbackAssetPath: AppAssets.verticalTimeBar,
                      orientation: TimeBarOrientation.horizontal,
                      activeColor: bottomActiveColor,
                      isPlayerSide: bottomIsPlayer,
                      timeLabel: formatDuration(bottomRemaining),
                      readyToFlash:
                          isConnected &&
                          showTimeBars &&
                          timerHasStarted &&
                          bottomIsActiveWindow &&
                          !isGameOver &&
                          bottomRemaining.inMilliseconds == 0,
                      flashTint: bottomFlashTint,
                      flashDuration: const Duration(milliseconds: 700),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String formatDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) {
      return '0.0s';
    }
    final halfSteps = (ms / 500).ceil();
    final halfSecondValue = halfSteps / 2;
    return '${halfSecondValue.toStringAsFixed(1)}s';
  }
}
