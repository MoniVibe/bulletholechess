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

  test('sheshbesh dice map has six generated faces', () {
    expect(AppAssets.diceFaces.length, 6);
    for (var face = 1; face <= 6; face++) {
      final path = AppAssets.diceFaceAsset(face);
      expect(path, isNotNull);
      expect(path!.startsWith('assets/generated/sheshbesh/'), isTrue);
      expect(path.endsWith('.png'), isTrue);
    }
  });

  test('coin sprites use generated sheshbesh assets', () {
    expect(
      AppAssets.whiteCoin.startsWith('assets/generated/sheshbesh/'),
      isTrue,
    );
    expect(
      AppAssets.blackCoin.startsWith('assets/generated/sheshbesh/'),
      isTrue,
    );
    expect(AppAssets.redCoin.startsWith('assets/generated/sheshbesh/'), isTrue);
    expect(AppAssets.whiteCoin.endsWith('.png'), isTrue);
    expect(AppAssets.blackCoin.endsWith('.png'), isTrue);
    expect(AppAssets.redCoin.endsWith('.png'), isTrue);
  });

  test('board skins point to bundled assets', () {
    expect(AppAssets.chessBoardClassic, 'assets/generated/ui/board.png');
    expect(AppAssets.chessBoardRed, 'assets/Boardalt.png.png');
    expect(
      AppAssets.backgammonBoardClassic,
      'assets/generated/sheshbesh/backgammon_board_classic.png',
    );
  });
}
