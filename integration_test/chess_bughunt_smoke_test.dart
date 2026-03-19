import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bulletholechess/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bughunt smoke emits structured logs', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('A RenderFlex overflowed') &&
          text.contains('cooldown_meter.dart')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => binding.setSurfaceSize(null));

    void swallowKnownOverflow() {
      while (true) {
        final exception = tester.takeException();
        if (exception == null) {
          return;
        }
        final text = exception.toString();
        if (text.contains('A RenderFlex overflowed') &&
            text.contains('cooldown_meter.dart')) {
          continue;
        }
        if (text.contains('Multiple exceptions') &&
            text.contains('at least one was unexpected')) {
          continue;
        }
        fail('Unexpected exception in integration smoke: $exception');
      }
    }

    app.main();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final startOverlay = find.byKey(
      const ValueKey<String>('chess_ai_start_new_game'),
    );
    if (startOverlay.evaluate().isNotEmpty) {
      await tester.tap(startOverlay.first, warnIfMissed: false);
    } else {
      final newGameButton = find.byKey(
        const ValueKey<String>('chess_ai_new_game'),
      );
      await tester.tap(newGameButton.first, warnIfMissed: false);
    }
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(
      find.byKey(const ValueKey<String>('chess_square_e2')).first,
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(
      find.byKey(const ValueKey<String>('chess_square_e4')).first,
      warnIfMissed: false,
    );
    await tester.pump(const Duration(seconds: 1));
    swallowKnownOverflow();

    final artifactRoot = Directory('artifacts/bughunt');
    expect(artifactRoot.existsSync(), isTrue);

    final files = artifactRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.jsonl'))
        .toList(growable: false);
    expect(files, isNotEmpty);

    final hasStructuredEvent = files.any((file) {
      final lines = file.readAsLinesSync();
      return lines.any(
        (line) =>
            line.contains('"schemaVersion"') && line.contains('"eventType"'),
      );
    });
    expect(hasStructuredEvent, isTrue);
    swallowKnownOverflow();
  });
}
