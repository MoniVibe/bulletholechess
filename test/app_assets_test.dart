import 'package:bulletholechess/src/game/ui/app_assets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('default piece sprites keep standard white/black contrast', () {
    expect(AppAssets.pieceSprites['P'], 'assets/generated/pieces/wP.png');
    expect(AppAssets.pieceSprites['K'], 'assets/generated/pieces/wK.png');
    expect(AppAssets.pieceSprites['p'], 'assets/generated/pieces/bP.png');
    expect(AppAssets.pieceSprites['k'], 'assets/generated/pieces/bK.png');
  });

  test('board skins point to bundled assets', () {
    expect(AppAssets.chessBoardClassic, 'assets/generated/ui/board.png');
    expect(AppAssets.chessBoardRed, 'assets/Boardalt.png.png');
  });

  test(
    'sashite piece assets are present in the runtime asset manifest',
    () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets().toSet();

      for (final path in AppAssets.sashitePieceSprites.values) {
        expect(
          assets.contains(path),
          isTrue,
          reason:
              'Missing "$path" from AssetManifest; multiplayer piece rendering '
              'will fail when that skin is selected.',
        );
      }
    },
  );
}
