import '../../exercises/domain/vocabulary.dart';
import '../../settings/domain/user_settings.dart';
import 'workout.dart';

/// The automatic warm-ups, lightest first: the share of the first working
/// set's weight each lifts, and its reps. Warm-ups past the last repeat it.
const warmupRamp = [(share: 0.5, reps: 8), (share: 0.75, reps: 4)];

/// Whether exercises of [type] start with automatic warm-ups: only those
/// lifting a load for reps. Bodyweight ones (added weight or assistance
/// included) and timed ones do not.
bool takesWarmups(LoggingType type) => type == LoggingType.weightReps;

/// [exercise] starting with the warm-ups of [warmupRamp], all empty: when
/// [takesWarmups], it has no warm-up yet and they fit in
/// [WorkoutLimits.maxSets].
WorkoutExercise withWarmups(WorkoutExercise exercise) {
  final sets = exercise.sets;
  if (!takesWarmups(exercise.loggingType) ||
      sets.any((set) => set.isWarmup) ||
      sets.length + warmupRamp.length > WorkoutLimits.maxSets) {
    return exercise;
  }
  return exercise.copyWith(
    sets: [
      for (final _ in warmupRamp) const WorkoutSet(type: SetType.warmup),
      ...sets,
    ],
  );
}

/// [swapped], made from [before] by `swapExercise`, without the warm-ups
/// still untouched in [before] (nothing entered, not done) when it does not
/// [takesWarmups]: they were there for the exercise swapped out.
WorkoutExercise withoutUnusedWarmups(
  WorkoutExercise before,
  WorkoutExercise swapped,
) {
  if (takesWarmups(swapped.loggingType)) return swapped;
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
/// set lifts [workingKg], as [warmupRamp] has it: its share of the weight
/// rounded to [warmupStepKg] in [unit], never below one step nor above
/// [workingKg]. Null while [workingKg] is unknown or 0.
({double weightKg, int reps})? rampedWarmup(
  int position,
  double? workingKg,
  WeightUnit unit,
) {
  if (workingKg == null || !(workingKg > 0)) return null;
  final ramp = warmupRamp[position.clamp(0, warmupRamp.length - 1)];
  final step = unit.fromKg(warmupStepKg(unit));
  final working = unit.fromKg(workingKg);
  final rounded = (working * ramp.share / step).round() * step;
  final weight = rounded < step ? step : rounded;
  return (
    weightKg: weight > working ? workingKg : unit.toKg(weight),
    reps: ramp.reps,
  );
}
