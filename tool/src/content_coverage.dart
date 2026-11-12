// The coverage audit of the live exercise library: counts by muscle,
// equipment, equipment profile, level and pattern, the exercises a user
// could not swap or vary, and text that looks wrong. Its one rule is the
// program generator's: every muscle has [maxExercisesPerMuscle] exercises
// the generator may give a beginner, in every equipment profile.
//
// Used by tool/coverage_report.dart.
import 'package:get_workout/features/exercises/domain/content_rules.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/program_generator.dart'
    show leftOutPatterns, maxExercisesPerMuscle;

/// Whether the generator may give [e] to a user of [level] who owns the
/// equipment of [profile]: at most one level above, a strength pattern, and
/// doable with the profile through `equipment` or an alternative set.
bool generatorUsable(ExerciseEntry e, EquipmentProfile profile, Level level) {
  final own = Level.values.byCode(e.data['level']);
  final pattern = MovementPattern.values.byCode(e.data['movementPattern']);
  return own != null &&
      own.index <= level.index + 1 &&
      pattern != null &&
      !leftOutPatterns.contains(pattern) &&
      e.fitsProfile(profile);
}

/// For each profile and muscle, how many of [live] the generator may give a
/// beginner (the smallest pool) as a main-muscle exercise.
Map<EquipmentProfile, Map<Muscle, int>> generatorCoverage(
  List<ExerciseEntry> live,
) => {
  for (final profile in EquipmentProfile.values)
    profile: {
      for (final muscle in Muscle.values)
        muscle: live
            .where(
              (e) =>
                  e.strings('mainMuscles').contains(muscle.code) &&
                  generatorUsable(e, profile, Level.beginner),
            )
            .length,
    },
};

/// Cells allowed fewer than [maxExercisesPerMuscle], because no standard
/// exercise with that equipment loads the muscle as a main mover: without
/// a load, side delts get the prone Y raise and an isometric (the presses
/// that also work them are front-delt exercises), and forearms get the
/// hangs. The generator still covers them, repeating within the week.
const coverageExceptions = {
  (EquipmentProfile.bodyweight, Muscle.midDelt): 2,
  (EquipmentProfile.bodyweight, Muscle.forearm): 2,
};

/// How many usable exercises [muscle] needs in [profile].
int neededFor(EquipmentProfile profile, Muscle muscle) =>
    coverageExceptions[(profile, muscle)] ?? maxExercisesPerMuscle;

/// The cells of [coverage] below [neededFor], as
/// `profile × muscle: n, needs m`.
List<String> shortfalls(Map<EquipmentProfile, Map<Muscle, int>> coverage) => [
  for (final MapEntry(key: profile, value: counts) in coverage.entries)
    for (final MapEntry(key: muscle, value: count) in counts.entries)
      if (count < neededFor(profile, muscle))
        '${profile.code} × ${muscle.code}: $count, '
            'needs ${neededFor(profile, muscle)}',
];

/// How many of [exercises] carry each of [codes] in [key] (a code or a list
/// of codes), every code listed, in order.
Map<String, int> countBy(
  List<ExerciseEntry> exercises,
  String key,
  List<String> codes,
) => {
  for (final code in codes)
    code: exercises.where((e) {
      final value = e.data[key];
      return value is List ? value.contains(code) : value == code;
    }).length,
};

/// How many of [exercises] can use each equipment code, through `equipment`
/// or an alternative set.
Map<String, int> countByEquipment(List<ExerciseEntry> exercises) => {
  for (final item in Equipment.values)
    item.code: exercises
        .where((e) => e.equipmentSets.any((set) => set.contains(item.code)))
        .length,
};

/// The ids of [live] exercises the app offers neither an alternative nor a
/// variation for: no pinned alternative, no other exercise sharing a main
/// muscle and the movement pattern, and no other member of the family.
List<String> withoutSwaps(List<ExerciseEntry> live) => [
  for (final e in live)
    if (e.strings('pinnedAlternatives').isEmpty &&
        !live.any(
          (o) =>
              o.id != e.id &&
              (o.data['family'] == e.data['family'] ||
                  (o.data['movementPattern'] == e.data['movementPattern'] &&
                      o
                          .strings('mainMuscles')
                          .any(e.strings('mainMuscles').contains))),
        ))
      e.id,
];

/// Families of [live] with a single member, as family → id.
Map<String, String> singleFamilies(List<ExerciseEntry> live) {
  final members = <String, List<String>>{};
  for (final e in live) {
    final family = e.data['family'];
    if (family is String) (members[family] ??= []).add(e.id);
  }
  return {
    for (final MapEntry(key: family, value: ids) in members.entries)
      if (ids.length == 1) family: ids.single,
  };
}

/// A name reduced to its words, lower case, without punctuation, plural
/// `s` or order, so "Curls, Dumbbell" and "Dumbbell Curl" meet.
String nameKey(String name) {
  final words =
      name
          .toLowerCase()
          .split(RegExp('[^a-z0-9]+'))
          .where((w) => w.isNotEmpty)
          .map(
            (w) => w.length > 3 && w.endsWith('s')
                ? w.substring(0, w.length - 1)
                : w,
          )
          .toList()
        ..sort();
  return words.join(' ');
}

/// Pairs of exercises whose names or aliases share a [nameKey], as
/// `id = id ("name" / "name")`, each pair once.
List<String> nearDuplicateNames(List<ExerciseEntry> exercises) {
  final owners = <String, Map<String, String>>{};
  for (final e in exercises) {
    for (final name in [?e.name, ...e.aliases]) {
      (owners[nameKey(name)] ??= {}).putIfAbsent(e.id, () => name);
    }
  }
  final pairs = <String>{};
  for (final named in owners.values) {
    final ids = named.keys.toList()..sort();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        pairs.add(
          '${ids[i]} = ${ids[j]} '
          '("${named[ids[i]]}" / "${named[ids[j]]}")',
        );
      }
    }
  }
  return pairs.toList()..sort();
}

