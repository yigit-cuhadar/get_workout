// The content rules of the exercise library (SPEC.md, "Vocabulary" and
// `exercises/{id}`), checked on the content-file shape of an exercise: the
// map of `content/exercises/*.json`, with its `id` and `status`, and
// `equipmentAlternatives` as lists of codes.
//
// Shared by tool/validate_content.dart, the importer and the admin panel, so
// it is pure Dart and its messages are the validator's output.
import 'vocabulary.dart';

List<String> _codes(List<Coded> values) => [for (final v in values) v.code];

final loggingTypes = _codes(LoggingType.values);
const weightedLoggingTypes = {
  LoggingType.weightReps,
  LoggingType.weightedBodyweight,
  LoggingType.assistedBodyweight,
  LoggingType.weightDuration,
};
final muscles = _codes(Muscle.values);
final equipment = _codes(Equipment.values);
final movementPatterns = _codes(MovementPattern.values);
final mechanics = _codes(Mechanic.values);
final lateralities = _codes(Laterality.values);
final levels = _codes(Level.values);
final forces = _codes(Force.values);
final positions = _codes(Position.values);
final grips = _codes(Grip.values);
final gripWidths = _codes(GripWidth.values);
final statuses = _codes(ExerciseStatus.values);
const languages = {'en'};

// Per-exercise limits.
const maxEquipmentAlternatives = 3;
const maxMainMuscles = 2;
const maxSecondaryMuscles = 4;
const minRestS = 15;
const maxRestS = 600;
const maxAliases = 8;
const setupLines = (min: 2, max: 5);
const executionLines = (min: 2, max: 5);
const mistakeLines = (min: 2, max: 4);
const cueLines = (min: 1, max: 3);

// Coverage minimums of the live library.
const minTotal = 400;
const minMainPerMuscle = 12;
const minPerEquipment = 4;
const minPerEquipmentOverrides = {'jump_rope': 1};
const minPerPattern = 8;
const minPerProfileMuscle = 3;
const equipmentProfiles = {
  'bodyweight-only': {'bodyweight', 'pull_up_bar', 'dip_station'},
  'dumbbells': {'dumbbell', 'bench', 'bodyweight'},
  'bands': {'resistance_band', 'bodyweight'},
};

const allowedKeys = {
  'id',
  'status',
  'loggingType',
  'mechanic',
  'laterality',
  'level',
  'force',
  'movementPattern',
  'position',
  'grip',
  'gripWidth',
  'equipment',
  'equipmentAlternatives',
  'mainMuscles',
  'secondaryMuscles',
  'family',
  'familyRank',
  'pinnedAlternatives',
  'excludedAlternatives',
  'defaultRestS',
  'incrementKg',
  'popularity',
  'l10n',
};
const allowedTextKeys = {
  'name',
  'aliases',
  'setup',
  'execution',
  'mistakes',
  'safety',
  'cues',
};

final idPattern = RegExp(r'^ex_[a-z0-9]+(_[a-z0-9]+)*$');
final familyPattern = RegExp(r'^[a-z0-9]+(_[a-z0-9]+)*$');

/// A broken rule of one exercise. [field] is the key it concerns, with
/// `l10n.en.` in front for text fields.
class ContentProblem {
  const ContentProblem(this.field, this.message);

  final String field;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ContentProblem &&
      other.field == field &&
      other.message == message;

  @override
  int get hashCode => Object.hash(field, message);

  @override
  String toString() => '$field: $message';
}

