/// Centralized asset registry for the visual layer.
///
/// Reasoning:
/// - Keeps asset paths in one place to avoid hard-coded strings across widgets.
/// - Makes it easy to swap art drops without touching game logic.
class AppAssets {
  static const double boardPlayableInsetRatio = 120 / 1024;
  static const double boardPlayableSizeRatio = 784 / 1024;

  static const String appBackground = 'assets/generated/ui/background.png';
  static const String boardFrame = 'assets/generated/ui/board.png';
  static const String horizontalTimeBar =
      'assets/generated/ui/time_bar_horizontal.png';
  static const String verticalTimeBar =
      'assets/generated/ui/time_bar_vertical.png';

  static const String settingsIcon = 'assets/Settings.png';
  static const String newGameIcon = 'assets/Newgame.png';
  static const String rematchIcon = 'assets/rematch.png';
  static const String feedbackIcon = 'assets/feedback.png';

  /// FEN piece symbol to sprite path mapping.
  static const Map<String, String> pieceSprites = <String, String>{
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

  static String? pieceSpriteFor(String fenPiece) => pieceSprites[fenPiece];
}
