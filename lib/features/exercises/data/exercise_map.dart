import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/exercise.dart';
import '../domain/vocabulary.dart';

/// Builds an [Exercise] from a stored document: a Firestore document, or an
/// entry of `content/exercises/*.json` (which carries its own `id` and no
/// `updatedAt`). Fields it does not know, like `contentHash`, are ignored.
///
/// Firestore cannot hold arrays of arrays, so there `equipmentAlternatives`
/// is a list of `{items: [code, ...]}` maps; the content files keep plain
/// lists of codes. Both are read.
///
/// Throws a [FormatException] naming the exercise and field when a required
/// field is missing, has the wrong type or holds an unknown code, so a
/// document is either read completely or not at all.
Exercise exerciseFromMap(String id, Map<String, Object?> map) {
  final read = _Reader(id, map);
  final l10nMap = read.map('l10n');
  final l10n = {
    for (final language in l10nMap.keys)
      language: _textFromMap(id, language, _Reader(id, l10nMap).map(language)),
  };
  if (!l10n.containsKey(Exercise.fallbackLanguage)) {
    read.fail('l10n.${Exercise.fallbackLanguage}', 'is missing');
  }
  return Exercise(
    id: id,
    status: read.code('status', ExerciseStatus.values),
    loggingType: read.code('loggingType', LoggingType.values),
    mechanic: read.code('mechanic', Mechanic.values),
    laterality: read.code('laterality', Laterality.values),
    level: read.code('level', Level.values),
    force: read.code('force', Force.values),
    movementPattern: read.code('movementPattern', MovementPattern.values),
    position: read.code('position', Position.values),
    grip: read.optionalCode('grip', Grip.values),
    gripWidth: read.optionalCode('gripWidth', GripWidth.values),
    equipment: read.codes('equipment', Equipment.values, nonEmpty: true),
    equipmentAlternatives: [
      for (final (index, set) in read.list('equipmentAlternatives').indexed)
        read.codesOf(
          'equipmentAlternatives[$index]',
          set is Map<Object?, Object?> ? set['items'] : set,
          Equipment.values,
          nonEmpty: true,
        ),
    ],
    mainMuscles: read.codes('mainMuscles', Muscle.values, nonEmpty: true),
    secondaryMuscles: read.codes('secondaryMuscles', Muscle.values),
    family: read.string('family'),
    familyRank: read.integer('familyRank'),
    pinnedAlternatives: read.strings('pinnedAlternatives'),
    excludedAlternatives: read.strings('excludedAlternatives'),
    defaultRestS: read.integer('defaultRestS'),
    incrementKg: read.optionalNumber('incrementKg')?.toDouble(),
    popularity: read.integer('popularity'),
    l10n: l10n,
    updatedAt: read.optionalTimestamp('updatedAt'),
  );
}

/// The Firestore form of [exercise], without `id` (the document id) and
/// `updatedAt` (set by the server on write). Optional fields that are unset
/// are left out.
Map<String, Object?> exerciseToMap(Exercise exercise) => {
  'status': exercise.status.code,
  'loggingType': exercise.loggingType.code,
  'mechanic': exercise.mechanic.code,
  'laterality': exercise.laterality.code,
  'level': exercise.level.code,
  'force': exercise.force.code,
  'movementPattern': exercise.movementPattern.code,
  'position': exercise.position.code,
  'grip': ?exercise.grip?.code,
  'gripWidth': ?exercise.gripWidth?.code,
  'equipment': _codes(exercise.equipment),
  if (exercise.equipmentAlternatives.isNotEmpty)
    'equipmentAlternatives': [
      for (final set in exercise.equipmentAlternatives) {'items': _codes(set)},
    ],
  'mainMuscles': _codes(exercise.mainMuscles),
  'secondaryMuscles': _codes(exercise.secondaryMuscles),
  'family': exercise.family,
  'familyRank': exercise.familyRank,
  'pinnedAlternatives': exercise.pinnedAlternatives,
  'excludedAlternatives': exercise.excludedAlternatives,
  'defaultRestS': exercise.defaultRestS,
  'incrementKg': ?exercise.incrementKg,
  'popularity': exercise.popularity,
  'l10n': {
    for (final MapEntry(key: language, value: text) in exercise.l10n.entries)
      language: {
        'name': text.name,
        'aliases': text.aliases,
        'setup': text.setup,
        'execution': text.execution,
        'mistakes': text.mistakes,
        'safety': ?text.safety,
        'cues': text.cues,
      },
  },
};

List<String> _codes(List<Coded> values) => [
  for (final value in values) value.code,
];

ExerciseText _textFromMap(
  String id,
  String language,
  Map<String, Object?> map,
) {
  final read = _Reader(id, map, path: 'l10n.$language');
  return ExerciseText(
    name: read.string('name'),
    aliases: read.strings('aliases'),
    setup: read.strings('setup'),
    execution: read.strings('execution'),
    mistakes: read.strings('mistakes'),
    safety: read.optionalString('safety'),
    cues: read.strings('cues'),
  );
}

/// Typed field access that fails with a [FormatException] naming the field.
class _Reader {
  _Reader(this.id, this.data, {this.path});

  final String id;
  final Map<String, Object?> data;

  /// Prefix for field names in error messages, for nested maps.
  final String? path;

  Never fail(String field, String problem) => throw FormatException(
    'Exercise $id: ${path == null ? field : '$path.$field'} $problem',
  );

  T _required<T>(String field) => switch (data[field]) {
    final T value => value,
    null => fail(field, 'is missing'),
    final other => fail(field, 'is not a $T: $other'),
  };

  T? _optional<T>(String field) => switch (data[field]) {
    null => null,
    final T value => value,
    final other => fail(field, 'is not a $T: $other'),
  };

  String string(String field) {
    final value = _required<String>(field);
    return value.isEmpty ? fail(field, 'is empty') : value;
  }

  String? optionalString(String field) => _optional<String>(field);

  int integer(String field) => _required<int>(field);

  num? optionalNumber(String field) => _optional<num>(field);

  DateTime? optionalTimestamp(String field) =>
      _optional<Timestamp>(field)?.toDate();

  Map<String, Object?> map(String field) =>
      Map<String, Object?>.from(_required<Map<Object?, Object?>>(field));

  /// An absent list reads as empty.
  List<Object?> list(String field) => _optional<List<Object?>>(field) ?? [];

  List<String> strings(String field) => [
    for (final item in list(field))
      item is String ? item : fail(field, 'has a non-string item: $item'),
  ];

  T code<T extends Coded>(String field, List<T> values) {
    final code = _required<String>(field);
    return values.byCode(code) ?? fail(field, 'has unknown code "$code"');
  }

  T? optionalCode<T extends Coded>(String field, List<T> values) {
    final code = _optional<String>(field);
    if (code == null) return null;
    return values.byCode(code) ?? fail(field, 'has unknown code "$code"');
  }

  List<T> codes<T extends Coded>(
    String field,
    List<T> values, {
    bool nonEmpty = false,
  }) => codesOf(
    field,
    _required<List<Object?>>(field),
    values,
    nonEmpty: nonEmpty,
  );

  /// [raw] read as a list of codes; [field] names it in errors.
  List<T> codesOf<T extends Coded>(
    String field,
    Object? raw,
    List<T> values, {
    bool nonEmpty = false,
  }) {
    if (raw is! List<Object?>) fail(field, 'is not a list: $raw');
    if (nonEmpty && raw.isEmpty) fail(field, 'is empty');
    return [
      for (final item in raw)
        values.byCode(item) ?? fail(field, 'has unknown code "$item"'),
    ];
  }
}
