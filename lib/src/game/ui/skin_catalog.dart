import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import 'app_assets.dart';

export 'package:bullethole_shared/bullethole_shared.dart'
    show ChessBoardSkinOption, ChessPieceSkinOption;

/// Chess-only skin catalog.
class SkinCatalog {
  static const ChessBoardSkinOption chessBoardSashite = ChessBoardSkinOption(
    id: 'chess_sashite',
    label: 'Sashite Classic (CC0)',
    assetPath: AppAssets.chessBoardSashite,
    playableInsetRatio: AppAssets.chessBoardFullInsetRatio,
    playableSizeRatio: AppAssets.chessBoardFullSizeRatio,
  );

  static const ChessBoardSkinOption chessBoardPearl = ChessBoardSkinOption(
    id: 'chess_pearl',
    label: 'Pearl Board',
    assetPath: AppAssets.chessBoardClassic,
    playableInsetRatio: AppAssets.chessBoardPlayableInsetRatio,
    playableSizeRatio: AppAssets.chessBoardPlayableSizeRatio,
  );

  static const List<ChessBoardSkinOption> chessBoardSkins =
      <ChessBoardSkinOption>[chessBoardSashite, chessBoardPearl];

  static const ChessPieceSkinOption chessPiecesSashite = ChessPieceSkinOption(
    id: 'chess_sashite_western',
    label: 'Sashite Western (CC0)',
    spriteMap: AppAssets.sashitePieceSprites,
    pieceScale: 1.26,
    pieceYOffset: 0,
  );

  static const ChessPieceSkinOption chessPiecesClassic = ChessPieceSkinOption(
    id: 'chess_classic',
    label: 'Classic Pieces',
    spriteMap: AppAssets.classicPieceSprites,
    pieceScale: 1.26,
    pieceYOffset: -0.04,
  );

  static const ChessPieceSkinOption chessPiecesRed = ChessPieceSkinOption(
    id: 'chess_red_pieces',
    label: 'Ruby Pieces',
    spriteMap: AppAssets.redPieceSprites,
    pieceScale: 1.26,
    pieceYOffset: -0.04,
  );

  static const ChessPieceSkinOption chessPiecesNeon = ChessPieceSkinOption(
    id: 'chess_neon',
    label: 'Neon Glow',
    spriteMap: AppAssets.classicPieceSprites,
    pieceScale: 1.26,
    pieceYOffset: -0.04,
    tintColor: Color(0xFF00E5FF),
    isPremium: true,
  );

  static const ChessPieceSkinOption chessPiecesBronze = ChessPieceSkinOption(
    id: 'chess_bronze',
    label: 'Bronze Tone',
    spriteMap: AppAssets.classicPieceSprites,
    pieceScale: 1.26,
    pieceYOffset: -0.04,
    tintColor: Color(0xFFE6A23C),
    isPremium: true,
  );

  static const List<ChessPieceSkinOption> chessPieceSkins =
      <ChessPieceSkinOption>[
        chessPiecesSashite,
        chessPiecesClassic,
        chessPiecesRed,
        chessPiecesNeon,
        chessPiecesBronze,
      ];

  static String get defaultChessBoardSkinId => chessBoardSashite.id;
  static String get defaultChessPieceSkinId => chessPiecesClassic.id;

  static ChessBoardSkinOption chessBoardById(String id) {
    return chessBoardSkins.firstWhere(
      (skin) => skin.id == id,
      orElse: () => chessBoardSashite,
    );
  }

  static ChessPieceSkinOption chessPieceById(String id) {
    return chessPieceSkins.firstWhere(
      (skin) => skin.id == id,
      orElse: () => chessPiecesClassic,
    );
  }
}
