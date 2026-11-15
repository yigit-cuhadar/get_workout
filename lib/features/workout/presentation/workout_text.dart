import 'package:intl/intl.dart';

import '../../../core/grouping.dart';

import '../../../l10n/app_localizations.dart';
import '../../calculators/domain/plates.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/effort.dart';
import '../domain/exercise_stats.dart';
import '../domain/progression.dart';
import '../domain/set_logging.dart';
import '../domain/set_selection.dart';
import '../domain/workout.dart';
import '../domain/workout_editing.dart' as editing;

extension WorkoutText on AppLocalizations {
  /// The plates on each side of the bar in the plate breakdown, heaviest
  /// first, each plate on its own: `25 + 25 + 1.25 kg`; a dash for none.
  String platesEachSideText(List<PlateCount> perSide, WeightUnit unit) {
    if (perSide.isEmpty) return '—';
    final number = NumberFormat.decimalPattern(localeName)
      ..maximumFractionDigits = 2;
    final plates = [
      for (final plate in perSide)
        for (var i = 0; i < plate.count; i++)
          number.format(unit.fromKg(plate.weightKg)),
    ].join(' + ');
    return switch (unit) {
      WeightUnit.kg => programWeightKg(plates),
      WeightUnit.lb => programWeightLb(plates),
    };
  }

  /// Set [set] of [exercise] as the set column labels it: a warm-up as
  /// such, else its number among the working sets, marked for a drop set.
  String setLabel(WorkoutExercise exercise, int set) {
    final number = exercise.sets.take(set + 1).where((s) => !s.isWarmup).length;
    return switch (exercise.sets[set].type) {
      SetType.warmup => workoutWarmupShort,
      SetType.drop => '$number$workoutDropShort',
      SetType.normal => '$number',
    };
  }

  /// Set [set] of [exercise] as the one to do now, its kind in words:
  /// `Bench Press · set 2 of 3`, `Bench Press · Drop set 2 of 3` (out of
  /// the working sets), `Bench Press · Warm-up 1 of 2` (out of the
  /// warm-ups), or `Bench Press · Warm-up` for the only one.
  String setToDo(WorkoutExercise exercise, int set) {
    final sets = exercise.sets;
    final type = sets[set].type;
    final before = sets.take(set + 1);
    if (type == SetType.warmup) {
      final warmups = sets.where((s) => s.isWarmup).length;
      return warmups == 1
          ? workoutSetToDoWarmup(exercise.name)
          : workoutSetToDoWarmupOf(
              exercise.name,
              before.where((s) => s.isWarmup).length,
              warmups,
            );
    }
    final number = before.where((s) => !s.isWarmup).length;
    final working = sets.where((s) => !s.isWarmup).length;
    return type == SetType.drop
        ? workoutSetToDoDrop(exercise.name, number, working)
        : workoutLockScreenCurrent(exercise.name, '$number', working);
  }

  /// After a rest, set [set] of [exercise] as [setToDo] names it, e.g.
  /// `Next: Bench Press · Warm-up 1 of 2`.
  String restNextText(WorkoutExercise exercise, int set) =>
      restNotificationNext(setToDo(exercise, set));

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

  /// Set [index] of [exercise] for a screen reader, e.g. `Set 2, done`,
  /// `Warm-up set` or `Set 2, drop set`.
  String setBubbleLabel(WorkoutExercise exercise, int index) {
    final set = exercise.sets[index];
    final number = exercise.sets
        .take(index + 1)
        .where((s) => !s.isWarmup)
        .length;
    final label = switch (set.type) {
      SetType.warmup => workoutWarmupBubble,
      SetType.drop => workoutDropBubble(number),
      SetType.normal => workoutSetBubble(number),
    };
    return set.done ? workoutBubbleDone(label) : label;
  }

  String setTypeLabel(SetType type) => switch (type) {
    SetType.normal => workoutSetNormal,
    SetType.warmup => workoutSetWarmup,
    SetType.drop => workoutSetDrop,
  };