/// Every rule [d] breaks on its own, in a fixed order. Library-wide rules
/// (unique ids and names, references, ranks, coverage) are [checkLibrary]'s.
List<ContentProblem> exerciseProblems(Map<String, Object?> d) {
  final problems = <ContentProblem>[];
  void err(String field, String message) =>
      problems.add(ContentProblem(field, message));

  for (final key in d.keys) {
    if (!allowedKeys.contains(key)) err(key, 'unknown field "$key"');
  }

  final id = d['id'];
  if (id is! String || !idPattern.hasMatch(id)) {
    err('id', 'id must match ${idPattern.pattern}');
  }
  void code(String key, Iterable<String> allowed, {bool optional = false}) {
    final value = d[key];
    if (value == null && optional) return;
    if (value is! String || !allowed.contains(value)) {
      err(key, '$key "$value" is not one of ${allowed.join(', ')}');
    }
  }

  code('status', statuses);
  code('loggingType', loggingTypes);
  code('mechanic', mechanics);
  code('laterality', lateralities);
  code('level', levels);
  code('force', forces);
  code('movementPattern', movementPatterns);
  code('position', positions);
  code('grip', grips, optional: true);
  code('gripWidth', gripWidths, optional: true);

  void codeList(String key, Iterable<String> allowed, int min, int max) {
    final value = d[key];
    if (value is! List) {
      err(key, '$key must be a list');
      return;
    }
    if (value.length < min || value.length > max) {
      err(key, '$key must have $min-$max items, has ${value.length}');
    }
    for (final item in value) {
      if (item is! String || !allowed.contains(item)) {
        err(key, '$key has unknown code "$item"');
      }
    }
    if (value.toSet().length != value.length) err(key, '$key has duplicates');
  }

  codeList('equipment', equipment, 1, equipment.length);
  const alternativesKey = 'equipmentAlternatives';
  final alternatives = d[alternativesKey];
  if (alternatives != null) {
    if (alternatives is! List) {
      err(alternativesKey, '$alternativesKey must be a list of equipment sets');
    } else {
      if (alternatives.length > maxEquipmentAlternatives) {
        err(
          alternativesKey,
          '$alternativesKey has ${alternatives.length} sets, '
          'max $maxEquipmentAlternatives',
        );
      }
      for (final set in alternatives) {
        if (set is! List || set.isEmpty) {
          err(alternativesKey, '$alternativesKey sets must be non-empty lists');
          continue;
        }
        for (final item in set) {
          if (item is! String || !equipment.contains(item)) {
            err(alternativesKey, '$alternativesKey has unknown code "$item"');
          }
        }
        if (set.toSet().length != set.length) {
          err(alternativesKey, '$alternativesKey set $set has duplicates');
        }
      }
    }
  }
  final entry = ExerciseEntry(d);
  final sets = entry.equipmentSets.map((s) => s.toSet()).toList();
  for (final (i, set) in sets.indexed) {
    final field = i == 0 ? 'equipment' : alternativesKey;
    if (set.contains(Equipment.bodyweight.code) && set.length > 1) {
      err(field, 'bodyweight must be listed alone: ${set.join(', ')}');
    }
    for (final other in sets.take(i)) {
      if (other.length == set.length && other.containsAll(set)) {
        err(field, 'equipment set {${set.join(', ')}} is listed twice');
      }
    }
  }
  codeList('mainMuscles', muscles, 1, maxMainMuscles);
  codeList('secondaryMuscles', muscles, 0, maxSecondaryMuscles);
  final overlap = entry
      .strings('mainMuscles')
      .toSet()
      .intersection(entry.strings('secondaryMuscles').toSet());
  if (overlap.isNotEmpty) {
    err(
      'secondaryMuscles',
      'muscles both main and secondary: ${overlap.join(', ')}',
    );
  }

  final family = d['family'];
  if (family is! String || !familyPattern.hasMatch(family)) {
    err('family', 'family must be snake_case');
  }
  void positiveInt(String key, {int min = 1, int? max}) {
    final value = d[key];
    if (value is! int || value < min || (max != null && value > max)) {
      err(key, '$key must be an integer in $min..${max ?? '∞'}');
    }
  }

  positiveInt('familyRank');
  positiveInt('popularity');
  positiveInt('defaultRestS', min: minRestS, max: maxRestS);

  for (final key in ['pinnedAlternatives', 'excludedAlternatives']) {
    final value = d[key];
    if (value is! List || value.any((v) => v is! String)) {
      err(key, '$key must be a list of ids');
    }
  }

  final increment = d['incrementKg'];
  final weighted = weightedLoggingTypes.any(
    (type) => type.code == d['loggingType'],
  );
  if (weighted && (increment is! num || increment <= 0)) {
    err(
      'incrementKg',
      'incrementKg must be a positive number for ${d['loggingType']}',
    );
  }
  if (!weighted && increment != null) {
    err('incrementKg', 'incrementKg must be absent for ${d['loggingType']}');
  }

  final l10n = d['l10n'];
  if (l10n is! Map) {
    err('l10n', 'l10n must be a map');
    return problems;
  }
  for (final lang in l10n.keys) {
    if (!languages.contains(lang)) {
      err('l10n', 'l10n has unexpected language "$lang"');
    }
  }
  final text = l10n['en'];
  if (text is! Map) {
    err('l10n', 'l10n.en is missing');
    return problems;
  }
  for (final key in text.keys) {
    if (!allowedTextKeys.contains(key)) {
      err('l10n.en.$key', 'l10n.en has unknown field "$key"');
    }
  }

  void checkString(String field, String label, Object? value) {
    if (value is! String || value.isEmpty) {
      err(field, '$label must be a non-empty string');
    } else if (value.trim() != value || value.contains('  ')) {
      err(field, '$label has stray spaces: "$value"');
    }
  }

  void stringList(String key, ({int min, int max}) limits) {
    final field = 'l10n.en.$key';
    final value = text[key];
    if (value is! List) {
      err(field, '$field must be a list');
      return;
    }
    if (value.length < limits.min || value.length > limits.max) {
      err(
        field,
        '$field must have ${limits.min}-${limits.max} items, '
        'has ${value.length}',
      );
    }
    for (final item in value) {
      checkString(field, '$field item', item);
    }
    if (value.toSet().length != value.length) {
      err(field, '$field has duplicates');
    }
  }

  checkString('l10n.en.name', 'l10n.en.name', text['name']);
  stringList('aliases', (min: 0, max: maxAliases));
  stringList('setup', setupLines);
  stringList('execution', executionLines);
  stringList('mistakes', mistakeLines);
  stringList('cues', cueLines);
  if (text['safety'] != null) {
    checkString('l10n.en.safety', 'l10n.en.safety', text['safety']);
  }
  final name = text['name'];
  final aliases = text['aliases'];
  if (name is String &&
      aliases is List &&
      aliases.any(
        (a) => a is String && a.toLowerCase() == name.toLowerCase(),
      )) {
    err('l10n.en.aliases', 'an alias repeats the name');
  }
  return problems;
}

