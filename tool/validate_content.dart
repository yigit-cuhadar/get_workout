// Validates the exercise library in content/exercises/*.json against the
// vocabulary and data model in SPEC.md, then checks library coverage.
//
// Run from the app root: dart run tool/validate_content.dart [dir]
// Exits non-zero on any error.
import 'dart:convert';
import 'dart:io';

// Vocabulary from SPEC.md. The app's domain code replaces these later.
const loggingTypes = {
  'reps',
  'weight_reps',
  'weighted_bodyweight',
  'assisted_bodyweight',
  'duration',
  'weight_duration',
};
const weightedLoggingTypes = {
  'weight_reps',
  'weighted_bodyweight',
  'assisted_bodyweight',
  'weight_duration',
};
const muscles = [
  'pec',
  'lat',
  'trap',
  'front_delt',
  'mid_delt',
  'rear_delt',
  'biceps',
  'triceps',
  'forearm',
  'abdominal',
  'oblique',
  'erector',
  'glute',
  'hip_flexor',
  'abductor',
  'adductor',
  'quads',
  'hamstring',
  'calf',
];
const equipment = [
  'barbell',
  'ez_bar',
  'trap_bar',
  'dumbbell',
  'kettlebell',
  'plate',
  'cable',
  'machine',
  'smith_machine',
  'bench',
  'pull_up_bar',
  'dip_station',
  'resistance_band',
  'suspension_trainer',
  'rings',
  'medicine_ball',
  'stability_ball',
  'ab_wheel',
  'landmine',
  'sled',
  'bodyweight',
  'other',
];
const movementPatterns = [
  'squat',
  'hinge',
  'lunge',
  'horizontal_push',
  'vertical_push',
  'horizontal_pull',
  'vertical_pull',
  'carry',
  'core_flexion',
  'core_stability',
  'rotation',
  'explosive',
  'isolation',
  'mobility',
];
const mechanics = {'compound', 'isolation'};
const lateralities = {'bilateral', 'unilateral', 'alternating'};
const levels = {'beginner', 'intermediate', 'advanced'};
const forces = {'push', 'pull', 'static'};
const positions = {
  'standing',
  'seated',
  'supine',
  'prone',
  'incline',
  'decline',
  'hanging',
  'kneeling',
  'side_lying',
  'quadruped',
};
const grips = {'overhand', 'underhand', 'neutral', 'mixed'};
const gripWidths = {'narrow', 'shoulder', 'wide'};
const languages = {'en'};
const statuses = {'draft', 'live', 'retired'};

// Coverage minimums.
const minTotal = 400;
const minMainPerMuscle = 12;
const minPerEquipment = 4;
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

class Exercise {
  Exercise(this.file, this.data);

  final String file;
  final Map<String, Object?> data;

  String get id => data['id'] is String ? data['id']! as String : '?';
  String get where => '$file [$id]';

  List<String> strings(String key) {
    final value = data[key];
    return value is List ? value.whereType<String>().toList() : const [];
  }

  Map<String, Object?> get text {
    final l10n = data['l10n'];
    final en = l10n is Map ? l10n['en'] : null;
    return en is Map<String, Object?> ? en : const {};
  }
}

final errors = <String>[];
final warnings = <String>[];

void main(List<String> args) {
  final dir = Directory(args.isNotEmpty ? args.first : 'content/exercises');
  if (!dir.existsSync()) {
    stderr.writeln('No such directory: ${dir.path}');
    exit(2);
  }
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final exercises = <Exercise>[];
  final perFile = <String, int>{};
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      errors.add('$name: invalid JSON: ${e.message}');
      continue;
    }
    if (decoded is! List) {
      errors.add('$name: top level must be a JSON array');
      continue;
    }
    perFile[name] = decoded.length;
    for (final (i, item) in decoded.indexed) {
      if (item is! Map<String, Object?>) {
        errors.add('$name: item $i is not an object');
        continue;
      }
      final exercise = Exercise(name, item);
      checkExercise(exercise);
      exercises.add(exercise);
    }
  }

  // Draft and retired exercises are not shown to users, so popularity,
  // family ranks and coverage only count live ones.
  final live = exercises.where((e) => e.data['status'] == 'live').toList();
  checkLibrary(exercises, live);
  final coverage = checkCoverage(live);

  stdout.writeln('Files:');
  perFile.forEach((file, count) => stdout.writeln('  $file: $count'));
  stdout.writeln('Total: ${exercises.length} (live: ${live.length})');
  stdout.writeln(coverage);
  for (final warning in warnings) {
    stdout.writeln('WARNING $warning');
  }
  for (final error in errors) {
    stderr.writeln('ERROR $error');
  }
  if (errors.isNotEmpty) {
    stderr.writeln('${errors.length} error(s).');
    exit(1);
  }
  stdout.writeln('OK');
}

