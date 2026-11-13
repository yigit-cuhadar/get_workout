import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../../settings/domain/user_settings.dart';
import 'warmups.dart';
import 'workout.dart';

/// The values a set records, by logging type.
typedef SetValues = ({double? weightKg, int? reps, int? durationS});

enum SetIssue {
  weightMissing,
  weightOutOfRange,
  repsMissing,
  repsOutOfRange,
  durationMissing,
  durationOutOfRange,
  rirOutOfRange,

  /// A drop without weight or reps, too many drops, or drops on a set that
  /// is not a drop set.
  dropsInvalid,
}

/// What a set of each logging type records.
extension LoggingTypeSets on LoggingType {
  bool get logsReps => !isDurationBased;

  /// The kinds its sets can be: drop sets only for rep-based types.
  List<SetType> get setTypes => [
    for (final type in SetType.values)
      if (type != SetType.drop || logsReps) type,
  ];

  /// Bodyweight types: an empty weight means none added (or no assistance).
  bool get weightOptional =>
      this == LoggingType.weightedBodyweight ||
      this == LoggingType.assistedBodyweight;

  /// The weight is a load, so weight × reps is volume and an estimated
  /// one-rep max makes sense. Assistance is not a load.
  bool get logsLoad =>
      this == LoggingType.weightReps || this == LoggingType.weightedBodyweight;
}

/// What keeps [set] from being done for an exercise of [type]. NaN fails
/// every range.
Set<SetIssue> validateSet(WorkoutSet set, LoggingType type) {
  final weight = set.weightKg;
  final reps = set.reps;
  final duration = set.durationS;
  final rir = set.rir;
  final dropsOk =
      set.drops.isEmpty ||
      (set.type == SetType.drop &&
          type.logsReps &&
          set.drops.length <= WorkoutLimits.maxDrops &&
          set.drops.every(
            (drop) =>
                _validWeight(drop.weightKg, optional: type.weightOptional) &&
                _validReps(drop.reps),
          ));
  return {
    if (type.logsWeight && weight == null && !type.weightOptional)
      SetIssue.weightMissing,
    if (type.logsWeight && weight != null && !_validWeight(weight))
      SetIssue.weightOutOfRange,
    if (type.logsReps && reps == null) SetIssue.repsMissing,
    if (type.logsReps && reps != null && !_validReps(reps))
      SetIssue.repsOutOfRange,
    if (type.isDurationBased && duration == null) SetIssue.durationMissing,
    if (type.isDurationBased &&
        duration != null &&
        !_within(duration, 1, WorkoutLimits.maxDurationS))
      SetIssue.durationOutOfRange,
    if (rir != null && !_within(rir, 0, WorkoutLimits.maxRir))
      SetIssue.rirOutOfRange,
    if (!dropsOk) SetIssue.dropsInvalid,
  };
}

bool _validWeight(double? kg, {bool optional = false}) =>
    kg == null ? optional : _within(kg, 0, WorkoutLimits.maxWeightKg);

bool _validReps(int? reps) =>
    reps != null && _within(reps, 1, WorkoutLimits.maxReps);

/// False for NaN, whose comparisons are all false.
bool _within(num value, num min, num max) => value >= min && value <= max;

/// The set at the place of set [index] of [exercise] last time: its
/// working sets matched in order; a warm-up has none. [lastSets] are the
/// working sets of the exercise's latest workout.
WorkoutSet? lastTimeSet(
  WorkoutExercise exercise,
  int index,
  List<WorkoutSet> lastSets,
) {
  final set = exercise.sets.elementAtOrNull(index);
  if (set == null || set.isWarmup) return null;
  final position = exercise.sets.take(index).where((s) => !s.isWarmup).length;
  return lastSets.elementAtOrNull(position);
}

/// The values shown as hints in the empty fields of set [index] of
/// [exercise], and logged when it is ticked with them still empty. Each
/// value comes from the first that has it: the closest done set of the same
/// type before it in this workout, the same set last time (see
/// [lastTimeSet]), the program's target (the bottom of its rep range). A
/// warm-up only follows the warm-up before it; with [ramp], a warm-up of
/// an exercise that [takesWarmups] is instead [rampedWarmup] by its
/// position from the first working set's weight (as entered, else as
/// suggested), once that is known.
SetValues suggestedValues(
  WorkoutExercise exercise,
  int index,
  List<WorkoutSet> lastSets, {
  WarmupRamp? ramp,
}) {
  final set = exercise.sets.elementAtOrNull(index);
  if (set == null) return (weightKg: null, reps: null, durationS: null);
  final first = exercise.sets.indexWhere((s) => !s.isWarmup);
  if (set.isWarmup &&
      ramp != null &&
      takesWarmups(exercise.loggingType) &&
      first >= 0) {
    final working =
        exercise.sets[first].weightKg ??
        suggestedValues(exercise, first, lastSets).weightKg;
    final position = exercise.sets.take(index).where((s) => s.isWarmup);
    final ramped = rampedWarmup(
      position.length,
      working,
      ramp.unit,
      ramp.steps,
    );
    if (ramped != null) {
      return (weightKg: ramped.weightKg, reps: ramped.reps, durationS: null);
    }
  }
  final previous = exercise.sets
      .take(index)
      .lastWhere((s) => s.done && s.type == set.type, orElse: () => _none);
  final last = lastTimeSet(exercise, index, lastSets);
  final goal = set.isWarmup ? null : exercise.goal;
  return (
    weightKg: previous.weightKg ?? last?.weightKg ?? goal?.targetKg,
    reps: previous.reps ?? last?.reps ?? goal?.repMin,
    durationS: previous.durationS ?? last?.durationS ?? goal?.durationS,
  );
}

const _none = WorkoutSet();

/// [set] ticked done, its empty values taken from [suggestion] where
/// [type] records them; null when it is still not valid.
WorkoutSet? completeSet(
  WorkoutSet set,
  LoggingType type,
  SetValues suggestion,
) {
  final filled = set.copyWith(
    weightKg: () =>
        type.logsWeight ? set.weightKg ?? suggestion.weightKg : set.weightKg,
    reps: () => type.logsReps ? set.reps ?? suggestion.reps : set.reps,
    durationS: () => type.isDurationBased
        ? set.durationS ?? suggestion.durationS
        : set.durationS,
    done: true,
  );
  return validateSet(filled, type).isEmpty ? filled : null;
}

/// A stepper's [steps] (−1 or +1) applied to a lifted weight of [kg], or
/// of [hint] while it is empty, else of none: moved by its unit's
/// [WeightUnitConversion.weightStep] from the weight as [unit] shows it,
/// to hundredths as fields show them, kept from 0 to
/// [WorkoutLimits.maxWeightKg].
double steppedWeightKg(double? kg, double? hint, int steps, WeightUnit unit) {
  final shown = unit.shownFromKg(kg ?? hint ?? 0);
  final hundredths = ((shown + steps * unit.weightStep) * 100).round();
  final stepped = unit.toKg(hundredths / 100);
  return stepped.clamp(0, WorkoutLimits.maxWeightKg);
}

/// What the seconds stepper moves a set's duration by.
const durationStepS = 5;

/// A stepper's [steps] (−1 or +1) applied to reps or seconds of [value],
/// or of [hint] while it is empty, else of none: kept from 1 to [max].
int steppedCount(int? value, int? hint, int steps, int max) =>
    ((value ?? hint ?? 0) + steps).clamp(1, max);
