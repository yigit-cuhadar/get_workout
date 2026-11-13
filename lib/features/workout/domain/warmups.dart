import '../../exercises/domain/vocabulary.dart';
import '../../settings/domain/user_settings.dart';
import 'workout.dart';

/// What warm-up suggestions follow: the user's unit and the sets of their
/// scheme ([WarmupSettings.rampSteps]).
typedef WarmupRamp = ({WeightUnit unit, List<WarmupStep> steps});

/// Whether exercises of [type] start with automatic warm-ups: only those
/// lifting a load for reps. Bodyweight ones (added weight or assistance
/// included) and timed ones do not.
bool takesWarmups(LoggingType type) => type == LoggingType.weightReps;

/// Whether [exercise], placed after [before] in a workout, may have
/// automatic warm-ups: it [takesWarmups] and, with
/// [WarmupScope.firstPerMuscle] in [settings], no exercise before it that
/// itself [takesWarmups] works its main muscle (the first of its main
/// muscles; one without is a group of its own). Such an earlier exercise
/// counts with or without its warm-ups; push-ups or a plank do not.
bool warmupsAllowed(
  WorkoutExercise exercise,
  List<WorkoutExercise> before,
  WarmupSettings? settings,
) {
  if (!takesWarmups(exercise.loggingType)) return false;
  final muscle = exercise.mainMuscles.firstOrNull;
  return settings?.scope != WarmupScope.firstPerMuscle ||
      muscle == null ||
      !before.any(
        (e) =>
            takesWarmups(e.loggingType) && e.mainMuscles.firstOrNull == muscle,
      );
}

/// [exercise] as it enters a workout whose exercises [before] it are
/// [before], starting with one empty warm-up per set of [settings]' scheme
/// when [warmupsAllowed], it has no warm-up yet, and they fit in
/// [WorkoutLimits.maxSets].
WorkoutExercise warmedUp(
  WorkoutExercise exercise,
  List<WorkoutExercise> before,
  WarmupSettings settings,
) {
  final steps = settings.steps;
  final sets = exercise.sets;
  if (steps.isEmpty ||
      !warmupsAllowed(exercise, before, settings) ||
      sets.any((set) => set.isWarmup) ||
      sets.length + steps.length > WorkoutLimits.maxSets) {
    return exercise;
  }
  return exercise.copyWith(
    sets: [
      for (final _ in steps) const WorkoutSet(type: SetType.warmup),
      ...sets,
    ],
  );
}

/// [exercises] entering a workout after [before], each [warmedUp] against
/// the ones before it, in order.
List<WorkoutExercise> warmedUpAll(
  List<WorkoutExercise> exercises,
  List<WorkoutExercise> before,
  WarmupSettings settings,
) {
  final result = <WorkoutExercise>[];
  for (final exercise in exercises) {
    result.add(warmedUp(exercise, [...before, ...result], settings));
  }
  return result;
}

/// [swapped], made from [before] by `swapExercise`, without the warm-ups
/// still untouched in [before] (nothing entered, not done) unless warm-ups
/// are [allowed] for it (see [warmupsAllowed]): they were there for the
/// exercise swapped out.
WorkoutExercise withoutUnusedWarmups(
  WorkoutExercise before,
  WorkoutExercise swapped, {
  required bool allowed,
}) {
  if (allowed) return swapped;
  const untouched = WorkoutSet(type: SetType.warmup);
  return swapped.copyWith(
    sets: [
      for (final (i, set) in swapped.sets.indexed)
        if (before.sets.elementAtOrNull(i) != untouched) set,
    ],
  );
}

/// The steps a warm-up's weight is rounded to in [unit], in kg: 2.5 kg or
/// 5 lb.
double warmupStepKg(WeightUnit unit) => unit.toKg(switch (unit) {
  WeightUnit.kg => 2.5,
  WeightUnit.lb => 5,
});

/// Warm-up [position] (0 for the first) of an exercise whose first working
/// set lifts [workingKg], as [steps] have it (past the last, the last): its
/// share of the weight rounded to [warmupStepKg] in [unit], never below one
/// step nor above [workingKg]. Null while [workingKg] is unknown or 0, or
/// without [steps].
({double weightKg, int reps})? rampedWarmup(
  int position,
  double? workingKg,
  WeightUnit unit,
  List<WarmupStep> steps,
) {
  if (workingKg == null || !(workingKg > 0) || steps.isEmpty) return null;
  final step = steps[position.clamp(0, steps.length - 1)];
  final unitStep = unit.fromKg(warmupStepKg(unit));
  final working = unit.fromKg(workingKg);
  final rounded = (working * step.percent / 100 / unitStep).round() * unitStep;
  final weight = rounded < unitStep ? unitStep : rounded;
  return (
    weightKg: weight > working ? workingKg : unit.toKg(weight),
    reps: step.reps,
  );
}
