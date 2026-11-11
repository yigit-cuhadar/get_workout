import 'package:forge_core/forge_core.dart';

import '../../programs/domain/active_program.dart';
import 'exercise_stats.dart';
import 'workout.dart';

/// Stats as read at finishing: [current] when the server confirmed them,
/// false when they came from the device's cache and may be stale.
typedef StatsRead = ({ExerciseStats? stats, bool current});

/// Workouts that do an exercise, for rebuilding its stats; [complete] is
/// false when there were more than one query returns.
typedef ExerciseWorkouts = ({List<Workout> workouts, bool complete});

/// Finished workouts (`users/{uid}/workouts`), the stats derived from them
/// (`users/{uid}/exerciseStats`) and, when a workout moves it on, the active
/// program (`users/{uid}.activeProgram`), all written together in one batch.
///
/// Writes only start: Firestore applies them to its local cache at once and
/// sends them whenever the device is online; [isStored] tells later whether
/// the server took them. Stream errors arrive as [Failure]s.
abstract interface class WorkoutRepository {
  /// A new, unused workout id, made on the device.
  String newWorkoutId(String uid);

  /// The stats of [exerciseId], null when there are none (yet); again on
  /// every change.
  Stream<ExerciseStats?> watchStats(String uid, String exerciseId);

  /// The stats of [exerciseIds]: from the server when it answers quickly,
  /// else from the device's cache. Ids whose stats cannot be read at all
  /// (offline and never loaded on this device) are missing from the map.
  Future<Result<Map<String, StatsRead>>> getStats(
    String uid,
    List<String> exerciseIds,
  );

  /// Stores finished [workout] under its id, replaces the stats of each
  /// exercise in [stats] and, with [advance], the active program, in one
  /// batch: the server takes all of it or none.
  Future<Result<void>> saveWorkout(
    String uid,
    Workout workout,
    Map<String, ExerciseStats> stats, {
    ActiveProgram? advance,
  });

  /// Whether the server holds workout [id], once every write this device
  /// started has been answered; true after a successful [saveWorkout],
  /// false after a refused one. Waits while offline; fails when the server
  /// cannot be asked.
  Future<Result<bool>> isStored(String uid, String id);

  /// The workouts doing [exerciseId], from the server.
  Future<Result<ExerciseWorkouts>> workoutsWith(String uid, String exerciseId);

  /// Replaces the stats of [exerciseId]; null removes them.
  Future<Result<void>> saveStats(
    String uid,
    String exerciseId,
    ExerciseStats? stats,
  );
}

/// What the device keeps for a user between launches: the workout in
/// progress, finished ones the server has not confirmed yet, and the
/// exercises whose stats need rebuilding.
class LocalWorkouts extends Equatable {
  const LocalWorkouts({
    this.draft,
    this.finished = const [],
    this.staleStats = const {},
  });

  final Workout? draft;
  final List<Workout> finished;

  /// Exercise ids whose stats were computed from what the device knew, or
  /// not at all, and are rebuilt from the workouts once online.
  final Set<String> staleStats;

  LocalWorkouts copyWith({
    Workout? Function()? draft,
    List<Workout>? finished,
    Set<String>? staleStats,
  }) => LocalWorkouts(
    draft: draft != null ? draft() : this.draft,
    finished: finished ?? this.finished,
    staleStats: staleStats ?? this.staleStats,
  );

  @override
  List<Object?> get props => [draft, finished, staleStats];
}

/// [LocalWorkouts] per user on the device, so a crash or a killed app never
/// loses a set. A user only ever gets their own.
abstract interface class LocalWorkoutStore {
  /// Empty when [uid] has nothing kept. Content that cannot be read is moved
  /// aside, never overwritten, and reported as a failure; while it cannot
  /// be moved, [save] is refused.
  Future<Result<LocalWorkouts>> load(String uid);

  /// Replaces what is kept for [uid], all at once.
  Future<Result<void>> save(String uid, LocalWorkouts workouts);
}