  /// What a set of [type] is, in one line.
  String setTypeHint(SetType type) => switch (type) {
    SetType.normal => workoutSetNormalHint,
    SetType.warmup => workoutSetWarmupHint,
    SetType.drop => workoutSetDropHint,
  };

  /// What [step] of [scale] means in one line, e.g. `1 rep left`; the
  /// scale's easiest step stands for that many reps left or more.
  String effortStepMeaning(EffortStep step, EffortScale scale) {
    if (step.failed) return effortFailedMeaning;
    if (scale == EffortScale.byFeel && step.rir == 2) {
      return helpRepsLeftRange(2, 3);
    }
    return step == scale.steps.first
        ? helpRepsLeftPlus(step.rir)
        : helpRepsLeft(step.rir);
  }

  /// [effortStepMeaning] as short as an answer row has it, e.g. `4+ reps
  /// left`, `last rep missed`.
  String effortStepShortMeaning(EffortStep step, EffortScale scale) {
    if (step.failed) return effortFailedShort;
    if (scale == EffortScale.byFeel && step.rir == 2) {
      return helpRepsLeftRange(2, 3);
    }
    return step == scale.steps.first
        ? effortRepsLeftPlus(step.rir)
        : helpRepsLeft(step.rir);
  }

  /// What adding a set of [type] does, in the add-set sheet.
  String addSetHint(SetType type) => switch (type) {
    SetType.normal => addSetNormalHint,
    SetType.warmup => addSetWarmupHint,
    SetType.drop => addSetDropHint,
  };

  /// The workout's short name where space is tight: a program day's name
  /// without its program's (`Push`, kept as `Push Pull Legs · Push`) while
  /// [programs] still has that program; else its name.
  String workoutShortName(Workout workout, List<Program> programs) {
    final program = programs
        .where((p) => p.id == workout.programId)
        .firstOrNull;
    if (program == null || !workout.isFromProgram) return workout.name;
    final prefix = workoutProgramDayName(program.name, '');
    final name = workout.name;
    return name.startsWith(prefix) && name.length > prefix.length
        ? name.substring(prefix.length)
        : name;
  }

  /// The workout header's line: its [name] (see [workoutShortName]) and,
  /// while a set is to do, the [selected] set's exercise among all, e.g.
  /// `Push · exercise 1 of 6`.
  String workoutHeaderLine(
    Workout workout,
    String name,
    SetSelection? selected,
  ) {
    final exercise = selected?.exercise;
    if (exercise == null || !workout.hasUndoneSets) return name;
    return workoutHeaderProgress(name, exercise + 1, workout.exercises.length);
  }

  /// The open card's last time: its date and best working set
  /// ([bestSet]) in [unit], e.g. `Last time: Fri, Nov 6 · 82.5 kg × 6`.
  String lastSessionText(LastSession last, LoggingType type, WeightUnit unit) {
    final best = bestSet(last.sets, type);
    final date = DateFormat.MMMEd(localeName).format(last.date);
    return best == null
        ? workoutLastTime(date)
        : workoutLastTimeBest(date, setWithUnitText(best, type, unit));
  }

  /// The rest panel's line on what comes after the rest, [next] of
  /// [workout] when one is left: `next: set 4 · 82.5 × 8` with its
  /// [values] (none while unknown), the exercise named instead of the set
  /// when it is not [after]'s; `All sets done` otherwise.
  String restPanelNextText(
    Workout workout,
    SetRef? next,
    SetRef? after,
    SetValues values,
    WeightUnit unit,
  ) {
    if (next == null) return restPanelAllSetsDone;
    final exercise = workout.exercises[next.exercise];
    final set = exercise.sets[next.set];
    final number = exercise.sets
        .take(next.set + 1)
        .where((s) => !s.isWarmup)
        .length;
    final what = next.exercise != after?.exercise || set.isWarmup
        ? exercise.name
        : set.type == SetType.drop
        ? effortAskDropSetName(number)
        : effortAskSetName(number);
    final shown = setText(
      WorkoutSet(
        weightKg: values.weightKg,
        reps: values.reps,
        durationS: values.durationS,
      ),
      exercise.loggingType,
      unit,
    );
    return restPanelNext(shown.isEmpty ? what : '$what · $shown');
  }

