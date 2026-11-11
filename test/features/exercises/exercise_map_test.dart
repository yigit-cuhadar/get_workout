import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/data/exercise_map.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

Map<String, Object?> validMap() => {
  'status': 'live',
  'loggingType': 'weight_reps',
  'mechanic': 'compound',
  'laterality': 'bilateral',
  'level': 'beginner',
  'force': 'push',
  'movementPattern': 'horizontal_push',
  'position': 'supine',
  'equipment': ['dumbbell', 'bench'],
  'equipmentAlternatives': [
    ['kettlebell', 'bench'],
  ],
  'mainMuscles': ['pec'],
  'secondaryMuscles': ['triceps'],
  'family': 'bench_press',
  'familyRank': 3,
  'pinnedAlternatives': <String>[],
  'excludedAlternatives': <String>[],
  'defaultRestS': 90,
  'popularity': 5,
  'l10n': {
    'en': {
      'name': 'Dumbbell Bench Press',
      'aliases': ['DB Bench'],
      'setup': ['Lie down.'],
      'execution': ['Press.'],
      'mistakes': ['Bouncing.'],
      'cues': ['Drive'],
    },
    'tr': {
      'name': 'Dambıl Bench Press',
      'aliases': <String>[],
      'setup': <String>[],
      'execution': <String>[],
      'mistakes': <String>[],
      'cues': <String>[],
    },
  },
};

void main() {
  test('reads every field', () {
    final updatedAt = DateTime.utc(2026, 11, 1);
    final exercise = exerciseFromMap('ex_1', {
      ...validMap(),
      'grip': 'neutral',
      'incrementKg': 2,
      'updatedAt': Timestamp.fromDate(updatedAt),
    });

    expect(exercise.id, 'ex_1');
    expect(exercise.status, ExerciseStatus.live);
    expect(exercise.equipment, [Equipment.dumbbell, Equipment.bench]);
    expect(exercise.equipmentAlternatives, [
      [Equipment.kettlebell, Equipment.bench],
    ]);
    expect(exercise.grip, Grip.neutral);
    expect(exercise.gripWidth, isNull);
    expect(exercise.incrementKg, 2.0);
    expect(exercise.updatedAt?.toUtc(), updatedAt);
  });

  test('text falls back to English for a missing language', () {
    final exercise = exerciseFromMap('ex_1', validMap());

    expect(exercise.text('tr').name, 'Dambıl Bench Press');
    expect(exercise.text('de').name, 'Dumbbell Bench Press');
  });

  test('reads equipment alternatives in the Firestore shape', () {
    final exercise = exerciseFromMap('ex_1', {
      ...validMap(),
      'equipmentAlternatives': [
        {
          'items': ['kettlebell', 'bench'],
        },
        {
          'items': ['bodyweight'],
        },
      ],
      'contentHash': 'abc123',
    });
    expect(exercise.equipmentAlternatives, [
      [Equipment.kettlebell, Equipment.bench],
      [Equipment.bodyweight],
    ]);
    expect(exerciseToMap(exercise)['equipmentAlternatives'], [
      {
        'items': ['kettlebell', 'bench'],
      },
      {
        'items': ['bodyweight'],
      },
    ]);
  });

  test('absent equipment alternatives read as none', () {
    final exercise = exerciseFromMap(
      'ex_1',
      validMap()..remove('equipmentAlternatives'),
    );
    expect(exercise.equipmentAlternatives, isEmpty);
  });

  group('rejects with a message naming the field', () {
    void expectRejected(Map<String, Object?> map, String field) => expect(
      () => exerciseFromMap('ex_1', map),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('ex_1'), contains(field)),
        ),
      ),
    );

    test('an unknown required code', () {
      expectRejected({...validMap(), 'level': 'expert'}, 'level');
    });

    test('an unknown optional code', () {
      expectRejected({...validMap(), 'grip': 'hook'}, 'grip');
    });

    test('an unknown code in a list', () {
      expectRejected({
        ...validMap(),
        'mainMuscles': ['pec', 'neck'],
      }, 'mainMuscles');
    });

    test('an unknown code in an equipment alternative', () {
      expectRejected({
        ...validMap(),
        'equipmentAlternatives': [
          ['bench'],
          ['laser'],
        ],
      }, 'equipmentAlternatives[1]');
    });

    test('an equipment alternative map without items', () {
      expectRejected({
        ...validMap(),
        'equipmentAlternatives': [
          {
            'codes': ['bench'],
          },
        ],
      }, 'equipmentAlternatives[0]');
    });

    test('a missing required field', () {
      expectRejected(validMap()..remove('popularity'), 'popularity');
    });

    test('a field of the wrong type', () {
      expectRejected({...validMap(), 'familyRank': '3'}, 'familyRank');
    });

    test('empty equipment', () {
      expectRejected({...validMap(), 'equipment': <String>[]}, 'equipment');
    });

    test('no main muscle', () {
      expectRejected({...validMap(), 'mainMuscles': <String>[]}, 'mainMuscles');
    });

    test('no English text', () {
      final map = validMap();
      (map['l10n']! as Map<String, Object?>).remove('en');
      expectRejected(map, 'l10n.en');
    });

    test('a text without a name', () {
      final map = validMap();
      ((map['l10n']! as Map<String, Object?>)['tr']! as Map<String, Object?>)
          .remove('name');
      expectRejected(map, 'l10n.tr.name');
    });
  });
}
