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
    this.lastMoveHighlightColor = const Color(0xFFD7CA64),
    this.secondaryMoveFrom,
    this.secondaryMoveTo,
    this.secondaryMoveHighlightColor = const Color(0xFFE57373),
    this.queuedMoveFrom,
    this.queuedMoveTo,
    this.checkedKingSquares = const <String>{},
    this.isCheckmate = false,
    this.boardMessage,
    super.key,
  });

  final Map<String, String> pieces;
  final String playerColor;
  final String? selectedSquare;
  final Set<String> legalTargets;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final Color lastMoveHighlightColor;
  final String? secondaryMoveFrom;
  final String? secondaryMoveTo;
  final Color secondaryMoveHighlightColor;
  final String? queuedMoveFrom;
  final String? queuedMoveTo;
  final Set<String> checkedKingSquares;
  final bool isCheckmate;
  final String? boardMessage;
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
            final isPrimaryMoveSquare =
                square == lastMoveFrom || square == lastMoveTo;
            final isSecondaryMoveSquare =
                square == secondaryMoveFrom || square == secondaryMoveTo;
            final isQueuedSquare =
                square == queuedMoveFrom || square == queuedMoveTo;
            final isCheckedKingSquare = checkedKingSquares.contains(square);

            final baseColor = isDarkSquare
                ? const Color(0xFF8D6E63)
                : const Color(0xFFE8D7C7);
            Color squareColor = baseColor;
            if (isPrimaryMoveSquare) {
              squareColor = lastMoveHighlightColor;
            }
            if (isSecondaryMoveSquare) {
              squareColor = isPrimaryMoveSquare
                  ? Color.lerp(
                      lastMoveHighlightColor,
                      secondaryMoveHighlightColor,
                      0.5,
                    )!
                  : secondaryMoveHighlightColor;
            }

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
                    if (isQueuedSquare)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFF006064),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (isCheckedKingSquare)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                colors: <Color>[
                                  const Color(0x00FFFFFF).withValues(alpha: 0),
                                  const Color(0xFFFBC02D).withValues(
                                    alpha: isCheckmate ? 0.26 : 0.18,
                                  ),
                                  const Color(
                                    0xFFD84315,
                                  ).withValues(alpha: isCheckmate ? 0.4 : 0.28),
                                ],
                                stops: const <double>[0.45, 0.78, 1.0],
                              ),
                              border: Border.all(
                                color: const Color(
                                  0xFFF57F17,
                                ).withValues(alpha: isCheckmate ? 0.9 : 0.72),
                                width: isCheckmate ? 3 : 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (boardMessage != null && boardMessage!.isNotEmpty)
                      Positioned(
                        left: 8,
                        right: 8,
                        top: 8,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xEE1B1B1B),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xD9FBC02D),
                                width: isCheckmate ? 1.5 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                boardMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFF9F6EE),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                              ),
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