/// One exercise of a library in the content-file shape, read leniently.
class ExerciseEntry {
  ExerciseEntry(this.data, {this.file});

  final Map<String, Object?> data;

  /// The file it came from, when it came from one.
  final String? file;

  String get id => data['id'] is String ? data['id']! as String : '?';
  String get where => file == null ? id : '$file [$id]';
  bool get isLive => data['status'] == ExerciseStatus.live.code;

  List<String> strings(String key) {
    final value = data[key];
    return value is List ? value.whereType<String>().toList() : const [];
  }

  /// `equipment` followed by every `equipmentAlternatives` set; the exercise
  /// can be done with any one of them.
  List<List<String>> get equipmentSets {
    final alternatives = data['equipmentAlternatives'];
    return [
      strings('equipment'),
      if (alternatives is List)
        for (final set in alternatives)
          if (set is List) set.whereType<String>().toList(),
    ];
  }

  Map<String, Object?> get text {
    final l10n = data['l10n'];
    final en = l10n is Map ? l10n['en'] : null;
    return en is Map<String, Object?> ? en : const {};
  }
}

/// What [checkLibrary] found across a library.
class LibraryCheck {
  const LibraryCheck({
    required this.errors,
    required this.warnings,
    required this.coverage,
  });

  final List<String> errors;
  final List<String> warnings;

  /// A printable coverage table.
  final String coverage;
}

/// The rules across [exercises]: unique ids and names, valid references and,
/// among live exercises only (draft and retired ones are not shown to users),
/// popularity 1..N, family ranks 1..N and the coverage minimums.
LibraryCheck checkLibrary(List<ExerciseEntry> exercises) {
  final errors = <String>[], warnings = <String>[];
  final live = exercises.where((e) => e.isLive).toList();
  _checkReferences(exercises, live, errors, warnings);
  final coverage = _checkCoverage(live, errors);
  return LibraryCheck(errors: errors, warnings: warnings, coverage: coverage);
}