  /// Set [index] of [exercise] by its kind and number among the working
  /// sets, e.g. `Set 2`, `Drop set 3`.
  String ratedSetName(WorkoutExercise exercise, int index) {
    final sets = exercise.sets;
    final number = sets.take(index + 1).where((s) => !s.isWarmup).length;
    return sets[index].type == SetType.drop
        ? effortDropSetName(number)
        : effortSetName(number);
  }

  /// The effort question about set [index] of [exercise] just done, e.g.
  /// `How hard was set 3?`, `RPE of drop set 2?`.
  String effortAskTitle(
    EffortScale scale,
    WorkoutExercise exercise,
    int index,
  ) {
    final sets = exercise.sets;
    final number = sets.take(index + 1).where((s) => !s.isWarmup).length;
    final set = sets[index].type == SetType.drop
        ? effortAskDropSetName(number)
        : effortAskSetName(number);
    return switch (scale) {
      EffortScale.byFeel => effortAskFeel(set),
      EffortScale.rir => effortRirTitle,
      EffortScale.rpe => effortRpeTitle,
    };
  }

  /// What the effort row of [scale] asks about selected done set [index]
  /// of [exercise], e.g. `Set 1 · how hard was it?`.
  String effortRowQuestion(
    EffortScale scale,
    WorkoutExercise exercise,
    int index,
  ) {
    final set = ratedSetName(exercise, index);
    return switch (scale) {
      EffortScale.byFeel => effortRowFeel(set),
      EffortScale.rir => effortRowRir(set),
      EffortScale.rpe => effortRowRpe(set),
    };
  }

  /// What set [asked] of [workout] just did, under its effort question,
  /// in [unit]: `80 kg × 8`, its exercise first when it is not the
  /// [selected] one.
  String effortAskValues(
    Workout workout,
    SetRef asked,
    SetSelection? selected,
    WeightUnit unit,
  ) {
    final exercise = workout.exercises[asked.exercise];
    final values = setWithUnitText(
      exercise.sets[asked.set],
      exercise.loggingType,
      unit,
    );
    return selected?.exercise == asked.exercise
        ? values
        : effortAskValuesOf(exercise.name, values);
  }

  /// The effort question of [scale] asked while no rest runs, under the
  /// set it is about ([effortDoneValues]), e.g. `How hard was it?`.
  String effortQuestionText(EffortScale scale) => switch (scale) {
    EffortScale.byFeel => effortQuestionFeel,
    EffortScale.rir => effortRirTitle,
    EffortScale.rpe => effortRpeTitle,
  };

  /// Set [asked] of [workout] as done, over the effort question asked
  /// while no rest runs, in [unit]: `Set 1 done · 82.5 kg × 8`, its
  /// exercise first when it is not the [selected] one.
  String effortDoneValues(
    Workout workout,
    SetRef asked,
    SetSelection? selected,
    WeightUnit unit,
  ) {
    final exercise = workout.exercises[asked.exercise];
    final done = effortQuestionDone(
      ratedSetName(exercise, asked.set),
      setWithUnitText(exercise.sets[asked.set], exercise.loggingType, unit),
    );
    return selected?.exercise == asked.exercise
        ? done
        : effortAskValuesOf(exercise.name, done);
  }

  /// The progress of [exercise] in working sets, e.g. `Squat · 1/3`, as
  /// "of N" counts them everywhere.
  String exerciseProgress(WorkoutExercise exercise) => workoutExerciseProgress(
    exercise.name,
    workingSets(exercise.sets).length,
    exercise.sets.where((s) => !s.isWarmup).length,
  );

