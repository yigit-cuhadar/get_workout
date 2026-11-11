// The content rules of the ready-made programs (SPEC.md, `programs/{id}` and
// `programs/{id}/detail/main`), checked on the content-file shape: the map
// of one `content/programs/<id>.json`, with its `id`, the card fields and
// `days` together.
//
// Shared by tool/validate_content.dart and the importer, so it is pure Dart
// and its messages are the validator's output. Programs are checked against
// the exercise library in its content-file shape ([ExerciseEntry]).
import 'content_rules.dart';
import 'vocabulary.dart';

final goals = [for (final goal in Goal.values) goal.code];
final equipmentProfiles = [
  for (final profile in EquipmentProfile.values) profile.code,
];
const durationLoggingTypes = {LoggingType.duration, LoggingType.weightDuration};

// Card and detail limits.
const programDays = (min: 1, max: 7);
const programWeeks = (min: 1, max: 52);
const maxProgramNameLength = 60;
const summarySentences = (min: 1, max: 2);
const maxDayNameLength = 40;
const dayItems = (min: 1, max: 20);
const itemSets = (min: 1, max: 10);
const itemReps = (min: 1, max: 100);
const itemDurationS = (min: 5, max: 3600);
const itemRestS = (min: 0, max: 600);

// The catalogue's split of live programs (SPEC.md, "Monetization").
const freePrograms = 6;
const premiumPrograms = 19;

/// Seconds one set takes, without its rest, in the session estimate.
const workSecondsPerSet = 40;

/// The muscles whose weekly sets are held against [weeklySetBands].
const majorMuscles = {
  Muscle.pec,
  Muscle.lat,
  Muscle.midDelt,
  Muscle.biceps,
  Muscle.triceps,
  Muscle.glute,
  Muscle.quads,
  Muscle.hamstring,
};

/// Weekly sets per major muscle a program of each level is expected to give.
/// Outside the band is a warning, not an error: focus and short programs
/// leave it on purpose and say so in their summary.
const weeklySetBands = {
  Level.beginner: (min: 6, max: 12),
  Level.intermediate: (min: 10, max: 18),
  Level.advanced: (min: 12, max: 20),
};

const programKeys = {
  'id',
  'status',
  'premium',
  'level',
  'goal',
  'daysPerWeek',
  'lengthWeeks',
  'equipment',
  'equipmentProfile',
  'order',
  'l10n',
  'days',
};
const programTextKeys = {'name', 'summary'};
const dayKeys = {'name', 'items'};
const itemKeys = {
  'exerciseId',
  'sets',
  'repMin',
  'repMax',
  'durationS',
  'restS',
  'group',
};

final programIdPattern = RegExp(r'^pr_[a-z0-9]+(_[a-z0-9]+)*$');
final groupPattern = RegExp(r'^[A-Z]$');
final _sentenceEnd = RegExp(r'[.!?](\s+|$)');

/// One program in the content-file shape, read leniently.
class ProgramEntry {
  ProgramEntry(this.data, {this.file});

  final Map<String, Object?> data;

  /// The file it came from, when it came from one.
  final String? file;

  String get id => data['id'] is String ? data['id']! as String : '?';
  String get where => file == null ? id : '$file [$id]';
  bool get isLive => data['status'] == ExerciseStatus.live.code;
  bool get isPremium => data['premium'] == true;

  /// The English name, when there is one.
  String? get name {
    final l10n = data['l10n'];
    final en = l10n is Map ? l10n['en'] : null;
    final name = en is Map ? en['name'] : null;
    return name is String && name.isNotEmpty ? name : null;
  }

  Level? get level => Level.values.byCode(data['level']);

  /// The days that are maps, with the items of each that are maps.
  List<({String name, List<Map<String, Object?>> items})> get days {
    final days = data['days'];
    if (days is! List) return const [];
    return [
      for (final day in days.whereType<Map<String, Object?>>())
        (
          name: day['name'] is String ? day['name']! as String : '',
          items: switch (day['items']) {
            final List<Object?> items =>
              items.whereType<Map<String, Object?>>().toList(),
            _ => const [],
          },
        ),
    ];
  }
}

