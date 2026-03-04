import 'package:bulletholechess/src/game/ui/skin_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chess board catalog exposes expected ids', () {
    final ids = SkinCatalog.chessBoardSkins.map((skin) => skin.id).toSet();
    expect(ids, containsAll(<String>{'chess_pearl', 'chess_red'}));
  });

  test('chess piece catalog exposes expected ids', () {
    final ids = SkinCatalog.chessPieceSkins.map((skin) => skin.id).toSet();
    expect(
      ids,
      containsAll(<String>{'chess_classic', 'chess_red_pieces', 'chess_neon'}),
    );
  });

  test('unknown skin ids fall back to defaults', () {
    final board = SkinCatalog.chessBoardById('missing');
    final pieces = SkinCatalog.chessPieceById('missing');
    expect(board.id, SkinCatalog.defaultChessBoardSkinId);
    expect(pieces.id, SkinCatalog.defaultChessPieceSkinId);
  });
}
