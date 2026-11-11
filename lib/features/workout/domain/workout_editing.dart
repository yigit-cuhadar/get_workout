import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/active_program.dart';
import '../../programs/domain/program.dart';
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

/// [workout] finished [at]: only its done sets, exercises left without one
/// removed, and no program goals.
Workout finishWorkout(Workout workout, DateTime at) => workout.copyWith(
  finishedAt: at,
  exercises: relabelGroups([
    for (final exercise in workout.exercises)
      if (exercise.doneSets case final done when done.isNotEmpty)
        exercise.copyWith(sets: done, goal: () => null),
  ]),
);

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
/// Exercises not in [catalogue] are left out; rest is the program's, or
/// the exercise's default. The result still needs `validateProgram`.
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
      restS: (exercise.goal?.restS ?? known.defaultRestS).clamp(
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
