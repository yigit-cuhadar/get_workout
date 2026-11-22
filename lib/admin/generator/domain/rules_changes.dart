import 'package:forge_core/forge_core.dart';

import 'generator_rules.dart';

/// One validator problem: where, and what is wrong there.
class RulesProblem extends Equatable {
  const RulesProblem(this.path, this.message);

  /// [text] as the server writes it: `<path>: <problem>`.
  factory RulesProblem.parse(String text) {
    final colon = text.indexOf(': ');
    return colon < 0
        ? RulesProblem(const [], text)
        : RulesProblem(
            parsePath(text.substring(0, colon)),
            text.substring(colon + 2),
          );
  }

  final RulesPath path;
  final String message;

  /// Whether it is about [field] or a part of it; with [exact], about
  /// [field] alone.
  bool concerns(RulesPath field, {bool exact = false}) {
    if (path.length < field.length || (exact && path.length != field.length)) {
      return false;
    }
    for (var i = 0; i < field.length; i++) {
      if (path[i] != field[i]) return false;
    }
    return true;
  }

  @override
  List<Object?> get props => [path, message];
}

enum ChangeKind {
  /// [RulesChange.before] became [RulesChange.after]; for a slot, the whole
  /// slot.
  value,
  added,
  removed,

  /// The ids of a list's kept items, in their old and new order.
  order,
}

/// One change between two versions of the rules.
class RulesChange extends Equatable {
  const RulesChange(
    this.kind, {
    this.beforePath,
    this.afterPath,
    this.before,
    this.after,
  });

  final ChangeKind kind;

  /// Where it is in the old rules (null when added) and in the new ones
  /// (null when removed).
  final RulesPath? beforePath;
  final RulesPath? afterPath;
  final Object? before;
  final Object? after;

  RulesPath get path => afterPath ?? beforePath!;

  @override
  List<Object?> get props => [kind, beforePath, afterPath, before, after];
}

/// The index in [before] of each item of [after] kept from it: items are
/// matched by id, each old one at most once, and the items at [added]
/// never (a new template stays new whatever its id).
List<int?> _matchById(
  List<JsonMap> before,
  List<JsonMap> after, {
  Set<int> added = const {},
}) {
  final taken = <int>{};
  final match = <int?>[];
  for (final (i, item) in after.indexed) {
    int? found;
    for (var j = 0; j < before.length && !added.contains(i); j++) {
      if (!taken.contains(j) && before[j]['id'] == item['id']) {
        found = j;
        break;
      }
    }
    if (found != null) taken.add(found);
    match.add(found);
  }
  return match;
}

/// The path in [loaded] of what [path] is in [draft]: templates and
/// splits are matched by id, the templates at [newTemplates] never; null
/// for one [loaded] does not have.
RulesPath? loadedPathOf(
  GeneratorRules draft,
  GeneratorRules loaded,
  RulesPath path, {
  Set<int> newTemplates = const {},
}) {
  switch (path) {
    case [final String section, final int i, ...final rest]
        when section == 'templates' || section == 'splits':
      final isTemplates = section == 'templates';
      final match = _matchById(
        isTemplates ? loaded.templates : loaded.splits,
        isTemplates ? draft.templates : draft.splits,
        added: isTemplates ? newTemplates : const {},
      );
      return switch (match.elementAtOrNull(i)) {
        final j? => [section, j, ...rest],
        null => null,
      };
    default:
      return path;
  }
}

