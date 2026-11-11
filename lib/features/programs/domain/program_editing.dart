import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import 'program.dart';

const _defaultRepMin = 8;
const _defaultRepMax = 12;
const _defaultDurationS = 30;

/// For a custom exercise, which has no default rest of its own.
const _defaultRestS = 90;

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
    restS: (exercise.defaultRestS ?? _defaultRestS).clamp(
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

/// The items of a day as they move: a group is one block, any other item a
/// block of its own. Returns `[start, end)` ranges.
List<(int, int)> _blocks(List<ProgramItem> items) {
  final blocks = <(int, int)>[];
  var start = 0;
  for (var i = 1; i <= items.length; i++) {
    final group = items[start].group;
    if (i == items.length || group == null || items[i].group != group) {
      blocks.add((start, i));
      start = i;
    }
  }
  return blocks;
}

/// The `[start, end)` range of the group [index] belongs to, or of the item
/// alone when it has none.
(int, int) groupRange(List<ProgramItem> items, int index) =>
    _blocks(items).firstWhere((block) => block.$1 <= index && index < block.$2);

/// Whether something follows the item at [index] and its group.
bool canLinkWithNext(List<ProgramItem> items, int index) =>
    groupRange(items, index).$2 < items.length;

/// The items [linkWithNext] joins: [index]'s group, or the item alone, and
/// the group or item after it.
(int, int) _linkRange(List<ProgramItem> items, int index) {
  final (start, end) = groupRange(items, index);
  return (start, groupRange(items, end).$2);
}

/// How many items the group would have after [linkWithNext] of [index];
/// two makes a superset, more a circuit.
int linkedSize(List<ProgramItem> items, int index) {
  final (start, end) = _linkRange(items, index);
  return end - start;
}

/// Joins the item at [index], with its group, and the item or group after
/// it into one group. Needs [canLinkWithNext].
List<ProgramItem> linkWithNext(List<ProgramItem> items, int index) {
  final (start, end) = _linkRange(items, index);
  const marker = '*';
  return relabelGroups([
    for (final (i, item) in items.indexed)
      i >= start && i < end ? item.copyWith(group: () => marker) : item,
  ]);
}

/// Dissolves the group the item at [index] belongs to.
List<ProgramItem> ungroup(List<ProgramItem> items, int index) {
  final (start, end) = groupRange(items, index);
  return relabelGroups([
    for (final (i, item) in items.indexed)
      i >= start && i < end ? item.copyWith(group: () => null) : item,
  ]);
}

/// Removes the item at [index]; a group left with one item dissolves.
List<ProgramItem> removeItem(List<ProgramItem> items, int index) =>
    relabelGroups([...items]..removeAt(index));

/// Moves the item at [from] so it lands at [to], as in a plain list move,
/// without splitting a group: within its group it moves on its own;
/// otherwise its whole group moves, and it is never dropped inside another
/// group but next to it.
List<ProgramItem> moveItem(List<ProgramItem> items, int from, int to) {
  if (from == to) return items;
  final blocks = _blocks(items);
  int blockOf(int index) =>
      blocks.indexWhere((block) => block.$1 <= index && index < block.$2);
  final source = blockOf(from);
  final (start, end) = blocks[source];
  if (end - start > 1 && to >= start && to < end) {
    final moved = [...items];
    moved.insert(to, moved.removeAt(from));
    return moved;
  }
  final target = blockOf(to);
  final order = [...blocks]..removeAt(source);
  // Moving down lands after the target block, moving up before it.
  final at = order.indexOf(blocks[target]) + (to > from ? 1 : 0);
  order.insert(at, blocks[source]);
  return relabelGroups([for (final (s, e) in order) ...items.sublist(s, e)]);
}

/// Letters every group A, B, C... in order and clears the group of items
/// that are alone in theirs.
List<ProgramItem> relabelGroups(List<ProgramItem> items) {
  final result = <ProgramItem>[];
  var letter = 0;
  for (final (start, end) in _blocks(items)) {
    final single = end - start == 1;
    final label = single ? null : String.fromCharCode(0x41 + letter++ % 26);
    for (var i = start; i < end; i++) {
      result.add(items[i].copyWith(group: () => label));
    }
  }
  return result;
}

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
  for (final (start, end) in _blocks(day.items)) {
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
