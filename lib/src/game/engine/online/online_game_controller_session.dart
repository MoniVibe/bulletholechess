part of '../online_game_controller.dart';

extension _OnlineGameControllerSession on OnlineGameController {
  void _clearSelection() {
    _selectedSquare = null;
    _legalTargets = <String>{};
  }

  void _refreshSelectionForCurrentBoard() {
    final color = _myColor;
    if (_selectedSquare == null || color == null) {
      return;
    }

    final piece = boardPieces[_selectedSquare!];
    if (piece == null || ChessRules.pieceColor(piece) != color) {
      _clearSelection();
      return;
    }

    _legalTargets = ChessRules.legalDestinationsFrom(
      game: _game,
      square: _selectedSquare!,
      color: color,
    );
  }

  void _send(Map<String, dynamic> payload) {
    _transportClient.sendJson(payload);
  }

  int _derivedActionIndex() => history.length;

  int _derivedTurnIndex() => (_derivedActionIndex() ~/ 2) + 1;

  Map<String, Object?> _sessionSnapshot() {
    return <String, Object?>{
      'turnIndex': _derivedTurnIndex(),
      'actionIndexOrPlyIndex': _derivedActionIndex(),
      'connectionState': _connectionState.name,
      'status': _status,
      'matchId': _matchId,
      'myColor': _myColor,
      'turnColor': turnColor,
      'result': _result,
      'historyLen': history.length,
      'fen': _game.fen,
      'cooldownSeconds': _cooldownDuration.inSeconds,
      'whiteRemainingMs': cooldownRemaining('w').inMilliseconds,
      'blackRemainingMs': cooldownRemaining('b').inMilliseconds,
      'hasQueuedMove': hasQueuedMove,
      'queuedMove': queuedMoveLabel,
      'feedback': _feedback,
    };
  }
}
