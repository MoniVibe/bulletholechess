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
  static const String horizontalTimeBar =
      'assets/generated/ui/time_bar_horizontal.png';
  static const String verticalTimeBar =
      'assets/generated/ui/time_bar_vertical.png';
  static const String horizontalTimeBarAccent =
      'assets/generated/ui/time_bar_horizontal_red.png';
  static const String verticalTimeBarAccent =
      'assets/generated/ui/time_bar_vertical_gold.png';

  static const String settingsIcon = 'assets/Settings.png';
  static const String newGameIcon = 'assets/Newgame.png';
  static const String rematchIcon = 'assets/rematch.png';
  static const String feedbackIcon = 'assets/feedback.png';

  /// Default chess piece mapping (white + black).
  static const Map<String, String> classicPieceSprites = <String, String>{
    'P': 'assets/generated/pieces/wP.png',
    'R': 'assets/generated/pieces/wR.png',
    'N': 'assets/generated/pieces/wN.png',
    'B': 'assets/generated/pieces/wB.png',
    'Q': 'assets/generated/pieces/wQ.png',
    'K': 'assets/generated/pieces/wK.png',
    'p': 'assets/generated/pieces/bP.png',
    'r': 'assets/generated/pieces/bR.png',
    'n': 'assets/generated/pieces/bN.png',
    'b': 'assets/generated/pieces/bB.png',
    'q': 'assets/generated/pieces/bQ.png',
    'k': 'assets/generated/pieces/bK.png',
  };

  /// Alternate red skin mapping used as an optional player skin.
  static const Map<String, String> redPieceSprites = <String, String>{
    'P': 'assets/generated/pieces/rP.png',
    'R': 'assets/generated/pieces/rR.png',
    'N': 'assets/generated/pieces/rN.png',
    'B': 'assets/generated/pieces/rB.png',
    'Q': 'assets/generated/pieces/rQ.png',
    'K': 'assets/generated/pieces/rK.png',
    'p': 'assets/generated/pieces/rP.png',
    'r': 'assets/generated/pieces/rR.png',
    'n': 'assets/generated/pieces/rN.png',
    'b': 'assets/generated/pieces/rB.png',
    'q': 'assets/generated/pieces/rQ.png',
    'k': 'assets/generated/pieces/rK.png',
  };

  /// Backward-compatible alias for default board rendering.
  static const Map<String, String> pieceSprites = classicPieceSprites;

  static String? pieceSpriteFor(String fenPiece) => pieceSprites[fenPiece];
}
