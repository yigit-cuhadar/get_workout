import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../../core/text_length.dart';
import '../../programs/domain/active_program.dart';
import '../../programs/domain/program.dart';
import '../../../core/grouping.dart';
import '../../programs/domain/program_editing.dart';
import '../../programs/domain/program_schedule.dart';
import 'exercise_stats.dart';
import 'set_logging.dart';
import 'workout.dart';

/// [exercise] as a workout exercise named in [language], in [goal]'s group:
/// one empty set per set of [goal], or a single one without a goal. The
/// goal keeps only its targets.
WorkoutExercise exerciseFor(
  Exercise exercise,
  String language, {
  ProgramItem? goal,
}) => WorkoutExercise(
  exerciseId: exercise.id,
  name: exercise.text(language).name,
  loggingType: exercise.loggingType,
  mainMuscles: exercise.mainMuscles,
  secondaryMuscles: exercise.secondaryMuscles,
  group: goal?.group,
  sets: List.filled(
    (goal?.sets ?? 1).clamp(1, WorkoutLimits.maxSets),
    const WorkoutSet(),
  ),
  goal: goal == null
      ? null
      : ProgramItem(
          exerciseId: goal.exerciseId,
          sets: goal.sets,
          repMin: goal.repMin,
          repMax: goal.repMax,
          durationS: goal.durationS,
          restS: goal.restS,
          targetKg: goal.targetKg,
        ),
);

/// Where a new set of [type] goes in [exercise]: a warm-up after the last
/// warm-up (before the working sets, at the start without one), any other
/// set at the end.
int newSetPosition(WorkoutExercise exercise, SetType type) =>
    type == SetType.warmup
    ? exercise.sets.lastIndexWhere((set) => set.isWarmup) + 1
    : exercise.sets.length;

/// A workout of day [dayIndex] of [program], its items as goals. Items whose
/// exercise is not in [catalogue] (deleted or retired) are left out.
Workout workoutFromProgramDay({
  required String id,
  required DateTime startedAt,
  required String name,
  required Program program,
  required int dayIndex,
  required Map<String, Exercise> catalogue,
  required String language,
}) => Workout(
  id: id,
  startedAt: startedAt,
  programId: program.id,
  dayIndex: dayIndex,
  name: name,
  exercises: relabelGroups([
    for (final item in program.days[dayIndex].items)
      if (catalogue[item.exerciseId] case final exercise?)
        exerciseFor(exercise, language, goal: item),
  ]),
);

/// [current] doing [replacement] instead, in the same place and group. Its
/// sets stay when the logging type does; otherwise as many empty sets of
/// the same kinds take their place. The goal is fitted to the new type.
WorkoutExercise swapExercise(
  WorkoutExercise current,
  Exercise replacement,
  String language,
) {
  final type = replacement.loggingType;
  final goal = current.goal;
  return current.copyWith(
    exerciseId: replacement.id,
    name: replacement.text(language).name,
    loggingType: type,
    mainMuscles: replacement.mainMuscles,
    secondaryMuscles: replacement.secondaryMuscles,
    sets: type == current.loggingType
        ? current.sets
        : [
            for (final set in current.sets)
              WorkoutSet(
                type: set.type == SetType.drop && !type.logsReps
                    ? SetType.normal
                    : set.type,
              ),
          ],
    goal: () => goal == null
        ? null
        : fitToLoggingType(goal.copyWith(exerciseId: replacement.id), type),
  );
}

/// [workout] finished [at], never before it started (a device clock set
/// back): only its done sets, exercises left without one removed, and no
/// program goals.
Workout finishWorkout(Workout workout, DateTime at) => workout.copyWith(
  finishedAt: at.isBefore(workout.startedAt) ? workout.startedAt : at,
  exercises: relabelGroups([
    for (final exercise in workout.exercises)
      if (exercise.doneSets case final done when done.isNotEmpty)
        exercise.copyWith(sets: done, goal: () => null),
  ]),
);

/// Whether [workout] stays within [WorkoutLimits], which the rules
/// enforce: a name, and no more exercises, sets or note text than allowed.
bool fitsLimits(Workout workout) =>
    workout.name.isNotEmpty &&
    workout.name.length <= WorkoutLimits.maxNameLength &&
    (workout.note?.length ?? 0) <= WorkoutLimits.maxNoteLength &&
    workout.exercises.length <= WorkoutLimits.maxExercises &&
    workout.exercises.every(
      (e) =>
          e.sets.length <= WorkoutLimits.maxSets &&
          (e.note?.length ?? 0) <= WorkoutLimits.maxExerciseNoteLength &&
          e.sets.every(
            (s) => (s.note?.length ?? 0) <= WorkoutLimits.maxSetNoteLength,
          ),
    );

