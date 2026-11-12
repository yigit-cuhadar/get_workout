import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:get_workout/features/exercises/domain/content_rules.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

import '../../tool/src/content_coverage.dart';
import '../../tool/src/content_validator.dart';

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
  group('generatorUsable', () {
    const beginner = Level.beginner;

    test('takes one level above the user, not two', () {
      expect(generatorUsable(ex('a'), EquipmentProfile.bands, beginner), true);
      expect(
        generatorUsable(
          ex('a', level: 'intermediate'),
          EquipmentProfile.bands,
          beginner,
        ),
        true,
      );
      expect(
        generatorUsable(
          ex('a', level: 'advanced'),
          EquipmentProfile.bands,
          beginner,
        ),
        false,
      );
      expect(
        generatorUsable(
          ex('a', level: 'advanced'),
          EquipmentProfile.bands,
          Level.intermediate,
        ),
        true,
      );
    });

    test('leaves out mobility and explosive patterns', () {
      for (final pattern in ['mobility', 'explosive']) {
        expect(
          generatorUsable(
            ex('a', pattern: pattern),
            EquipmentProfile.fullGym,
            beginner,
          ),
          false,
        );
      }
    });

    test('fits the profile through equipment or an alternative set', () {
      final rowing = ex(
        'a',
        equipment: ['kettlebell'],
        alternatives: [
          ['dumbbell'],
        ],
      );
      expect(
        generatorUsable(rowing, EquipmentProfile.dumbbells, beginner),
        true,
      );
      expect(generatorUsable(rowing, EquipmentProfile.bands, beginner), false);
      expect(generatorUsable(rowing, EquipmentProfile.fullGym, beginner), true);
    });
  });

  group('shortfalls', () {
    test('names every profile and muscle below the minimum', () {
      final coverage = generatorCoverage([
        for (final id in ['a', 'b', 'c']) ex(id),
      ]);

      expect(coverage[EquipmentProfile.bands]![Muscle.pec], 3);
      expect(coverage[EquipmentProfile.bands]![Muscle.lat], 0);
      final found = shortfalls(coverage);
      expect(found, isNot(contains(startsWith('bands × pec'))));
      expect(found, contains('bands × lat: 0, needs 3'));
      expect(
        found,
        hasLength(EquipmentProfile.values.length * (Muscle.values.length - 1)),
      );
    });

    test('counts main muscles only, and not advanced exercises', () {
      final coverage = generatorCoverage([
        ex('a', main: ['lat'], secondary: ['pec']),
        ex('b', level: 'advanced'),
      ]);

      expect(coverage[EquipmentProfile.fullGym]![Muscle.pec], 0);
      expect(coverage[EquipmentProfile.fullGym]![Muscle.lat], 1);
    });

    test('holds the exception cells to their own minimum', () {
      expect(neededFor(EquipmentProfile.bodyweight, Muscle.midDelt), 2);
      expect(neededFor(EquipmentProfile.bands, Muscle.midDelt), 3);
      final found = shortfalls(
        generatorCoverage([
          ex('a', main: ['mid_delt']),
          ex('b', main: ['mid_delt']),
        ]),
      );
      expect(found, isNot(contains(startsWith('bodyweight × mid_delt'))));
      expect(found, contains('bands × mid_delt: 2, needs 3'));
    });

    test('pass for the content files', () {
      final report = validateContent(Directory('content/exercises'));

      expect(report.errors, isEmpty);
      expect(shortfalls(generatorCoverage(report.live)), isEmpty);
    });
  });

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