/// The `equipment` of a program: the primary `equipment` of every exercise
/// it uses, in vocabulary order. Unknown exercise ids are left out.
List<String> programEquipment(
  ProgramEntry program,
  Map<String, ExerciseEntry> library,
) {
  final used = {
    for (final day in program.days)
      for (final item in day.items)
        ...?library[item['exerciseId']]?.strings('equipment'),
  };
  return [
    for (final e in Equipment.values)
      if (used.contains(e.code)) e.code,
  ];
}

/// Every rule [d] breaks, on its own and against [library] (every exercise,
/// by id, whatever its status). Rules across programs are [checkCatalogue]'s.
List<ContentProblem> programProblems(
  Map<String, Object?> d,
  Map<String, ExerciseEntry> library,
) {
  final check = _Problems();

  for (final key in d.keys) {
    if (!programKeys.contains(key)) check.err(key, 'unknown field "$key"');
  }
  final id = d['id'];
  if (id is! String || !programIdPattern.hasMatch(id)) {
    check.err('id', 'id must match ${programIdPattern.pattern}');
  }
  check
    ..code('status', d['status'], statuses)
    ..code('level', d['level'], levels)
    ..code('goal', d['goal'], goals)
    ..code('equipmentProfile', d['equipmentProfile'], equipmentProfiles);
  if (d['premium'] is! bool) {
    check.err('premium', 'premium must be true or false');
  }
  final order = d['order'];
  if (order is! int || order < 1) {
    check.err('order', 'order must be an integer ≥ 1');
  }
  if (d['lengthWeeks'] != null) {
    check.intIn('lengthWeeks', d['lengthWeeks'], programWeeks);
  }
  _checkText(d['l10n'], check);

  final days = d['days'];
  if (days is! List || days.isEmpty || days.length > programDays.max) {
    check.err(
      'days',
      'days must be a list of ${programDays.min}-${programDays.max}',
    );
  }
  check.intIn('daysPerWeek', d['daysPerWeek'], programDays);
  if (days is List && d['daysPerWeek'] != days.length) {
    check.err(
      'daysPerWeek',
      'daysPerWeek is ${d['daysPerWeek']} but there are ${days.length} days',
    );
  }

  final program = ProgramEntry(d);
  final profile = EquipmentProfile.values.byCode(d['equipmentProfile']);
  if (days is List) {
    for (final (i, day) in days.indexed) {
      _checkDay('days[$i]', day, library, profile, program.level, check);
    }
  }

  final equipment = d['equipment'];
  final expected = programEquipment(program, library);
  if (equipment is! List ||
      equipment.length != expected.length ||
      !expected.indexed.every((e) => equipment[e.$1] == e.$2)) {
    check.err('equipment', 'equipment must be [${expected.join(', ')}]');
  }
  return check.problems;
}

class _Problems {
  final problems = <ContentProblem>[];

  void err(String field, String message) =>
      problems.add(ContentProblem(field, message));

  void code(String field, Object? value, Iterable<String> allowed) {
    if (value is! String || !allowed.contains(value)) {
      err(field, '$field "$value" is not one of ${allowed.join(', ')}');
    }
  }

  void intIn(String field, Object? value, ({int min, int max}) range) {
    if (value is! int || value < range.min || value > range.max) {
      err(field, '$field must be an integer in ${range.min}..${range.max}');
    }
  }

  void string(String field, Object? value, {int? maxLength}) {
    if (value is! String || value.isEmpty) {
      err(field, '$field must be a non-empty string');
    } else if (value.trim() != value || value.contains('  ')) {
      err(field, '$field has stray spaces: "$value"');
    } else if (maxLength != null && value.length > maxLength) {
      err(field, '$field is longer than $maxLength characters');
    }
  }
}

void _checkText(Object? l10n, _Problems check) {
  if (l10n is! Map) {
    check.err('l10n', 'l10n must be a map');
    return;
  }
  for (final lang in l10n.keys) {
    if (!languages.contains(lang)) {
      check.err('l10n', 'l10n has unexpected language "$lang"');
    }
  }
  final text = l10n['en'];
  if (text is! Map) {
    check.err('l10n', 'l10n.en is missing');
    return;
  }
  for (final key in text.keys) {
    if (!programTextKeys.contains(key)) {
      check.err('l10n.en.$key', 'l10n.en has unknown field "$key"');
    }
  }
  check.string('l10n.en.name', text['name'], maxLength: maxProgramNameLength);
  const field = 'l10n.en.summary';
  final summary = text['summary'];
  check.string(field, summary);
  if (summary is String && summary.isNotEmpty) {
    final sentences = _sentenceEnd.allMatches(summary).length;
    if (!_sentenceEnd.hasMatch(summary.substring(summary.length - 1)) ||
        sentences < summarySentences.min ||
        sentences > summarySentences.max) {
      check.err(
        field,
        '$field must be ${summarySentences.min}-${summarySentences.max} '
        'full sentences',
      );
    }
  }
}

