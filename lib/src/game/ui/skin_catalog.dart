import 'package:bullethole_shared/bullethole_shared.dart';
import 'package:flutter/material.dart';

import 'app_assets.dart';

export 'package:bullethole_shared/bullethole_shared.dart'
    show ChessBoardSkinOption, ChessPieceSkinOption;

/// Chess-only skin catalog.
class SkinCatalog {
  static const ChessBoardSkinOption chessBoardPearl = ChessBoardSkinOption(
    id: 'chess_pearl',
    label: 'Pearl Board',
    assetPath: AppAssets.chessBoardClassic,
    playableInsetRatio: AppAssets.chessBoardPlayableInsetRatio,
    playableSizeRatio: AppAssets.chessBoardPlayableSizeRatio,
  );

  static const ChessBoardSkinOption chessBoardRed = ChessBoardSkinOption(
    id: 'chess_red',
    label: 'Red Board',
    assetPath: AppAssets.chessBoardRed,
    playableInsetRatio: AppAssets.chessBoardPlayableInsetRatio,
    playableSizeRatio: AppAssets.chessBoardPlayableSizeRatio,
  );

  static const List<ChessBoardSkinOption> chessBoardSkins =
      <ChessBoardSkinOption>[chessBoardPearl, chessBoardRed];

  static const ChessPieceSkinOption chessPiecesClassic = ChessPieceSkinOption(
    id: 'chess_classic',
    label: 'Classic Pieces',
    spriteMap: AppAssets.classicPieceSprites,
  );

  static const ChessPieceSkinOption chessPiecesRed = ChessPieceSkinOption(
    id: 'chess_red_pieces',
    label: 'Ruby Pieces',
    spriteMap: AppAssets.redPieceSprites,
  );

  static const ChessPieceSkinOption chessPiecesNeon = ChessPieceSkinOption(
    id: 'chess_neon',
    label: 'Neon Glow',
    spriteMap: AppAssets.classicPieceSprites,
    tintColor: Color(0xFF00E5FF),
    isPremium: true,
  );

  static const ChessPieceSkinOption chessPiecesBronze = ChessPieceSkinOption(
    id: 'chess_bronze',
    label: 'Bronze Tone',
    spriteMap: AppAssets.classicPieceSprites,
    tintColor: Color(0xFFE6A23C),
    isPremium: true,
  );

  static const List<ChessPieceSkinOption> chessPieceSkins =
      <ChessPieceSkinOption>[
        chessPiecesClassic,
        chessPiecesRed,
        chessPiecesNeon,
        chessPiecesBronze,
      ];

  static String get defaultChessBoardSkinId => chessBoardPearl.id;
  static String get defaultChessPieceSkinId => chessPiecesClassic.id;

  static ChessBoardSkinOption chessBoardById(String id) {
    return chessBoardSkins.firstWhere(
      (skin) => skin.id == id,
      orElse: () => chessBoardPearl,
    );
  }

  static ChessPieceSkinOption chessPieceById(String id) {
    return chessPieceSkins.firstWhere(
      (skin) => skin.id == id,
      orElse: () => chessPiecesClassic,
    );
  }
}
