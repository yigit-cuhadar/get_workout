import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/active_program.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_schedule.dart';
import '../../programs/domain/program_usecases.dart';
import 'exercise_stats.dart';
import 'workout.dart';
import 'workout_editing.dart';
import 'workout_end_notice.dart';
import 'workout_lock_screen.dart';
import 'workout_repository.dart';

typedef StatsRef = ({String uid, String exerciseId});
typedef WorkoutRef = ({String uid, String id});
typedef LocalWorkoutsSave = ({String uid, LocalWorkouts workouts});

/// The active program and that program as the device knows them when a
/// workout finishes.
typedef KnownProgram = ({ActiveProgram? active, Program? program});

/// [program] is null when the programs are not known (yet).
/// [at] ends the workout at that time instead of now, as when it ended
/// itself (see [idleEnd]).
typedef WorkoutFinish = ({
  String uid,
  Workout workout,
  KnownProgram? program,
  DateTime? at,
});

/// The stored workout, what it amounted to, the exercises whose stats
/// need rebuilding (those not confirmed by the server at finishing), and
/// the user's finished workouts with it; null when the server could not
/// count them.
typedef FinishedWorkout = ({
  Workout workout,
  WorkoutSummary summary,
  Set<String> staleStats,
  int? workoutCount,
});

/// [catalogue] has the live exercises by id.
typedef WorkoutAsProgram = ({
  String uid,
  Workout workout,
  String name,
  Map<String, Exercise> catalogue,
});

/// Day [dayIndex] of [program] gets [items]; see `changedProgramDay`.
typedef ProgramDayUpdate = ({
  String uid,
  Program program,
  int dayIndex,
  List<ProgramItem> items,
  Map<String, Exercise> catalogue,
});

/// A [WorkoutEndNotice] at [at].
typedef EndNotice = ({DateTime at, String title, String body});

class ScheduleWorkoutEndNotice implements UseCase<void, EndNotice> {
  const ScheduleWorkoutEndNotice(this._notice);
  final WorkoutEndNotice _notice;

  @override
  Future<Result<void>> call(EndNotice params) =>
      _notice.schedule(params.at, title: params.title, body: params.body);
}

class CancelWorkoutEndNotice implements UseCase<void, NoParams> {
  const CancelWorkoutEndNotice(this._notice);
  final WorkoutEndNotice _notice;

  @override
  Future<Result<void>> call(NoParams params) => _notice.cancel();
}

class LoadLocalWorkouts implements UseCase<LocalWorkouts, String> {
  const LoadLocalWorkouts(this._store);
  final LocalWorkoutStore _store;

  /// [params] is the user's id.
  @override
  Future<Result<LocalWorkouts>> call(String params) => _store.load(params);
}

class KeepLocalWorkouts implements UseCase<void, LocalWorkoutsSave> {
  const KeepLocalWorkouts(this._store);
  final LocalWorkoutStore _store;

  @override
  Future<Result<void>> call(LocalWorkoutsSave params) =>
      _store.save(params.uid, params.workouts);
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

class WatchAllExerciseStats {
  const WatchAllExerciseStats(this._repository);
  final WorkoutRepository _repository;

