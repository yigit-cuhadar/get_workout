import 'package:forge_core/forge_core.dart';

import '../../exercises/domain/vocabulary.dart';
import 'program.dart';

enum ProgramIssue {
  nameMissing,
  nameTooLong,
  lengthWeeksOutOfRange,
  noDays,
  tooManyDays,
}

enum DayIssue { nameTooLong, noItems, tooManyItems }

enum ItemIssue {
  /// The exercise is not in the catalogue: deleted, retired or unknown.
  exerciseUnavailable,
  setsOutOfRange,
  repsMissing,
  repsOutOfRange,
  repRangeInverted,
  durationMissing,
  durationOutOfRange,
  restOutOfRange,
  targetOutOfRange,

  /// A rep range on a duration exercise, a duration on a rep-based one, or
  /// a target on one that logs no weight.
  wrongTarget,

  /// The group has only this item, or its items are not adjacent.
  groupInvalid,
}

/// The position of an item: its day and its place in that day.
typedef ItemRef = ({int day, int item});

/// Everything wrong with a program, by where it shows in the builder.
class ProgramValidation extends Equatable {
  const ProgramValidation({
    this.program = const {},
    this.days = const {},
    this.items = const {},
  });

  final Set<ProgramIssue> program;

  /// Only days with issues are keys.
  final Map<int, Set<DayIssue>> days;

  /// Only items with issues are keys.
  final Map<ItemRef, Set<ItemIssue>> items;

  bool get isValid => program.isEmpty && days.isEmpty && items.isEmpty;

  Set<DayIssue> dayIssues(int day) => days[day] ?? const {};

  Set<ItemIssue> itemIssues(int day, int item) =>
      items[(day: day, item: item)] ?? const {};

  @override
  List<Object?> get props => [program, days, items];
}

/// Validates [program]; [loggingTypes] has the logging type of every
/// available exercise by id.
ProgramValidation validateProgram(
  Program program,
  Map<String, LoggingType> loggingTypes,
) {
  final name = program.name.trim();
  final weeks = program.lengthWeeks;
  final dayCount = program.days.length;
  final days = <int, Set<DayIssue>>{};
  final items = <ItemRef, Set<ItemIssue>>{};
  for (final (d, day) in program.days.indexed) {
    final dayIssues = {
      if (day.name.trim().length > ProgramLimits.maxDayNameLength)
        DayIssue.nameTooLong,
      if (day.items.isEmpty) DayIssue.noItems,
      if (day.items.length > ProgramLimits.maxItemsPerDay)
        DayIssue.tooManyItems,
    };
    if (dayIssues.isNotEmpty) days[d] = dayIssues;
    final badGroups = invalidGroupIndexes(day.items);
    for (final (i, item) in day.items.indexed) {
      final itemIssues = {
        ...validateItem(item, loggingTypes[item.exerciseId]),
        if (badGroups.contains(i)) ItemIssue.groupInvalid,
      };
      if (itemIssues.isNotEmpty) items[(day: d, item: i)] = itemIssues;
    }
  }
  return ProgramValidation(
    program: {
      if (name.isEmpty) ProgramIssue.nameMissing,
      if (name.length > ProgramLimits.maxNameLength) ProgramIssue.nameTooLong,
      if (weeks != null &&
          !_within(
            weeks,
            ProgramLimits.minLengthWeeks,
            ProgramLimits.maxLengthWeeks,
          ))
        ProgramIssue.lengthWeeksOutOfRange,
      if (dayCount == 0) ProgramIssue.noDays,
      if (dayCount > ProgramLimits.maxDays) ProgramIssue.tooManyDays,
    },
    days: days,
    items: items,
  );
}

/// What is wrong with [item] on its own; [type] is its exercise's logging
/// type, null when the exercise is unavailable (only ranges are then
/// checked). NaN fails every range.
Set<ItemIssue> validateItem(ProgramItem item, LoggingType? type) {
  final repMin = item.repMin;
  final repMax = item.repMax;
  final duration = item.durationS;
  final target = item.targetKg;
  final hasReps = repMin != null || repMax != null;
  bool repsOk(int? reps) =>
      reps == null ||
      _within(reps, ProgramLimits.minReps, ProgramLimits.maxReps);
  return {
    if (type == null) ItemIssue.exerciseUnavailable,
    if (!_within(item.sets, ProgramLimits.minSets, ProgramLimits.maxSets))
      ItemIssue.setsOutOfRange,
    if (type != null &&
        !type.isDurationBased &&
        (repMin == null || repMax == null))
      ItemIssue.repsMissing,
    if (!repsOk(repMin) || !repsOk(repMax)) ItemIssue.repsOutOfRange,
    if (repMin != null && repMax != null && repMin > repMax)
      ItemIssue.repRangeInverted,
    if (type != null && type.isDurationBased && duration == null)
      ItemIssue.durationMissing,
    if (duration != null &&
        !_within(
          duration,
          ProgramLimits.minDurationS,
          ProgramLimits.maxDurationS,
        ))
      ItemIssue.durationOutOfRange,
    if (!_within(item.restS, 0, ProgramLimits.maxRestS))
      ItemIssue.restOutOfRange,
    if (target != null && !_within(target, 0, ProgramLimits.maxTargetKg))
      ItemIssue.targetOutOfRange,
    if (type != null &&
        ((type.isDurationBased && hasReps) ||
            (!type.isDurationBased && duration != null) ||
            (!type.logsWeight && target != null)))
      ItemIssue.wrongTarget,
  };
}

/// The indexes of grouped [items] whose group has a single item or is
/// split by other items.
Set<int> invalidGroupIndexes(List<ProgramItem> items) {
  final runs = <String, int>{};
  final members = <String, List<int>>{};
  String? previous;
  for (final (i, item) in items.indexed) {
    final group = item.group;
    if (group != null) {
      members.putIfAbsent(group, () => []).add(i);
      if (group != previous) runs[group] = (runs[group] ?? 0) + 1;
    }
    previous = group;
  }
  return {
    for (final MapEntry(key: group, value: indexes) in members.entries)
      if (indexes.length < 2 || runs[group]! > 1) ...indexes,
  };
}

/// False for NaN, whose comparisons are all false.
bool _within(num value, num min, num max) => value >= min && value <= max;
