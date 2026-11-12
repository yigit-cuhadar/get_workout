import 'dart:async';

import 'package:flutter/services.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/workout_lock_screen.dart';

/// [WorkoutLockScreen] on iOS: one Live Activity for the whole workout,
/// through the Runner's `getworkout/workout_activity` channel
/// (`AppDelegate.swift`), drawn by the `RestTimer` widget extension. It
/// shows the workout, or the rest while one runs; a rest's end is its
/// stale date, from which it shows the workout again by itself, so a rest
/// that ends while the app is suspended needs no update. Below iOS 16.2
/// nothing shows and nothing fails; with Live Activities turned off, or
/// while the app may not start one (not active), a show fails, so it is
/// tried again.
class IosWorkoutLockScreen implements WorkoutLockScreen {
  const IosWorkoutLockScreen([
    this._channel = const MethodChannel('getworkout/workout_activity'),
  ]);

  final MethodChannel _channel;

  @override
  Future<Result<void>> show(LockScreenWorkout workout) => guard(() async {
    final rest = workout.rest;
    final shown = await _channel.invokeMethod<bool>('show', {
      'name': workout.name,
      'startedAt': workout.startedAt.millisecondsSinceEpoch,
      'current': workout.current,
      'restEndsAt': rest?.endsAt.millisecondsSinceEpoch,
      'restTitle': rest?.title,
      'restDetail': rest?.detail,
    });
    if (shown == false) {
      throw const UnknownFailure('Live Activity not shown: turned off');
    }
  });

  @override
  Future<Result<void>> clear() =>
      guard(() => _channel.invokeMethod<void>('end'));

  /// The Runner keeps a tap until it is taken, so one that launched the app
  /// before this listened is not lost: taken when listening starts and
  /// whenever the Runner says "tapped".
  @override
  Stream<void> taps() {
    late final StreamController<void> controller;
    Future<void> take() async {
      try {
        if (await _channel.invokeMethod<bool>('takeTap') ?? false) {
          controller.add(null);
        }
      } on PlatformException catch (error) {
        Log.e('workout', 'Live Activity tap not taken: ${error.message}');
      }
    }

    controller = StreamController(
      onListen: () {
        _channel.setMethodCallHandler((call) async {
          if (call.method == 'tapped') await take();
        });
        unawaited(take());
      },
      onCancel: () => _channel.setMethodCallHandler(null),
    );
    return controller.stream;
  }
}
