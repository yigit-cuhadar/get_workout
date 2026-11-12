import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../domain/workout_lock_screen.dart';

/// [WorkoutLockScreen] on Android, for the rest only: an ongoing, silent
/// notification whose system chronometer counts down and which the system
/// removes at the end, on the silent `rest` channel (`NotificationsModule`),
/// waiting until notifications are initialised. Outside a rest nothing
/// shows. Shown only where the device lets the app notify; it never asks.
class AndroidWorkoutLockScreen implements WorkoutLockScreen {
  const AndroidWorkoutLockScreen(this._notifications);

  final Future<Notifications> _notifications;

  /// The countdown's id. The rest notification (1) announces the end; this
  /// one never alerts.
  static const id = 2;

  @override
  Future<Result<void>> show(LockScreenWorkout workout) async {
    final rest = workout.rest;
    if (rest == null) return clear();
    return (await _notifications).showCountdown(
      id,
      endsAt: rest.endsAt,
      title: rest.title,
      body: rest.detail,
    );
  }

  @override
  Future<Result<void>> clear() async => (await _notifications).cancel(id);

  @override
  Stream<void> taps() => const Stream.empty();
}
