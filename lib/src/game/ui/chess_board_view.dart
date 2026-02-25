import 'package:flutter/material.dart';

class ChessBoardView extends StatelessWidget {
  const ChessBoardView({
    required this.pieces,
    required this.playerColor,
    required this.onSquareTap,
    this.selectedSquare,
    this.legalTargets = const <String>{},
    this.lastMoveFrom,
    this.lastMoveTo,
    super.key,
  });

  final Map<String, String> pieces;
  final String playerColor;
  final String? selectedSquare;
  final Set<String> legalTargets;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final ValueChanged<String> onSquareTap;

  static const _files = 'abcdefgh';

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 64,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
          ),
          itemBuilder: (context, index) {
            final boardIndex = playerColor == 'w' ? index : 63 - index;
            final row = boardIndex ~/ 8;
            final col = boardIndex % 8;
            final square = '${_files[col]}${8 - row}';
            final piece = pieces[square];
            final isDarkSquare = (row + col).isOdd;
            final isSelected = selectedSquare == square;
            final isTarget = legalTargets.contains(square);
            final isLastMoveSquare =
                square == lastMoveFrom || square == lastMoveTo;

            final baseColor = isDarkSquare
                ? const Color(0xFF8D6E63)
                : const Color(0xFFE8D7C7);
            final squareColor = isLastMoveSquare
                ? const Color(0xFFD7CA64)
                : baseColor;

            return Material(
              color: squareColor,
              child: InkWell(
                onTap: () => onSquareTap(square),
                child: Stack(
                  children: [
                    if (isSelected)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF2196F3),
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    if (isTarget)
                      Center(
                        child: piece == null
                            ? Container(
                                width: 14,
                                height: 14,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xCC1B5E20),
                                ),
                              )
                            : Container(
                                width: double.infinity,
                                height: double.infinity,
                                margin: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xCC1B5E20),
                                    width: 2,
                                  ),
                                ),
                              ),
                      ),
                    if (piece != null)
                      Center(
                        child: Text(
                          piece,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: piece == piece.toUpperCase()
                                ? const Color(0xFFF6F1E7)
                                : const Color(0xFF1A1A1A),
                            shadows: const [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      right: 3,
                      bottom: 1,
                      child: Text(
                        square,
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.black.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
