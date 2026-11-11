// The rules of the ready-made programs (SPEC.md, `programs/{id}` and
// `programs/{id}/detail/main`), checked on the content-file shape: the map
// of one `content/programs/<id>.json`, with its `id`, the card fields and
// `days` together.
//
// The days are checked by the app's own [validateProgram], so a catalogue
// program is always one the builder accepts; this file adds only what the
// catalogue asks beyond that: the card, the equipment profile and level of
// each exercise, and the catalogue as a whole. Shared by
// tool/validate_content.dart and the importer, so it is pure Dart and its
// messages are the validator's output.
import '../../exercises/domain/content_rules.dart';
import '../../exercises/domain/vocabulary.dart';
import 'program.dart';
import 'program_editing.dart';
import 'program_validation.dart';

final goals = [for (final goal in Goal.values) goal.code];
final equipmentProfiles = [
  for (final profile in EquipmentProfile.values) profile.code,
];
const summarySentences = (min: 1, max: 2);

// The catalogue's split of live programs (SPEC.md, "Monetization").
const freePrograms = 6;
const premiumPrograms = 19;

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
  'minutes',
  'equipmentProfile',
  'order',
  'l10n',
  'days',
};
const programTextKeys = {'name', 'summary'};
const dayKeys = {'name', 'items'};

/// The fields of a stored program item, but `targetKg`: a catalogue
/// program sets no weights.
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
  Level? get level => Level.values.byCode(data['level']);

  /// The English text, or an empty map.
  Map<Object?, Object?> get text {
    final l10n = data['l10n'];
    final en = l10n is Map ? l10n['en'] : null;
    return en is Map ? en : const {};
  }

  /// The English name, when there is one.
  String? get name => switch (text['name']) {
    final String name when name.isNotEmpty => name,
    _ => null,
  };

  /// The program as the app holds it. A value of the wrong type becomes one
  /// that [validateProgram] rejects (or null, for an optional one), so it is
  /// reported there.
  Program get program {
    final weeks = data['lengthWeeks'];
    final days = data['days'];
    return Program(
      name: name ?? '',
      origin: ProgramOrigin.catalog,
      sourceId: id,
      lengthWeeks: weeks == null ? null : (weeks is int ? weeks : 0),
      days: [
        if (days is List)
          // A day or item that is not an object stays in place, empty, so
          // the app's issues keep their indexes.
          for (final day in days) day is Map ? _day(day) : const ProgramDay(),
      ],
    );
  }

  static ProgramDay _day(Map<Object?, Object?> day) {
    final items = day['items'];
    return ProgramDay(
      name: day['name'] is String ? day['name']! as String : '',
      items: [
        if (items is List)
          for (final item in items) _item(item is Map ? item : const {}),
      ],
    );
  }

  static ProgramItem _item(Map<Object?, Object?> item) {
    int? optional(String key) => switch (item[key]) {
      null => null,
      final int value => value,
      _ => -1,
    };
    return ProgramItem(
      exerciseId: item['exerciseId'] is String
          ? item['exerciseId']! as String
          : '',
      sets: optional('sets') ?? -1,
      repMin: optional('repMin'),
      repMax: optional('repMax'),
      durationS: optional('durationS'),
      restS: optional('restS') ?? -1,
      group: item['group'] is String ? item['group']! as String : null,
    );
  }
}

/// The logging type of every live exercise of [library], by id: what the
/// app's [validateProgram] takes as the available exercises.
Map<String, LoggingType> liveLoggingTypes(Map<String, ExerciseEntry> library) =>
    {
      for (final MapEntry(key: id, value: e) in library.entries)
        if (e.isLive) id: ?LoggingType.values.byCode(e.data['loggingType']),
    };

