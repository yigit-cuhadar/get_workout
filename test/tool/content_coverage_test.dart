import 'package:flutter_test/flutter_test.dart';

import 'package:get_workout/features/exercises/domain/content_rules.dart';

import '../../tool/src/content_coverage.dart';

ExerciseEntry ex(
  String id, {
  String level = 'beginner',
  String pattern = 'isolation',
  List<String> equipment = const ['bodyweight'],
  List<List<String>>? alternatives,
  List<String> main = const ['pec'],
  List<String> secondary = const [],
  String? family,
  List<String> pinned = const [],
  Map<String, Object?>? text,
}) => ExerciseEntry({
  'id': id,
  'status': 'live',
  'level': level,
  'movementPattern': pattern,
  'equipment': equipment,
  'equipmentAlternatives': ?alternatives,
  'mainMuscles': main,
  'secondaryMuscles': secondary,
  'family': family ?? id,
  'pinnedAlternatives': pinned,
  'l10n': {
    'en':
        text ??
        {
          'name': id,
          'setup': ['Stand tall.'],
          'execution': ['Press up.'],
          'mistakes': ['Rushing.'],
          'cues': ['Brace'],
        },
  },
});

void main() {
  test('countBy counts codes in single values and lists', () {
    final exercises = [
      ex('a', main: ['pec', 'triceps']),
      ex('b', main: ['pec'], level: 'advanced'),
    ];

    expect(countBy(exercises, 'mainMuscles', ['pec', 'triceps', 'lat']), {
      'pec': 2,
      'triceps': 1,
      'lat': 0,
    });
    expect(countBy(exercises, 'level', ['beginner', 'advanced']), {
      'beginner': 1,
      'advanced': 1,
    });
  });

  test('countByEquipment counts alternative sets too', () {
    final counts = countByEquipment([
      ex(
        'a',
        equipment: ['kettlebell'],
        alternatives: [
          ['dumbbell', 'bench'],
        ],
      ),
      ex('b', equipment: ['dumbbell']),
    ]);

    expect(counts['dumbbell'], 2);
    expect(counts['bench'], 1);
    expect(counts['kettlebell'], 1);
    expect(counts['cable'], 0);
  });

  test('withoutSwaps lists exercises with no alternative or variation', () {
    final found = withoutSwaps([
      ex('family_a', family: 'f'),
      ex('family_b', family: 'f', main: ['lat']),
      ex('pattern_a', main: ['quads', 'glute'], pattern: 'squat'),
      ex('pattern_b', main: ['glute'], pattern: 'squat'),
      ex('other_pattern', main: ['glute'], pattern: 'hinge'),
      ex('pinned', main: ['calf'], pinned: ['family_a']),
    ]);

    expect(found, ['other_pattern']);
  });

  test('singleFamilies maps lone families to their exercise', () {
    expect(
      singleFamilies([
        ex('a', family: 'f'),
        ex('b', family: 'f'),
        ex('c', family: 'g'),
      ]),
      {'g': 'c'},
    );
  });

  group('names', () {
    test('nameKey ignores case, punctuation, plurals and order', () {
      expect(nameKey('Curls, Dumbbell'), nameKey('Dumbbell Curl'));
      expect(nameKey('Push-Up'), nameKey('push up'));
      expect(nameKey('Press'), isNot(nameKey('Pres')));
      expect(nameKey('Abs'), 'abs');
    });

    test('nearDuplicateNames pairs names and aliases once', () {
      ExerciseEntry named(String id, String name, [List<String>? aliases]) =>
          ex(id, text: {'name': name, 'aliases': ?aliases});

      expect(
        nearDuplicateNames([
          named('ex_a', 'Dumbbell Curl', ['DB Curl']),
          named('ex_b', 'Curls, Dumbbell'),
          named('ex_c', 'Hammer Curl', ['DB Curl']),
          named('ex_d', 'Plank'),
        ]),
        [
          'ex_a = ex_b ("Dumbbell Curl" / "Curls, Dumbbell")',
          'ex_a = ex_c ("DB Curl" / "DB Curl")',
        ],
      );
    });
  });

  test('textDefects finds fragments, non-sentences and copied fields', () {
    final defects = textDefects([
      ex(
        'a',
        text: {
          'setup': ['Stand tall.', 'grip it'],
          'execution': ['Go.'],
          'mistakes': ['Rushing.'],
          'safety': 'Stop if it hurts',
          'cues': ['Up'],
        },
      ),
      ex(
        'b',
        text: {
          'setup': ['Stand tall.', 'grip it'],
          'execution': ['Press up.'],
          'mistakes': ['Rushing.'],
          'cues': ['Brace'],
        },
      ),
    ]);

    expect(defects.short, [
      'a setup: "grip it"',
      'a execution: "Go."',
      'a cues: "Up"',
      'b setup: "grip it"',
    ]);
    expect(defects.unpunctuated, [
      'a setup: "grip it"',
      'a safety: "Stop if it hurts"',
      'b setup: "grip it"',
    ]);
    expect(defects.shared, ['setup: a, b', 'mistakes: a, b']);
  });
}
