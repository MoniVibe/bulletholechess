/// Centralized asset registry for the visual layer.
///
/// Reasoning:
/// - Keeps asset paths in one place to avoid hard-coded strings across widgets.
/// - Makes it easy to swap art drops without touching game logic.
class AppAssets {
  static const double chessBoardPlayableInsetRatio = 120 / 1024;
  static const double chessBoardPlayableSizeRatio = 784 / 1024;

  static const String appBackground = 'assets/generated/ui/background.png';
  static const String chessBoardClassic = 'assets/generated/ui/board.png';
  static const String chessBoardRed = 'assets/Boardalt.png.png';
  static const String backgammonBoardClassic =
      'assets/generated/sheshbesh/backgammon_board_classic.png';
  static const String horizontalTimeBar =
      'assets/generated/ui/time_bar_horizontal.png';
  static const String verticalTimeBar =
      'assets/generated/ui/time_bar_vertical.png';

  static const String settingsIcon = 'assets/Settings.png';
  static const String newGameIcon = 'assets/Newgame.png';
  static const String rematchIcon = 'assets/rematch.png';
  static const String feedbackIcon = 'assets/feedback.png';
  static const String whiteCoin = 'assets/generated/sheshbesh/white_coin.png';
  static const String blackCoin = 'assets/generated/sheshbesh/black_coin.png';
  static const String redCoin = 'assets/generated/sheshbesh/red_coin.png';

  static const Map<int, String> diceFaces = <int, String>{
    1: 'assets/generated/sheshbesh/dice_1.png',
    2: 'assets/generated/sheshbesh/dice_2.png',
    3: 'assets/generated/sheshbesh/dice_3.png',
    4: 'assets/generated/sheshbesh/dice_4.png',
    5: 'assets/generated/sheshbesh/dice_5.png',
    6: 'assets/generated/sheshbesh/dice_6.png',
  };

  /// FEN piece symbol to sprite path mapping.
  static const Map<String, String> pieceSprites = <String, String>{
    // White side uses red variants for better contrast in the new visual pack.
    'P': 'assets/generated/pieces/rP.png',
    'R': 'assets/generated/pieces/rR.png',
    'N': 'assets/generated/pieces/rN.png',
    'B': 'assets/generated/pieces/rB.png',
    'Q': 'assets/generated/pieces/rQ.png',
    'K': 'assets/generated/pieces/rK.png',
    'p': 'assets/generated/pieces/bP.png',
    'r': 'assets/generated/pieces/bR.png',
    'n': 'assets/generated/pieces/bN.png',
    'b': 'assets/generated/pieces/bB.png',
    'q': 'assets/generated/pieces/bQ.png',
    'k': 'assets/generated/pieces/bK.png',
  };

  // Backward compatibility aliases while migrating call sites.
  static const double boardPlayableInsetRatio = chessBoardPlayableInsetRatio;
  static const double boardPlayableSizeRatio = chessBoardPlayableSizeRatio;
  static const String boardFrame = chessBoardClassic;
  static const String sheshbeshBoardAlt = chessBoardRed;
  static const String sheshbeshBoardClassic = backgammonBoardClassic;

  static String? pieceSpriteFor(String fenPiece) => pieceSprites[fenPiece];

  static String? diceFaceAsset(int face) => diceFaces[face];
}