  /// [step] as a choice of [scale] shows it: `Easy`, `4` (RIR), `RPE 7`,
  /// `RPE 6 or less`, `Failed`.
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
      EffortScale.rpe =>
        step.rir >= 4 ? effortRpeSixOrLess : workoutRpe(10 - step.rir),
    };
  }

  /// The effort of [set] on [scale], e.g. `Hard`, `RIR 2`, `RPE 8` or
  /// `Failed`; null without one.
  String? effortText(WorkoutSet set, EffortScale scale) {
    final step = scale.stepOf(set);
    if (step == null) return null;
    if (step.failed) return effortFailed;
    return switch (scale) {
      EffortScale.byFeel || EffortScale.rpe => effortStepLabel(step, scale),
      EffortScale.rir => workoutRir(step.rir),
    };
  }

  /// A set as it was done with the weight's unit, e.g. `80 kg × 8`,
  /// `+10 kg × 8` (added) or `−20 kg × 8` (assistance).
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
    final weight = liftedWeightText(kg, unit);
    // As the weight field's label says: added, or assistance.
    final load = switch (type) {
      LoggingType.weightedBodyweight => workoutAddedWeight(weight),
      LoggingType.assistedBodyweight => setPanelAssist(weight),
      _ => weight,
    };
    return '$load × $work';
  }

  /// [setWithUnitText] followed by a drop set's drops, e.g. `80 kg × 6 ·
  /// 60 × 8 · 40 × 10`.
  String setWithDropsText(WorkoutSet set, LoggingType type, WeightUnit unit) =>
      [
        setWithUnitText(set, type, unit),
        for (final drop in set.drops)
          setText(
            WorkoutSet(weightKg: drop.weightKg, reps: drop.reps),
            type,
            unit,
          ),
      ].join(' · ');

  /// The label set [index] of [exercise] would get as a set of [type],
  /// moved where [editing.retypedSetPosition] puts it.
  String setLabelAs(WorkoutExercise exercise, int index, SetType type) {
    final set = exercise.sets[index];
    if (set.type == type) return setLabel(exercise, index);
    final to = editing.retypedSetPosition(exercise, index, type);
    final retyped = exercise.copyWith(
      sets: [...exercise.sets]
        ..removeAt(index)
        ..insert(to, set.copyWith(type: type)),
    );
    return setLabel(retyped, to);
  }

  /// Whole minutes; under one, "< 1 min".
  String durationMinutes(Duration duration) {
    if (duration.inSeconds < 60) return workoutUnderAMinute;
    return workoutMinutes((duration.inSeconds / 60).round());
  }

  /// The header of the set table of an exercise of [type]: set, the values
  /// [setValues] gives, then effort.
  List<String> setColumns(LoggingType type, WeightUnit unit) => [
    historySet,
    if (type.logsWeight) weightLabel(type, unit),
    if (type.logsReps) workoutReps,
    if (type.isDurationBased) historyTime,
    historyEffort,
  ];

  /// [set] in the value columns of [setColumns]: the weight in [unit]
  /// without the unit (none when there is none or it is 0, as [setText]),
  /// reps or time.
  List<String> setValues(WorkoutSet set, LoggingType type, WeightUnit unit) {
    final kg = set.weightKg;
    final seconds = set.durationS;
    return [
      if (type.logsWeight) kg == null || kg == 0 ? '' : weightField(kg, unit),
      if (type.logsReps) '${set.reps ?? ''}',
      if (type.isDurationBased) seconds == null ? '' : programSeconds(seconds),
    ];
  }

  /// The effort of [set] on [scale] and its note, e.g. `Hard · last rep
  /// slow`; empty without either.
  String setRemark(WorkoutSet set, EffortScale scale) =>
      [?effortText(set, scale), ?set.note].join(' · ');

  String lastTimeText(DateTime date) =>
      workoutLastTime(DateFormat.MMMEd(localeName).format(date));
}

/// Exercise [index] of a superset or circuit by its group and place in it,
/// e.g. `A1`.
String groupItemLabel(List<WorkoutExercise> exercises, int index) {
  final (start, _) = groupRange(exercises, index);
  return '${exercises[index].group ?? ''}${index - start + 1}';
}