void _checkDay(
  String field,
  Object? day,
  Map<String, ExerciseEntry> library,
  EquipmentProfile? profile,
  Level? level,
  _Problems check,
) {
  if (day is! Map<String, Object?>) {
    check.err(field, '$field must be an object');
    return;
  }
  for (final key in day.keys) {
    if (!dayKeys.contains(key)) {
      check.err('$field.$key', '$field has unknown field "$key"');
    }
  }
  check.string('$field.name', day['name'], maxLength: maxDayNameLength);
  final items = day['items'];
  if (items is! List ||
      items.length < dayItems.min ||
      items.length > dayItems.max) {
    check.err(
      '$field.items',
      '$field.items must be a list of ${dayItems.min}-${dayItems.max}',
    );
  }
  if (items is! List) return;
  for (final (j, item) in items.indexed) {
    final itemField = '$field.items[$j]';
    if (item is! Map<String, Object?>) {
      check.err(itemField, '$itemField must be an object');
      continue;
    }
    _checkItem(itemField, item, library, profile, level, check);
  }
  _checkGroups(field, items, check);
}

void _checkItem(
  String field,
  Map<String, Object?> item,
  Map<String, ExerciseEntry> library,
  EquipmentProfile? profile,
  Level? level,
  _Problems check,
) {
  for (final key in item.keys) {
    if (!itemKeys.contains(key)) {
      check.err('$field.$key', '$field has unknown field "$key"');
    }
  }
  check
    ..intIn('$field.sets', item['sets'], itemSets)
    ..intIn('$field.restS', item['restS'], itemRestS);
  final group = item['group'];
  if (group != null && (group is! String || !groupPattern.hasMatch(group))) {
    check.err('$field.group', '$field.group must be one letter A-Z');
  }

  final exerciseId = item['exerciseId'];
  final exercise = library[exerciseId];
  if (exercise == null) {
    check.err(
      '$field.exerciseId',
      '$field uses unknown exercise "$exerciseId"',
    );
    return;
  }
  if (!exercise.isLive) {
    check.err(
      '$field.exerciseId',
      '$field uses $exerciseId, which is ${exercise.data['status']}',
    );
  }

  final loggingType = LoggingType.values.byCode(exercise.data['loggingType']);
  if (loggingType != null) {
    final byDuration = durationLoggingTypes.contains(loggingType);
    if (byDuration) {
      check.intIn('$field.durationS', item['durationS'], itemDurationS);
    } else {
      final repMin = item['repMin'], repMax = item['repMax'];
      check
        ..intIn('$field.repMin', repMin, itemReps)
        ..intIn('$field.repMax', repMax, itemReps);
      if (repMin is int && repMax is int && repMin > repMax) {
        check.err('$field.repMin', '$field has repMin above repMax');
      }
    }
    for (final key in byDuration ? ['repMin', 'repMax'] : ['durationS']) {
      if (item.containsKey(key)) {
        check.err(
          '$field.$key',
          '$field has $key, but $exerciseId is logged by '
              '${byDuration ? 'duration' : 'reps'}',
        );
      }
    }
  }

  if (profile != null && !exercise.fitsProfile(profile)) {
    check.err(
      '$field.exerciseId',
      '$exerciseId cannot be done with the ${profile.code} equipment',
    );
  }
  // An exercise may be one level above its program, not two: no advanced
  // exercise in a beginner program.
  final exerciseLevel = Level.values.byCode(exercise.data['level']);
  if (level != null &&
      exerciseLevel != null &&
      exerciseLevel.index > level.index + 1) {
    check.err(
      '$field.exerciseId',
      '$exerciseId is ${exerciseLevel.code}, too hard for a '
          '${level.code} program',
    );
  }
}

