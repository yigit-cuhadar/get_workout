import '../../settings/domain/user_settings.dart';
import 'warmups.dart';
import 'workout.dart';

/// Whether the set bar tells about effort: once a set of [workout] is
/// ticked, until the tip is seen or a set has an effort.
bool effortTipDue(Workout workout, Set<Tip> seen) {
  final sets = [for (final exercise in workout.exercises) ...exercise.sets];
  return !seen.contains(Tip.effort) &&
      sets.any((set) => set.done) &&
      !sets.any((set) => set.rir != null || set.toFailure);
}

/// Whether the add-set sheet tells what the set types are.
bool setTypesTipDue(Set<Tip> seen) => !seen.contains(Tip.setTypes);

/// Whether the workout in progress tells that warm-ups were added: while
/// [autoWarmups] is on and an exercise of [workout] that [takesWarmups]
/// has one, until the tip is seen.
bool autoWarmupsTipDue(
  Workout workout,
  Set<Tip> seen, {
  required bool autoWarmups,
}) =>
    autoWarmups &&
    !seen.contains(Tip.autoWarmups) &&
    workout.exercises.any(
      (exercise) =>
          takesWarmups(exercise.loggingType) &&
          exercise.sets.any((set) => set.isWarmup),
    );
