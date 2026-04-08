import 'dart:convert';
import 'dart:io';

import 'package:chess/chess.dart' as chess;

import 'config.dart';
import 'models.dart';
import 'report_formatter.dart';

void writeWeirdLogFile(String path, List<WeirdEvent> weirdEvents) {
  final file = File(path);
  if (file.parent.path.isNotEmpty && file.parent.path != '.') {
    file.parent.createSync(recursive: true);
  }

  final buffer = StringBuffer();
  for (final weird in weirdEvents) {
    buffer.writeln(jsonEncode(weird.toJson()));
  }
  file.writeAsStringSync(buffer.toString());
}

void writeWeirdGamePgn({
  required String pgnDirPath,
  required chess.Chess game,
  required int gameIndex,
  required int seed,
  required List<WeirdEvent> weirdEventsForGame,
  required String resultTag,
}) {
  final pgnDir = Directory(pgnDirPath);
  pgnDir.createSync(recursive: true);

  final pgnGame = game.copy();
  pgnGame.set_header(<String>[
    'Event',
    'Bullethole Chess AI Duel Weird Game',
    'Site',
    'local',
    'Round',
    gameIndex.toString(),
    'White',
    'DumbAI-White',
    'Black',
    'DumbAI-Black',
    'Result',
    resultTag,
  ]);
  final pgnBody = pgnGame.pgn(<String, dynamic>{'max_width': 100});

  final eventTypes = weirdEventsForGame
      .map((event) => event.type)
      .toSet()
      .join(',');
  final fileName = 'game-${gameIndex.toString().padLeft(4, '0')}.pgn';
  final filePath = joinPath(pgnDir.path, fileName);
  final output = StringBuffer()
    ..writeln('; AI duel weird game dump')
    ..writeln('; seed: $seed')
    ..writeln('; gameIndex: $gameIndex')
    ..writeln('; weirdTypes: $eventTypes')
    ..writeln('; weirdCount: ${weirdEventsForGame.length}')
    ..writeln('; finalFen: ${game.fen}');

  for (final event in weirdEventsForGame) {
    final capAdvLabel = formatCapAdvForDisplay(event.materialAdvantageAtCap);
    output.writeln(
      '; [${event.type}] ply=${event.ply} side=${event.sideToMove} '
      'legalMoves=${event.legalMoveCount} material=${event.materialSignature}'
      '$capAdvLabel note=${event.message}',
    );
  }

  output
    ..writeln()
    ..writeln(pgnBody);

  File(filePath).writeAsStringSync(output.toString());
}

void preparePgnOutputDir(String pgnDirPath) {
  final pgnDir = Directory(pgnDirPath);
  if (!pgnDir.existsSync()) {
    pgnDir.createSync(recursive: true);
    return;
  }

  for (final entity in pgnDir.listSync(recursive: false, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.pgn')) {
      entity.deleteSync();
    }
  }
}

String resultTagForGame({
  required bool wasCapped,
  required String? winner,
  required String? terminationReason,
}) {
  if (wasCapped || terminationReason == null) {
    return '*';
  }
  if (winner == 'w') {
    return '1-0';
  }
  if (winner == 'b') {
    return '0-1';
  }
  if (terminationReason.startsWith('draw_')) {
    return '1/2-1/2';
  }
  return '*';
}
