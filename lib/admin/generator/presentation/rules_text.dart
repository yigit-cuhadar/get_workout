import '../../shell/admin_text.dart';
import '../domain/generator_rules.dart';
import '../domain/rules_changes.dart';

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

/// A day's name, or "Day n" without one.
String dayName(Object? day, int index) => switch (day) {
  {'l10n': {'en': {'name': final String name}}} when name.trim().isNotEmpty =>
    name,
  _ => 'Day ${index + 1}',
};

/// A split's name, or its id without one.
String splitName(Object? split) => switch (split) {
  {'l10n': {'en': {'name': final String name}}} when name.isNotEmpty => name,
  {'id': final Object? id} => '$id',
  _ => '',
};

/// The words for [path] from [from] on; [dayList] names the days.
List<String> _words(RulesPath path, int from, {Object? dayList}) {
  final words = <String>[];
  for (var i = from; i < path.length; i++) {
    final segment = path[i];
    final parent = i > 0 ? path[i - 1] : null;
    switch (segment) {
      case final int index when parent == 'dayList':
        words.add(
          dayName(
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

bool _inSeconds(RulesPath path) =>
    path.any((segment) => const {'restS', 'holdS', 'setupS'}.contains(segment));

bool _inMinutes(RulesPath path) => path.any(
  (segment) => const {'sessionMax', 'sessionMinutes'}.contains(segment),
);

bool _isRange(RulesPath path) =>
    path.contains('sets') ||
    (path.isNotEmpty && _rangeKeys.contains(path.last));

bool _isSlot(RulesPath path) =>
    path.length > 1 && path[path.length - 2] == 'slots';

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

/// A slot in a line: "Primary · Squat, Quads · Isolation · priority 1".
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
    final Map<Object?, Object?> _ when _isSlot(path) => slotSummary(value),
    final Map<Object?, Object?> _ when path.lastOrNull == 'pick' =>
      pickLabels(value).isEmpty ? 'nothing' : pickLabels(value).join(', '),
    final Map<Object?, Object?> _ => 'set',
    final num number => '$number$unit',
    _ => _item(path, value),
  };
}

/// A change as the review lists it.
typedef ChangeLine = ({String where, String now, String after});

/// [change] from [before] to [after] in words.
ChangeLine changeLine(
  RulesChange change,
  GeneratorRules before,
  GeneratorRules after,
) {
  final (beforePath, afterPath) = (change.beforePath, change.afterPath);
  return switch (change.kind) {
    ChangeKind.added => (
      where: '${placeOf(after, afterPath!)} added',
      now: '—',
      after: 'added',
    ),
    ChangeKind.removed => (
      where: '${placeOf(before, beforePath!)} removed',
      now: 'there',
      after: '—',
    ),
    ChangeKind.order => (
      where: '${_sections[change.path.first] ?? change.path.first} · order',
      now: valueText(const ['id'], change.before),
      after: valueText(const ['id'], change.after),
    ),
    ChangeKind.value => (
      where: [
        placeOf(after, afterPath!),
        if (_isSlot(afterPath)) 'changed',
      ].join(' '),
      now: valueText(afterPath, change.before, units: true),
      after: valueText(afterPath, change.after, units: true),
    ),
  };
}
