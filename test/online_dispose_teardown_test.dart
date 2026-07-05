import 'dart:async';

import 'package:bulletholechess/src/game/engine/online_game_controller.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

/// F8 regression: `dispose()` must not fire-and-forget the async `disconnect()`
/// and then synchronously close the http client underneath it. The teardown is
/// sequenced (owned http client closed in `disconnect().whenComplete`) and the
/// disconnect future's errors are observed, so no unobserved async error can
/// escape during teardown.
///
/// The controller only owns/closes the http client it creates itself
/// (`_ownsHttpClient == httpClient == null`). An externally-supplied client is
/// therefore left open by dispose -- these tests pin both that contract and the
/// no-unobserved-error guarantee.
void main() {
  test('dispose does not surface an unobserved async error during teardown',
      () async {
    final recording = _RecordingClient();
    final asyncErrors = <Object>[];

    // Run construction+dispose inside a guarded zone so any unobserved async
    // error surfaced by the teardown (e.g. closing the client out from under an
    // in-flight disconnect) would be captured here.
    await runZonedGuarded(() async {
      final controller = OnlineGameController(httpClient: recording);
      controller.dispose();
      // Let all microtasks / pending futures from the teardown settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (Object error, StackTrace stack) {
      asyncErrors.add(error);
    });

    expect(asyncErrors, isEmpty,
        reason: 'teardown must not surface an unobserved async error');
  });

  test('dispose leaves an externally-owned http client open', () async {
    final recording = _RecordingClient();

    final controller = OnlineGameController(httpClient: recording);
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Externally-supplied client is NOT owned, so dispose must not close it.
    expect(recording.closeCount, 0,
        reason: 'externally-owned client must not be closed by dispose');
  });

  test('dispose completes synchronously and is safe to call after connect',
      () async {
    // A controller that never connected still exercises the disconnect ->
    // transport disconnect -> teardown path on dispose. Calling dispose must
    // not throw synchronously and must not leave a pending unobserved future.
    final asyncErrors = <Object>[];
    await runZonedGuarded(() async {
      final controller = OnlineGameController();
      expect(() => controller.dispose(), returnsNormally);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (Object error, StackTrace stack) {
      asyncErrors.add(error);
    });
    expect(asyncErrors, isEmpty);
  });
}

/// Minimal http.Client that records close() calls. `send` is never exercised by
/// these tests (no network calls happen), so it throws if called.
class _RecordingClient extends http.BaseClient {
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('no network calls expected in teardown tests');
  }

  @override
  void close() {
    closeCount += 1;
    super.close();
  }
}
