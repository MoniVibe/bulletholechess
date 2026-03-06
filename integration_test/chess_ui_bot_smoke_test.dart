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

void main() {
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

Future<void> _enterOnlineModeAndFindMatch(WidgetTester tester) async {
  final onlineTab = find.text('Online');
  expect(onlineTab, findsWidgets);
  await tester.tap(onlineTab.first);
  await tester.pump(const Duration(milliseconds: 300));

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

  await tester.tap(backendField);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.enterText(backendField, _backendUrl);
  await tester.pump(const Duration(milliseconds: 120));

  await tester.tap(nameField);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.enterText(nameField, _displayName);
  await tester.pump(const Duration(milliseconds: 120));

  await tester.tap(findMatchButton);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _startLocalGame(WidgetTester tester) async {
  final startOverlay = find.byKey(
    const ValueKey<String>('chess_ai_start_new_game'),
  );
  if (startOverlay.evaluate().isNotEmpty) {
    await tester.tap(startOverlay.first);
    await tester.pump(const Duration(milliseconds: 300));
    return;
  }

  final newGameButton = find.byKey(const ValueKey<String>('chess_ai_new_game'));
  if (newGameButton.evaluate().isNotEmpty) {
    await tester.tap(newGameButton.first);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<int> _playChessMoves(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: _maxSeconds));
  final idleLimit = const Duration(seconds: _idleSeconds);
  var lastProgressAt = DateTime.now();
  var moves = 0;

  while (DateTime.now().isBefore(deadline) && moves < _maxMoves) {
    final moved = await _attemptChessMove(tester);
    if (moved) {
      moves += 1;
      lastProgressAt = DateTime.now();
      await tester.pump(const Duration(milliseconds: 250));
      continue;
    }

    await tester.pump(const Duration(milliseconds: 250));
    if (DateTime.now().difference(lastProgressAt) >= idleLimit) {
      break;
    }
  }

  return moves;
}

Future<bool> _attemptChessMove(WidgetTester tester) async {
  for (final source in _allSquares) {
    final sourceFinder = find.byKey(ValueKey<String>('chess_square_$source'));
    if (sourceFinder.evaluate().isEmpty) {
      continue;
    }

    await tester.tap(sourceFinder.first);
    await tester.pump(const Duration(milliseconds: 100));

    final targets = _keyValuesWithPrefix(tester, 'chess_target_')
        .map((value) => value.substring('chess_target_'.length))
        .where((square) => square.length == 2)
        .toList(growable: false);
    if (targets.isEmpty) {
      continue;
    }

    final target = targets.first;
    final targetFinder = find.byKey(ValueKey<String>('chess_square_$target'));
    if (targetFinder.evaluate().isEmpty) {
      continue;
    }

    await tester.tap(targetFinder.first);
    await tester.pump(const Duration(milliseconds: 150));
    return true;
  }

  return false;
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

final List<String> _allSquares = <String>[
  for (final rank in <String>['1', '2', '3', '4', '5', '6', '7', '8'])
    for (final file in <String>['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'])
      '$file$rank',
];
