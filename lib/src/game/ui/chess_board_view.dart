import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_assets.dart';

/// Renders the chess board with animated piece movement and drag-to-move.
///
/// Pieces are tracked as identity-stable sprites laid out in an absolute
/// overlay, so a move slides the piece from its old square to its new one
/// instead of snapping. Input is handled by a single gesture surface: a tap
/// selects/moves (delegating to [onSquareTap]); a drag picks the piece up,
/// lifts it under the finger, and drops it on the release square.
class ChessBoardView extends StatefulWidget {
  const ChessBoardView({
    required this.pieces,
    required this.playerColor,
    required this.onSquareTap,
    this.boardAssetPath = AppAssets.chessBoardClassic,
    this.playableInsetRatio = AppAssets.chessBoardPlayableInsetRatio,
    this.playableSizeRatio = AppAssets.chessBoardPlayableSizeRatio,
    this.whitePieceSprites = AppAssets.pieceSprites,
    this.blackPieceSprites = AppAssets.pieceSprites,
    this.whitePieceScale = _legacyPieceVisualScale,
    this.blackPieceScale = _legacyPieceVisualScale,
    this.whitePieceYOffset = _legacyPieceVisualYOffset,
    this.blackPieceYOffset = _legacyPieceVisualYOffset,
    this.invertWhitePieceColors = false,
    this.invertBlackPieceColors = false,
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
  final String boardAssetPath;
  final double playableInsetRatio;
  final double playableSizeRatio;
  final Map<String, String> whitePieceSprites;
  final Map<String, String> blackPieceSprites;
  final double whitePieceScale;
  final double blackPieceScale;
  final double whitePieceYOffset;
  final double blackPieceYOffset;
  final bool invertWhitePieceColors;
  final bool invertBlackPieceColors;
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

  static const double _legacyPieceVisualScale = 1.26;
  static const double _legacyPieceVisualYOffset = -0.04;

  @override
  State<ChessBoardView> createState() => _ChessBoardViewState();
}

class _ChessBoardViewState extends State<ChessBoardView> {
  static const String _files = 'abcdefgh';
  static const Duration _moveDuration = Duration(milliseconds: 200);
  static const Duration _captureFadeDuration = Duration(milliseconds: 200);
  static const Curve _moveCurve = Curves.easeOutCubic;
  static const double _pieceLiftPixels = 3.5;
  static const double _pieceHeightBoostPixels = 2.0;
  static const double _selectedLiftPixels = 6.0;
  static const double _dragLiftPixels = 14.0;
  static const double _dragScale = 1.14;
  static const TextStyle _pieceFallbackStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: Color(0xFF121212),
  );

  final List<_PieceSprite> _sprites = <_PieceSprite>[];
  // Captured/removed sprites kept briefly so they can fade out in place.
  final List<_PieceSprite> _departing = <_PieceSprite>[];
  int _nextSpriteId = 0;
  double _squareSize = 0;

  String? _dragFrom;
  Offset? _dragPos;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _seedSprites();
  }

