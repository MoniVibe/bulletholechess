import 'package:bulletholechess/src/game/ui/app_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('piece sprite mapping covers all FEN piece symbols', () {
    const expectedFenSymbols = <String>{
      'P',
      'R',
      'N',
      'B',
      'Q',
      'K',
      'p',
      'r',
      'n',
      'b',
      'q',
      'k',
    };

    expect(AppAssets.pieceSprites.keys.toSet(), expectedFenSymbols);
  });

  test('piece sprites use generated transparent assets', () {
    for (final spritePath in AppAssets.pieceSprites.values) {
      expect(spritePath.startsWith('assets/generated/pieces/'), isTrue);
      expect(spritePath.endsWith('.png'), isTrue);
    }
  });
}