void _checkReferences(
  List<ExerciseEntry> exercises,
  List<ExerciseEntry> live,
  List<String> errors,
  List<String> warnings,
) {
  final byId = <String, ExerciseEntry>{};
  for (final e in exercises) {
    if (byId.containsKey(e.id)) {
      errors.add('${e.where}: duplicate id, also in ${byId[e.id]!.file}');
    }
    byId[e.id] = e;
  }

  final ids = byId.keys.toSet();
  for (final e in exercises) {
    for (final key in ['pinnedAlternatives', 'excludedAlternatives']) {
      for (final ref in e.strings(key)) {
        if (ref == e.id || !ids.contains(ref)) {
          errors.add('${e.where}: $key has invalid id "$ref"');
        }
      }
    }
  }

  final byRank = <int, ExerciseEntry>{};
  for (final e in live) {
    final rank = e.data['popularity'];
    if (rank is! int) continue;
    if (byRank.containsKey(rank)) {
      errors.add(
        '${e.where}: popularity $rank also used by ${byRank[rank]!.id}',
      );
    }
    byRank[rank] = e;
  }
  for (var rank = 1; rank <= live.length; rank++) {
    if (!byRank.containsKey(rank)) errors.add('popularity $rank is unused');
  }

  final byName = <String, ExerciseEntry>{};
  for (final e in exercises) {
    final name = e.text['name'];
    if (name is! String) continue;
    final key = name.toLowerCase();
    if (byName.containsKey(key)) {
      errors.add('${e.where}: name "$name" also used by ${byName[key]!.id}');
    }
    byName[key] = e;
  }
  final aliasOwners = <String, List<String>>{};
  for (final e in exercises) {
    final aliases = e.text['aliases'];
    if (aliases is! List) continue;
    for (final alias in aliases.whereType<String>()) {
      final key = alias.toLowerCase();
      final named = byName[key];
      if (named != null && named.id != e.id) {
        errors.add('${e.where}: alias "$alias" is the name of ${named.id}');
      }
      (aliasOwners[key] ??= []).add(e.id);
    }
  }
  aliasOwners.forEach((alias, owners) {
    if (owners.length > 1) {
      warnings.add('alias "$alias" shared by ${owners.join(', ')}');
    }
  });

  final families = <String, List<ExerciseEntry>>{};
  for (final e in live) {
    final family = e.data['family'];
    if (family is String) (families[family] ??= []).add(e);
  }
  families.forEach((family, members) {
    final ranks = members.map((e) => e.data['familyRank']).toList();
    final listing = members
        .map((e) => '${e.id}=${e.data['familyRank']}')
        .join(', ');
    if (!ranks.contains(1)) {
      errors.add('family $family has no exercise with rank 1');
    }
    if (ranks.toSet().length != ranks.length) {
      errors.add('family $family has repeated ranks: $listing');
    }
    final expected = {for (var r = 1; r <= ranks.length; r++) r};
    if (!ranks.toSet().containsAll(expected)) {
      errors.add('family $family ranks are not 1..${ranks.length}: $listing');
    }
    final patterns = members.map((e) => e.data['movementPattern']).toSet();
    if (patterns.length > 1) {
      warnings.add(
        'family $family mixes movement patterns ${patterns.join(', ')}: '
        '${members.map((e) => '${e.id}=${e.data['movementPattern']}').join(', ')}',
      );
    }
  });
}

String _checkCoverage(List<ExerciseEntry> exercises, List<String> errors) {
  final out = StringBuffer('\nCoverage\n');
  void line(String label, int count, int min) {
    final ok = count >= min;
    out.writeln(
      '  ${ok ? '  ' : '!!'} ${label.padRight(28)} $count (min $min)',
    );
    if (!ok) errors.add('coverage: $label has $count, needs $min');
  }

  line('total', exercises.length, minTotal);

  out.writeln(' Main muscle');
  for (final muscle in muscles) {
    final count = exercises
        .where((e) => e.strings('mainMuscles').contains(muscle))
        .length;
    line(muscle, count, minMainPerMuscle);
  }

  out.writeln(' Equipment');
  for (final item in equipment) {
    final count = exercises
        .where((e) => e.equipmentSets.any((set) => set.contains(item)))
        .length;
    if (item == Equipment.other.code) {
      out.writeln('     ${item.padRight(28)} $count');
    } else {
      line(item, count, minPerEquipmentOverrides[item] ?? minPerEquipment);
    }
  }

  out.writeln(' Movement pattern');
  for (final pattern in movementPatterns) {
    final count = exercises
        .where((e) => e.data['movementPattern'] == pattern)
        .length;
    line(pattern, count, minPerPattern);
  }

  equipmentProfiles.forEach((profile, allowed) {
    out.writeln(' Profile $profile {${allowed.join(', ')}}');
    final doable = exercises.where(
      (e) => e.equipmentSets.any((set) => set.every(allowed.contains)),
    );
    for (final muscle in muscles) {
      final count = doable
          .where((e) => e.strings('mainMuscles').contains(muscle))
          .length;
      line('$profile: $muscle', count, minPerProfileMuscle);
    }
  });
  return out.toString();
}
