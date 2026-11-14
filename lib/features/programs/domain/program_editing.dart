import 'dart:math' as math;

import '../../../core/grouping.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import 'program.dart';

const _defaultRepMin = 8;
const _defaultRepMax = 12;
const _defaultDurationS = 30;

/// For a custom exercise, which has no default rest of its own.
const fallbackRestS = 90;

/// [items] with [change] applied to the item at [index] and, when it is in
/// a superset or circuit, to every item of its group, which keeps the
/// group's rounds and rest in step.
List<ProgramItem> editInGroup(
  List<ProgramItem> items,
  int index,
  ProgramItem Function(ProgramItem item) change,
) {
  final (start, end) = groupRange(items, index);
  return [
    for (final (i, item) in items.indexed)
      i >= start && i < end ? change(item) : item,
  ];
}

/// [items] with the group of the item at [index] in step: every item takes
/// the first one's sets (the rounds) and the last one's rest (the rest
/// after the group).
List<ProgramItem> alignGroup(List<ProgramItem> items, int index) {
  final (start, end) = groupRange(items, index);
  final sets = items[start].sets;
  final restS = items[end - 1].restS;
  return editInGroup(
    items,
    index,
    (item) => item.copyWith(sets: sets, restS: restS),
  );
}

/// A new item for [exercise]: 3 sets of 8-12 reps, or of 30 s for duration
/// exercises, resting the exercise's default rest, or 90 s for a custom one.
ProgramItem defaultItem(Exercise exercise) {
  final timed = exercise.loggingType.isDurationBased;
  return ProgramItem(
    exerciseId: exercise.id,
    sets: 3,
    repMin: timed ? null : _defaultRepMin,
    repMax: timed ? null : _defaultRepMax,
    durationS: timed ? _defaultDurationS : null,
    restS: (exercise.defaultRestS ?? fallbackRestS).clamp(
      0,
      ProgramLimits.maxRestS,
    ),
  );
}

/// [item] with the kind of target [type] takes: a rep range, or a
/// duration, the other removed; kept when stored, the defaults of
/// [defaultItem] when not; and a target weight only when [type] logs one.
/// Returns [item] itself when it already fits.
ProgramItem fitToLoggingType(ProgramItem item, LoggingType type) {
  final timed = type.isDurationBased;
  final hasRange = item.repMin != null && item.repMax != null;
  final fitted = item.copyWith(
    repMin: () => timed ? null : (hasRange ? item.repMin : _defaultRepMin),
    repMax: () => timed ? null : (hasRange ? item.repMax : _defaultRepMax),
    durationS: () => timed ? item.durationS ?? _defaultDurationS : null,
    targetKg: () => type.logsWeight ? item.targetKg : null,
  );
  return fitted == item ? item : fitted;
}

/// [item] doing [exercise] instead. Sets, rest and group stay, and the
/// targets as far as they fit; see [fitToLoggingType].
ProgramItem replaceExercise(ProgramItem item, Exercise exercise) =>
    fitToLoggingType(
      item.copyWith(exerciseId: exercise.id),
      exercise.loggingType,
    );

/// The estimated length of [day]. Per set: work, then rest, where work is
/// 3 s per rep at the middle of the rep range or the set's duration. In a
/// group, rest follows only the round's last item, once per round (rounds =
/// the group's most sets).
Duration estimateDay(ProgramDay day) {
  const secondsPerRep = 3;
  int work(ProgramItem item) =>
      item.durationS ??
      (((item.repMin ?? 0) + (item.repMax ?? item.repMin ?? 0)) *
              secondsPerRep /
              2)
          .round();
  var seconds = 0;
  for (final (start, end) in groupBlocks(day.items)) {
    final members = day.items.sublist(start, end);
    if (members.length == 1) {
      final item = members.single;
      seconds += item.sets * (work(item) + item.restS);
      continue;
    }
    var rounds = 0;
    for (final item in members) {
      seconds += item.sets * work(item);
      if (item.sets > rounds) rounds = item.sets;
    }
    seconds += rounds * members.last.restS;
  }
  return Duration(seconds: seconds);
}

/// The shortest and longest session of a program, in whole minutes.
typedef SessionMinutes = ({int min, int max});

/// [days]' [SessionMinutes] by [estimateDay], each day rounded to whole
/// minutes and at least one; null without days. The catalogue stores it on
/// each card.
SessionMinutes? sessionMinutes(List<ProgramDay> days) {
  if (days.isEmpty) return null;
  final minutes = [
    for (final day in days)
      math.max(1, (estimateDay(day).inSeconds / 60).round()),
  ]..sort();
  return (min: minutes.first, max: minutes.last);
}
