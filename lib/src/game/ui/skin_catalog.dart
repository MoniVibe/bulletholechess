import 'package:flutter/material.dart';

import 'app_assets.dart';

enum PieceSkinRenderMode { image, flat }

/// Backgammon board style option.
@immutable
class BoardSkinOption {
  const BoardSkinOption({
    required this.id,
    required this.label,
    this.assetPath,
    this.tintOverlay,
    this.isPremium = false,
  });

  final String id;
  final String label;
  final String? assetPath;
  final Color? tintOverlay;
  final bool isPremium;
}

/// Backgammon checker style option.
@immutable
class PieceSkinOption {
  const PieceSkinOption({
    required this.id,
    required this.label,
    required this.mode,
    this.whiteAssetPath,
    this.blackAssetPath,
    this.tintColor,
    this.isPremium = false,
  });

  final String id;
  final String label;
  final PieceSkinRenderMode mode;
  final String? whiteAssetPath;
  final String? blackAssetPath;
  final Color? tintColor;
  final bool isPremium;

  String? assetForColor(String color) {
    return color == 'w' ? whiteAssetPath : blackAssetPath;
  }
}

/// Chess board style option.
@immutable
class ChessBoardSkinOption {
  const ChessBoardSkinOption({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.playableInsetRatio,
    required this.playableSizeRatio,
    this.isPremium = false,
  });

  final String id;
  final String label;
  final String assetPath;
  final double playableInsetRatio;
  final double playableSizeRatio;
  final bool isPremium;
}

/// Chess piece style option (maps FEN symbols to sprites).
@immutable
class ChessPieceSkinOption {
  const ChessPieceSkinOption({
    required this.id,
    required this.label,
    required this.spriteMap,
    this.tintColor,
    this.isPremium = false,
  });

  final String id;
  final String label;
  final Map<String, String> spriteMap;
  final Color? tintColor;
  final bool isPremium;
}

class SkinCatalog {
  // Chess skins
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
    spriteMap: AppAssets.pieceSprites,
  );

  static const ChessPieceSkinOption chessPiecesNeon = ChessPieceSkinOption(
    id: 'chess_neon',
    label: 'Neon Glow',
    spriteMap: AppAssets.pieceSprites,
    tintColor: Color(0xFF00E5FF),
  );

  static const ChessPieceSkinOption chessPiecesBronze = ChessPieceSkinOption(
    id: 'chess_bronze',
    label: 'Bronze Tone',
    spriteMap: AppAssets.pieceSprites,
    tintColor: Color(0xFFE6A23C),
    isPremium: true,
  );

  static const List<ChessPieceSkinOption> chessPieceSkins =
      <ChessPieceSkinOption>[
        chessPiecesClassic,
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

  // Backgammon skins
  static const BoardSkinOption backgammonBoardClassic = BoardSkinOption(
    id: 'bg_classic',
    label: 'Backgammon Classic',
    assetPath: AppAssets.backgammonBoardClassic,
    tintOverlay: Color(0x12000000),
  );

  static const BoardSkinOption backgammonBoardPainted = BoardSkinOption(
    id: 'bg_painted',
    label: 'Modern Painted',
    assetPath: null,
    isPremium: true,
  );

  static const List<BoardSkinOption> backgammonBoardSkins = <BoardSkinOption>[
    backgammonBoardClassic,
    backgammonBoardPainted,
  ];

  static const PieceSkinOption backgammonPiecesRoyal = PieceSkinOption(
    id: 'bg_royal',
    label: 'Royal Coins',
    mode: PieceSkinRenderMode.image,
    whiteAssetPath: AppAssets.whiteCoin,
    blackAssetPath: AppAssets.blackCoin,
  );

  static const PieceSkinOption backgammonPiecesRuby = PieceSkinOption(
    id: 'bg_ruby',
    label: 'Ruby Coins',
    mode: PieceSkinRenderMode.image,
    whiteAssetPath: AppAssets.redCoin,
    blackAssetPath: AppAssets.blackCoin,
  );

  static const PieceSkinOption backgammonPiecesNeon = PieceSkinOption(
    id: 'bg_neon',
    label: 'Neon Coins',
    mode: PieceSkinRenderMode.image,
    whiteAssetPath: AppAssets.whiteCoin,
    blackAssetPath: AppAssets.blackCoin,
    tintColor: Color(0xFF00E5FF),
    isPremium: true,
  );

  static const PieceSkinOption backgammonPiecesMinimal = PieceSkinOption(
    id: 'bg_minimal',
    label: 'Minimal Chips',
    mode: PieceSkinRenderMode.flat,
  );

  static const List<PieceSkinOption> backgammonPieceSkins = <PieceSkinOption>[
    backgammonPiecesRuby,
    backgammonPiecesRoyal,
    backgammonPiecesNeon,
    backgammonPiecesMinimal,
  ];

  static String get defaultBackgammonBoardSkinId => backgammonBoardPainted.id;
  static String get defaultBackgammonPieceSkinId => backgammonPiecesRoyal.id;

  static BoardSkinOption backgammonBoardById(String id) {
    return backgammonBoardSkins.firstWhere(
      (skin) => skin.id == id,
      orElse: () => backgammonBoardClassic,
    );
  }

  static PieceSkinOption backgammonPieceById(String id) {
    return backgammonPieceSkins.firstWhere(
      (skin) => skin.id == id,
      orElse: () => backgammonPiecesRoyal,
    );
  }
}