/// Whether finished [workout] can be stored: it has an exercise, every set
/// is valid for its exercise, it [fitsLimits] and it does not finish before
/// it started.
bool isStorable(Workout workout) =>
    workout.exercises.isNotEmpty &&
    workout.exercises.every(
      (e) => e.sets.every((s) => validateSet(s, e.loggingType).isEmpty),
    ) &&
    fitsLimits(workout) &&
    !(workout.finishedAt?.isBefore(workout.startedAt) ?? false);

/// Why a change to the stored workouts is refused.
enum WorkoutChangeIssue {
  noDoneSet,
  startInFuture,
  endInFuture,

  /// Over [WorkoutLimits.maxWorkoutDuration], or ending before it starts.
  badDuration,

  /// Not [isStorable] once its unticked sets are left out.
  invalid,
}

/// What keeps edited [workout] from being stored [now], null when nothing
/// does. Its unticked sets do not count; they are left out.
WorkoutChangeIssue? changeIssue(Workout workout, DateTime now) {
  final start = workout.startedAt;
  final end = workout.finishedAt ?? start;
  final length = end.difference(start);
  return workout.doneSetCount == 0
      ? WorkoutChangeIssue.noDoneSet
      : start.isAfter(now)
      ? WorkoutChangeIssue.startInFuture
      : end.isAfter(now)
      ? WorkoutChangeIssue.endInFuture
      : length.isNegative || length > WorkoutLimits.maxWorkoutDuration
      ? WorkoutChangeIssue.badDuration
      : isStorable(finishWorkout(workout, end))
      ? null
      : WorkoutChangeIssue.invalid;
}

/// Whether [workout] did the next day of the [active] program, which then
/// moves on. [program] is the active program as it is now.
bool advancesProgram(Workout workout, ActiveProgram? active, Program? program) {
  final dayIndex = workout.dayIndex;
  if (active == null ||
      program == null ||
      dayIndex == null ||
      program.days.isEmpty ||
      program.id != active.programId ||
      workout.programId != active.programId) {
    return false;
  }
  final schedule = ProgramSchedule(active, dayCount: program.days.length);
  return schedule.nextDayIndex == dayIndex;
}

/// A one-day program of the user's own repeating finished [workout], named
/// [name]: per exercise its working sets, their rep range or longest
/// duration, and its heaviest weight (least assistance) as the target.
/// Rest is the exercise's default ([fallbackRestS] for a custom one).
/// Exercises not in [catalogue] are left out. The result still needs
/// `validateProgram`.
Program programFromWorkout(
  Workout workout, {
  required String name,
  required Map<String, Exercise> catalogue,
}) {
  ProgramItem? item(WorkoutExercise exercise) {
    final known = catalogue[exercise.exerciseId];
    if (known == null) return null;
    final type = exercise.loggingType;
    final working = workingSets(exercise.sets);
    final sets = working.isEmpty ? exercise.doneSets : working;
    final reps = [for (final set in sets) ?set.reps]..sort();
    final durations = [for (final set in sets) ?set.durationS]..sort();
    final weights = [
      for (final set in sets)
        if (set.weightKg case final kg? when kg > 0) kg,
    ]..sort();
    int clampReps(int reps) =>
        reps.clamp(ProgramLimits.minReps, ProgramLimits.maxReps);
    return ProgramItem(
      exerciseId: exercise.exerciseId,
      sets: sets.length.clamp(ProgramLimits.minSets, ProgramLimits.maxSets),
      repMin: type.logsReps && reps.isNotEmpty ? clampReps(reps.first) : null,
      repMax: type.logsReps && reps.isNotEmpty ? clampReps(reps.last) : null,
      durationS: type.isDurationBased && durations.isNotEmpty
          ? durations.last.clamp(
              ProgramLimits.minDurationS,
              ProgramLimits.maxDurationS,
            )
          : null,
      restS: (known.defaultRestS ?? fallbackRestS).clamp(
        0,
        ProgramLimits.maxRestS,
      ),
      targetKg: type.logsWeight && weights.isNotEmpty
          ? (type == LoggingType.assistedBodyweight
                    ? weights.first
                    : weights.last)
                .clamp(0, ProgramLimits.maxTargetKg)
                .toDouble()
          : null,
      group: exercise.group,
    );
  }

  return Program(
    name: cutToLength(name.trim(), ProgramLimits.maxNameLength),
    days: [
      ProgramDay(
        items: relabelGroups([
          for (final exercise in workout.exercises) ?item(exercise),
        ]),
      ),
    ],
  );
}
