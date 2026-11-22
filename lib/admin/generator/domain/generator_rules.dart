import 'package:forge_core/forge_core.dart';

/// A JSON object as the rules callables speak it.
typedef JsonMap = Map<String, Object?>;

/// Where a value sits in the rules: object keys and list indices, as in
/// `templates[0].dayList[1].slots[2].pick`.
typedef RulesPath = List<Object>;

/// [path] as the server writes it in its problems.
String pathText(RulesPath path) {
  final text = StringBuffer();
  for (final segment in path) {
    if (segment is int) {
      text.write('[$segment]');
    } else {
      if (text.isNotEmpty) text.write('.');
      text.write(segment);
    }
  }
  return '$text';
}

final _segment = RegExp(r'\[(\d+)\]|([^.\[\]]+)');

/// The path of [text], the inverse of [pathText].
RulesPath parsePath(String text) => [
  for (final match in _segment.allMatches(text))
    if (match.group(1) case final index?) int.parse(index) else match.group(2)!,
];

/// Whether two JSON values are equal, numbers by value (`2 == 2.0`).
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key) || !jsonEquals(value, b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _jsonHash(Object? value) => switch (value) {
  final Map<Object?, Object?> map => Object.hashAllUnordered([
    for (final MapEntry(:key, :value) in map.entries)
      Object.hash(key, _jsonHash(value)),
  ]),
  final List<Object?> list => Object.hashAll(list.map(_jsonHash)),
  _ => value.hashCode,
};

/// The generator's rules (SPEC.md, Data model, `generator/rules`) as the
/// JSON the server speaks, unknown fields included. Never changed in place:
/// [set] and the list helpers copy the objects on the way to the change.
class GeneratorRules {
  GeneratorRules(this.json);

  final JsonMap json;

  /// The value at [path]; null when absent.
  Object? at(RulesPath path) {
    Object? value = json;
    for (final segment in path) {
      value = switch ((value, segment)) {
        (final Map<Object?, Object?> map, final String key) => map[key],
        (final List<Object?> list, final int i) when i < list.length => list[i],
        _ => null,
      };
      if (value == null) return null;
    }
    return value;
  }

  /// Whether [path] names a value, null included.
  bool has(RulesPath path) {
    if (path.isEmpty) return true;
    final parent = at(path.sublist(0, path.length - 1));
    return switch ((parent, path.last)) {
      (final Map<Object?, Object?> map, final String key) => map.containsKey(
        key,
      ),
      (final List<Object?> list, final int i) => i < list.length,
      _ => false,
    };
  }

  /// The rules with [value] at [path]; null removes an object's key.
  GeneratorRules set(RulesPath path, Object? value) =>
      GeneratorRules(_set(json, path, 0, value) as JsonMap);

  /// The rules with the list at [path] replaced by [change] of it.
  GeneratorRules updateList(
    RulesPath path,
    List<Object?> Function(List<Object?> list) change,
  ) => set(path, change([...?at(path) as List<Object?>?]));

  GeneratorRules insert(RulesPath list, int index, Object? value) =>
      updateList(list, (items) => items..insert(index, value));

  GeneratorRules add(RulesPath list, Object? value) =>
      updateList(list, (items) => items..add(value));

  GeneratorRules removeAt(RulesPath list, int index) =>
      updateList(list, (items) => items..removeAt(index));

  GeneratorRules move(RulesPath list, int from, int to) =>
      updateList(list, (items) => items..insert(to, items.removeAt(from)));

  static Object? _set(Object? node, RulesPath path, int depth, Object? value) {
    if (depth == path.length) return value;
    final segment = path[depth];
    switch ((node, segment)) {
      case (final List<Object?> list, final int i):
        return [...list]..[i] = _set(list[i], path, depth + 1, value);
      case (final Map<Object?, Object?>? map, final String key):
        final copy = <String, Object?>{
          for (final MapEntry(:key, :value) in (map ?? const {}).entries)
            '$key': value,
        };
        final child = _set(copy[key], path, depth + 1, value);
        if (child == null && depth == path.length - 1) {
          copy.remove(key);
        } else {
          copy[key] = child;
        }
        return copy;
      default:
        throw ArgumentError('no ${pathText(path)} in the rules');
    }
  }

  List<JsonMap> _objects(String key) => [
    for (final item in json[key] as List? ?? const [])
      if (item is Map) item.cast<String, Object?>(),
  ];

  List<JsonMap> get splits => _objects('splits');
  List<JsonMap> get templates => _objects('templates');

  /// The index of the template [id] in [templates]; null when none.
  int? templateIndex(Object? id) {
    final index = templates.indexWhere((template) => template['id'] == id);
    return index < 0 ? null : index;
  }

  int? splitIndex(Object? id) {
    final index = splits.indexWhere((split) => split['id'] == id);
    return index < 0 ? null : index;
  }

  @override
  bool operator ==(Object other) =>
      other is GeneratorRules && jsonEquals(json, other.json);

  @override
  late final int hashCode = _jsonHash(json);
}

/// A version of the rules as the server keeps it; version 0 and no [rules]
/// when none was ever published.
class StoredRules extends Equatable {
  const StoredRules({
    required this.version,
    this.rules,
    this.publishedAt,
    this.publishedByEmail,
    this.note,
    this.restores,
  });

  final int version;
  final GeneratorRules? rules;
  final DateTime? publishedAt;
  final String? publishedByEmail;
  final String? note;

  /// The version this one brought back.
  final int? restores;

  @override
  List<Object?> get props => [
    version,
    rules,
    publishedAt,
    publishedByEmail,
    note,
    restores,
  ];
}

enum FindingKind {
  /// No program for the answers.
  refused,

  /// A target muscle without direct work.
  uncovered,

  /// A day under half the session.
  short,
}

/// What the check found in the program of one standard answer.
class Finding extends Equatable {
  const Finding({
    required this.goal,
    required this.level,
    required this.daysPerWeek,
    required this.equipment,
    required this.kind,
    required this.detail,
  });

  final String goal;
  final String level;
  final int daysPerWeek;

  /// The equipment preset's code.
  final String equipment;
  final FindingKind kind;
  final String detail;

  /// The standard answer it was found in.
  (String, String, int, String) get answer =>
      (goal, level, daysPerWeek, equipment);

  @override
  List<Object?> get props => [
    goal,
    level,
    daysPerWeek,
    equipment,
    kind,
    detail,
  ];
}

/// How many standard answers [findings] are about, of [kind] or of any.
int answerCount(List<Finding> findings, [FindingKind? kind]) => {
  for (final finding in findings)
    if (kind == null || finding.kind == kind) finding.answer,
}.length;

/// The server's check of unpublished rules: the validator's [problems],
/// and when there are none, the [findings] over the standard answers.
class RulesCheck extends Equatable {
  const RulesCheck({this.problems = const [], this.findings = const []});

  /// Each as `<path>: <problem>`.
  final List<String> problems;
  final List<Finding> findings;

  @override
  List<Object?> get props => [problems, findings];
}

/// [rules] published as version [base] + 1; [restores] names the version a
/// restore brings back.
class RulesPublish extends Equatable {
  const RulesPublish({
    required this.base,
    required this.rules,
    this.note,
    this.restores,
  });

  final int base;
  final GeneratorRules rules;
  final String? note;
  final int? restores;

  @override
  List<Object?> get props => [base, rules, note, restores];
}

/// The longest publish note, as the server allows it.
const maxRulesNote = 300;

/// The rules changed since the page loaded them; nothing was published.
final class GeneratorRulesStaleFailure extends Failure {
  const GeneratorRulesStaleFailure([
    super.message = 'the rules changed since this page loaded',
    Object? cause,
  ]) : super(cause: cause);
}

/// The server's validator refused the rules; nothing was published.
final class GeneratorRulesInvalidFailure extends Failure {
  const GeneratorRulesInvalidFailure(this.problems, [Object? cause])
    : super('the rules have problems', cause: cause);

  /// Each as `<path>: <problem>`.
  final List<String> problems;
}

/// The rules functions cannot be called: not deployed to this project, or
/// without permission to call them.
final class GeneratorRulesUnavailableFailure extends Failure {
  const GeneratorRulesUnavailableFailure([
    super.message = 'the generator rules functions cannot be called',
    Object? cause,
  ]) : super(cause: cause);
}

/// A slot to fill in: the first of a day is a primary one, the others
/// accessories of priority 2. Its pick is empty until edited, which the
/// validator reports.
JsonMap newSlot({required bool first}) => {
  'role': first ? 'primary' : 'accessory',
  'pick': <String, Object?>{},
  'priority': first ? 1 : 2,
};

/// Day [index] of a template, named "Day n", without slots.
JsonMap newDay(int index) => {
  'l10n': {
    'en': {'name': 'Day ${index + 1}'},
  },
  'slots': <Object?>[],
  'extras': <Object?>[],
};

/// A template of [split] for every level and goal, three days a week,
/// with an id none of [rules]' templates has.
JsonMap newTemplate(GeneratorRules rules, {required String split}) {
  var id = 'new_template';
  for (var n = 2; rules.templateIndex(id) != null; n++) {
    id = 'new_template_$n';
  }
  return {
    'id': id,
    'split': split,
    'days': 3,
    'levels': ['beginner', 'intermediate', 'advanced'],
    'priority': 0,
    'dayList': [for (var d = 0; d < 3; d++) newDay(d)],
  };
}