  /// [uid]'s stats by exercise id.
  Stream<Map<String, ExerciseStats>> call(String uid) =>
      _repository.watchAllStats(uid);
}

/// Finishes the workout in progress now (see [finishWorkout]) and stores it
/// with each exercise's stats updated and, when it did the active program's
/// next day, the program moved on, in one batch that also works offline.
/// Refused with a [ValidationFailure] when no set is done, a done set is
/// invalid or the workout exceeds its limits.
///
/// Firestore transactions need the server, so the stats are computed from
/// what the device knows. Stats that cannot be read at all (offline, never
/// loaded here) are left alone rather than overwritten; they and stats read
/// from the cache are reported stale, to be rebuilt from the workouts. With
/// the programs unknown, the program is left and the summary says so.
class FinishWorkout implements UseCase<FinishedWorkout, WorkoutFinish> {
  FinishWorkout(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final WorkoutRepository _repository;
  final DateTime Function() _clock;

  @override
  Future<Result<FinishedWorkout>> call(WorkoutFinish params) async {
    final workout = finishWorkout(params.workout, params.at ?? _clock());
    if (workout.exercises.isEmpty) {
      return const Err(ValidationFailure('no done set'));
    }
    if (!isStorable(workout)) {
      return const Err(ValidationFailure('invalid workout'));
    }
    // Counted alongside, before this one is stored.
    final counted = _repository.countWorkouts(params.uid);
    final read = await _repository.getStats(params.uid, workout.exerciseIds);
    if (read case Err(:final failure)) return Err(failure);
    final before = read.valueOrNull!;
    final after = <String, ExerciseStats>{};
    final stale = <String>{};
    for (final id in workout.exerciseIds) {
      final known = before[id];
      if (known == null || !known.current) stale.add(id);
      if (known == null) {
        Log.e('workout', 'stats of $id unreadable; left as they are');
        continue;
      }
      final updated = applyWorkout(known.stats, workout, id);
      if (updated != null) after[id] = updated;
    }
    final program = params.program;
    final programUnknown = workout.isFromProgram && program == null;
    final advance =
        program != null &&
            advancesProgram(workout, program.active, program.program)
        ? ProgramSchedule(
            program.active!,
            dayCount: program.program!.days.length,
          ).complete(on: CalendarDate.of(workout.startedAt))
        : null;
    final previous = await _previousOfDay(params.uid, workout);
    final firstEver = await _firstEver(params.uid, before);
    final saved = await _repository.saveWorkout(
      params.uid,
      workout,
      after,
      advance: advance,
    );
    if (saved case Err(:final failure)) return Err(failure);
    final active = program?.active;
    final known = program?.program;
    final summary = summarizeWorkout(
      workout,
      before: {
        for (final MapEntry(:key, :value) in before.entries) key: value.stats,
      },
      after: after,
      programUnknown: programUnknown,
    );
    return Ok((
      workout: workout,
      summary: summary.copyWith(
        firstEver: firstEver,
        programWeek: () =>
            active != null &&
                known != null &&
                known.id == workout.programId &&
                active.programId == known.id
            ? ProgramSchedule(
                active,
                dayCount: known.days.length,
                lengthWeeks: known.lengthWeeks,
              ).week(CalendarDate.of(workout.startedAt))
            : null,
        previous: () => previous == null ? null : workoutTotals(previous),
      ),
      staleStats: stale,
      workoutCount: switch (await counted) {
        Ok(:final value) => value + 1,
        Err() => null,
      },
    ));
  }

  /// Whether a workout whose exercises' stats were [before] is the user's
  /// first: none of them was done before and no workout is stored yet.
  /// False when that cannot be read.
  Future<bool> _firstEver(String uid, Map<String, StatsRead> before) async {
    if (before.values.any((read) => read.stats != null)) return false;
    return (await _repository.hasWorkouts(uid)).valueOrNull == false;
  }

  /// The latest workout of [workout]'s program day before it; null for a
  /// free workout, the day's first, or when it cannot be read.
  Future<Workout?> _previousOfDay(String uid, Workout workout) async {
    final programId = workout.programId;
    final dayIndex = workout.dayIndex;
    if (programId == null || dayIndex == null) return null;
    final read = await _repository.programWorkouts(uid, programId);
    Workout? latest;
    for (final other in read.valueOrNull ?? const <Workout>[]) {
      if (other.id == workout.id ||
          other.dayIndex != dayIndex ||
          !other.startedAt.isBefore(workout.startedAt)) {
        continue;
      }
      if (latest == null || other.startedAt.isAfter(latest.startedAt)) {
        latest = other;
      }
    }
    return latest;
  }
}

/// Whether the server took a finished workout; see
/// [WorkoutRepository.isStored].
class ConfirmStoredWorkout implements UseCase<bool, WorkoutRef> {
  const ConfirmStoredWorkout(this._repository);
  final WorkoutRepository _repository;

  @override
  Future<Result<bool>> call(WorkoutRef params) =>
      _repository.isStored(params.uid, params.id);
}

/// Rebuilds an exercise's stats from every workout doing it, read from the
/// server (see [rebuildStats]). When the server returns only part of them,
/// the stats are left: a partial rebuild would lose records.
class RebuildExerciseStats implements UseCase<void, StatsRef> {
  const RebuildExerciseStats(this._repository);
  final WorkoutRepository _repository;

  @override
  Future<Result<void>> call(StatsRef params) async {
    final read = await _repository.workoutsWith(params.uid, params.exerciseId);
    switch (read) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: (workouts: _, complete: false)):
        Log.e('workout', 'too many workouts to rebuild ${params.exerciseId}');
        return const Ok(null);
      case Ok(value: (:final workouts, complete: true)):
        return _repository.saveStats(
          params.uid,
          params.exerciseId,
          rebuildStats(params.exerciseId, workouts),
        );
    }
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

/// Stores [ProgramDayUpdate.items] as the day's items, refused like
/// [SaveProgram] when the program would not be valid.
class UpdateProgramDay implements UseCase<String, ProgramDayUpdate> {
  const UpdateProgramDay(this._saveProgram);
  final SaveProgram _saveProgram;

  @override
  Future<Result<String>> call(ProgramDayUpdate params) {
    final program = params.program;
    return _saveProgram((
      uid: params.uid,
      program: program.copyWith(
        days: [
          for (final (i, day) in program.days.indexed)
            i == params.dayIndex ? day.copyWith(items: params.items) : day,
        ],
      ),
      loggingTypes: <String, LoggingType>{
        for (final MapEntry(:key, :value) in params.catalogue.entries)
          key: value.loggingType,
      },
    ));
  }
}

class ShowWorkoutOnLockScreen implements UseCase<void, LockScreenWorkout> {
  const ShowWorkoutOnLockScreen(this._lockScreen);
  final WorkoutLockScreen _lockScreen;

  @override
  Future<Result<void>> call(LockScreenWorkout params) =>
      _lockScreen.show(params);
}

class ClearWorkoutFromLockScreen implements UseCase<void, NoParams> {
  const ClearWorkoutFromLockScreen(this._lockScreen);
  final WorkoutLockScreen _lockScreen;

  @override
  Future<Result<void>> call(NoParams params) => _lockScreen.clear();
}

/// Taps on the workout's lock-screen activity; for one listener.
class WatchLockScreenTaps {
  const WatchLockScreenTaps(this._lockScreen);
  final WorkoutLockScreen _lockScreen;

  Stream<void> call() => _lockScreen.taps();
}

/// The rest buttons pressed on the workout's lock-screen activity; for one
/// listener.
class WatchLockScreenRestActions {
  const WatchLockScreenRestActions(this._lockScreen);
  final WorkoutLockScreen _lockScreen;

  Stream<LockScreenRestPress> call() => _lockScreen.restActions();
}
