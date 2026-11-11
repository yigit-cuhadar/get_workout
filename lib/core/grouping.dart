/// Something in a list where adjacent entries sharing a group letter form a
/// superset (two) or a circuit (three or more): program items and the
/// exercises of a workout.
abstract interface class Groupable<T> {
  String? get group;

  /// This entry in [group], or in none for null.
  T withGroup(String? group);
}

/// The entries as they move: a group is one block, any other entry a block
/// of its own. Returns `[start, end)` ranges.
List<(int, int)> groupBlocks<T extends Groupable<T>>(List<T> items) {
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

/// The `[start, end)` range of the group [index] belongs to, or of the entry
/// alone when it has none.
(int, int) groupRange<T extends Groupable<T>>(List<T> items, int index) =>
    groupBlocks(items)
        .firstWhere((block) => block.$1 <= index && index < block.$2);

/// Whether something follows the entry at [index] and its group.
bool canLinkWithNext<T extends Groupable<T>>(List<T> items, int index) =>
    groupRange(items, index).$2 < items.length;

/// The entries [linkWithNext] joins: [index]'s group, or the entry alone,
/// and the group or entry after it.
(int, int) _linkRange<T extends Groupable<T>>(List<T> items, int index) {
  final (start, end) = groupRange(items, index);
  return (start, groupRange(items, end).$2);
}

/// How many entries the group would have after [linkWithNext] of [index];
/// two makes a superset, more a circuit.
int linkedSize<T extends Groupable<T>>(List<T> items, int index) {
  final (start, end) = _linkRange(items, index);
  return end - start;
}

/// Joins the entry at [index], with its group, and the entry or group after
/// it into one group. Needs [canLinkWithNext].
List<T> linkWithNext<T extends Groupable<T>>(List<T> items, int index) {
  final (start, end) = _linkRange(items, index);
  const marker = '*';
  return relabelGroups([
    for (final (i, item) in items.indexed)
      i >= start && i < end ? item.withGroup(marker) : item,
  ]);
}

/// Dissolves the group the entry at [index] belongs to.
List<T> ungroup<T extends Groupable<T>>(List<T> items, int index) {
  final (start, end) = groupRange(items, index);
  return relabelGroups([
    for (final (i, item) in items.indexed)
      i >= start && i < end ? item.withGroup(null) : item,
  ]);
}

/// Removes the entry at [index]; a group left with one entry dissolves.
List<T> removeItem<T extends Groupable<T>>(List<T> items, int index) =>
    relabelGroups([...items]..removeAt(index));

/// Moves the entry at [from] so it lands at [to], as in a plain list move,
/// without splitting a group: within its group it moves on its own;
/// otherwise its whole group moves, and it is never dropped inside another
/// group but next to it.
List<T> moveItem<T extends Groupable<T>>(List<T> items, int from, int to) {
  if (from == to) return items;
  final blocks = groupBlocks(items);
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

/// Letters every group A, B, C... in order and clears the group of entries
/// that are alone in theirs.
List<T> relabelGroups<T extends Groupable<T>>(List<T> items) {
  final result = <T>[];
  var letter = 0;
  for (final (start, end) in groupBlocks(items)) {
    final single = end - start == 1;
    final label = single ? null : String.fromCharCode(0x41 + letter++ % 26);
    for (var i = start; i < end; i++) {
      result.add(items[i].withGroup(label));
    }
  }
  return result;
}
