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

/// The workouts doing each exercise, read together: from the server when it
/// answers for all of them quickly ([current]), else from the device's
/// cache, which may lack some.
typedef WorkoutsByExercise = ({
  Map<String, ExerciseWorkouts> workouts,
  bool current,
});

/// A stored workout and whether it has changes the server has not
/// confirmed yet.
typedef StoredWorkout = ({Workout workout, bool pending});

/// Where a page of the history ends. Only the repository reads [position].
final class HistoryCursor {
  const HistoryCursor(this.position);
  final Object position;
}

/// Finished workouts, newest first. [end] is the last one's place, null
/// when there is none; [more] tells that older ones may follow.
typedef HistoryPage = ({List<Workout> workouts, HistoryCursor? end, bool more});

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

  /// The stats of [exerciseIds], read together: from the server when it
  /// answers for all of them quickly, else from the device's cache. Ids whose stats cannot be read at all
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

  /// The workouts doing [exerciseId], from the server once every write
  /// this device started has been answered; waits while offline.
  Future<Result<ExerciseWorkouts>> workoutsWith(String uid, String exerciseId);

  /// Replaces the stats of [exerciseId]; null removes them.
  Future<Result<void>> saveStats(
    String uid,
    String exerciseId,
    ExerciseStats? stats,
  );

  /// The workouts doing each of [exerciseIds]; see [WorkoutsByExercise].
  Future<Result<WorkoutsByExercise>> workoutsDoing(
    String uid,
    List<String> exerciseIds,
  );

  /// One page of the finished workouts, again on every change, the
  /// device's cache first. The first page starts at the newest; a later one
  /// [after] the end of the page before it. Without [through] a page holds a
  /// fixed number of workouts; with it, every workout down to that end, so
  /// pages loaded one after another never skip or repeat one.
  Stream<HistoryPage> watchHistory(
    String uid, {
    HistoryCursor? after,
    HistoryCursor? through,
  });

  /// Workout [id], null when there is none (or it cannot be read); again on
  /// every change.
  Stream<StoredWorkout?> watchWorkout(String uid, String id);

  /// Replaces stored [workout] and the stats of each exercise in [stats]
  /// (null removes them) in one batch. Like [saveWorkout] it only starts
  /// the write; a refusal arrives on [rejectedEdits].
  Future<Result<void>> updateWorkout(
    String uid,
    Workout workout,
    Map<String, ExerciseStats?> stats,
  );

  /// Removes workout [id] and replaces [stats] as [updateWorkout] does.
  Future<Result<void>> deleteWorkout(
    String uid,
    String id,
    Map<String, ExerciseStats?> stats,
  );

  /// Edits and deletions the server refused after they had started; their
  /// change has left the device's cache again.
  Stream<Failure> get rejectedEdits;
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
