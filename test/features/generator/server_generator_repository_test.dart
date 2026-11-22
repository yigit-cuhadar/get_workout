import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/data/server_generator_repository.dart';
import 'package:get_workout/features/generator/domain/generator_options.dart';
import 'package:get_workout/features/generator/domain/generator_repository.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockFunctions extends Mock implements FirebaseFunctions {}

class MockCallable extends Mock implements HttpsCallable {}

class MockCallableResult extends Mock implements HttpsCallableResult<Object?> {}

class FunctionsError extends FirebaseFunctionsException {
  FunctionsError(String code, {String? reason})
    : super(
        code: code,
        message: 'error',
        details: reason == null ? null : {'reason': reason},
      );
}

/// A response as `generateProgram` gives it.
Map<String, Object?> response({List<Object?>? days}) => {
  'program': {
    'name': 'Upper/lower',
    'lengthWeeks': 8,
    'days':
        days ??
        [
          {
            'name': 'Upper A',
            'items': [
              {
                'exerciseId': 'bench',
                'sets': 3,
                'repMin': 6,
                'repMax': 10,
                'restS': 120,
              },
              {
                'exerciseId': 'plank',
                'sets': 2,
                'durationS': 40,
                'restS': 60,
                'group': 'A',
              },
            ],
          },
        ],
  },
  'split': 'upper_lower',
  'template': 'ul_4',
  'weeklySets': {'pec': 3},
  'targeted': ['pec', 'calf'],
  'uncovered': ['calf'],
  'rulesVersion': 2,
};

