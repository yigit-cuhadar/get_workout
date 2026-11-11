import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/exercise_stats.dart';
import '../domain/workout.dart';

extension WorkoutText on AppLocalizations {
  /// A number in [unit] for a text field: up to two decimals, no trailing
  /// zeros, no grouping.
  String weightField(double kg, WeightUnit unit) =>
      numberField(unit.fromKg(kg));

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

  /// The weight column's heading for [type].
  String weightColumn(LoggingType type, WeightUnit unit) {
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
    return '${numberField(unit.fromKg(kg))} × $work';
  }

  /// The program goal of [exercise], e.g. `3 × 8–12 · 60 kg`.
  String? goalText(WorkoutExercise exercise, WeightUnit unit) {
    final goal = exercise.goal;
    return goal == null ? null : workoutGoal(itemSummary(goal, unit));
  }

  String setTypeLabel(SetType type) => switch (type) {
    SetType.normal => workoutSetNormal,
    SetType.warmup => workoutSetWarmup,
    SetType.drop => workoutSetDrop,
  };

  /// `RIR 2`, or `RPE 8` with [rpe].
  String effortText(int rir, {required bool rpe}) =>
      rpe ? workoutRpe(10 - rir) : workoutRir(rir);

  String durationMinutes(Duration duration) {
    final minutes = (duration.inSeconds / 60).round();
    return workoutMinutes(minutes);
  }

  String recordText(NewRecord record, WeightUnit unit) {
    final value = record.value;
    final text = switch (record.kind) {
      RecordKind.heaviestWeight => recordHeaviestWeight(
        weightText(value, unit),
      ),
      RecordKind.bestE1rm => recordBestE1rm(weightText(value, unit)),
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
