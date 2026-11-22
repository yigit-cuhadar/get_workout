import 'package:forge_core/forge_core.dart';

import 'generator_rules.dart';

/// The parts of the rules page, each editing some of the rules' sections.
enum RulesTab {
  templates('Templates', {'splits', 'templates'}),
  dosing('Dosing', {'dosing', 'grouping'}),
  volume('Volume', {'volume'}),
  selection('Selection', {'selection'}),
  areas('Areas', {'focus', 'skip', 'time', 'lengthWeeks'});

  const RulesTab(this.label, this.sections);

  final String label;

  /// The top-level keys of the rules it edits.
  final Set<String> sections;
}

/// The tab that edits [path]; null for a path outside every tab.
RulesTab? tabOf(RulesPath path) => switch (path.firstOrNull) {
  final String section =>
    RulesTab.values.where((tab) => tab.sections.contains(section)).firstOrNull,
  _ => null,
};

/// A stored code as words: `build_muscle` → "Build muscle".
String codeWords(String code) {
  final words = code.replaceAll('_', ' ');
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

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

  RulesTab? get tab => tabOf(path);

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

/// One changed value of the rules, as the review lists it.
class RulesChange extends Equatable {
  const RulesChange({
    required this.path,
    required this.where,
    required this.now,
    required this.after,
  });

  /// Where it is in the rules after the change (before, for a removal).
  final RulesPath path;
  final String where;
  final String now;
  final String after;

  RulesTab? get tab => tabOf(path);

  @override
  List<Object?> get props => [path, where, now, after];
}

const _sections = {
  'splits': 'Splits',
  'templates': 'Templates',
  'dosing': 'Dosing',
  'grouping': 'Dosing · grouping',
  'volume': 'Volume',
  'selection': 'Selection',
  'focus': 'Areas · focus',
  'skip': 'Areas · leave out',
  'time': 'Areas · time',
  'lengthWeeks': 'Areas · length in weeks',
};

/// The rules' field names as words; any other key is a code.
const _fields = {
  'restS': 'rest',
  'holdS': 'hold',
  'sets': 'sets',
  'reps': 'reps',
  'bodyweightReps': 'bodyweight reps',
  'cap': 'cap',
  'tier': 'tier',
  'equipment': 'equipment',
  'goalEquipment': 'goal extra',
  'aboveLevel': 'above level',
  'repeat': 'repeat',
  'family': 'family',
  'popularity': 'popularity',
  'variety': 'variety',
  'extraSets': 'extra sets',
  'max': 'most areas',
  'setupS': 'setup per exercise',
  'sessionMinutes': 'session lengths',
  'sessionMax': 'sessions up to',
  'roles': 'roles',
  'size': 'size',
  'goals': 'goals',
  'name': 'name',
  'info': 'info',
  'extras': 'extra focus muscles',
  'pick': 'picks',
  'patterns': 'patterns',
  'muscles': 'muscles',
  'mechanic': 'mechanic',
  'priority': 'priority',
  'key': 'key',
  'role': 'role',
  'split': 'split',
  'days': 'days a week',
  'levels': 'levels',
  'id': 'id',
  'slots': 'slots',
  'dayList': 'days',
};

/// Keys that add nothing a reader needs.
const _silent = {'targets', 'areas', 'l10n', 'en'};

/// Text values shown as typed, not as codes.
const _texts = {'id', 'name', 'info', 'key', 'split'};

const _rangeKeys = {'reps', 'bodyweightReps'};

String _dayName(Object? day, int index) => switch (day) {
  {'l10n': {'en': {'name': final String name}}} when name.trim().isNotEmpty =>
    name,
  _ => 'Day ${index + 1}',
};

/// The words for [path] from [from] on; [day] names a day of [dayList].
List<String> _words(RulesPath path, int from, {Object? dayList}) {
  final words = <String>[];
  for (var i = from; i < path.length; i++) {
    final segment = path[i];
    final parent = i > 0 ? path[i - 1] : null;
    switch (segment) {
      case final int index when parent == 'dayList':
        words.add(
          _dayName(
            dayList is List ? dayList.elementAtOrNull(index) : null,
            index,
          ),
        );
      case final int index when parent == 'slots':
        words.add('slot ${index + 1}');
      case final int index when parent == 'grouping':
        words.add('rule ${index + 1}');
      case final int index
          when _rangeKeys.contains(parent) || (i > 1 && path[i - 2] == 'sets'):
        words.add(index == 0 ? 'min' : 'max');
      case final int index:
        words.add('#${index + 1}');
      case 'dayList' || 'slots' when i + 1 < path.length:
        break;
      case final String key when i == 0:
        words.add(_sections[key] ?? key);
      case final String key when _silent.contains(key):
        break;
      case final String key:
        words.add(_fields[key] ?? codeWords(key));
    }
  }
  return words;
}

/// Where [path] is, in words, naming templates, splits and days as
/// [rules] has them: "Template upper_lower_4 · Upper A · slot 3 · role".
String placeOf(GeneratorRules rules, RulesPath path) {
  final words = switch (path) {
    ['templates', final int t, ...] => [
      'Template ${rules.at(['templates', t, 'id']) ?? '#${t + 1}'}',
      ..._words(path, 2, dayList: rules.at(['templates', t, 'dayList'])),
    ],
    ['splits', final int s, ...] => [
      'Split ${rules.at(['splits', s, 'id']) ?? '#${s + 1}'}',
      ..._words(path, 2),
    ],
    _ => _words(path, 0),
  };
  return words.isEmpty ? 'The rules' : words.join(' · ');
}

/// The path in [loaded] of what [path] is in [draft]: templates and
/// splits are matched by id; null for one [loaded] does not have.
RulesPath? loadedPathOf(
  GeneratorRules draft,
  GeneratorRules loaded,
  RulesPath path,
) => switch (path) {
  ['templates', final int t, ...final rest] => switch (loaded.templateIndex(
    draft.at(['templates', t, 'id']),
  )) {
    final index? => ['templates', index, ...rest],
    null => null,
  },
  ['splits', final int s, ...final rest] => switch (loaded.splitIndex(
    draft.at(['splits', s, 'id']),
  )) {
    final index? => ['splits', index, ...rest],
    null => null,
  },
  _ => path,
};

bool _inSeconds(RulesPath path) =>
    path.any((segment) => const {'restS', 'holdS', 'setupS'}.contains(segment));

bool _inMinutes(RulesPath path) => path.any(
  (segment) => const {'sessionMax', 'sessionMinutes'}.contains(segment),
);

bool _isRange(RulesPath path) =>
    path.contains('sets') ||
    (path.isNotEmpty && _rangeKeys.contains(path.last));

String _item(RulesPath path, Object? value) => switch (value) {
  final String text when path.isNotEmpty && _texts.contains(path.last) => text,
  final String code => codeWords(code),
  null => '—',
  _ => '$value',
};

/// The labels of what a slot's [pick] asks for: patterns, muscles and
/// mechanic.
List<String> pickLabels(Object? pick) => [
  if (pick is Map) ...[
    for (final key in const ['patterns', 'muscles'])
      if (pick[key] case final List<Object?> codes)
        for (final code in codes) codeWords('$code'),
    if (pick['mechanic'] case final String mechanic) codeWords(mechanic),
  ],
];

/// A slot in a line: "Primary · Squat, Quads · isolation · priority 1".
String slotSummary(Object? slot) {
  if (slot is! Map) return '—';
  final picks = pickLabels(slot['pick']);
  return [
    codeWords('${slot['role'] ?? '?'}'),
    if (picks.isNotEmpty) picks.join(', '),
    'priority ${slot['priority'] ?? '?'}',
    if (slot['key'] case final String key) 'key $key',
  ].join(' · ');
}

/// [value] at [path] as the page shows it; with [units], seconds and
/// minutes say so.
String valueText(RulesPath path, Object? value, {bool units = false}) {
  final unit = !units
      ? ''
      : _inSeconds(path)
      ? ' s'
      : _inMinutes(path)
      ? ' min'
      : '';
  return switch (value) {
    null when path.isNotEmpty && path.last == 'goals' => 'every goal',
    null when path.contains('targets') => '0',
    null => 'none',
    [final num low, final num high] when _isRange(path) => '$low–$high$unit',
    final List<Object?> items when items.isEmpty => 'none',
    final List<Object?> items =>
      '${items.map((item) => _item(path, item)).join(', ')}$unit',
    final Map<Object?, Object?> _
        when path.length > 1 && path[path.length - 2] == 'slots' =>
      slotSummary(value),
    final Map<Object?, Object?> _ when path.lastOrNull == 'pick' =>
      pickLabels(value).isEmpty ? 'nothing' : pickLabels(value).join(', '),
    final Map<Object?, Object?> _ => 'set',
    final num number => '$number$unit',
    _ => _item(path, value),
  };
}

final _verb = RegExp(r' · (added|removed|changed)$');

/// What publishing [after] in place of [before] changes, one line per
/// changed value; templates and splits are matched by id, a template's
/// changed slot is one line.
List<RulesChange> rulesChanges(GeneratorRules before, GeneratorRules after) {
  final changes = <RulesChange>[];

  void line(RulesPath path, List<String> words, String now, String next) =>
      changes.add(
        RulesChange(
          path: path,
          // "slot 3 changed", not "slot 3 · changed".
          where: words
              .join(' · ')
              .replaceFirstMapped(_verb, (match) => ' ${match[1]}'),
          now: now,
          after: next,
        ),
      );

  void walk(RulesPath path, List<String> words, Object? a, Object? b) {
    if (jsonEquals(a, b)) return;
    if (a is Map && b is Map) {
      for (final key in {...a.keys, ...b.keys}) {
        final child = [...path, '$key'];
        walk(
          child,
          [...words, ..._words(child, child.length - 1)],
          a[key],
          b[key],
        );
      }
      return;
    }
    if (a is List && b is List && [...a, ...b].any((item) => item is Map)) {
      for (var i = 0; i < a.length || i < b.length; i++) {
        final child = [...path, i];
        final itemWords = [...words, ..._words(child, child.length - 1)];
        if (i >= a.length) {
          line(child, [...itemWords, 'added'], '—', 'added');
        } else if (i >= b.length) {
          line(child, [...itemWords, 'removed'], 'there', '—');
        } else {
          walk(child, itemWords, a[i], b[i]);
        }
      }
      return;
    }
    line(
      path,
      words,
      valueText(path, a, units: true),
      valueText(path, b, units: true),
    );
  }

  /// The lists at [section] matched by id: added, removed, changed (by
  /// [changed]) and reordered.
  void byId(
    String section,
    String noun,
    List<JsonMap> a,
    List<JsonMap> b,
    void Function(RulesPath path, List<String> words, JsonMap a, JsonMap b)
    changed,
  ) {
    final oldIds = [for (final item in a) item['id']];
    final newIds = [for (final item in b) item['id']];
    for (final (i, item) in b.indexed) {
      final words = ['$noun ${item['id']}'];
      final old = oldIds.indexOf(item['id']);
      if (old < 0) {
        line([section, i], [...words, 'added'], '—', 'added');
      } else {
        changed([section, i], words, a[old], item);
      }
    }
    for (final (i, item) in a.indexed) {
      if (!newIds.contains(item['id'])) {
        line([section, i], ['$noun ${item['id']}', 'removed'], 'there', '—');
      }
    }
    final kept = [
      for (final id in oldIds)
        if (newIds.contains(id)) id,
    ];
    final keptAfter = [
      for (final id in newIds)
        if (oldIds.contains(id)) id,
    ];
    if (!jsonEquals(kept, keptAfter)) {
      line(
        [section],
        [_sections[section]!, 'order'],
        kept.join(', '),
        keptAfter.join(', '),
      );
    }
  }

  void template(RulesPath path, List<String> words, JsonMap a, JsonMap b) {
    for (final key in {...a.keys, ...b.keys}) {
      if (key == 'dayList') continue;
      walk([...path, key], [...words, _fields[key] ?? key], a[key], b[key]);
    }
    final oldDays = a['dayList'] is List ? a['dayList']! as List : const [];
    final newDays = b['dayList'] is List ? b['dayList']! as List : const [];
    for (var d = 0; d < oldDays.length || d < newDays.length; d++) {
      final dayPath = [...path, 'dayList', d];
      if (d >= oldDays.length) {
        line(
          dayPath,
          [...words, _dayName(newDays[d], d), 'added'],
          '—',
          'added',
        );
        continue;
      }
      if (d >= newDays.length) {
        line(
          dayPath,
          [...words, _dayName(oldDays[d], d), 'removed'],
          'there',
          '—',
        );
        continue;
      }
      final (oldDay, newDay) = (oldDays[d], newDays[d]);
      final dayWords = [...words, _dayName(newDay, d)];
      if (oldDay is! Map || newDay is! Map) {
        walk(dayPath, dayWords, oldDay, newDay);
        continue;
      }
      for (final key in {...oldDay.keys, ...newDay.keys}) {
        final child = [...dayPath, '$key'];
        if (key != 'slots') {
          walk(
            child,
            [...dayWords, ..._words(child, child.length - 1)],
            oldDay[key],
            newDay[key],
          );
          continue;
        }
        final oldSlots = oldDay[key] is List ? oldDay[key] as List : const [];
        final newSlots = newDay[key] is List ? newDay[key] as List : const [];
        for (var s = 0; s < oldSlots.length || s < newSlots.length; s++) {
          final slotWords = [...dayWords, 'slot ${s + 1}'];
          final old = s < oldSlots.length ? oldSlots[s] : null;
          final next = s < newSlots.length ? newSlots[s] : null;
          if (jsonEquals(old, next)) continue;
          line(
            [...child, s],
            [
              ...slotWords,
              if (old == null)
                'added'
              else if (next == null)
                'removed'
              else
                'changed',
            ],
            old == null ? '—' : slotSummary(old),
            next == null ? '—' : slotSummary(next),
          );
        }
      }
    }
  }

  final sections = {..._sections.keys, ...before.json.keys, ...after.json.keys};
  for (final section in sections) {
    final (a, b) = (before.json[section], after.json[section]);
    if (jsonEquals(a, b)) continue;
    switch (section) {
      case 'templates':
        byId(section, 'Template', before.templates, after.templates, template);
      case 'splits':
        byId(
          section,
          'Split',
          before.splits,
          after.splits,
          (path, words, a, b) => walk(path, words, a, b),
        );
      default:
        walk([section], _words([section], 0), a, b);
    }
  }
  return changes;
}
