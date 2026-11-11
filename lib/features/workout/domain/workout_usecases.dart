import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program_usecases.dart';
import 'exercise_stats.dart';
import 'set_logging.dart';
import 'workout.dart';
import 'workout_editing.dart';
import 'workout_repository.dart';

typedef WorkoutDraft = ({String uid, Workout workout});
typedef StatsRef = ({String uid, String exerciseId});

/// The stored workout and what it amounted to.
typedef FinishedWorkout = ({Workout workout, WorkoutSummary summary});

/// [catalogue] has the live exercises by id.
typedef WorkoutAsProgram = ({
  String uid,
  Workout workout,
  String name,
  Map<String, Exercise> catalogue,
});

class LoadActiveWorkout implements UseCase<Workout?, String> {
  const LoadActiveWorkout(this._store);
  final ActiveWorkoutStore _store;

  /// [params] is the user's id.
  @override
  Future<Result<Workout?>> call(String params) => _store.load(params);
}

class KeepActiveWorkout implements UseCase<void, WorkoutDraft> {
  const KeepActiveWorkout(this._store);
  final ActiveWorkoutStore _store;

  @override
  Future<Result<void>> call(WorkoutDraft params) =>
      _store.save(params.uid, params.workout);
}

class ClearActiveWorkout implements UseCase<void, String> {
  const ClearActiveWorkout(this._store);
  final ActiveWorkoutStore _store;

  /// [params] is the user's id.
  @override
  Future<Result<void>> call(String params) => _store.clear(params);
}

class NewWorkoutId {
  const NewWorkoutId(this._repository);
  final WorkoutRepository _repository;

  String call(String uid) => _repository.newWorkoutId(uid);
}

class WatchExerciseStats {
  const WatchExerciseStats(this._repository);
  final WorkoutRepository _repository;

  Stream<ExerciseStats?> call(StatsRef ref) =>
      _repository.watchStats(ref.uid, ref.exerciseId);
}

class WatchRejectedWorkoutWrites {
  const WatchRejectedWorkoutWrites(this._repository);
  final WorkoutRepository _repository;

  Stream<Failure> call() => _repository.rejectedWrites;
}

/// Finishes the workout in progress now (see [finishWorkout]) and stores it
/// with each exercise's stats updated, in one batch that also works
/// offline. Refused with a [ValidationFailure] when no set is done, a
/// done set is invalid or the workout exceeds its limits.
///
/// Firestore transactions need the server, so the stats are computed from
/// what the device knows. Stats that cannot be read at all (offline, never
/// loaded here) are left alone rather than overwritten with this workout's
/// alone; rebuilding them from the workouts catches up.
class FinishWorkout implements UseCase<FinishedWorkout, WorkoutDraft> {
  FinishWorkout(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final WorkoutRepository _repository;
  final DateTime Function() _clock;

  @override
  Future<Result<FinishedWorkout>> call(WorkoutDraft params) async {
    final workout = finishWorkout(params.workout, _clock());
    if (workout.exercises.isEmpty) {
      return const Err(ValidationFailure('no done set'));
    }
    final invalid = workout.exercises.any(
      (e) => e.sets.any((s) => validateSet(s, e.loggingType).isNotEmpty),
    );
    if (invalid || !fitsLimits(workout)) {
      return const Err(ValidationFailure('invalid workout'));
    }
    final read = await _repository.getStats(params.uid, workout.exerciseIds);
    if (read case Err(:final failure)) return Err(failure);
    final before = read.valueOrNull!;
    final after = <String, ExerciseStats>{};
    final records = <NewRecord>[];
    for (final id in workout.exerciseIds) {
      if (!before.containsKey(id)) {
        Log.e('workout', 'stats of $id unreadable; left as they are');
        continue;
      }
      final updated = applyWorkout(before[id], workout, id);
      if (updated == null) continue;
      after[id] = updated;
      final name = workout.exercises.firstWhere((e) => e.exerciseId == id).name;
      for (final kind in beatenRecords(before[id], updated, workout)) {
        records.add(
          NewRecord(
            exerciseId: id,
            name: name,
            kind: kind,
            value: updated.records[kind]!.value,
          ),
        );
      }
    }
    final saved = await _repository.saveWorkout(params.uid, workout, after);
    return saved.map(
      (_) => (workout: workout, summary: summarizeWorkout(workout, records)),
    );
  }
}

/// Stores a finished workout as a one-day program of the user's own (see
/// [programFromWorkout]) and returns its id; refused like [SaveProgram]
/// when the program would not be valid.
class SaveWorkoutAsProgram implements UseCase<String, WorkoutAsProgram> {
  const SaveWorkoutAsProgram(this._saveProgram);
  final SaveProgram _saveProgram;

  @override
  Future<Result<String>> call(WorkoutAsProgram params) => _saveProgram((
    uid: params.uid,
    program: programFromWorkout(
      params.workout,
      name: params.name,
      catalogue: params.catalogue,
    ),
    loggingTypes: <String, LoggingType>{
      for (final MapEntry(:key, :value) in params.catalogue.entries)
        key: value.loggingType,
    },
  ));
}
