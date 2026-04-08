part of '../online_game_controller.dart';

extension _OnlineGameControllerHealth on OnlineGameController {
  void _applyBackendHealthResult({
    required BackendHealthResult result,
    required String eventName,
  }) {
    _backendHealthState = result.ok
        ? BackendHealthState.healthy
        : BackendHealthState.unhealthy;
    _backendHealthMessage = result.ok ? null : result.message;
    _backendHealthCheckedAt = result.checkedAt;
    _logEvent(
      eventName,
      details: <String, Object?>{
        'ok': result.ok,
        'statusCode': result.statusCode,
        'message': _backendHealthMessage,
      },
    );
  }
}
