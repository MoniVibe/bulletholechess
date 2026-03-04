import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'sheshbesh_ai_engine.dart';
import 'sheshbesh_model.dart';
import 'sheshbesh_rules.dart';

class LocalGameController extends ChangeNotifier {
  LocalGameController({
    Duration initialCooldownDuration = const Duration(seconds: 3),
    this.aiThinkDelayMin = const Duration(milliseconds: 900),
    this.aiThinkDelayMax = const Duration(milliseconds: 1700),
    SheshBeshAiEngine? aiEngine,
    Random? random,
  }) : _random = random ?? Random(),
       _aiEngine = aiEngine ?? SheshBeshAiEngine(random: random ?? Random()),
       _cooldownDuration = initialCooldownDuration {
    _resetRuntimeState(activateGame: false);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onTick(),
    );
  }

  final Duration aiThinkDelayMin;
  final Duration aiThinkDelayMax;
  final Random _random;
  final SheshBeshAiEngine _aiEngine;

  late Timer _ticker;
  Timer? _aiTurnTimer;

  Duration _cooldownDuration;
  bool _disposed = false;
  bool _hasActiveGame = false;
  bool _aiTurnPending = false;

  String _playerColor = 'w';
  String _turnColor = 'w';
  String? _winnerColor;
  String? _feedback;

  late SheshBeshPosition _position;
  List<int> _remainingDice = <int>[];
  TurnDecision _currentDecision = const TurnDecision(
    legalMoves: <SheshBeshMove>[],
    maxMovesUsable: 0,
    maxUsedPips: 0,
  );
  DateTime _whiteReadyAt = DateTime.now();
  DateTime _blackReadyAt = DateTime.now();
  DateTime _turnDeadlineAt = DateTime.now();

  int? _selectedPoint;
  bool _selectedFromBar = false;
  Set<int> _legalTargetPoints = <int>{};
  bool _canBearOffTarget = false;
  Map<int, int> _targetDiceSpentHints = <int, int>{};
  Map<int, int> _sourceDiceUsageHints = <int, int>{};

  SheshBeshMove? _playerLastMove;
  SheshBeshMove? _opponentLastMove;

  final List<String> _history = <String>[];

  Duration get cooldownDuration => _cooldownDuration;
  String get playerColor => _playerColor;
  String get aiColor => SheshBeshRules.oppositeColor(_playerColor);
  String get turnColor => _turnColor;
  bool get hasActiveGame => _hasActiveGame;
  bool get isGameOver => _winnerColor != null;
  String? get winnerColor => _winnerColor;
  String? get winnerLabel =>
      _winnerColor == null ? null : (_winnerColor == 'w' ? 'White' : 'Black');

  String? get feedback => _feedback;

  List<SheshBeshPoint> get points => _position.points;
  int barCount(String color) => _position.barCount(color);
  int borneOffCount(String color) => _position.borneOffCount(color);
  List<int> get remainingDice => List<int>.unmodifiable(_remainingDice);
  Duration get activeTurnRemaining => _turnRemaining();

  Duration timerRemaining(String color) {
    if (!_hasActiveGame || isGameOver) {
      return Duration.zero;
    }
    if (color == _turnColor) {
      return _turnRemaining();
    }
    return cooldownRemaining(color);
  }

  int? get selectedPoint => _selectedPoint;
  bool get selectedFromBar => _selectedFromBar;
  Set<int> get legalTargetPoints => _legalTargetPoints;
  bool get canBearOffTarget => _canBearOffTarget;
  Map<int, int> get targetDiceSpentHints =>
      Map<int, int>.unmodifiable(_targetDiceSpentHints);
  Map<int, int> get sourceDiceUsageHints =>
      Map<int, int>.unmodifiable(_sourceDiceUsageHints);
  Set<int> get playableSourcePoints => _derivePlayableSourcePoints();
  bool get canEnterFromBar => _deriveCanEnterFromBar();

  SheshBeshMove? get playerLastMove => _playerLastMove;
  SheshBeshMove? get opponentLastMove => _opponentLastMove;

  List<String> get history => List<String>.unmodifiable(_history);

  bool get canPlayerInteract {
    return _hasActiveGame &&
        !isGameOver &&
        _turnColor == _playerColor &&
        _turnRemaining().inMilliseconds > 0 &&
        cooldownRemaining(_playerColor).inMilliseconds == 0;
  }

  String get statusText {
    if (!_hasActiveGame) {
      return 'Start a new sheshbesh game to begin.';
    }
    if (_winnerColor != null) {
      return '${winnerLabel!} wins. Start a new game.';
    }

    final diceText = _remainingDice.join(' ');
    final turnLabel = _turnColor == 'w' ? 'White' : 'Black';
    final turnIsPlayer = _turnColor == _playerColor;
    final cooldown = cooldownRemaining(_turnColor);
    final turnRemaining = _turnRemaining();
    if (turnRemaining.inMilliseconds == 0) {
      return '$turnLabel timed out. Turn will pass.';
    }

    if (cooldown.inMilliseconds > 0) {
      return '$turnLabel cooling down (${_formatDuration(cooldown)}).';
    }

    if (!_currentDecision.hasMoves) {
      return '$turnLabel has no legal moves and will pass.';
    }

    if (turnIsPlayer) {
      return 'Your turn (${_formatDuration(turnRemaining)}). Dice: $diceText';
    }

    if (_aiTurnPending) {
      return 'Bot is thinking. Dice: $diceText';
    }

    return 'Bot turn (${_formatDuration(turnRemaining)}). Dice: $diceText';
  }

  Duration cooldownRemaining(String color) {
    final readyAt = color == 'w' ? _whiteReadyAt : _blackReadyAt;
    final remaining = readyAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }

  void startNewGame({bool playerAsWhite = true, Duration? cooldownDuration}) {
    _cancelAiTimer();
    _playerColor = playerAsWhite ? 'w' : 'b';
    if (cooldownDuration != null) {
      _cooldownDuration = cooldownDuration;
    }

    _resetRuntimeState(activateGame: true);

    final opening = SheshBeshRules.determineOpeningStarter(_random);
    _history.add(
      'Opening roll W${opening.whiteRoll} / B${opening.blackRoll}. '
      '${opening.startingColor == 'w' ? 'White' : 'Black'} starts.',
    );

    _beginTurn(opening.startingColor);
    _refreshDecision();
    _maybeScheduleAiTurn();
    notifyListeners();
  }

  void tapPoint(int pointIndex) {
    if (!canPlayerInteract || isGameOver) {
      return;
    }
    if (pointIndex < 0 || pointIndex >= 24) {
      return;
    }

    if (_position.barCount(_turnColor) > 0) {
      _selectedFromBar = true;
      _selectedPoint = null;
      _updateSelectionTargets();
      final moved = _attemptSelectedMove(toPoint: pointIndex);
      if (!moved) {
        _feedback = 'Enter from bar first.';
        notifyListeners();
      }
      return;
    }

    final isOwnPoint = _pointOwnedBy(pointIndex, _turnColor);

    if (_selectedPoint != null) {
      final moved = _attemptSelectedMove(toPoint: pointIndex);
      if (moved) {
        return;
      }
    }

    if (!isOwnPoint) {
      _feedback = 'Select one of your checkers.';
      notifyListeners();
      return;
    }

    if (_selectedPoint == pointIndex) {
      _clearSelection();
      notifyListeners();
      return;
    }

    _selectedFromBar = false;
    _selectedPoint = pointIndex;
    _feedback = null;
    _updateSelectionTargets();
    notifyListeners();
  }

  void tapBar() {
    if (!canPlayerInteract || isGameOver) {
      return;
    }
    if (_position.barCount(_turnColor) == 0) {
      return;
    }
    _selectedFromBar = true;
    _selectedPoint = null;
    _feedback = null;
    _updateSelectionTargets();
    notifyListeners();
  }

  void tapBearOff() {
    if (!canPlayerInteract || isGameOver) {
      return;
    }
    if (!_canBearOffTarget) {
      return;
    }
    _attemptSelectedMove(bearOff: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.cancel();
    _cancelAiTimer();
    super.dispose();
  }

  void _onTick() {
    if (_disposed || !_hasActiveGame || isGameOver) {
      return;
    }

    if (_maybeExpireTurnOnTimeout()) {
      return;
    }

    _refreshDecision();
    if (_maybeAutoPassStuckTurn()) {
      return;
    }
    _maybeScheduleAiTurn();
    notifyListeners();
  }

  bool _attemptSelectedMove({int? toPoint, bool bearOff = false}) {
    final source = _selectedSourceKind();
    if (source == _SelectedSource.none) {
      return false;
    }

    final matching = _currentDecision.legalMoves
        .where((move) {
          if (source == _SelectedSource.bar &&
              move.source != SheshBeshMoveSource.bar) {
            return false;
          }
          if (source == _SelectedSource.point) {
            if (move.source != SheshBeshMoveSource.point ||
                move.fromPoint != _selectedPoint) {
              return false;
            }
          }
          if (bearOff) {
            return move.bearsOff;
          }
          return !move.bearsOff && move.toPoint == toPoint;
        })
        .toList(growable: false);

    if (matching.isEmpty) {
      return false;
    }

    // If several dice map to the same destination, prefer the larger die.
    matching.sort((a, b) => b.die.compareTo(a.die));
    _applyMove(matching.first, moverColor: _turnColor, actorIsPlayer: true);
    return true;
  }

  void _applyMove(
    SheshBeshMove move, {
    required String moverColor,
    required bool actorIsPlayer,
  }) {
    _position = SheshBeshRules.applyMove(
      position: _position,
      color: moverColor,
      move: move,
    );

    _remainingDice.remove(move.die);

    if (actorIsPlayer) {
      _playerLastMove = move;
    } else {
      _opponentLastMove = move;
    }

    _history.add(move.describe(moverColor));
    _feedback = null;
    _clearSelection();

    _winnerColor = SheshBeshRules.winnerColor(_position);
    if (_winnerColor != null) {
      _aiTurnPending = false;
      _cancelAiTimer();
      notifyListeners();
      return;
    }

    _refreshDecision();

    if (_remainingDice.isEmpty || !_currentDecision.hasMoves) {
      if (_remainingDice.isNotEmpty && !_currentDecision.hasMoves) {
        _history.add(
          '${moverColor == 'w' ? 'W' : 'B'} no legal moves with '
          'remaining dice ${_remainingDice.join(', ')}.',
        );
      }
      _endCurrentTurn();
      return;
    }

    notifyListeners();
  }

  void _endCurrentTurn({bool applyMoverCooldown = true}) {
    final mover = _turnColor;
    if (applyMoverCooldown) {
      _setCooldownForMover(mover);
    }
    _beginTurn(SheshBeshRules.oppositeColor(mover));
    _refreshDecision();
    _maybeScheduleAiTurn();
    notifyListeners();
  }

  void _beginTurn(String color) {
    _turnColor = color;
    _turnDeadlineAt = DateTime.now().add(_cooldownDuration);
    _remainingDice = SheshBeshRules.rollTurnDice(_random);
    _clearSelection();
    _history.add(
      '${color == 'w' ? 'W' : 'B'} rolls ${_remainingDice.join(' + ')}',
    );
  }

  bool _maybeAutoPassStuckTurn() {
    if (!_hasActiveGame ||
        isGameOver ||
        _turnRemaining().inMilliseconds == 0 ||
        cooldownRemaining(_turnColor).inMilliseconds > 0) {
      return false;
    }
    if (_currentDecision.hasMoves) {
      return false;
    }

    _history.add('${_turnColor == 'w' ? 'W' : 'B'} passes (no legal moves).');
    _endCurrentTurn();
    return true;
  }

  void _maybeScheduleAiTurn() {
    if (!_hasActiveGame ||
        isGameOver ||
        _turnColor != aiColor ||
        _turnRemaining().inMilliseconds == 0 ||
        cooldownRemaining(aiColor).inMilliseconds > 0 ||
        !_currentDecision.hasMoves ||
        _aiTurnPending) {
      return;
    }

    _aiTurnPending = true;
    _aiTurnTimer = Timer(_nextAiThinkDelay(), _runAiTurn);
  }

  void _runAiTurn() {
    if (_disposed) {
      return;
    }

    if (!_hasActiveGame ||
        isGameOver ||
        _turnColor != aiColor ||
        _turnRemaining().inMilliseconds == 0 ||
        cooldownRemaining(aiColor).inMilliseconds > 0) {
      _aiTurnPending = false;
      notifyListeners();
      return;
    }

    _refreshDecision();
    if (!_currentDecision.hasMoves) {
      _aiTurnPending = false;
      _maybeAutoPassStuckTurn();
      notifyListeners();
      return;
    }

    while (!isGameOver && _turnColor == aiColor && _remainingDice.isNotEmpty) {
      if (_turnRemaining().inMilliseconds == 0) {
        _aiTurnPending = false;
        _maybeExpireTurnOnTimeout();
        return;
      }
      final move = _aiEngine.chooseMove(
        position: _position,
        color: aiColor,
        dice: _remainingDice,
      );
      if (move == null) {
        break;
      }

      _applyMove(move, moverColor: aiColor, actorIsPlayer: false);

      if (_turnColor != aiColor || isGameOver) {
        break;
      }
    }

    _aiTurnPending = false;
    notifyListeners();
  }

  void _refreshDecision() {
    if (!_hasActiveGame || isGameOver) {
      _currentDecision = const TurnDecision(
        legalMoves: <SheshBeshMove>[],
        maxMovesUsable: 0,
        maxUsedPips: 0,
      );
      _updateSelectionTargets();
      return;
    }

    _currentDecision = SheshBeshRules.computeTurnDecision(
      position: _position,
      color: _turnColor,
      dice: _remainingDice,
    );

    if (!_currentDecision.hasMoves) {
      _clearSelection();
      _sourceDiceUsageHints = <int, int>{};
      return;
    }

    if (_position.barCount(_turnColor) > 0) {
      _selectedFromBar = true;
      _selectedPoint = null;
      _updateSelectionTargets();
      return;
    }

    // Keep the selection only if it still has legal targets.
    if (_selectedPoint != null) {
      final selectedStillValid = _currentDecision.legalMoves.any(
        (move) =>
            move.source == SheshBeshMoveSource.point &&
            move.fromPoint == _selectedPoint,
      );
      if (!selectedStillValid) {
        _selectedPoint = null;
      }
    }

    _updateSelectionTargets();
  }

  void _updateSelectionTargets() {
    final targets = <int>{};
    var canBearOff = false;

    final source = _selectedSourceKind();
    if (source == _SelectedSource.none) {
      _legalTargetPoints = const <int>{};
      _canBearOffTarget = false;
      _rebuildDiceUsageHints(source: source);
      return;
    }

    for (final move in _currentDecision.legalMoves) {
      final matchesSource = switch (source) {
        _SelectedSource.bar => move.source == SheshBeshMoveSource.bar,
        _SelectedSource.point =>
          move.source == SheshBeshMoveSource.point &&
              move.fromPoint == _selectedPoint,
        _SelectedSource.none => false,
      };
      if (!matchesSource) {
        continue;
      }
      if (move.bearsOff) {
        canBearOff = true;
        continue;
      }
      if (move.toPoint != null) {
        targets.add(move.toPoint!);
      }
    }

    _legalTargetPoints = targets;
    _canBearOffTarget = canBearOff;
    _rebuildDiceUsageHints(source: source);
  }

  _SelectedSource _selectedSourceKind() {
    if (_selectedFromBar) {
      return _SelectedSource.bar;
    }
    if (_selectedPoint != null) {
      return _SelectedSource.point;
    }
    return _SelectedSource.none;
  }

  bool _pointOwnedBy(int point, String color) {
    final stack = _position.points[point];
    return stack.color == color && stack.count > 0;
  }

  Set<int> _derivePlayableSourcePoints() {
    if (!_hasActiveGame ||
        isGameOver ||
        _turnRemaining().inMilliseconds == 0 ||
        cooldownRemaining(_turnColor).inMilliseconds > 0) {
      return const <int>{};
    }
    return _currentDecision.legalMoves
        .where((move) => move.source == SheshBeshMoveSource.point)
        .map((move) => move.fromPoint!)
        .toSet();
  }

  bool _deriveCanEnterFromBar() {
    if (!_hasActiveGame ||
        isGameOver ||
        _turnRemaining().inMilliseconds == 0 ||
        cooldownRemaining(_turnColor).inMilliseconds > 0) {
      return false;
    }
    return _currentDecision.legalMoves.any(
      (move) => move.source == SheshBeshMoveSource.bar,
    );
  }

  bool _maybeExpireTurnOnTimeout() {
    if (!_hasActiveGame || isGameOver || _turnRemaining().inMilliseconds > 0) {
      return false;
    }

    final expiredColor = _turnColor;
    _history.add(
      '${expiredColor == 'w' ? 'W' : 'B'} time expired. Turn passed.',
    );
    _cancelAiTimer();
    _endCurrentTurn(applyMoverCooldown: false);
    return true;
  }

  Duration _turnRemaining() {
    final remaining = _turnDeadlineAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }

  void _rebuildDiceUsageHints({required _SelectedSource source}) {
    _sourceDiceUsageHints = <int, int>{};
    _targetDiceSpentHints = <int, int>{};

    if (!_hasActiveGame ||
        isGameOver ||
        !_currentDecision.hasMoves ||
        _turnRemaining().inMilliseconds == 0 ||
        cooldownRemaining(_turnColor).inMilliseconds > 0) {
      return;
    }

    final pointMoves = _currentDecision.legalMoves
        .where(
          (move) =>
              move.source == SheshBeshMoveSource.point &&
              move.fromPoint != null,
        )
        .toList(growable: false);
    for (final move in pointMoves) {
      final sourcePoint = move.fromPoint!;
      final maxDiceSpent = _maxDiceSpentFollowingMove(move);
      final prior = _sourceDiceUsageHints[sourcePoint] ?? 0;
      if (maxDiceSpent > prior) {
        _sourceDiceUsageHints[sourcePoint] = maxDiceSpent;
      }

      if (source == _SelectedSource.point &&
          _selectedPoint == sourcePoint &&
          !move.bearsOff &&
          move.toPoint != null) {
        final targetPoint = move.toPoint!;
        final targetPrior = _targetDiceSpentHints[targetPoint] ?? 0;
        if (maxDiceSpent > targetPrior) {
          _targetDiceSpentHints[targetPoint] = maxDiceSpent;
        }
      }
    }

    if (source == _SelectedSource.bar) {
      final barMoves = _currentDecision.legalMoves
          .where(
            (move) =>
                move.source == SheshBeshMoveSource.bar &&
                !move.bearsOff &&
                move.toPoint != null,
          )
          .toList(growable: false);
      for (final move in barMoves) {
        final targetPoint = move.toPoint!;
        final maxDiceSpent = _maxDiceSpentFollowingMove(move);
        final prior = _targetDiceSpentHints[targetPoint] ?? 0;
        if (maxDiceSpent > prior) {
          _targetDiceSpentHints[targetPoint] = maxDiceSpent;
        }
      }
    }
  }

  int _maxDiceSpentFollowingMove(SheshBeshMove firstMove) {
    final nextPosition = SheshBeshRules.applyMove(
      position: _position,
      color: _turnColor,
      move: firstMove,
    );
    final nextDice = _consumeDie(_remainingDice, firstMove.die);
    final additional = firstMove.bearsOff || firstMove.toPoint == null
        ? 0
        : _maxAdditionalDiceForChecker(
            position: nextPosition,
            checkerPoint: firstMove.toPoint!,
            dice: nextDice,
          );
    return 1 + additional;
  }

  int _maxAdditionalDiceForChecker({
    required SheshBeshPosition position,
    required int checkerPoint,
    required List<int> dice,
  }) {
    if (dice.isEmpty) {
      return 0;
    }

    final decision = SheshBeshRules.computeTurnDecision(
      position: position,
      color: _turnColor,
      dice: dice,
    );
    if (!decision.hasMoves) {
      return 0;
    }

    var best = 0;
    // Follow the same checker across the turn so the hint reflects
    // "how many dice this single piece can still spend".
    for (final move in decision.legalMoves) {
      if (move.source != SheshBeshMoveSource.point ||
          move.fromPoint != checkerPoint) {
        continue;
      }
      final nextPosition = SheshBeshRules.applyMove(
        position: position,
        color: _turnColor,
        move: move,
      );
      final nextDice = _consumeDie(dice, move.die);
      final tail = move.bearsOff || move.toPoint == null
          ? 0
          : _maxAdditionalDiceForChecker(
              position: nextPosition,
              checkerPoint: move.toPoint!,
              dice: nextDice,
            );
      final spent = 1 + tail;
      if (spent > best) {
        best = spent;
      }
    }
    return best;
  }

  List<int> _consumeDie(List<int> dice, int die) {
    final nextDice = List<int>.from(dice);
    final index = nextDice.indexOf(die);
    if (index >= 0) {
      nextDice.removeAt(index);
    }
    return nextDice;
  }

  void _setCooldownForMover(String moverColor) {
    final readyAt = DateTime.now().add(_cooldownDuration);
    if (moverColor == 'w') {
      _whiteReadyAt = readyAt;
      return;
    }
    _blackReadyAt = readyAt;
  }

  void _clearSelection() {
    _selectedPoint = null;
    _selectedFromBar = false;
    _legalTargetPoints = <int>{};
    _canBearOffTarget = false;
    _targetDiceSpentHints = <int, int>{};
  }

  void _cancelAiTimer() {
    _aiTurnTimer?.cancel();
    _aiTurnTimer = null;
    _aiTurnPending = false;
  }

  Duration _nextAiThinkDelay() {
    final minMs = aiThinkDelayMin.inMilliseconds;
    final maxMs = aiThinkDelayMax.inMilliseconds;
    if (maxMs <= minMs) {
      return Duration(milliseconds: minMs);
    }
    final delta = _random.nextInt(maxMs - minMs + 1);
    return Duration(milliseconds: minMs + delta);
  }

  void _resetRuntimeState({required bool activateGame}) {
    _position = SheshBeshRules.initialPosition();
    _hasActiveGame = activateGame;
    _turnColor = 'w';
    _winnerColor = null;
    _feedback = null;
    _remainingDice = <int>[];
    _currentDecision = const TurnDecision(
      legalMoves: <SheshBeshMove>[],
      maxMovesUsable: 0,
      maxUsedPips: 0,
    );
    _clearSelection();
    _playerLastMove = null;
    _opponentLastMove = null;
    _history.clear();
    final now = DateTime.now();
    _whiteReadyAt = now;
    _blackReadyAt = now;
    _turnDeadlineAt = now;
    _sourceDiceUsageHints = <int, int>{};
    _targetDiceSpentHints = <int, int>{};
  }

  static String _formatDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) {
      return '0.0s';
    }
    final halfSteps = (ms / 500).ceil();
    return '${(halfSteps / 2).toStringAsFixed(1)}s';
  }
}

enum _SelectedSource { none, point, bar }