/// Items sharing a group letter sit next to each other, and a group has at
/// least two of them (a superset, or a circuit from three).
void _checkGroups(String field, List<Object?> items, _Problems check) {
  final sizes = <String, int>{};
  String? previous;
  for (final item in items) {
    final group = item is Map ? item['group'] : null;
    if (group is String) {
      if (group != previous && sizes.containsKey(group)) {
        check.err('$field.items', '$field: group $group is split by others');
      }
      sizes[group] = (sizes[group] ?? 0) + 1;
    }
    previous = group is String ? group : null;
  }
  sizes.forEach((group, size) {
    if (size < 2) {
      check.err('$field.items', '$field: group $group has one item');
    }
  });
}

/// The weekly numbers of a program: an estimate of each day's minutes and
/// the sets each muscle gets in a week (SPEC.md, "Volume").
class ProgramSummary {
  const ProgramSummary({required this.minutesPerDay, required this.weeklySets});

  final List<int> minutesPerDay;
  final Map<Muscle, double> weeklySets;
}

/// [program]'s [ProgramSummary]. A set takes [workSecondsPerSet] plus its
/// rest; every day is done once a week. Unknown exercises count nothing.
ProgramSummary summarizeProgram(
  ProgramEntry program,
  Map<String, ExerciseEntry> library,
) {
  final minutes = <int>[];
  final sets = <Muscle, double>{};
  for (final day in program.days) {
    var seconds = 0;
    for (final item in day.items) {
      final count = item['sets'] is int ? item['sets']! as int : 0;
      final rest = item['restS'] is int ? item['restS']! as int : 0;
      seconds += count * (workSecondsPerSet + rest);
      final exercise = library[item['exerciseId']];
      if (exercise == null) continue;
      for (final (key, weight) in [
        ('mainMuscles', 1.0),
        ('secondaryMuscles', 0.5),
      ]) {
        for (final muscle in exercise.strings(key)) {
          final m = Muscle.values.byCode(muscle);
          if (m != null) sets[m] = (sets[m] ?? 0) + count * weight;
        }
      }
    }
    minutes.add((seconds / 60).round());
  }
  return ProgramSummary(minutesPerDay: minutes, weeklySets: sets);
}

/// What [checkCatalogue] found across the programs.
class CatalogueCheck {
  const CatalogueCheck({required this.errors, required this.warnings});

  final List<String> errors;
  final List<String> warnings;
}

/// The rules across [programs]: unique ids, names and orders, and among live
/// programs exactly [freePrograms] free and [premiumPrograms] premium ones.
/// Warns when a live program's weekly sets for a [majorMuscles] muscle fall
/// outside its level's [weeklySetBands].
CatalogueCheck checkCatalogue(
  List<ProgramEntry> programs,
  Map<String, ExerciseEntry> library,
) {
  final errors = <String>[], warnings = <String>[];
  void unique(String label, Object? Function(ProgramEntry) key) {
    final seen = <Object, ProgramEntry>{};
    for (final p in programs) {
      final value = key(p);
      if (value == null) continue;
      final other = seen[value];
      if (other != null) {
        errors.add('${p.where}: $label "$value" also used by ${other.id}');
      }
      seen[value] = p;
    }
  }

  unique('id', (p) => p.id);
  unique('name', (p) => p.name?.toLowerCase());
  unique('order', (p) => p.data['order']);

  final live = programs.where((p) => p.isLive).toList();
  final premium = live.where((p) => p.isPremium).length;
  final free = live.length - premium;
  if (free != freePrograms || premium != premiumPrograms) {
    errors.add(
      'live programs: $free free and $premium premium, '
      'needs $freePrograms and $premiumPrograms',
    );
  }

  for (final p in live) {
    final band = weeklySetBands[p.level];
    if (band == null) continue;
    final sets = summarizeProgram(p, library).weeklySets;
    for (final muscle in majorMuscles) {
      final count = sets[muscle] ?? 0;
      if (count < band.min || count > band.max) {
        warnings.add(
          '${p.where}: ${muscle.code} gets $count weekly sets, '
          '${p.level!.code} band is ${band.min}-${band.max}',
        );
      }
    }
  }
  return CatalogueCheck(errors: errors, warnings: warnings);
}
