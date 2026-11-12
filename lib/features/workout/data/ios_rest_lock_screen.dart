import 'package:flutter/services.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/rest_lock_screen.dart';

/// [RestLockScreen] on iOS: a Live Activity, through the Runner's
/// `getworkout/rest_activity` channel (`AppDelegate.swift`), drawn by the
/// `RestTimer` widget extension. The system counts down to the end and,
/// should the app be suspended then, shows [RestCountdown.over] from the
/// end on (its stale date). Below iOS 16.2 nothing shows and nothing
/// fails; with Live Activities turned off, or while the app may not start
/// one (not active), a show fails, so it is tried again.
class IosRestLockScreen implements RestLockScreen {
  const IosRestLockScreen([
    this._channel = const MethodChannel('getworkout/rest_activity'),
  ]);

  final MethodChannel _channel;

  @override
  Future<Result<void>> show(RestCountdown countdown) => guard(() async {
    final shown = await _channel.invokeMethod<bool>('show', {
      'endsAt': countdown.endsAt.millisecondsSinceEpoch,
      'title': countdown.title,
      'detail': countdown.detail,
      'over': countdown.over,
    });
    if (shown == false) {
      throw const UnknownFailure('Live Activity not shown: turned off');
    }
  });

  @override
  Future<Result<void>> clear() =>
      guard(() => _channel.invokeMethod<void>('end'));
}
