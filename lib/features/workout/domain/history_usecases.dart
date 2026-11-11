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

/// Stores a [WorkoutChange] in one batch that also works offline, never
/// changing the active program. Returns the exercises it touched, before
/// and after: their stats must then be rebuilt from the server's workouts,
/// which also repairs a rebuild that read before this change and wrote
/// after it.
///
/// The batch carries those stats rebuilt (see [rebuildStats]) only for the
/// exercises whose workouts the server returned in full; stats read from
/// the cache, which may lack workouts, or of an exercise with more workouts
/// than can be read, are left as they are until then. The rebuild leaves
/// the latter too, so they may stay stale.
///
/// The new version keeps only its done sets, like a finished workout, and
/// is refused with a [ValidationFailure] for any [changeIssue].
class SaveWorkoutChange implements UseCase<Set<String>, WorkoutChange> {
  SaveWorkoutChange(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final WorkoutRepository _repository;
  final DateTime Function() _clock;

  @override
  Future<Result<Set<String>>> call(WorkoutChange params) async {
    final before = params.before;
    final changed = params.after;
    if (changed != null) {
      if (changeIssue(changed, _clock()) case final issue?) {
        return Err(ValidationFailure(issue.name));
      }
    }
    final after = changed == null
        ? null
        : finishWorkout(changed, changed.finishedAt ?? changed.startedAt);
    final id = after?.id ?? before?.id;
    if (id == null) return const Ok({});
    final exerciseIds = [
      ...{...?before?.exerciseIds, ...?after?.exerciseIds},
    ];
    final read = await _repository.workoutsDoing(params.uid, exerciseIds);
    if (read case Err(:final failure)) return Err(failure);
    final (:workouts, :current) = read.valueOrNull!;
    final stats = <String, ExerciseStats?>{};
    for (final exerciseId in exerciseIds) {
      final known = workouts[exerciseId]!;
      if (!current || !known.complete) continue;
      stats[exerciseId] = rebuildStats(exerciseId, [
        for (final workout in known.workouts)
          if (workout.id != id) workout,
        ?after,
      ]);
    }
    final saved = after == null
        ? await _repository.deleteWorkout(params.uid, id, stats)
        : await _repository.updateWorkout(params.uid, after, stats);
    return saved.map((_) => exerciseIds.toSet());
  }
}
