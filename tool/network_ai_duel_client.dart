// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bullethole_shared/bullethole_shared_runtime.dart';
import 'package:chess/chess.dart' as chess;
import 'package:http/http.dart' as http;

import 'package:bulletholechess/src/game/engine/chess_rules.dart';
import 'package:bulletholechess/src/game/engine/dumb_ai_engine.dart';

part 'network_ai_duel_client/config.dart';
part 'network_ai_duel_client/session_state_machine.dart';
part 'network_ai_duel_client/protocol_message_handler.dart';
part 'network_ai_duel_client/cooldown_forfeit_helpers.dart';
part 'network_ai_duel_client/jsonl_logger.dart';

Future<void> main(List<String> args) async {
  await runZoned(
    () async {
      final config = _Config.parse(args);
      final logger = _JsonlLogger(
        path: config.logFilePath,
        runId: config.runId,
        role: config.role,
        seed: config.seed,
      );
      await logger.log(<String, Object?>{
        'event': 'client_start',
        'at': DateTime.now().toIso8601String(),
        'backendUrl': config.backendUrl,
        'name': config.displayName,
        'seed': config.seed,
        'cooldownSeconds': config.cooldownSeconds,
      });

      final httpClient = http.Client();
      final transport = MultiplayerTransportClient(
        httpClient: httpClient,
        requestTimeout: const Duration(seconds: 10),
      );

      final session = _ChessNetworkAiSession(
        config: config,
        transport: transport,
        logger: logger,
      );

      try {
        await session.run();
      } finally {
        await transport.disconnect();
        transport.dispose();
        httpClient.close();
        await logger.close();
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (_isSuppressedNoiseLine(line)) {
          return;
        }
        parent.print(zone, line);
      },
    ),
  );
}

bool _isSuppressedNoiseLine(String line) {
  final normalized = line.trim().toLowerCase();
  return normalized == 'player is in check.' ||
      normalized == 'king of opponent player is in check.';
}
