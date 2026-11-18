import 'package:forge_core/forge_core.dart';

import 'workout.dart';

/// How long a workout in progress may go without a new set before it ends
/// itself.
const workoutIdleLimit = Duration(hours: 4);

/// When [workout] ends itself: [workoutIdleLimit] after its last set was
/// ticked ([lastSetAt]), or after it started when none was.
DateTime idleEnd(Workout workout, DateTime? lastSetAt) =>
    (lastSetAt ?? workout.startedAt).add(workoutIdleLimit);

/// The notification, on this device, that a workout left open ended
/// itself: stored at its last set, or discarded without one.
abstract interface class WorkoutEndNotice {
  /// Replaces any pending notice with one at [at].
  Future<Result<void>> schedule(
    DateTime at, {
    required String title,
    required String body,
  });

  /// Cancels the pending notice, if any.
  Future<Result<void>> cancel();
}