/// What publishing [after] in place of [before] changes, one change per
/// changed value; templates and splits are matched by id (the templates at
/// [newTemplates] are added whatever their id), a template's changed slot
/// is one change.
List<RulesChange> rulesChanges(
  GeneratorRules before,
  GeneratorRules after, {
  Set<int> newTemplates = const {},
}) {
  final changes = <RulesChange>[];

  void walk(RulesPath pathA, RulesPath pathB, Object? a, Object? b) {
    if (jsonEquals(a, b)) return;
    if (a is Map && b is Map) {
      for (final key in {...a.keys, ...b.keys}) {
        walk([...pathA, '$key'], [...pathB, '$key'], a[key], b[key]);
      }
      return;
    }
    if (a is List && b is List && [...a, ...b].any((item) => item is Map)) {
      for (var i = 0; i < a.length || i < b.length; i++) {
        if (i >= a.length) {
          changes.add(
            RulesChange(
              ChangeKind.added,
              afterPath: [...pathB, i],
              after: b[i],
            ),
          );
        } else if (i >= b.length) {
          changes.add(
            RulesChange(
              ChangeKind.removed,
              beforePath: [...pathA, i],
              before: a[i],
            ),
          );
        } else {
          walk([...pathA, i], [...pathB, i], a[i], b[i]);
        }
      }
      return;
    }
    changes.add(
      RulesChange(
        ChangeKind.value,
        beforePath: pathA,
        afterPath: pathB,
        before: a,
        after: b,
      ),
    );
  }

  /// A template's fields, and its slots one change each.
  void template(RulesPath pathA, RulesPath pathB, JsonMap a, JsonMap b) {
    for (final key in {...a.keys, ...b.keys}) {
      if (key == 'dayList') continue;
      walk([...pathA, key], [...pathB, key], a[key], b[key]);
    }
    final oldDays = a['dayList'] is List ? a['dayList']! as List : const [];
    final newDays = b['dayList'] is List ? b['dayList']! as List : const [];
    for (var d = 0; d < oldDays.length || d < newDays.length; d++) {
      final (dayA, dayB) = ([...pathA, 'dayList', d], [...pathB, 'dayList', d]);
      if (d >= oldDays.length) {
        changes.add(
          RulesChange(ChangeKind.added, afterPath: dayB, after: newDays[d]),
        );
        continue;
      }
      if (d >= newDays.length) {
        changes.add(
          RulesChange(ChangeKind.removed, beforePath: dayA, before: oldDays[d]),
        );
        continue;
      }
      final (oldDay, newDay) = (oldDays[d], newDays[d]);
      if (oldDay is! Map || newDay is! Map) {
        walk(dayA, dayB, oldDay, newDay);
        continue;
      }
      for (final key in {...oldDay.keys, ...newDay.keys}) {
        final (keyA, keyB) = ([...dayA, '$key'], [...dayB, '$key']);
        if (key != 'slots') {
          walk(keyA, keyB, oldDay[key], newDay[key]);
          continue;
        }
        final oldSlots = oldDay[key] is List ? oldDay[key] as List : const [];
        final newSlots = newDay[key] is List ? newDay[key] as List : const [];
        for (var s = 0; s < oldSlots.length || s < newSlots.length; s++) {
          final old = s < oldSlots.length ? oldSlots[s] : null;
          final next = s < newSlots.length ? newSlots[s] : null;
          if (jsonEquals(old, next)) continue;
          changes.add(
            RulesChange(
              old == null
                  ? ChangeKind.added
                  : next == null
                  ? ChangeKind.removed
                  : ChangeKind.value,
              beforePath: old == null ? null : [...keyA, s],
              afterPath: next == null ? null : [...keyB, s],
              before: old,
              after: next,
            ),
          );
        }
      }
    }
  }

  /// The lists at [section] matched by id: added, changed (by [changed]),
  /// removed and reordered.
  void byId(
    String section,
    List<JsonMap> a,
    List<JsonMap> b,
    void Function(RulesPath pathA, RulesPath pathB, JsonMap a, JsonMap b)
    changed, {
    Set<int> added = const {},
  }) {
    final match = _matchById(a, b, added: added);
    for (final (i, item) in b.indexed) {
      switch (match[i]) {
        case final j?:
          changed([section, j], [section, i], a[j], item);
        case null:
          changes.add(
            RulesChange(ChangeKind.added, afterPath: [section, i], after: item),
          );
      }
    }
    for (final (j, item) in a.indexed) {
      if (!match.contains(j)) {
        changes.add(
          RulesChange(
            ChangeKind.removed,
            beforePath: [section, j],
            before: item,
          ),
        );
      }
    }
    final kept = [for (final j in match.nonNulls) a[j]['id']];
    final keptBefore = [
      for (final (j, item) in a.indexed)
        if (match.contains(j)) item['id'],
    ];
    if (!jsonEquals(keptBefore, kept)) {
      changes.add(
        RulesChange(
          ChangeKind.order,
          beforePath: [section],
          afterPath: [section],
          before: keptBefore,
          after: kept,
        ),
      );
    }
  }

  const known = [
    'splits',
    'templates',
    'dosing',
    'grouping',
    'volume',
    'selection',
    'focus',
    'skip',
    'time',
    'lengthWeeks',
  ];
  for (final section in {...known, ...before.json.keys, ...after.json.keys}) {
    final (a, b) = (before.json[section], after.json[section]);
    if (jsonEquals(a, b)) continue;
    switch (section) {
      case 'templates':
        byId(
          section,
          before.templates,
          after.templates,
          template,
          added: newTemplates,
        );
      case 'splits':
        byId(section, before.splits, after.splits, walk);
      default:
        walk([section], [section], a, b);
    }
  }
  return changes;
}
