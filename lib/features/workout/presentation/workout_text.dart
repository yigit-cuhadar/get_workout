import 'package:intl/intl.dart';

import '../../../core/grouping.dart';

import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/effort.dart';
import '../domain/exercise_stats.dart';
import '../domain/workout.dart';

extension WorkoutText on AppLocalizations {
  /// A lifted weight in [unit] for a text field, as
  /// [WeightUnitConversion.shown] shows it: up to two decimals, no trailing
  /// zeros, no grouping.
  String weightField(double kg, WeightUnit unit) =>
      numberField(unit.shownFromKg(kg));

  String numberField(num value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  /// `1:05` or `1:02:03`.
  String elapsedText(Duration elapsed) {
    final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
    final h = seconds ~/ 3600;
    final m = (seconds ~/ 60) % 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  /// The label of the weight field for [type].
  String weightLabel(LoggingType type, WeightUnit unit) {
    final label = weightUnitLabel(unit);
    return switch (type) {
      LoggingType.weightedBodyweight => workoutAddedWeight(label),
      LoggingType.assistedBodyweight => workoutAssistance(label),
      _ => label,
    };
  }

  /// A set as it was done, e.g. `60 × 8`, `8`, `45 s` or `20 × 45 s`; the
  /// weight in [unit] without the unit.
  String setText(WorkoutSet set, LoggingType type, WeightUnit unit) {
    final kg = set.weightKg;
    final work = type.isDurationBased
        ? set.durationS == null
              ? ''
              : programSeconds(set.durationS!)
        : '${set.reps ?? ''}';
    if (!type.logsWeight || kg == null || kg == 0) return work;
    return '${weightField(kg, unit)} × $work';
  }

  /// The program goal of [exercise], e.g. `3 × 8–12 · 60 kg`.
  String? goalText(WorkoutExercise exercise, WeightUnit unit) {
    final goal = exercise.goal;
    return goal == null ? null : workoutGoal(itemSummary(goal, unit));
  }

  /// Set [index] of [exercise] in short: `W` for a warm-up, else its
  /// number among the working sets, e.g. `2`, or `2D` for a drop set.
  String setShortLabel(WorkoutExercise exercise, int index) {
    final number = _workingNumber(exercise, index);
    return switch (exercise.sets[index].type) {
      SetType.warmup => workoutWarmupShort,
      SetType.drop => '$number$workoutDropShort',
      SetType.normal => '$number',
    };
  }

  /// Set [index] of [exercise] for a screen reader, e.g. `Set 2, done`,
  /// `Warm-up set` or `Set 2, drop set`.
  String setBubbleLabel(WorkoutExercise exercise, int index) {
    final set = exercise.sets[index];
    final number = _workingNumber(exercise, index);
    final label = switch (set.type) {
      SetType.warmup => workoutWarmupBubble,
      SetType.drop => workoutDropBubble(number),
      SetType.normal => workoutSetBubble(number),
    };
    return set.done ? workoutBubbleDone(label) : label;
  }

  /// Where set [index] is among its kind, e.g. `Set 2 / 3`, `Warm-up 1 / 2`
  /// or `Set 2 / 3 · Drop set`.
  String setPositionText(WorkoutExercise exercise, int index) {
    final set = exercise.sets[index];
    final warmups = exercise.sets.where((s) => s.isWarmup).length;
    if (set.isWarmup) {
      final number = exercise.sets.take(index + 1).where((s) => s.isWarmup);
      return workoutWarmupOf(number.length, warmups);
    }
    final position = workoutSetOf(
      _workingNumber(exercise, index),
      exercise.sets.length - warmups,
    );
    return set.type == SetType.drop
        ? '$position · ${setTypeLabel(SetType.drop)}'
        : position;
  }

  int _workingNumber(WorkoutExercise exercise, int index) =>
      exercise.sets.take(index + 1).where((s) => !s.isWarmup).length;

  String setTypeLabel(SetType type) => switch (type) {
    SetType.normal => workoutSetNormal,
    SetType.warmup => workoutSetWarmup,
    SetType.drop => workoutSetDrop,
  };

  /// [step] as a choice of [scale] shows it: `Easy`, `4` (RIR), `6` (RPE),
  /// `Failed`.
  String effortStepLabel(EffortStep step, EffortScale scale) {
    if (step.failed) return effortFailed;
    return switch (scale) {
      EffortScale.byFeel => switch (step.rir) {
        >= 4 => effortEasy,
        >= 2 => effortModerate,
        1 => effortHard,
        _ => effortMax,
      },
      EffortScale.rir =>
        step.rir >= WorkoutLimits.maxRir ? workoutRirFivePlus : '${step.rir}',
      EffortScale.rpe => '${10 - step.rir}',
    };
  }

  /// What a by-feel [step] means, e.g. `1 left`; null on other scales.
  String? effortStepHint(EffortStep step, EffortScale scale) {
    if (scale != EffortScale.byFeel) return null;
    if (step.failed) return effortFailedHint;
    return switch (step.rir) {
      >= 4 => effortEasyHint,
      >= 2 => effortModerateHint,
      1 => effortHardHint,
      _ => effortMaxHint,
    };
  }

  /// The effort of [set] on [scale], e.g. `Hard`, `RIR 2`, `RPE 8` or
  /// `Failed`; null without one.
  String? effortText(WorkoutSet set, EffortScale scale) {
    final step = scale.stepOf(set);
    if (step == null) return null;
    if (step.failed) return effortFailed;
    return switch (scale) {
      EffortScale.byFeel => effortStepLabel(step, scale),
      EffortScale.rir => workoutRir(step.rir),
      EffortScale.rpe => workoutRpe(10 - step.rir),
    };
  }

  /// A set as it was done with the weight's unit, e.g. `80 kg × 8`.
  String setWithUnitText(WorkoutSet set, LoggingType type, WeightUnit unit) {
    final kg = set.weightKg;
    if (!type.logsWeight || kg == null || kg == 0) {
      return setText(set, type, unit);
    }
    final work = setText(
      WorkoutSet(reps: set.reps, durationS: set.durationS),
      type,
      unit,
    );
    return '${liftedWeightText(kg, unit)} × $work';
  }

  /// Whole minutes; under one, "< 1 min".
  String durationMinutes(Duration duration) {
    if (duration.inSeconds < 60) return workoutUnderAMinute;
    return workoutMinutes((duration.inSeconds / 60).round());
  }

  String recordText(NewRecord record, WeightUnit unit) {
    final value = record.value;
    final text = switch (record.kind) {
      RecordKind.heaviestWeight => recordHeaviestWeight(
        liftedWeightText(value, unit),
      ),
      RecordKind.bestE1rm => recordBestE1rm(estimatedWeightText(value, unit)),
      RecordKind.bestSetVolume => recordBestSetVolume(weightText(value, unit)),
      RecordKind.mostReps => recordMostReps(value.round()),
      RecordKind.longestDuration => recordLongestDuration(
        elapsedText(Duration(seconds: value.round())),
      ),
    };
    return workoutRecordLine(record.name, text);
  }

  String lastTimeText(DateTime date) =>
      workoutLastTime(DateFormat.MMMEd(localeName).format(date));
}

/// Exercise [index] of a superset or circuit by its group and place in it,
/// e.g. `A1`.
String groupItemLabel(List<WorkoutExercise> exercises, int index) {
  final (start, _) = groupRange(exercises, index);
  return '${exercises[index].group ?? ''}${index - start + 1}';
}
