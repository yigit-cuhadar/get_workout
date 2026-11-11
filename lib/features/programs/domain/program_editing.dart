import '../../../core/grouping.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import 'program.dart';

export '../../../core/grouping.dart';

const _defaultRepMin = 8;
const _defaultRepMax = 12;
const _defaultDurationS = 30;

/// A new item for [exercise]: 3 sets of 8-12 reps, or of 30 s for duration
/// exercises, resting the exercise's default rest.
ProgramItem defaultItem(Exercise exercise) {
  final timed = exercise.loggingType.isDurationBased;
  return ProgramItem(
    exerciseId: exercise.id,
    sets: 3,
    repMin: timed ? null : _defaultRepMin,
    repMax: timed ? null : _defaultRepMax,
    durationS: timed ? _defaultDurationS : null,
    restS: exercise.defaultRestS.clamp(0, ProgramLimits.maxRestS),
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
