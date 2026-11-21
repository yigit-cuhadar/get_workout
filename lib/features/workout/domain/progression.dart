import 'dart:math' as math;

import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../../settings/domain/user_settings.dart';
import 'exercise_stats.dart';
import 'workout.dart';

/// The best of [sets]' working sets for [type], or null without one: the
/// heaviest (the least assistance for an assisted exercise), then the most
/// reps, then the longest.
WorkoutSet? bestSet(List<WorkoutSet> sets, LoggingType type) {
  WorkoutSet? best;
  for (final set in sets) {
    if (set.isWarmup) continue;
    if (best == null || _compare(set, best, type) > 0) best = set;
  }
  return best;
}

/// Above zero when [a] is better than [b]; see [bestSet].
int _compare(WorkoutSet a, WorkoutSet b, LoggingType type) {
  if (type.logsWeight) {
    final kg = (a.weightKg ?? 0).compareTo(b.weightKg ?? 0);
    if (kg != 0) return type == LoggingType.assistedBodyweight ? -kg : kg;
  }
  final reps = (a.reps ?? 0).compareTo(b.reps ?? 0);
  if (reps != 0) return reps;
  return (a.durationS ?? 0).compareTo(b.durationS ?? 0);
}

/// A heavier load for [exercise] when [last] time every working set
/// reached the top of its program rep range: the heaviest of them one step
/// up, in kg, with the [reps] they hit. The step is the exercise's
/// [incrementKg] (in lb rounded to 2.5 lb, at least 2.5), else [unit]'s
/// weight step. Only for exercises lifting a load for reps with a rep
/// range; null otherwise.
({double kg, int reps})? progression(
  WorkoutExercise exercise,
  LastSession? last,
  WeightUnit unit, {
  double? incrementKg,
}) {
  final top = exercise.goal?.repMax;
  if (exercise.loggingType != LoggingType.weightReps ||
      top == null ||
      last == null) {
    return null;
  }
  final working = [
    for (final set in last.sets)
      if (!set.isWarmup) set,
  ];
  if (working.isEmpty ||
      working.any(
        (set) =>
            (set.reps ?? 0) < top || set.weightKg == null || set.weightKg! <= 0,
      )) {
    return null;
  }
  final heaviest = working
      .map((set) => set.weightKg!)
      .reduce((a, b) => a > b ? a : b);
  return (
    kg: unit.toKg(unit.shownFromKg(heaviest) + _step(unit, incrementKg)),
    reps: top,
  );
}

/// One progression step in [unit]: see [progression].
double _step(WeightUnit unit, double? incrementKg) {
  if (incrementKg == null || incrementKg <= 0) return unit.weightStep;
  return switch (unit) {
    WeightUnit.kg => incrementKg,
    WeightUnit.lb => math.max(
      2.5,
      (unit.fromKg(incrementKg) / 2.5).round() * 2.5,
    ),
  };
}

/// Whether a working set of [exercise] not done yet lifts less than [kg]
/// (or nothing yet), so the progression still has something to fill.
bool progressionOpen(WorkoutExercise exercise, double kg) => exercise.sets.any(
  (set) =>
      !set.isWarmup &&
      !set.done &&
      (set.weightKg == null || set.weightKg! < kg - _epsilonKg),
);

/// Below any weight a field can show.
const _epsilonKg = 1e-6;
