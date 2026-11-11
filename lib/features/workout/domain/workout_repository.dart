import 'package:forge_core/forge_core.dart';

import 'exercise_stats.dart';
import 'workout.dart';

/// Finished workouts (`users/{uid}/workouts`) and the stats derived from
/// them (`users/{uid}/exerciseStats`), together because a workout and its
/// stats are written in one batch.
///
/// Writes only start: Firestore applies them to its local cache at once and
/// sends them whenever the device is online. A write the server refuses
/// later arrives on [rejectedWrites]. Stream errors arrive as [Failure]s.
abstract interface class WorkoutRepository {
  /// A new, unused workout id, made on the device.
  String newWorkoutId(String uid);

  /// The stats of [exerciseId], null when there are none (yet); again on
  /// every change.
  Stream<ExerciseStats?> watchStats(String uid, String exerciseId);

  /// The current stats of [exerciseIds], read from the local cache, or from
  /// the server for those not cached. Ids whose stats cannot be read now
  /// (offline and never loaded on this device) are missing from the map;
  /// null means there are none.
  Future<Result<Map<String, ExerciseStats?>>> getStats(
    String uid,
    List<String> exerciseIds,
  );

  /// Stores finished [workout] under its id and replaces the stats of each
  /// exercise in [stats], in one batch.
  Future<Result<void>> saveWorkout(
    String uid,
    Workout workout,
    Map<String, ExerciseStats> stats,
  );

  Stream<Failure> get rejectedWrites;
}

/// The workout in progress, kept on the device for each user so a crash or
/// a killed app never loses a set. A user only ever gets their own.
abstract interface class ActiveWorkoutStore {
  /// Null when [uid] has none.
  Future<Result<Workout?>> load(String uid);

  /// Replaces [uid]'s workout in progress.
  Future<Result<void>> save(String uid, Workout workout);

  Future<Result<void>> clear(String uid);
}