/// The `equipment` of a program: the primary `equipment` of every exercise
/// it uses, in vocabulary order. Unknown exercise ids are left out.
List<String> programEquipment(
  ProgramEntry program,
  Map<String, ExerciseEntry> library,
) {
  final used = {
    for (final day in program.program.days)
      for (final item in day.items)
        ...?library[item.exerciseId]?.strings('equipment'),
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
  final entry = ProgramEntry(d);

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
  _checkText(d['l10n'], check);

  final days = d['days'];
  if (days is! List) {
    check.err('days', 'days must be a list');
  } else if (d['daysPerWeek'] != days.length) {
    check.err(
      'daysPerWeek',
      'daysPerWeek is ${d['daysPerWeek']} but there are ${days.length} days',
    );
  }

  final profile = EquipmentProfile.values.byCode(d['equipmentProfile']);
  if (days is List) {
    for (final (i, day) in days.indexed) {
      _checkDay('days[$i]', day, library, profile, entry.level, check);
    }
  }
  _checkWithApp(entry.program, library, check);

  final equipment = d['equipment'];
  final expected = programEquipment(entry, library);
  if (equipment is! List ||
      equipment.length != expected.length ||
      !expected.indexed.every((e) => equipment[e.$1] == e.$2)) {
    check.err('equipment', 'equipment must be [${expected.join(', ')}]');
  }

  if (sessionMinutes(entry.program.days) case (:final min, :final max)) {
    final minutes = d['minutes'];
    if (minutes is! Map || minutes['min'] != min || minutes['max'] != max) {
      check.err('minutes', 'minutes must be {"min": $min, "max": $max}');
    }
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

  /// A catalogue text is never blank and has no stray spaces; its length is
  /// the app's rule.
  void string(String field, Object? value) {
    if (value is! String || value.isEmpty) {
      err(field, '$field must be a non-empty string');
    } else if (value.trim() != value || value.contains('  ')) {
      err(field, '$field has stray spaces: "$value"');
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
  check.string('l10n.en.name', text['name']);
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
  check.string('$field.name', day['name']);
  final items = day['items'];
  if (items is! List) return;
  for (final (j, item) in items.indexed) {
    final itemField = '$field.items[$j]';
    if (item is! Map<String, Object?>) {
      check.err(itemField, '$itemField must be an object');
      continue;
    }
    for (final key in item.keys) {
      if (!itemKeys.contains(key)) {
        check.err('$itemField.$key', '$itemField has unknown field "$key"');
      }
    }
    final group = item['group'];
    if (group != null && (group is! String || !groupPattern.hasMatch(group))) {
      check.err('$itemField.group', '$itemField.group must be one letter A-Z');
    }
    final exerciseId = item['exerciseId'];
    final exercise = library[exerciseId];
    if (exercise == null) continue;
    if (profile != null && !exercise.fitsProfile(profile)) {
      check.err(
        '$itemField.exerciseId',
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
        '$itemField.exerciseId',
        '$exerciseId is ${exerciseLevel.code}, too hard for a '
            '${level.code} program',
      );
    }
  }
}

/// Reports what the app's [validateProgram] finds in [program], in the
/// content file's field names.
void _checkWithApp(
  Program program,
  Map<String, ExerciseEntry> library,
  _Problems check,
) {
  final result = validateProgram(program, liveLoggingTypes(library));
  for (final issue in result.program) {
    switch (issue) {
      case ProgramIssue.nameMissing:
        break; // Reported by the text check.
      case ProgramIssue.nameTooLong:
        check.err(
          'l10n.en.name',
          'l10n.en.name is longer than ${ProgramLimits.maxNameLength} '
              'characters',
        );
      case ProgramIssue.lengthWeeksOutOfRange:
        check.err(
          'lengthWeeks',
          'lengthWeeks must be an integer in '
              '${ProgramLimits.minLengthWeeks}..${ProgramLimits.maxLengthWeeks}',
        );
      case ProgramIssue.noDays || ProgramIssue.tooManyDays:
        check.err('days', 'days must be a list of 1-${ProgramLimits.maxDays}');
    }
  }
  result.days.forEach((d, issues) {
    final field = 'days[$d]';
    for (final issue in issues) {
      switch (issue) {
        case DayIssue.nameTooLong:
          check.err(
            '$field.name',
            '$field.name is longer than ${ProgramLimits.maxDayNameLength} '
                'characters',
          );
        case DayIssue.noItems || DayIssue.tooManyItems:
          check.err(
            '$field.items',
            '$field.items must be a list of 1-${ProgramLimits.maxItemsPerDay}',
          );
      }
    }
  });
  result.items.forEach((ref, issues) {
    final field = 'days[${ref.day}].items[${ref.item}]';
    final item = program.days[ref.day].items[ref.item];
    for (final issue in issues) {
      final (key, message) = switch (issue) {
        ItemIssue.exerciseUnavailable => (
          'exerciseId',
          'uses "${item.exerciseId}", which is not a live exercise',
        ),
        ItemIssue.setsOutOfRange => (
          'sets',
          'sets must be an integer in '
              '${ProgramLimits.minSets}..${ProgramLimits.maxSets}',
        ),
        ItemIssue.repsMissing => ('repMin', 'needs repMin and repMax'),
        ItemIssue.repsOutOfRange => (
          'repMin',
          'reps must be integers in '
              '${ProgramLimits.minReps}..${ProgramLimits.maxReps}',
        ),
        ItemIssue.repRangeInverted => ('repMin', 'has repMin above repMax'),
        ItemIssue.durationMissing => ('durationS', 'needs durationS'),
        ItemIssue.durationOutOfRange => (
          'durationS',
          'durationS must be an integer in '
              '${ProgramLimits.minDurationS}..${ProgramLimits.maxDurationS}',
        ),
        ItemIssue.restOutOfRange => (
          'restS',
          'restS must be an integer in 0..${ProgramLimits.maxRestS}',
        ),
        ItemIssue.targetOutOfRange || ItemIssue.wrongTarget => (
          'exerciseId',
          'does not match how ${item.exerciseId} is logged '
              '(${library[item.exerciseId]?.data['loggingType']})',
        ),
        ItemIssue.groupInvalid => (
          'group',
          'group ${item.group} needs two or more adjacent items',
        ),
      };
      check.err('$field.$key', '$field $message');
    }
  });
}

/// The weekly numbers of a program: the app's estimate of each day's
/// minutes and the sets each muscle gets in a week (SPEC.md, "Volume").
class ProgramSummary {
  const ProgramSummary({required this.minutesPerDay, required this.weeklySets});

  final List<int> minutesPerDay;
  final Map<Muscle, double> weeklySets;
}

/// [sets] as printed: `12` or `12.5`.
String formatSets(double sets) =>
    sets == sets.roundToDouble() ? '${sets.round()}' : '$sets';

/// [program]'s [ProgramSummary]: minutes from the app's [estimateDay];
/// every day is done once a week. Unknown exercises count no sets.
ProgramSummary summarizeProgram(
  ProgramEntry program,
  Map<String, ExerciseEntry> library,
) {
  final days = program.program.days;
  final sets = <Muscle, double>{};
  for (final day in days) {
    for (final item in day.items) {
      final exercise = library[item.exerciseId];
      if (exercise == null || item.sets < 0) continue;
      for (final (key, weight) in [
        ('mainMuscles', 1.0),
        ('secondaryMuscles', 0.5),
      ]) {
        for (final muscle in exercise.strings(key)) {
          final m = Muscle.values.byCode(muscle);
          if (m != null) sets[m] = (sets[m] ?? 0) + item.sets * weight;
        }
      }
    }
  }
  return ProgramSummary(
    minutesPerDay: [
      for (final day in days) (estimateDay(day).inSeconds / 60).round(),
    ],
    weeklySets: sets,
  );
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
          '${p.where}: ${muscle.code} gets ${formatSets(count)} weekly sets, '
          '${p.level!.code} band is ${band.min}-${band.max}',
        );
      }
    }
  }
  return CatalogueCheck(errors: errors, warnings: warnings);
}