/// The shortest a line of each text field may be, in characters: shorter
/// is a fragment. Terse lines such as "Lower slowly." are the house style.
const minTextLength = {
  'setup': 8,
  'execution': 8,
  'mistakes': 8,
  'safety': 8,
  'cues': 3,
};

/// The fields written as sentences: a capital first, a full stop last.
/// Cues are short phrases without one.
const sentenceKeys = {'setup', 'execution', 'mistakes', 'safety'};

/// The fields reported when two exercises have them word for word, which
/// suggests a copy left unedited. Single lines and cues repeat on purpose.
const sharedFieldKeys = {'setup', 'execution', 'mistakes'};

final _sentence = RegExp(r'^[A-Z0-9].*[.!?]$');

/// The text lines of [exercises] that are shorter than [minTextLength]
/// (`id key: "line"`), the [sentenceKeys] lines that are not a sentence
/// (`id key: "line"`), and the [sharedFieldKeys] fields identical across
/// exercises (`key: id, id`).
({List<String> short, List<String> unpunctuated, List<String> shared})
textDefects(List<ExerciseEntry> exercises) {
  final short = <String>[], unpunctuated = <String>[];
  final owners = <String, List<String>>{};
  for (final e in exercises) {
    for (final MapEntry(key: key, value: min) in minTextLength.entries) {
      final value = e.text[key];
      final lines = switch (value) {
        final List<Object?> list => list,
        null => const <Object?>[],
        _ => [value],
      };
      for (final line in lines) {
        final text = line is String ? line.trim() : '';
        if (text.length < min) short.add('${e.id} $key: "$text"');
        if (sentenceKeys.contains(key) && !_sentence.hasMatch(text)) {
          unpunctuated.add('${e.id} $key: "$text"');
        }
      }
      if (sharedFieldKeys.contains(key) && lines.isNotEmpty) {
        (owners['$key ${lines.join(' | ')}'] ??= []).add(e.id);
      }
    }
  }
  return (
    short: short,
    unpunctuated: unpunctuated,
    shared: [
      for (final MapEntry(key: field, value: ids) in owners.entries)
        if (ids.length > 1) '${field.split(' ').first}: ${ids.join(', ')}',
    ],
  );
}

/// The printable report of [live] exercises; the generator rule's
/// [shortfalls] decide whether the library passes.
String coverageReport(List<ExerciseEntry> live) {
  final out = StringBuffer();
  void table(String title, Map<String, int> counts) {
    out.writeln(title);
    counts.forEach((code, n) => out.writeln('  ${code.padRight(22)} $n'));
  }

  final muscles = [for (final m in Muscle.values) m.code];
  out.writeln('Live exercises: ${live.length}');
  table('Main muscle', countBy(live, 'mainMuscles', muscles));
  table('Secondary muscle', countBy(live, 'secondaryMuscles', muscles));
  table('Equipment (main or alternative set)', countByEquipment(live));
  table(
    'Level',
    countBy(live, 'level', [for (final l in Level.values) l.code]),
  );
  table(
    'Movement pattern',
    countBy(live, 'movementPattern', [
      for (final p in MovementPattern.values) p.code,
    ]),
  );

  final generator = generatorCoverage(live);
  out
    ..writeln(
      'Profiles: doable / usable by the generator for a beginner '
      '(level <= intermediate, no ${leftOutPatterns.map((p) => p.code).join(' or ')}), '
      'by main muscle',
    )
    ..writeln(
      '  ${''.padRight(12)}'
      '${EquipmentProfile.values.map((p) => p.code.padLeft(12)).join()}',
    );
  for (final muscle in Muscle.values) {
    out.write('  ${muscle.code.padRight(12)}');
    for (final profile in EquipmentProfile.values) {
      final doable = live
          .where(
            (e) =>
                e.strings('mainMuscles').contains(muscle.code) &&
                e.fitsProfile(profile),
          )
          .length;
      final usable = generator[profile]![muscle]!;
      final mark = usable < neededFor(profile, muscle) ? '!' : ' ';
      out.write('$mark$doable/$usable'.padLeft(12));
    }
    out.writeln();
  }
  out.write('  ${'all'.padRight(12)}');
  for (final profile in EquipmentProfile.values) {
    out.write(
      '${live.where((e) => e.fitsProfile(profile)).length}'.padLeft(12),
    );
  }
  out.writeln();

  void list(String title, Iterable<String> lines) {
    out.writeln('$title: ${lines.length}');
    for (final line in lines) {
      out.writeln('  $line');
    }
  }

  list('No alternative or variation', withoutSwaps(live));
  list('Single-member families', [
    for (final MapEntry(key: family, value: id) in singleFamilies(live).entries)
      '$family: $id',
  ]);
  list('Near-duplicate names', nearDuplicateNames(live));
  final text = textDefects(live);
  list('Empty or short text lines', text.short);
  list('Lines that are not a sentence', text.unpunctuated);
  list('Fields identical across exercises', text.shared);
  list('Generator rule exceptions', [
    for (final MapEntry(key: (profile, muscle), value: needed)
        in coverageExceptions.entries)
      '${profile.code} × ${muscle.code}: needs $needed',
  ]);
  list(
    'Generator rule: every muscle has $maxExercisesPerMuscle usable '
    'exercises in every profile; shortfalls',
    shortfalls(generator),
  );
  return out.toString();
}
