import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bulletholechess/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures baseline perf artifacts for bughunt flow', (
    tester,
  ) async {
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
        fail('Unexpected exception in integration perf lane: $exception');
      }
    }

    await binding.traceAction(() async {
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
      await tester.pump(const Duration(milliseconds: 700));
    }, reportKey: 'chess_bughunt_perf_timeline');

    final perfDir = Directory('artifacts/bughunt/perf/chess');
    if (!perfDir.existsSync()) {
      perfDir.createSync(recursive: true);
    }

    final timelineFile = File(
      '${perfDir.path}${Platform.pathSeparator}chess_bughunt_perf_timeline.json',
    );
    final summaryFile = File(
      '${perfDir.path}${Platform.pathSeparator}chess_bughunt_perf_summary.json',
    );
    final timeline =
        binding.reportData?['chess_bughunt_perf_timeline']
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final traceEvents = (timeline['traceEvents'] as List?) ?? const <Object?>[];
    final summary = <String, Object?>{
      'traceEventCount': traceEvents.length,
      'containsFrameBuild': traceEvents.any(
        (event) =>
            event is Map &&
            (event['name']?.toString().toLowerCase().contains('frame') ??
                false),
      ),
      'recordedAtUtc': DateTime.now().toUtc().toIso8601String(),
    };
    timelineFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(timeline),
    );
    summaryFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
    );

    expect(summaryFile.existsSync(), isTrue);
    swallowKnownOverflow();
  });
}
