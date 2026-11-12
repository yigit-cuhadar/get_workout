import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../domain/workout_lock_screen.dart';

/// [WorkoutLockScreen] on Android: ongoing, silent notifications on the
/// `rest` channel (`NotificationsModule`), whose system chronometers run
/// without the app, waiting until notifications are initialised. One shows
/// at a time: the workout ([workoutId], counting up from its start) or,
/// while a rest runs, the rest ([countdownId], counting down; the system
/// removes it at the end). The workout is scheduled to come back at the
/// rest's end, so it does even with the app suspended; under its own id,
/// since a notification replaced as the countdown times out could be
/// removed with it. Shown only where the device lets the app notify; it
/// never asks. A tap opens the app with [payload].
class AndroidWorkoutLockScreen implements WorkoutLockScreen {
  AndroidWorkoutLockScreen(this._notifications, {required this.payload});

  final Future<Notifications> _notifications;
  final String payload;

  /// The rest's countdown. The rest notification (1) announces the end;
  /// this one never alerts.
  static const countdownId = 2;
  static const workoutId = 3;

  /// Whether the rest shows, so the workout's notification is out of sight
  /// (it is then only scheduled); null when unknown, at start or after a
  /// failure.
  bool? _resting;

  @override
  Future<Result<void>> show(LockScreenWorkout workout) async {
    final notifications = await _notifications;
    final wasResting = _resting;
    _resting = null;
    final rest = workout.rest;
    final Result<void> result;
    if (rest != null) {
      result = await _all([
        () => notifications.showCountdown(
          countdownId,
          endsAt: rest.endsAt,
          title: rest.title,
          body: rest.detail,
          payload: payload,
        ),
        // Out of sight while the rest shows; replaces one scheduled before.
        if (wasResting != true) () => notifications.cancel(workoutId),
        () => notifications.scheduleStopwatch(
          workoutId,
          rest.endsAt,
          since: workout.startedAt,
          title: workout.name,
          body: workout.current,
          payload: payload,
        ),
      ]);
    } else {
      result = await _all([
        // Drops one still scheduled for the end of a rest cut short, which
        // would bring back what it showed then.
        if (wasResting != false) () => notifications.cancel(workoutId),
        () => notifications.showStopwatch(
          workoutId,
          since: workout.startedAt,
          title: workout.name,
          body: workout.current,
          payload: payload,
        ),
        () => notifications.cancel(countdownId),
      ]);
    }
    if (result.isOk) _resting = rest != null;
    return result;
  }

  @override
  Future<Result<void>> clear() async {
    final notifications = await _notifications;
    _resting = null;
    final result = await _all([
      () => notifications.cancel(countdownId),
      () => notifications.cancel(workoutId),
    ]);
    if (result.isOk) _resting = false;
    return result;
  }

  /// Taps come with the app's other notification taps, as [payload].
  @override
  Stream<void> taps() => const Stream.empty();

  /// Runs [calls] in order until one fails.
  static Future<Result<void>> _all(
    List<Future<Result<void>> Function()> calls,
  ) async {
    for (final call in calls) {
      final result = await call();
      if (!result.isOk) return result;
    }
    return const Ok(null);
  }
}
