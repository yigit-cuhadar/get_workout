import 'package:forge_core/forge_core.dart';

import 'exercise_stats.dart';
import 'workout.dart';
import 'workout_editing.dart';
import 'workout_repository.dart';
import 'workout_usecases.dart';

typedef HistoryQuery = ({
  String uid,
  HistoryCursor? after,
  HistoryCursor? through,
});

/// A change to the stored workouts: [after] added (no [before]), [before]
/// replaced by [after], or [before] deleted (no [after]).
typedef WorkoutChange = ({String uid, Workout? before, Workout? after});

class WatchHistory {
  const WatchHistory(this._repository);
  final WorkoutRepository _repository;

  Stream<HistoryPage> call(HistoryQuery query) => _repository.watchHistory(
    query.uid,
    after: query.after,
    through: query.through,
  );
}

class WatchStoredWorkout {
  const WatchStoredWorkout(this._repository);
  final WorkoutRepository _repository;

  Stream<StoredWorkout?> call(WorkoutRef ref) =>
      _repository.watchWorkout(ref.uid, ref.id);
}

class WatchRejectedWorkoutEdits {
  const WatchRejectedWorkoutEdits(this._repository);
  final WorkoutRepository _repository;

  Stream<Failure> call() => _repository.rejectedEdits;
}

/// Stores a [WorkoutChange] with the stats of every exercise it touches,
/// before and after, rebuilt from that exercise's workouts (see
/// [rebuildStats]), in one batch that also works offline. The active
/// program is never changed. Returns the exercises whose stats need
/// rebuilding later because their workouts came from the device's cache.
///
/// The new version keeps only its done sets, like a finished workout, and
/// is refused with a [ValidationFailure] when none is left, a set is
/// invalid or it exceeds its limits. Stats of an exercise with more
/// workouts than can be read are left as they are, as a rebuild leaves
/// them.
class SaveWorkoutChange implements UseCase<Set<String>, WorkoutChange> {
  const SaveWorkoutChange(this._repository);
  final WorkoutRepository _repository;

  @override
  Future<Result<Set<String>>> call(WorkoutChange params) async {
    final before = params.before;
    final changed = params.after;
    final after = changed == null
        ? null
        : finishWorkout(changed, changed.finishedAt ?? changed.startedAt);
    final id = after?.id ?? before?.id;
    if (id == null) return const Ok({});
    if (after != null && after.exercises.isEmpty) {
      return const Err(ValidationFailure('no done set'));
    }
    if (after != null && !isStorable(after)) {
      return const Err(ValidationFailure('invalid workout'));
    }
    final exerciseIds = [
      ...{...?before?.exerciseIds, ...?after?.exerciseIds},
    ];
    final read = await _repository.workoutsDoing(params.uid, exerciseIds);
    if (read case Err(:final failure)) return Err(failure);
    final (:workouts, :current) = read.valueOrNull!;
    final stats = <String, ExerciseStats?>{};
    for (final exerciseId in exerciseIds) {
      final known = workouts[exerciseId]!;
      if (!known.complete) {
        Log.e('workout', 'too many workouts to rebuild $exerciseId');
        continue;
      }
      stats[exerciseId] = rebuildStats(exerciseId, [
        for (final workout in known.workouts)
          if (workout.id != id) workout,
        ?after,
      ]);
    }
    final saved = after == null
        ? await _repository.deleteWorkout(params.uid, id, stats)
        : await _repository.updateWorkout(params.uid, after, stats);
    return saved.map((_) => current ? <String>{} : stats.keys.toSet());
  }
}
