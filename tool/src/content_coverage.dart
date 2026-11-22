// The coverage audit of the live exercise library: counts by muscle,
// equipment, equipment profile, level and pattern, the exercises a user
// could not swap or vary, and text that looks wrong.
//
// Used by tool/coverage_report.dart.
import 'package:get_workout/features/exercises/domain/content_rules.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

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

/// The printable report of [live] exercises.
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

  out
    ..writeln('Profiles: doable exercises by main muscle')
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
      out.write('$doable'.padLeft(12));
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
  return out.toString();
}
