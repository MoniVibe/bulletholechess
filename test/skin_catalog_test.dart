import 'package:bulletholechess/src/game/ui/skin_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chess and backgammon board skin catalogs are separated', () {
    final chessIds = SkinCatalog.chessBoardSkins.map((skin) => skin.id).toSet();
    final backgammonIds = SkinCatalog.backgammonBoardSkins
        .map((skin) => skin.id)
        .toSet();

    expect(chessIds.intersection(backgammonIds), isEmpty);
    expect(chessIds, contains('chess_red'));
    expect(backgammonIds, isNot(contains('chess_red')));
  });

  test('chess and backgammon piece skin catalogs are separated', () {
    final chessIds = SkinCatalog.chessPieceSkins.map((skin) => skin.id).toSet();
    final backgammonIds = SkinCatalog.backgammonPieceSkins
        .map((skin) => skin.id)
        .toSet();

    expect(chessIds.intersection(backgammonIds), isEmpty);
    expect(chessIds, contains('chess_classic'));
    expect(backgammonIds, contains('bg_royal'));
  });
}