void main() {
  late MockFunctions functions;
  late MockCallable callable;
  late FakeFirebaseFirestore firestore;
  late ServerGeneratorRepository repository;

  GenerationRequest request({
    int seed = 0,
    List<List<ProgramItem>> kept = const [],
    String? split,
  }) =>
      (answers: answers(split: split), seed: seed, kept: kept, language: 'en');

  setUp(() {
    functions = MockFunctions();
    callable = MockCallable();
    firestore = FakeFirebaseFirestore();
    repository = ServerGeneratorRepository(functions, firestore);
    when(() => functions.httpsCallable('generateProgram')).thenReturn(callable);
  });

  void answer(Object? data) {
    final result = MockCallableResult();
    when(() => result.data).thenReturn(data);
    when(() => callable.call<Object?>(any())).thenAnswer((_) async => result);
  }

  void refuse(FirebaseFunctionsException error) =>
      when(() => callable.call<Object?>(any())).thenThrow(error);

  group('the request', () {
    test('holds the answers as codes, the seed and the language', () {
      final data = ServerGeneratorRepository.requestData((
        answers: answers(
          days: 4,
          minutes: 45,
          equipment: {Equipment.dumbbell, Equipment.barbell},
          focus: {FocusArea.legs, FocusArea.chest},
          skip: {FocusArea.arms},
          sensitive: {SensitiveArea.lowerBack},
          style: EquipmentStyle.freeWeights,
          split: 'upper_lower',
        ),
        seed: 3,
        kept: const [],
        language: 'tr',
      ));
      expect(data, {
        'answers': {
          'goal': 'build_muscle',
          'level': 'intermediate',
          'daysPerWeek': 4,
          'sessionMinutes': 45,
          'equipment': ['barbell', 'dumbbell'],
          'focus': ['chest', 'legs'],
          'skip': ['arms'],
          'sensitive': ['lower_back'],
          'equipmentStyle': 'free_weights',
          'split': 'upper_lower',
        },
        'seed': 3,
        'lang': 'tr',
      });
    });

    test('leaves out the split when the app chooses, and no kept items', () {
      final data = ServerGeneratorRepository.requestData(
        request(kept: const [[], []]),
      );
      expect(data['answers'], isNot(contains('split')));
      expect(data, isNot(contains('kept')));
    });

    test('sends kept items per day with only the fields the server takes', () {
      final data = ServerGeneratorRepository.requestData(
        request(
          kept: [
            [],
            [
              const ProgramItem(
                exerciseId: 'row',
                sets: 4,
                repMin: 8,
                repMax: 10,
                restS: 90,
                targetKg: 60,
                group: 'A',
              ),
              const ProgramItem(
                exerciseId: 'plank',
                sets: 3,
                durationS: 45,
                restS: 60,
              ),
            ],
          ],
        ),
      );
      expect(data['kept'], [
        [],
        [
          {
            'exerciseId': 'row',
            'sets': 4,
            'restS': 90,
            'repMin': 8,
            'repMax': 10,
          },
          {'exerciseId': 'plank', 'sets': 3, 'restS': 60, 'durationS': 45},
        ],
      ]);
    });

    test('is what the callable is called with', () async {
      answer(response());
      await repository.generate(request(seed: 1));
      verify(
        () => callable.call<Object?>({
          'answers': {
            'goal': 'build_muscle',
            'level': 'intermediate',
            'daysPerWeek': 3,
            'sessionMinutes': 60,
            'equipment': [
              for (final item in Equipment.values)
                if (item != Equipment.bodyweight) item.code,
            ],
            'focus': <String>[],
            'skip': <String>[],
            'sensitive': <String>[],
            'equipmentStyle': 'any',
          },
          'seed': 1,
          'lang': 'en',
        }),
      ).called(1);
    });

    test('leaves out kept items the server would refuse', () {
      const good = ProgramItem(
        exerciseId: 'row',
        sets: 3,
        repMin: 8,
        repMax: 10,
        restS: 90,
      );
      final data = ServerGeneratorRepository.requestData(
        request(
          kept: [
            [
              good,
              good.copyWith(exerciseId: 'a', sets: 0),
              good.copyWith(exerciseId: 'b', sets: 11),
              good.copyWith(exerciseId: 'c', repMin: () => null),
              good.copyWith(exerciseId: 'd', repMin: () => 12),
              good.copyWith(exerciseId: 'e', repMax: () => 101),
              good.copyWith(exerciseId: 'f', restS: 601),
              good.copyWith(exerciseId: 'g', durationS: () => 30),
              const ProgramItem(
                exerciseId: 'h',
                sets: 3,
                durationS: 4,
                restS: 60,
              ),
            ],
          ],
        ),
      );
      expect(data['kept'], [
        [
          {
            'exerciseId': 'row',
            'sets': 3,
            'restS': 90,
            'repMin': 8,
            'repMax': 10,
          },
        ],
      ]);
      final none = ServerGeneratorRepository.requestData(
        request(
          kept: [
            [good.copyWith(sets: 0)],
          ],
        ),
      );
      expect(none, isNot(contains('kept')));
    });
  });

  group('the response', () {
    test('becomes the program, its days and the uncovered muscles', () async {
      answer(response());
      final program = (await repository.generate(request())).valueOrNull!;
      expect(program.splitName, 'Upper/lower');
      expect(program.lengthWeeks, 8);
      expect(program.targeted, {Muscle.pec, Muscle.calf});
      expect(program.uncovered, {Muscle.calf});
      expect(program.days.single.name, 'Upper A');
      expect(program.days.single.items, const [
        ProgramItem(
          exerciseId: 'bench',
          sets: 3,
          repMin: 6,
          repMax: 10,
          restS: 120,
        ),
        ProgramItem(
          exerciseId: 'plank',
          sets: 2,
          durationS: 40,
          restS: 60,
          group: 'A',
        ),
      ]);
    });

    test('takes whole numbers that arrive as doubles', () async {
      answer({
        ...response(),
        'program': {
          'name': 'Full body',
          'lengthWeeks': 6.0,
          'days': [
            {
              'name': 'Full body A',
              'items': [
                {
                  'exerciseId': 'squat',
                  'sets': 3.0,
                  'repMin': 5,
                  'repMax': 8,
                  'restS': 150.0,
                },
              ],
            },
          ],
        },
      });
      final program = (await repository.generate(request())).valueOrNull!;
      expect(program.lengthWeeks, 6);
      expect(program.days.single.items.single.sets, 3);
    });

    for (final (name, data) in [
      ('not an object', 'program'),
      ('no program', {'uncovered': <Object?>[]}),
      ('no days', response(days: [])),
      (
        'an item without sets',
        response(
          days: [
            {
              'name': 'A',
              'items': [
                {'exerciseId': 'x', 'restS': 60},
              ],
            },
          ],
        ),
      ),
      (
        'a fractional number',
        response(
          days: [
            {
              'name': 'A',
              'items': [
                {'exerciseId': 'x', 'sets': 2.5, 'restS': 60},
              ],
            },
          ],
        ),
      ),
      (
        'an item with a duration and reps',
        response(
          days: [
            {
              'name': 'A',
              'items': [
                {
                  'exerciseId': 'x',
                  'sets': 2,
                  'durationS': 30,
                  'repMin': 8,
                  'repMax': 10,
                  'restS': 60,
                },
              ],
            },
          ],
        ),
      ),
      (
        'an item with neither a duration nor reps',
        response(
          days: [
            {
              'name': 'A',
              'items': [
                {'exerciseId': 'x', 'sets': 2, 'restS': 60},
              ],
            },
          ],
        ),
      ),
      (
        'an item with half a rep range',
        response(
          days: [
            {
              'name': 'A',
              'items': [
                {'exerciseId': 'x', 'sets': 2, 'repMin': 8, 'restS': 60},
              ],
            },
          ],
        ),
      ),
      ('no targeted muscles', {...response()}..remove('targeted')),
      (
        'an unknown muscle',
        {
          ...response(),
          'uncovered': ['wings'],
        },
      ),
    ]) {
      test('fails when malformed: $name', () async {
        answer(data);
        expect(
          (await repository.generate(request())).failureOrNull,
          isA<UnknownFailure>(),
        );
      });
    }
  });

  group('a refusal', () {
    for (final (code, reason, refusal) in [
      ('permission-denied', 'not-premium', GenerationRefusal.notPremium),
      ('invalid-argument', 'invalid-input', GenerationRefusal.invalidInput),
      ('failed-precondition', 'no-rules', GenerationRefusal.noRules),
      ('failed-precondition', 'no-template', GenerationRefusal.noTemplate),
      ('failed-precondition', 'no-exercises', GenerationRefusal.noExercises),
    ]) {
      test('$code with $reason is typed', () async {
        refuse(FunctionsError(code, reason: reason));
        expect(
          (await repository.generate(request())).failureOrNull,
          isA<GenerationRefused>().having((f) => f.refusal, 'refusal', refusal),
        );
      });
    }

    for (final (code, failure) in [
      // The iOS SDK reports no connection as `unknown`.
      ('unknown', isA<NetworkFailure>()),
      ('unavailable', isA<NetworkFailure>()),
      ('deadline-exceeded', isA<NetworkFailure>()),
      ('unauthenticated', isA<PermissionFailure>()),
      ('internal', isA<UnknownFailure>()),
    ]) {
      test('$code without a reason is mapped', () async {
        refuse(FunctionsError(code));
        expect((await repository.generate(request())).failureOrNull, failure);
      });
    }
  });

  group('the options', () {
    Map<String, Object?> stored() => {
      'version': 3,
      'splits': [
        {
          'id': 'full_body',
          'l10n': {
            'en': {'name': 'Full body', 'info': 'Every muscle each day'},
            'tr': {'name': 'Tüm vücut', 'info': 'Her gün tüm kaslar'},
          },
          'fits': [
            {
              'days': 3,
              'levels': ['beginner', 'intermediate'],
            },
            {
              'days': 2,
              'levels': ['advanced'],
              'goals': ['lose_fat'],
            },
          ],
          'future': true,
        },
        // Unreadable ones are left out.
        {'id': 'no_text', 'fits': <Object?>[]},
        'nonsense',
      ],
      'sessionMinutes': [30, 45, 60],
      'maxFocusAreas': 2,
      'maxSkipAreas': 3,
      'focusAreas': {
        'chest': ['pec', 'wings'],
        'legs': ['quads', 'glute'],
        'tail': ['calf'],
      },
      'newField': 'ignored',
    };

    test('are read leniently', () async {
      await firestore.doc('generator/options').set(stored());
      expect(
        await repository.watchOptions().first,
        const GeneratorOptions(
          splits: [
            GeneratorSplit(
              id: 'full_body',
              l10n: {
                'en': (name: 'Full body', info: 'Every muscle each day'),
                'tr': (name: 'Tüm vücut', info: 'Her gün tüm kaslar'),
              },
              fits: [
                SplitFit(days: 3, levels: {Level.beginner, Level.intermediate}),
                SplitFit(
                  days: 2,
                  levels: {Level.advanced},
                  goals: {Goal.loseFat},
                ),
              ],
            ),
          ],
          sessionMinutes: [30, 45, 60],
          maxFocusAreas: 2,
          maxSkipAreas: 3,
          focusAreas: {
            FocusArea.chest: {Muscle.pec},
            FocusArea.legs: {Muscle.quads, Muscle.glute},
          },
        ),
      );
    });

    test('missing are a not-found failure', () async {
      await expectLater(
        repository.watchOptions().first,
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('without session lengths are a failure', () async {
      await firestore.doc('generator/options').set({
        ...stored(),
        'sessionMinutes': <Object?>[],
      });
      await expectLater(
        repository.watchOptions().first,
        throwsA(isA<UnknownFailure>()),
      );
    });
  });
}