void checkExercise(Exercise e) {
  final d = e.data;
  void err(String message) => errors.add('${e.where}: $message');

  for (final key in d.keys) {
    if (!allowedKeys.contains(key)) err('unknown field "$key"');
  }

  final id = d['id'];
  if (id is! String || !idPattern.hasMatch(id)) {
    err('id must match ${idPattern.pattern}');
  }
  void code(String key, Iterable<String> allowed, {bool optional = false}) {
    final value = d[key];
    if (value == null && optional) return;
    if (value is! String || !allowed.contains(value)) {
      err('$key "$value" is not one of ${allowed.join(', ')}');
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
      err('$key must be a list');
      return;
    }
    if (value.length < min || value.length > max) {
      err('$key must have $min-$max items, has ${value.length}');
    }
    for (final item in value) {
      if (item is! String || !allowed.contains(item)) {
        err('$key has unknown code "$item"');
      }
    }
    if (value.toSet().length != value.length) err('$key has duplicates');
  }

  codeList('equipment', equipment, 1, equipment.length);
  codeList('mainMuscles', muscles, 1, 2);
  codeList('secondaryMuscles', muscles, 0, 4);
  final overlap = e
      .strings('mainMuscles')
      .toSet()
      .intersection(e.strings('secondaryMuscles').toSet());
  if (overlap.isNotEmpty) {
    err('muscles both main and secondary: ${overlap.join(', ')}');
  }

  final family = d['family'];
  if (family is! String || !familyPattern.hasMatch(family)) {
    err('family must be snake_case');
  }
  void positiveInt(String key, {int min = 1, int? max}) {
    final value = d[key];
    if (value is! int || value < min || (max != null && value > max)) {
      err('$key must be an integer in $min..${max ?? '∞'}');
    }
  }

  positiveInt('familyRank');
  positiveInt('popularity');
  positiveInt('defaultRestS', min: 15, max: 600);

  for (final key in ['pinnedAlternatives', 'excludedAlternatives']) {
    final value = d[key];
    if (value is! List || value.any((v) => v is! String)) {
      err('$key must be a list of ids');
    }
  }

  final increment = d['incrementKg'];
  final weighted = weightedLoggingTypes.contains(d['loggingType']);
  if (weighted && (increment is! num || increment <= 0)) {
    err('incrementKg must be a positive number for ${d['loggingType']}');
  }
  if (!weighted && increment != null) {
    err('incrementKg must be absent for ${d['loggingType']}');
  }

  final l10n = d['l10n'];
  if (l10n is! Map) {
    err('l10n must be a map');
    return;
  }
  for (final lang in l10n.keys) {
    if (!languages.contains(lang)) err('l10n has unexpected language "$lang"');
  }
  final text = l10n['en'];
  if (text is! Map) {
    err('l10n.en is missing');
    return;
  }
  for (final key in text.keys) {
    if (!allowedTextKeys.contains(key)) err('l10n.en has unknown field "$key"');
  }

  void checkString(String label, Object? value) {
    if (value is! String || value.isEmpty) {
      err('$label must be a non-empty string');
    } else if (value.trim() != value || value.contains('  ')) {
      err('$label has stray spaces: "$value"');
    }
  }

  void stringList(String key, int min, int max) {
    final value = text[key];
    if (value is! List) {
      err('l10n.en.$key must be a list');
      return;
    }
    if (value.length < min || value.length > max) {
      err('l10n.en.$key must have $min-$max items, has ${value.length}');
    }
    for (final item in value) {
      checkString('l10n.en.$key item', item);
    }
    if (value.toSet().length != value.length) {
      err('l10n.en.$key has duplicates');
    }
  }

  checkString('l10n.en.name', text['name']);
  stringList('aliases', 0, 8);
  stringList('setup', 2, 5);
  stringList('execution', 2, 5);
  stringList('mistakes', 2, 4);
  stringList('cues', 1, 3);
  if (text['safety'] != null) checkString('l10n.en.safety', text['safety']);
  final name = text['name'];
  final aliases = text['aliases'];
  if (name is String &&
      aliases is List &&
      aliases.any(
        (a) => a is String && a.toLowerCase() == name.toLowerCase(),
      )) {
    err('an alias repeats the name');
  }
}

void checkLibrary(List<Exercise> exercises, List<Exercise> live) {
  final byId = <String, Exercise>{};
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

  final byRank = <int, Exercise>{};
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

  final byName = <String, Exercise>{};
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

  final families = <String, List<Exercise>>{};
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

String checkCoverage(List<Exercise> exercises) {
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
        .where((e) => e.strings('equipment').contains(item))
        .length;
    if (item == 'other') {
      out.writeln('     ${item.padRight(28)} $count');
    } else {
      line(item, count, minPerEquipment);
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
      (e) => e.strings('equipment').every(allowed.contains),
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