  @override
  void didUpdateWidget(covariant ChessBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playerColor != oldWidget.playerColor) {
      // Re-orienting the board would fling every piece across the screen and
      // makes any in-flight drag ambiguous, so snap to the new layout instead.
      _cancelDrag();
      _departing.clear();
      _seedSprites();
      return;
    }
    if (!mapEquals(oldWidget.pieces, widget.pieces)) {
      _reconcileSprites();
    }
  }

  void _seedSprites() {
    _sprites.clear();
    _departing.clear();
    widget.pieces.forEach((square, piece) {
      _sprites.add(
        _PieceSprite(id: _nextSpriteId++, square: square, piece: piece),
      );
    });
  }

  /// Diffs the previous sprite layout against the new [widget.pieces] map and
  /// updates sprite squares in place so [AnimatedPositioned] slides the movers.
  /// Departed pieces are matched to arrivals of the same glyph by nearest
  /// square (handles captures, castling, en passant); unmatched arrivals spawn
  /// fresh sprites and unmatched departures (captures) are dropped.
  void _reconcileSprites() {
    final newPieces = widget.pieces;
    final occupancy = <String, _PieceSprite>{
      for (final sprite in _sprites) sprite.square: sprite,
    };

    final kept = <_PieceSprite>[];
    final departed = <_PieceSprite>[];
    for (final sprite in _sprites) {
      if (newPieces[sprite.square] == sprite.piece) {
        kept.add(sprite);
      } else {
        departed.add(sprite);
      }
    }

    final arrivals = <MapEntry<String, String>>[];
    newPieces.forEach((square, piece) {
      final existing = occupancy[square];
      if (existing != null && existing.piece == piece) {
        return; // Square unchanged; sprite stays.
      }
      arrivals.add(MapEntry<String, String>(square, piece));
    });

    final used = <_PieceSprite>{};
    final result = <_PieceSprite>[...kept];
    for (final arrival in arrivals) {
      final square = arrival.key;
      final piece = arrival.value;
      _PieceSprite? best;
      var bestDistance = double.infinity;
      for (final candidate in departed) {
        if (used.contains(candidate) || candidate.piece != piece) {
          continue;
        }
        final distance = _squareDistance(candidate.square, square);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = candidate;
        }
      }
      if (best != null) {
        used.add(best);
        best.square = square;
        result.add(best);
      } else {
        result.add(
          _PieceSprite(id: _nextSpriteId++, square: square, piece: piece),
        );
      }
    }

    // Departed sprites with no matching arrival were captured/removed: let them
    // fade out in place rather than blink away.
    for (final sprite in departed) {
      if (!used.contains(sprite)) {
        _departing.add(sprite);
      }
    }

    _sprites
      ..clear()
      ..addAll(result);
  }

  double _squareDistance(String a, String b) {
    final ax = _files.indexOf(a[0]).toDouble();
    final ay = int.parse(a[1]).toDouble();
    final bx = _files.indexOf(b[0]).toDouble();
    final by = int.parse(b[1]).toDouble();
    final dx = ax - bx;
    final dy = ay - by;
    return dx * dx + dy * dy;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey<String>('chess_board_surface'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.17),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final playableRect = Rect.fromLTWH(
              constraints.maxWidth * widget.playableInsetRatio,
              constraints.maxHeight * widget.playableInsetRatio,
              constraints.maxWidth * widget.playableSizeRatio,
              constraints.maxHeight * widget.playableSizeRatio,
            );
            final squareSize = playableRect.width / 8;
            _squareSize = squareSize;

            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Image.asset(
                    widget.boardAssetPath,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context, error, stackTrace) {
                      return const DecoratedBox(
                        decoration: BoxDecoration(color: Color(0xFFDFD9CE)),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: playableRect.left,
                  top: playableRect.top,
                  width: playableRect.width,
                  height: playableRect.height,
                  child: _buildPlayLayer(squareSize),
                ),
                if (widget.boardMessage != null &&
                    widget.boardMessage!.isNotEmpty)
                  Positioned(
                    left: playableRect.left + 8,
                    top: playableRect.top + 8,
                    width: playableRect.width - 16,
                    child: IgnorePointer(child: _buildBoardMessage()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayLayer(double squareSize) {
    final children = <Widget>[];
    final hoverSquare = _dragging ? _squareAt(_dragPos) : null;

    children.addAll(_moveHighlightTiles(squareSize));
    children.addAll(_selectionTiles(squareSize, hoverSquare));
    children.addAll(_checkedKingTiles(squareSize));
    children.addAll(_targetTiles(squareSize));
    children.addAll(_queuedTiles(squareSize));
    children.addAll(_departingWidgets(squareSize));
    children.addAll(_spriteWidgets(squareSize));

    children.add(
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTap(details.localPosition),
          onPanStart: (details) => _handlePanStart(details.localPosition),
          onPanUpdate: (details) => _handlePanUpdate(details.localPosition),
          onPanEnd: (_) => _handlePanEnd(),
          onPanCancel: _cancelDrag,
        ),
      ),
    );

    return SizedBox(
      width: squareSize * 8,
      height: squareSize * 8,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  List<Widget> _departingWidgets(double squareSize) {
    final widgets = <Widget>[];
    for (final sprite in _departing) {
      final rect = _rectForSquare(sprite.square, squareSize);
      widgets.add(
        Positioned(
          key: ValueKey<String>('depart_${sprite.id}'),
          left: rect.left,
          top: rect.top,
          width: squareSize,
          height: squareSize,
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 1, end: 0),
              duration: _captureFadeDuration,
              curve: Curves.easeIn,
              onEnd: () {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _departing.removeWhere((s) => s.id == sprite.id);
                });
              },
              builder: (context, value, child) {
                return Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.55 + 0.45 * value,
                    child: child,
                  ),
                );
              },
              child: _spriteVisual(sprite, squareSize),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _spriteWidgets(double squareSize) {
    final widgets = <Widget>[];
    for (final sprite in _sprites) {
      final isDragged = _dragging && sprite.square == _dragFrom;
      if (isDragged && _dragPos != null) {
        widgets.add(
          Positioned(
            key: ValueKey<String>('sprite_${sprite.id}'),
            left: _dragPos!.dx - squareSize / 2,
            top: _dragPos!.dy - squareSize / 2,
            width: squareSize,
            height: squareSize,
            child: IgnorePointer(
              child: _spriteVisual(sprite, squareSize, dragging: true),
            ),
          ),
        );
        continue;
      }
      final rect = _rectForSquare(sprite.square, squareSize);
      final isSelected = widget.selectedSquare == sprite.square;
      widgets.add(
        AnimatedPositioned(
          key: ValueKey<String>('sprite_${sprite.id}'),
          duration: _moveDuration,
          curve: _moveCurve,
          left: rect.left,
          top: rect.top,
          width: squareSize,
          height: squareSize,
          child: IgnorePointer(
            child: _spriteVisual(sprite, squareSize, selected: isSelected),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _spriteVisual(
    _PieceSprite sprite,
    double squareSize, {
    bool selected = false,
    bool dragging = false,
  }) {
    final piece = sprite.piece;
    final isWhite = piece == piece.toUpperCase();
    final scale = (isWhite ? widget.whitePieceScale : widget.blackPieceScale)
        .clamp(0.5, 1.7);
    final yOffset =
        (isWhite ? widget.whitePieceYOffset : widget.blackPieceYOffset).clamp(
          -0.4,
          0.4,
        );
    final pieceSize = squareSize * scale;
    final lift =
        _pieceLiftPixels +
        (selected ? _selectedLiftPixels : 0.0) +
        (dragging ? _dragLiftPixels : 0.0);

    Widget spr128 = OverflowBox(
      alignment: Alignment.center,
      minWidth: 0,
      minHeight: 0,
      maxWidth: pieceSize,
      maxHeight: pieceSize + _pieceHeightBoostPixels,
      child: SizedBox(
        width: pieceSize,
        height: pieceSize + _pieceHeightBoostPixels,
        child: _buildPieceSprite(piece),
      ),
    );

    Widget content = Transform.translate(
      offset: Offset(0, squareSize * yOffset - lift),
      child: spr128,
    );

    if (dragging) {
      content = Transform.scale(scale: _dragScale, child: content);
    }

    return content;
  }

  // ---- Square-overlay tiles -------------------------------------------------

  List<Widget> _moveHighlightTiles(double squareSize) {
    final tiles = <Widget>[];
    final primary = <String>{
      if (widget.lastMoveFrom != null) widget.lastMoveFrom!,
      if (widget.lastMoveTo != null) widget.lastMoveTo!,
    };
    final secondary = <String>{
      if (widget.secondaryMoveFrom != null) widget.secondaryMoveFrom!,
      if (widget.secondaryMoveTo != null) widget.secondaryMoveTo!,
    };
    final squares = <String>{...primary, ...secondary};
    for (final square in squares) {
      Color color;
      if (primary.contains(square) && secondary.contains(square)) {
        color = Color.lerp(
          widget.lastMoveHighlightColor,
          widget.secondaryMoveHighlightColor,
          0.5,
        )!.withValues(alpha: 0.35);
      } else if (primary.contains(square)) {
        color = widget.lastMoveHighlightColor.withValues(alpha: 0.36);
      } else {
        color = widget.secondaryMoveHighlightColor.withValues(alpha: 0.34);
      }
      tiles.add(
        _tile(
          square,
          squareSize,
          DecoratedBox(decoration: BoxDecoration(color: color)),
        ),
      );
    }
    return tiles;
  }

  List<Widget> _selectionTiles(double squareSize, String? hoverSquare) {
    final tiles = <Widget>[];
    if (widget.selectedSquare != null) {
      tiles.add(
        _tile(
          widget.selectedSquare!,
          squareSize,
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF1DE9B6), width: 2.6),
            ),
          ),
        ),
      );
    }
    if (hoverSquare != null && hoverSquare != _dragFrom) {
      tiles.add(
        _tile(
          hoverSquare,
          squareSize,
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF1DE9B6).withValues(alpha: 0.12),
              border: Border.all(
                color: const Color(0xFF1DE9B6).withValues(alpha: 0.8),
                width: 2.2,
              ),
            ),
          ),
        ),
      );
    }
    return tiles;
  }

  List<Widget> _checkedKingTiles(double squareSize) {
    return widget.checkedKingSquares.map((square) {
      return _tile(
        square,
        squareSize,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: <Color>[
                const Color(0x00FFFFFF).withValues(alpha: 0),
                const Color(
                  0xFFFBC02D,
                ).withValues(alpha: widget.isCheckmate ? 0.26 : 0.18),
                const Color(
                  0xFFD84315,
                ).withValues(alpha: widget.isCheckmate ? 0.4 : 0.28),
              ],
              stops: const <double>[0.45, 0.78, 1.0],
            ),
            border: Border.all(
              color: const Color(
                0xFFF57F17,
              ).withValues(alpha: widget.isCheckmate ? 0.9 : 0.72),
              width: widget.isCheckmate ? 3 : 2,
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _targetTiles(double squareSize) {
    final tiles = <Widget>[];
    for (final square in widget.legalTargets) {
      final occupied = widget.pieces[square] != null;
      tiles.add(
        _tile(
          square,
          squareSize,
          Center(
            child: occupied
                ? Container(
                    width: double.infinity,
                    height: double.infinity,
                    margin: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xCC00A676),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  )
                : Container(
                    width: squareSize * 0.28,
                    height: squareSize * 0.28,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xCC00A676),
                    ),
                  ),
          ),
        ),
      );
    }
    return tiles;
  }

  List<Widget> _queuedTiles(double squareSize) {
    final squares = <String>{
      if (widget.queuedMoveFrom != null) widget.queuedMoveFrom!,
      if (widget.queuedMoveTo != null) widget.queuedMoveTo!,
    };
    return squares.map((square) {
      return _tile(
        square,
        squareSize,
        Padding(
          padding: const EdgeInsets.all(4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF4DD0E1), width: 2),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _tile(String square, double squareSize, Widget child) {
    final rect = _rectForSquare(square, squareSize);
    return Positioned(
      key: ValueKey<String>('tile_${square}_${child.runtimeType}'),
      left: rect.left,
      top: rect.top,
      width: squareSize,
      height: squareSize,
      child: IgnorePointer(child: child),
    );
  }

  Widget _buildBoardMessage() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE1B1B1B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xD9FBC02D),
          width: widget.isCheckmate ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          widget.boardMessage!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFF9F6EE),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }

  // ---- Gesture handling -----------------------------------------------------

  void _handleTap(Offset localPosition) {
    final square = _squareAt(localPosition);
    if (square != null) {
      widget.onSquareTap(square);
    }
  }

  void _handlePanStart(Offset localPosition) {
    final square = _squareAt(localPosition);
    if (square == null || widget.pieces[square] == null) {
      _cancelDrag();
      return;
    }
    // Select the piece so legal targets show, unless it is already selected
    // (re-tapping a selected square would toggle it off).
    if (widget.selectedSquare != square) {
      widget.onSquareTap(square);
    }
    setState(() {
      _dragging = true;
      _dragFrom = square;
      _dragPos = localPosition;
    });
  }

  void _handlePanUpdate(Offset localPosition) {
    if (!_dragging) {
      return;
    }
    setState(() {
      _dragPos = localPosition;
    });
  }

  void _handlePanEnd() {
    if (!_dragging || _dragFrom == null) {
      _cancelDrag();
      return;
    }
    final target = _squareAt(_dragPos);
    final from = _dragFrom;
    setState(() {
      _dragging = false;
      _dragFrom = null;
      _dragPos = null;
    });
    if (target != null && target != from) {
      widget.onSquareTap(target);
    }
  }

  void _cancelDrag() {
    if (!_dragging && _dragFrom == null && _dragPos == null) {
      return;
    }
    setState(() {
      _dragging = false;
      _dragFrom = null;
      _dragPos = null;
    });
  }

  // ---- Geometry -------------------------------------------------------------

  Rect _rectForSquare(String square, double squareSize) {
    final index = _displayIndexForSquare(square);
    final row = index ~/ 8;
    final col = index % 8;
    return Rect.fromLTWH(
      col * squareSize,
      row * squareSize,
      squareSize,
      squareSize,
    );
  }

  int _displayIndexForSquare(String square) {
    final col = _files.indexOf(square[0]);
    final rank = int.parse(square[1]);
    final boardIndex = (8 - rank) * 8 + col;
    return widget.playerColor == 'w' ? boardIndex : 63 - boardIndex;
  }

  String? _squareAt(Offset? position) {
    if (position == null || _squareSize <= 0) {
      return null;
    }
    final col = (position.dx / _squareSize).floor();
    final row = (position.dy / _squareSize).floor();
    if (col < 0 || col > 7 || row < 0 || row > 7) {
      return null;
    }
    return _squareForDisplayedCell(row * 8 + col);
  }

  String _squareForDisplayedCell(int index) {
    final boardIndex = widget.playerColor == 'w' ? index : 63 - index;
    final row = boardIndex ~/ 8;
    final col = boardIndex % 8;
    return '${_files[col]}${8 - row}';
  }

  // ---- Sprites --------------------------------------------------------------

  Widget _buildPieceSprite(String piece) {
    final isWhitePiece = piece == piece.toUpperCase();
    final spriteLookup = isWhitePiece
        ? widget.whitePieceSprites
        : widget.blackPieceSprites;
    final spritePath = spriteLookup[piece];
    if (spritePath == null) {
      return Center(child: Text(piece, style: _pieceFallbackStyle));
    }

    Widget sprite = Image.asset(
      spritePath,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      cacheWidth: 256,
      cacheHeight: 256,
      errorBuilder: (context, error, stackTrace) {
        return Center(child: Text(piece, style: _pieceFallbackStyle));
      },
    );

    final shouldInvert = isWhitePiece
        ? widget.invertWhitePieceColors
        : widget.invertBlackPieceColors;
    if (shouldInvert) {
      sprite = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          -1, 0, 0, 0, 255, //
          0, -1, 0, 0, 255, //
          0, 0, -1, 0, 255, //
          0, 0, 0, 1, 0, //
        ]),
        child: sprite,
      );
    }

    return sprite;
  }
}

class _PieceSprite {
  _PieceSprite({required this.id, required this.square, required this.piece});

  final int id;
  String square;
  final String piece;
}
