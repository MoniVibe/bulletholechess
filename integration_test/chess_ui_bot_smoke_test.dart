import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bulletholechess/main.dart' as app;

const bool _runOnline = bool.fromEnvironment(
  'UI_BOT_ONLINE',
  defaultValue: false,
);
const String _backendUrl = String.fromEnvironment(
  'BOT_BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);
const String _displayName = String.fromEnvironment(
  'BOT_NAME',
  defaultValue: 'ChessUiBot',
);
const int _maxMoves = int.fromEnvironment('BOT_MAX_MOVES', defaultValue: 10);
const int _maxSeconds = int.fromEnvironment(
  'BOT_MAX_SECONDS',
  defaultValue: 180,
);
const int _idleSeconds = int.fromEnvironment(
  'BOT_IDLE_SECONDS',
  defaultValue: 45,
);
const int _startupSeconds = int.fromEnvironment(
  'BOT_STARTUP_SECONDS',
  defaultValue: 90,
);

void main() {
  _installWindowsKeyboardAssertionGuard();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UI bot smoke for chess', (tester) async {
    await binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => binding.setSurfaceSize(null));

    app.main();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    if (_runOnline) {
      await _enterOnlineModeAndFindMatch(tester);
    } else {
      await _startLocalGame(tester);
    }

    final movesPlayed = await _playChessMoves(tester);
    debugPrint(
      '[UI-BOT][CHESS] mode=${_runOnline ? 'online' : 'local'} moves=$movesPlayed',
    );
    expect(
      movesPlayed,
      greaterThan(0),
      reason: 'Bot did not execute any UI move within time budget.',
    );
  });
}

void _installWindowsKeyboardAssertionGuard() {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains(
      'Attempted to send a key down event when no keys are in keysPressed',
    )) {
      debugPrint('[UI-BOT][CHESS] ignored windows keyboard assertion');
      return;
    }
    previous?.call(details);
  };

  final previousPlatform = ui.PlatformDispatcher.instance.onError;
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    final message = error.toString();
    if (message.contains(
      'Attempted to send a key down event when no keys are in keysPressed',
    )) {
      debugPrint('[UI-BOT][CHESS] ignored windows keyboard assertion');
      return true;
    }
    if (previousPlatform != null) {
      return previousPlatform(error, stack);
    }
    return false;
  };
}

