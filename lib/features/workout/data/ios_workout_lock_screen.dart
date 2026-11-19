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
/// tried again. During a rest it has −15 s, +15 s and Skip (iOS 17+),
/// labelled with [restButtons], which work without opening the app: the
/// Runner moves the rest shown at once and hands the press to
/// [restActions] on `getworkout/workout_activity_rest`, keeping it until
/// taken when the app does not run.
class IosWorkoutLockScreen implements WorkoutLockScreen {
  const IosWorkoutLockScreen({
    required this.restButtons,
    this._channel = const MethodChannel('getworkout/workout_activity'),
    this._restChannel = const MethodChannel('getworkout/workout_activity_rest'),
  });

  final ({String shorten, String extend, String skip}) Function() restButtons;
  final MethodChannel _channel;
  final MethodChannel _restChannel;

  @override
  Future<Result<void>> show(LockScreenWorkout workout) => guard(() async {
    final set = workout.set;
    final rest = workout.rest;
    final buttons = rest == null ? null : restButtons();
    final shown = await _channel.invokeMethod<bool>('show', {
      'name': workout.name,
      'startedAt': workout.startedAt.millisecondsSinceEpoch,
      'set': set == null
          ? null
          : {
              'exercise': set.exercise,
              'position': set.position,
              'line': set.line,
              'done': set.done,
            },
      'rest': rest == null || buttons == null
          ? null
          : {
              'startsAt': rest.startsAt.millisecondsSinceEpoch,
              'endsAt': rest.endsAt.millisecondsSinceEpoch,
              'title': rest.title,
              'detail': rest.detail,
              'shorten': buttons.shorten,
              'extend': buttons.extend,
              'skip': buttons.skip,
            },
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

  /// Presses while the app did not run, or before this listened, are
  /// taken when listening starts; later ones the Runner sends as
  /// "restAction".
  @override
  Stream<LockScreenRestAction> restActions() {
    late final StreamController<LockScreenRestAction> controller;
    void add(Object? name) {
      final action = LockScreenRestAction.values.asNameMap()[name];
      if (action != null) controller.add(action);
    }

    Future<void> takeKept() async {
      try {
        final kept = await _restChannel.invokeListMethod<String>(
          'takeRestActions',
        );
        kept?.forEach(add);
      } on PlatformException catch (error) {
        Log.e(
          'workout',
          'Live Activity rest presses not taken: '
              '${error.message}',
        );
      }
    }

    controller = StreamController(
      onListen: () {
        _restChannel.setMethodCallHandler((call) async {
          if (call.method == 'restAction') add(call.arguments);
        });
        unawaited(takeKept());
      },
      onCancel: () => _restChannel.setMethodCallHandler(null),
    );
    return controller.stream;
  }
}
