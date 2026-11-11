import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_queries.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

import 'fixtures.dart';

void main() {
  group('isDoableWith', () {
    final benchPress = exercise(
      'bench',
      equipment: [Equipment.barbell, Equipment.bench],
      equipmentAlternatives: [
        [Equipment.dumbbell, Equipment.bench],
        [Equipment.smithMachine, Equipment.bench],
      ],
    );

    test('needs every item of the main set', () {
      expect(
        benchPress.isDoableWith({Equipment.barbell, Equipment.bench}),
        isTrue,
      );
      expect(benchPress.isDoableWith({Equipment.barbell}), isFalse);
    });

    test('accepts any one alternative set, fully owned', () {
      expect(
        benchPress.isDoableWith({Equipment.dumbbell, Equipment.bench}),
        isTrue,
      );
      expect(
        benchPress.isDoableWith({Equipment.dumbbell, Equipment.smithMachine}),
        isFalse,
      );
    });

    test('bodyweight is always owned', () {
      expect(exercise('push_up').isDoableWith({}), isTrue);
      final dips = exercise(
        'dip',
        equipment: [Equipment.dipStation],
        equipmentAlternatives: [
          [Equipment.bodyweight],
        ],
      );
      expect(dips.isDoableWith({}), isTrue);
    });

    test('nothing owned fits nothing that needs equipment', () {
      expect(benchPress.isDoableWith({}), isFalse);
    });
  });

  group('searchExercises', () {
    final pushUp = exercise(
      'push_up',
      name: 'Push-Up',
      aliases: ['Press-Up'],
      popularity: 6,
    );
    final inclinePushUp = exercise(
      'incline_push_up',
      name: 'Incline Push-Up',
      popularity: 2,
    );
    final pushPress = exercise('push_press', name: 'Push Press', popularity: 9);
    final curl = exercise(
      'curl',
      name: 'Biceps Curl',
      aliases: ['Pushy Curl'],
      popularity: 1,
    );
    final all = [curl, pushPress, inclinePushUp, pushUp];

    test('ranks name-prefix matches first, then by popularity', () {
      expect(ids(searchExercises(all, 'push', language: 'en')), [
        'push_up',
        'push_press',
        'curl',
        'incline_push_up',
      ]);
    });

    test('ignores case, spaces and punctuation', () {
      expect(ids(searchExercises(all, 'PUSH UP', language: 'en')), [
        'push_up',
        'incline_push_up',
      ]);
      expect(ids(searchExercises(all, 'pushup', language: 'en')), [
        'push_up',
        'incline_push_up',
      ]);
    });

    test('matches aliases, but only names count as prefix', () {
      expect(ids(searchExercises(all, 'press-up', language: 'en')), [
        'push_up',
      ]);
    });

    test('ignores diacritics in the query and in the text', () {
      final squat = exercise(
        'squat',
        name: 'Squat',
        translations: {
          'tr': const ExerciseText(
            name: 'Çömelme',
            aliases: ['Şınavsız Ağırlık'],
          ),
        },
      );
      expect(ids(searchExercises([squat], 'comelme', language: 'tr')), [
        'squat',
      ]);
      expect(ids(searchExercises([squat], 'ÇÖMELME', language: 'tr')), [
        'squat',
      ]);
      expect(
        ids(searchExercises([squat], 'sinavsiz agirlik', language: 'tr')),
        ['squat'],
      );
      expect(
        ids(
          searchExercises(
            [exercise('cafe', name: 'Café')],
            'cafe',
            language: 'en',
          ),
        ),
        ['cafe'],
      );
      // A decomposed é (e + combining acute) folds the same way.
      expect(
        ids(
          searchExercises(
            [exercise('cafe', name: 'Café')],
            'café',
            language: 'en',
          ),
        ),
        ['cafe'],
      );
    });

    test('searches the requested language, falling back to English', () {
      final squat = exercise(
        'squat',
        name: 'Squat',
        translations: {'tr': const ExerciseText(name: 'Çömelme')},
      );
      expect(searchExercises([squat], 'squat', language: 'tr'), isEmpty);
      expect(ids(searchExercises([squat], 'squat', language: 'de')), ['squat']);
    });

    test('a blank query returns the list unchanged', () {
      expect(searchExercises(all, '  ', language: 'en'), all);
      expect(searchExercises(all, '-', language: 'en'), all);
    });

    test('no match gives an empty list', () {
      expect(searchExercises(all, 'deadlift', language: 'en'), isEmpty);
    });
  });

  group('filterExercises', () {
    final bench = exercise(
      'bench',
      main: [Muscle.pec],
      secondary: [Muscle.triceps],
      equipment: [Equipment.barbell, Equipment.bench],
      equipmentAlternatives: [
        [Equipment.dumbbell, Equipment.bench],
      ],
      level: Level.intermediate,
    );
    final dip = exercise(
      'dip',
      main: [Muscle.triceps],
      secondary: [Muscle.pec],
      equipment: [Equipment.dipStation],
      level: Level.beginner,
    );
    final row = exercise(
      'row',
      main: [Muscle.lat],
      equipment: [Equipment.dumbbell],
      level: Level.beginner,
      pattern: MovementPattern.horizontalPull,
    );
    final all = [bench, dip, row];

    List<String> filter(ExerciseFilter filter) =>
        ids(filterExercises(all, filter));

    test('an empty filter keeps everything', () {
      expect(filter(const ExerciseFilter()), ['bench', 'dip', 'row']);
    });

    test('muscle matches main or secondary, or main only', () {
      expect(filter(const ExerciseFilter(muscles: {Muscle.triceps})), [
        'bench',
        'dip',
      ]);
      expect(
        filter(
          const ExerciseFilter(
            muscles: {Muscle.triceps},
            mainMusclesOnly: true,
          ),
        ),
        ['dip'],
      );
      expect(
        filter(
          const ExerciseFilter(
            muscles: {Muscle.lat, Muscle.pec},
            mainMusclesOnly: true,
          ),
        ),
        ['bench', 'row'],
      );
    });

    test('equipment matches the main set, not the alternatives', () {
      expect(filter(const ExerciseFilter(equipment: {Equipment.dumbbell})), [
        'row',
      ]);
      expect(
        filter(
          const ExerciseFilter(
            equipment: {Equipment.bench, Equipment.dipStation},
          ),
        ),
        ['bench', 'dip'],
      );
    });

    test('level and movement pattern', () {
      expect(filter(const ExerciseFilter(levels: {Level.beginner})), [
        'dip',
        'row',
      ]);
      expect(
        filter(
          const ExerciseFilter(
            movementPatterns: {MovementPattern.horizontalPull},
          ),
        ),
        ['row'],
      );
    });

    test('doable with owned equipment, alternatives included', () {
      expect(
        filter(
          const ExerciseFilter(
            doableWith: {Equipment.dumbbell, Equipment.bench},
          ),
        ),
        ['bench', 'row'],
      );
      expect(filter(const ExerciseFilter(doableWith: {})), isEmpty);
    });

    test('criteria combine', () {
      expect(
        filter(
          const ExerciseFilter(
            muscles: {Muscle.pec},
            levels: {Level.beginner},
            doableWith: {Equipment.dipStation},
          ),
        ),
        ['dip'],
      );
    });
  });

  group('sortExercises', () {
    final all = [
      exercise('b', name: 'Bench Press', popularity: 3),
      exercise('a', name: 'Ab Wheel', popularity: 9),
      exercise('e', name: 'Écarté Fly', popularity: 1),
      exercise('d', name: 'deadlift', popularity: 2),
    ];

    test('by popularity', () {
      expect(ids(sortExercises(all, ExerciseSort.popularity, language: 'en')), [
        'e',
        'd',
        'b',
        'a',
      ]);
    });

    test('alphabetically, ignoring case and diacritics', () {
      expect(
        ids(sortExercises(all, ExerciseSort.alphabetical, language: 'en')),
        ['a', 'b', 'd', 'e'],
      );
    });

    test('an empty list stays empty', () {
      expect(
        sortExercises([], ExerciseSort.alphabetical, language: 'en'),
        isEmpty,
      );
    });
  });

  group('alternativesFor', () {
    const owned = {Equipment.dumbbell, Equipment.bench};
    Exercise press(
      String id, {
      int popularity = 50,
      List<Muscle> main = const [Muscle.pec],
      List<Equipment> equipment = const [Equipment.barbell, Equipment.bench],
      List<List<Equipment>> alternatives = const [],
      MovementPattern pattern = MovementPattern.horizontalPush,
      List<String> pinned = const [],
      List<String> excluded = const [],
    }) => exercise(
      id,
      popularity: popularity,
      main: main,
      equipment: equipment,
      equipmentAlternatives: alternatives,
      pattern: pattern,
      pinned: pinned,
      excluded: excluded,
    );

    final barbell = press('barbell', popularity: 1);
    final machine = press(
      'machine',
      popularity: 2,
      equipment: [Equipment.machine],
    );
    final dumbbell = press(
      'dumbbell',
      popularity: 5,
      equipment: [Equipment.dumbbell, Equipment.bench],
    );
    final smith = press(
      'smith',
      popularity: 3,
      equipment: [Equipment.smithMachine, Equipment.bench],
      alternatives: [
        [Equipment.dumbbell, Equipment.bench],
      ],
    );
    final pushUp = press(
      'push_up',
      popularity: 9,
      main: [Muscle.pec, Muscle.triceps],
      equipment: [Equipment.bodyweight],
    );
    final dip = press(
      'dip',
      popularity: 4,
      main: [Muscle.triceps],
      equipment: [Equipment.dipStation],
    );
    final fly = press(
      'fly',
      popularity: 6,
      pattern: MovementPattern.isolation,
      equipment: [Equipment.dumbbell],
    );
    final ohp = press(
      'ohp',
      popularity: 7,
      main: [Muscle.frontDelt],
      pattern: MovementPattern.verticalPush,
    );
    final catalogue = [
      barbell,
      machine,
      dumbbell,
      smith,
      pushUp,
      dip,
      fly,
      ohp,
    ];

    test('same main muscle and pattern, doable first, then popularity', () {
      final subject = press('subject');
      expect(
        ids(alternativesFor(subject, [subject, ...catalogue], owned: owned)),
        ['smith', 'dumbbell', 'push_up', 'barbell', 'machine'],
      );
    });

    test('any shared main muscle counts', () {
      final closeGrip = press('close_grip', main: [Muscle.triceps, Muscle.pec]);
      expect(ids(alternativesFor(closeGrip, catalogue, owned: const {})), [
        'push_up',
        'barbell',
        'machine',
        'smith',
        'dip',
        'dumbbell',
      ]);
    });

    test('never lists the exercise itself', () {
      expect(
        ids(alternativesFor(barbell, catalogue, owned: const {})),
        isNot(contains('barbell')),
      );
    });

    test('pinned first in pinned order, even when they do not match', () {
      final subject = press('subject', pinned: ['ohp', 'machine', 'missing']);
      expect(ids(alternativesFor(subject, catalogue, owned: owned)), [
        'ohp',
        'machine',
        'smith',
        'dumbbell',
        'push_up',
        'barbell',
      ]);
    });

    test('excluded ones are removed, also when pinned', () {
      final subject = press(
        'subject',
        pinned: ['machine', 'ohp'],
        excluded: ['ohp', 'smith', 'push_up'],
      );
      expect(ids(alternativesFor(subject, catalogue, owned: owned)), [
        'machine',
        'dumbbell',
        'barbell',
      ]);
    });

    test('nothing matching gives an empty list', () {
      final subject = press('subject', main: [Muscle.calf]);
      expect(alternativesFor(subject, catalogue, owned: owned), isEmpty);
    });
  });

  group('variationsOf', () {
    test('the rest of the family, easier to harder', () {
      final knee = exercise('knee', family: 'push_up', familyRank: 1);
      final standard = exercise('standard', family: 'push_up', familyRank: 3);
      final incline = exercise('incline', family: 'push_up', familyRank: 2);
      final archer = exercise('archer', family: 'push_up', familyRank: 5);
      final dip = exercise('dip', family: 'dip', familyRank: 2);

      expect(
        ids(variationsOf(standard, [archer, dip, standard, knee, incline])),
        ['knee', 'incline', 'archer'],
      );
    });

    test('an exercise alone in its family has none', () {
      final dip = exercise('dip', family: 'dip');
      expect(variationsOf(dip, [dip]), isEmpty);
    });
  });

  group('exercisesWorking', () {
    final bench = exercise(
      'bench',
      popularity: 1,
      main: [Muscle.pec],
      secondary: [Muscle.triceps, Muscle.frontDelt],
    );
    final dip = exercise(
      'dip',
      popularity: 5,
      main: [Muscle.triceps, Muscle.pec],
    );
    final pushdown = exercise(
      'pushdown',
      popularity: 3,
      main: [Muscle.triceps],
    );
    final closeGrip = exercise(
      'close_grip',
      popularity: 2,
      main: [Muscle.triceps],
      secondary: [Muscle.pec],
    );
    final squat = exercise('squat', main: [Muscle.quads]);
    final catalogue = [dip, squat, pushdown, bench, closeGrip];

    test('splits main from also-works, each by popularity', () {
      final triceps = exercisesWorking(Muscle.triceps, catalogue);
      expect(ids(triceps.main), ['close_grip', 'pushdown', 'dip']);
      expect(ids(triceps.alsoWorks), ['bench']);

      final pec = exercisesWorking(Muscle.pec, catalogue);
      expect(ids(pec.main), ['bench', 'dip']);
      expect(ids(pec.alsoWorks), ['close_grip']);
    });

    test('lists an exercise once, under main, when it is both', () {
      final both = exercise(
        'both',
        main: [Muscle.pec],
        secondary: [Muscle.pec],
      );
      final pec = exercisesWorking(Muscle.pec, [both]);
      expect(ids(pec.main), ['both']);
      expect(pec.alsoWorks, isEmpty);
    });

    test('a muscle nothing works gives two empty lists', () {
      final calf = exercisesWorking(Muscle.calf, catalogue);
      expect(calf.main, isEmpty);
      expect(calf.alsoWorks, isEmpty);
    });
  });
}