Future<void> _enterOnlineModeAndFindMatch(WidgetTester tester) async {
  final modeSwitch = find.byKey(const ValueKey<String>('chess_mode_switch'));
  if (modeSwitch.evaluate().isNotEmpty) {
    final dynamic widget = tester.widget(modeSwitch.first);
    widget.onChanged?.call(true);
    await tester.pump(const Duration(milliseconds: 250));
  } else {
    final onlineTab = find.text('Online');
    expect(onlineTab, findsWidgets);
    await _activateWidget(tester, onlineTab.first);
    await tester.pump(const Duration(milliseconds: 250));
  }

  final backendField = find.byKey(
    const ValueKey<String>('chess_online_backend_url'),
  );
  final nameField = find.byKey(
    const ValueKey<String>('chess_online_display_name'),
  );
  final findMatchButton = find.byKey(
    const ValueKey<String>('chess_online_find_match'),
  );

  expect(backendField, findsOneWidget);
  expect(nameField, findsOneWidget);
  expect(findMatchButton, findsOneWidget);

  final backendTextField = tester.widget<TextField>(backendField);
  backendTextField.controller?.text = _backendUrl;
  await tester.pump(const Duration(milliseconds: 120));

  final nameTextField = tester.widget<TextField>(nameField);
  nameTextField.controller?.text = _displayName;
  await tester.pump(const Duration(milliseconds: 120));

  await _activateWidget(tester, findMatchButton.first);
  await tester.pump(const Duration(milliseconds: 300));

  final disconnectButton = find.byKey(
    const ValueKey<String>('chess_online_disconnect'),
  );
  final requestNewGameButton = find.byKey(
    const ValueKey<String>('chess_online_new_game'),
  );
  final connectDeadline = DateTime.now().add(
    const Duration(seconds: _startupSeconds),
  );
  var requestedNewGame = false;
  while (DateTime.now().isBefore(connectDeadline)) {
    var connected = false;
    if (disconnectButton.evaluate().isNotEmpty) {
      final disconnect = tester.widget<OutlinedButton>(disconnectButton.first);
      connected = disconnect.onPressed != null;
    }

    if (!connected) {
      final findMatch = tester.widget<FilledButton>(findMatchButton.first);
      if (findMatch.onPressed != null) {
        await _activateWidget(tester, findMatchButton.first);
        await tester.pump(const Duration(milliseconds: 450));
        continue;
      }
    } else {
      if (!requestedNewGame && requestNewGameButton.evaluate().isNotEmpty) {
        final button = tester.widget<OutlinedButton>(
          requestNewGameButton.first,
        );
        if (button.onPressed != null) {
          await _activateWidget(tester, requestNewGameButton.first);
          requestedNewGame = true;
        }
      }
      if (requestedNewGame) {
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _startLocalGame(WidgetTester tester) async {
  final startOverlay = find.byKey(
    const ValueKey<String>('chess_ai_start_new_game'),
  );
  if (startOverlay.evaluate().isNotEmpty) {
    await _activateWidget(tester, startOverlay.first);
    await tester.pump(const Duration(milliseconds: 300));
    return;
  }

  final newGameButton = find.byKey(const ValueKey<String>('chess_ai_new_game'));
  if (newGameButton.evaluate().isNotEmpty) {
    await _activateWidget(tester, newGameButton.first);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<int> _playChessMoves(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: _maxSeconds));
  final idleLimit = const Duration(seconds: _idleSeconds);
  final startupDeadline = DateTime.now().add(
    const Duration(seconds: _startupSeconds),
  );
  var lastProgressAt = DateTime.now();
  var moves = 0;
  _BotMove? lastMove;
  final moveUsage = <String, int>{};
  var scanOffset = 0;

  while (DateTime.now().isBefore(deadline) && moves < _maxMoves) {
    if (_runOnline &&
        moves > 0 &&
        _isWaitingForOpponentOverlayVisible(tester)) {
      break;
    }

    if (_runOnline) {
      await _clearQueuedMoveIfAny(tester);
    }
    final moved = await _attemptChessMove(
      tester,
      avoidReverseOf: lastMove,
      moveUsage: moveUsage,
      scanOffset: scanOffset,
    );
    if (moved != null) {
      moves += 1;
      lastMove = moved;
      final key = '${moved.from}->${moved.to}';
      moveUsage[key] = (moveUsage[key] ?? 0) + 1;
      scanOffset = (scanOffset + 11) % _allSquares.length;
      lastProgressAt = DateTime.now();
      await tester.pump(const Duration(milliseconds: 250));
      continue;
    }
    if (_runOnline) {
      await _clearQueuedMoveIfAny(tester);
    }

    await tester.pump(const Duration(milliseconds: 250));
    final now = DateTime.now();
    final enforceIdle = moves > 0 || now.isAfter(startupDeadline);
    if (enforceIdle && now.difference(lastProgressAt) >= idleLimit) {
      break;
    }
  }

  return moves;
}

Future<_BotMove?> _attemptChessMove(
  WidgetTester tester, {
  _BotMove? avoidReverseOf,
  required Map<String, int> moveUsage,
  required int scanOffset,
}) async {
  final orderedSquares = <String>[
    ..._allSquares.skip(scanOffset),
    ..._allSquares.take(scanOffset),
  ];
  for (final source in orderedSquares) {
    final sourceFinder = find.byKey(ValueKey<String>('chess_square_$source'));
    if (sourceFinder.evaluate().isEmpty) {
      continue;
    }

    await _activateWidget(tester, sourceFinder.first);
    await tester.pump(const Duration(milliseconds: 100));

    final occupancyBeforeTap = _occupiedSquares(tester);
    final targets = _targetSquares(tester)
        .map((value) => value.substring('chess_target_'.length))
        .where((square) => square.length == 2)
        .toList(growable: false);
    if (targets.isEmpty) {
      continue;
    }

    final candidates = List<String>.from(targets);
    if (avoidReverseOf != null && candidates.length > 1) {
      candidates.removeWhere(
        (candidate) =>
            source == avoidReverseOf.to && candidate == avoidReverseOf.from,
      );
      if (candidates.isEmpty) {
        candidates.addAll(targets);
      }
    }

    final underRepeatLimit = candidates
        .where((candidate) => (moveUsage['$source->$candidate'] ?? 0) < 3)
        .toList(growable: false);
    final candidatePool = underRepeatLimit.isNotEmpty
        ? underRepeatLimit
        : candidates;

    final orderedTargets = List<String>.from(candidatePool)
      ..sort(
        (left, right) => (moveUsage['$source->$left'] ?? 0).compareTo(
          moveUsage['$source->$right'] ?? 0,
        ),
      );
    if (orderedTargets.isEmpty) {
      continue;
    }
    final target = orderedTargets.first;
    final targetFinder = find.byKey(ValueKey<String>('chess_square_$target'));
    if (targetFinder.evaluate().isEmpty) {
      continue;
    }

    await _activateWidget(tester, targetFinder.first);
    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 120));
      final occupancyAfterTap = _occupiedSquares(tester);
      if (!_sameStringSet(occupancyBeforeTap, occupancyAfterTap)) {
        return _BotMove(from: source, to: target);
      }
    }
  }

  return null;
}

bool _isWaitingForOpponentOverlayVisible(WidgetTester tester) {
  final waitingText = find.text('Waiting for opponent...');
  return waitingText.evaluate().isNotEmpty;
}

Set<String> _targetSquares(WidgetTester tester) =>
    _keyValuesWithPrefix(tester, 'chess_target_').toSet();

Set<String> _occupiedSquares(WidgetTester tester) {
  final occupied = <String>{};
  for (final square in _allSquares) {
    final squareFinder = find.byKey(ValueKey<String>('chess_square_$square'));
    if (squareFinder.evaluate().isEmpty) {
      continue;
    }
    final pieceFinder = find.descendant(
      of: squareFinder.first,
      matching: find.byType(OverflowBox),
    );
    if (pieceFinder.evaluate().isNotEmpty) {
      occupied.add(square);
    }
  }
  return occupied;
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final value in left) {
    if (!right.contains(value)) {
      return false;
    }
  }
  return true;
}

List<String> _keyValuesWithPrefix(WidgetTester tester, String prefix) {
  final values = <String>{};
  final finder = find.byWidgetPredicate(
    (widget) => widget.key is ValueKey<String>,
  );

  for (final element in finder.evaluate()) {
    final key = element.widget.key;
    if (key is! ValueKey<String>) {
      continue;
    }
    final value = key.value;
    if (value.startsWith(prefix)) {
      values.add(value);
    }
  }

  final list = values.toList(growable: false)..sort();
  return list;
}

Future<void> _clearQueuedMoveIfAny(WidgetTester tester) async {
  final clearQueueText = find.byWidgetPredicate((widget) {
    if (widget is! Text) {
      return false;
    }
    final data = widget.data;
    return data != null && data.startsWith('Clear Queue');
  });
  if (clearQueueText.evaluate().isEmpty) {
    return;
  }
  await _activateWidget(tester, clearQueueText.first);
  await tester.pump(const Duration(milliseconds: 120));
}

class _BotMove {
  const _BotMove({required this.from, required this.to});

  final String from;
  final String to;
}

final List<String> _allSquares = <String>[
  for (final rank in <String>['1', '2', '3', '4', '5', '6', '7', '8'])
    for (final file in <String>['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'])
      '$file$rank',
];

Future<void> _activateWidget(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    return;
  }
  final widget = tester.widget(finder.first);
  if (widget is InkWell && widget.onTap != null) {
    widget.onTap!.call();
    await tester.pump(const Duration(milliseconds: 80));
    return;
  }
  if (widget is FilledButton && widget.onPressed != null) {
    widget.onPressed!.call();
    await tester.pump(const Duration(milliseconds: 80));
    return;
  }
  if (widget is OutlinedButton && widget.onPressed != null) {
    widget.onPressed!.call();
    await tester.pump(const Duration(milliseconds: 80));
    return;
  }

  try {
    await tester.ensureVisible(finder.first);
  } catch (_) {}
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 80));
}
