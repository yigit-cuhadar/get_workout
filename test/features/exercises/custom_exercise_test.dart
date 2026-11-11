import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_queries.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

const _valid = CustomExercise(
  name: 'Landmine Press',
  mainMuscles: [Muscle.frontDelt],
  secondaryMuscles: [Muscle.triceps],
  equipment: [Equipment.landmine, Equipment.barbell],
);

CustomExercise _with({
  String name = 'Landmine Press',
  List<Muscle> main = const [Muscle.frontDelt],
  List<Muscle> secondary = const [],
  List<Equipment> equipment = const [],
  String? note,
}) => CustomExercise(
  name: name,
  mainMuscles: main,
  secondaryMuscles: secondary,
  equipment: equipment,
  note: note,
);

void main() {
  group('validateCustomExercise', () {
    test('accepts a complete exercise and a minimal one', () {
      expect(validateCustomExercise(_valid), isEmpty);
      expect(validateCustomExercise(_with()), isEmpty);
    });

    test('needs a name of 1 to 60 characters, not counting outer spaces', () {
      expect(validateCustomExercise(_with(name: '   ')), {
        CustomExerciseIssue.nameMissing,
      });
      expect(validateCustomExercise(_with(name: ' ${'a' * 60} ')), isEmpty);
      expect(validateCustomExercise(_with(name: 'a' * 61)), {
        CustomExerciseIssue.nameTooLong,
      });
    });

    test('needs a main muscle, and no muscle twice', () {
      expect(validateCustomExercise(_with(main: [])), {
        CustomExerciseIssue.mainMusclesMissing,
      });
      expect(
        validateCustomExercise(
          _with(main: [Muscle.pec], secondary: [Muscle.pec]),
        ),
        {CustomExerciseIssue.musclesRepeated},
      );
      expect(validateCustomExercise(_with(main: [Muscle.pec, Muscle.pec])), {
        CustomExerciseIssue.musclesRepeated,
      });
    });

    test('takes bodyweight only alone, and no equipment twice', () {
      expect(
        validateCustomExercise(_with(equipment: [Equipment.bodyweight])),
        isEmpty,
      );
      expect(
        validateCustomExercise(
          _with(equipment: [Equipment.bodyweight, Equipment.box]),
        ),
        {CustomExerciseIssue.equipmentInvalid},
      );
      expect(
        validateCustomExercise(
          _with(equipment: [Equipment.box, Equipment.box]),
        ),
        {CustomExerciseIssue.equipmentInvalid},
      );
    });

    test('takes a note of up to 500 characters', () {
      expect(validateCustomExercise(_with(note: 'a' * 500)), isEmpty);
      expect(validateCustomExercise(_with(note: 'a' * 501)), {
        CustomExerciseIssue.noteTooLong,
      });
    });
  });

  test('turns into an Exercise and back without loss', () {
    const stored = CustomExercise(
      id: 'custom_a',
      name: 'Landmine Press',
      loggingType: LoggingType.weightReps,
      mainMuscles: [Muscle.frontDelt],
      secondaryMuscles: [Muscle.triceps],
      equipment: [Equipment.landmine],
      note: 'Half kneeling',
    );
    final converted = stored.toExercise();
    expect(converted.isCustom, isTrue);
    expect(converted.text('de').name, 'Landmine Press');
    expect(converted.level, isNull);
    expect(converted.popularity, isNull);
    expect(CustomExercise.of(converted), stored);
    expect(exercise('ex_bench_press').isCustom, isFalse);
  });

  group('queries', () {
    final custom = Exercise.custom(
      id: 'custom_b',
      name: 'Band Press',
      loggingType: LoggingType.reps,
      mainMuscles: const [Muscle.pec],
    );
    final early = Exercise.custom(
      id: 'custom_z',
      name: 'Arm Circles',
      loggingType: LoggingType.duration,
      mainMuscles: const [Muscle.frontDelt],
    );
    final bench = exercise('ex_bench', popularity: 1);

    test('custom exercises sort first, by name, then the catalogue', () {
      expect(ids(withCustomExercises([bench], [custom, early])), [
        'custom_z',
        'custom_b',
        'ex_bench',
      ]);
      expect(withCustomExercises([bench], const []), [bench]);
    });

    test('a custom exercise has no alternatives or variations', () {
      expect(alternativesFor(custom, [custom, early, bench], owned: {}), []);
      expect(variationsOf(custom, [custom, early, bench]), []);
      expect(alternativesFor(bench, [custom, bench], owned: {}), []);
      expect(variationsOf(bench, [custom, bench]), []);
    });
  });

  group('SaveCustomExercise', () {
    late MockCustomExerciseRepository repository;
    late SaveCustomExercise save;

    setUpAll(() => registerFallbackValue(_valid));

    setUp(() {
      repository = MockCustomExerciseRepository();
      save = SaveCustomExercise(repository);
      when(() => repository.createCustomExercise(any(), any()))
          .thenAnswer((_) async => const Ok(null));
      when(() => repository.updateCustomExercise(any(), any()))
          .thenAnswer((_) async => const Ok(null));
      when(() => repository.countCustomExercises(any()))
          .thenAnswer((_) async => const Ok(3));
    });

    test('creates a new one trimmed, with a blank note dropped', () async {
      final result = await save((
        uid: 'u1',
        exercise: _with(name: '  Landmine Press ', note: '  '),
      ));
      expect(result.isOk, isTrue);
      verify(() => repository.createCustomExercise('u1', _with(note: null)))
          .called(1);
    });

    test('updates a stored one without counting', () async {
      const stored = CustomExercise(
        id: 'custom_a',
        name: 'Press',
        mainMuscles: [Muscle.pec],
        note: ' Slow ',
      );
      await save((uid: 'u1', exercise: stored));
      verify(
        () => repository.updateCustomExercise(
          'u1',
          const CustomExercise(
            id: 'custom_a',
            name: 'Press',
            mainMuscles: [Muscle.pec],
            note: 'Slow',
          ),
        ),
      ).called(1);
      verifyNever(() => repository.countCustomExercises(any()));
    });

    test('refuses an invalid one without writing', () async {
      final result = await save((uid: 'u1', exercise: _with(main: [])));
      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyZeroInteractions(repository);
    });

    test('refuses a new one at the limit, but still edits', () async {
      when(() => repository.countCustomExercises('u1'))
          .thenAnswer((_) async => const Ok(CustomExerciseLimits.maxCount));
      final result = await save((uid: 'u1', exercise: _valid));
      expect(result.failureOrNull, CustomExerciseLimits.limitReached);
      verifyNever(() => repository.createCustomExercise(any(), any()));

      const stored = CustomExercise(
        id: 'custom_a',
        name: 'Press',
        mainMuscles: [Muscle.pec],
      );
      expect((await save((uid: 'u1', exercise: stored))).isOk, isTrue);
    });

    test('passes on a failed count', () async {
      when(() => repository.countCustomExercises('u1'))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final result = await save((uid: 'u1', exercise: _valid));
      expect(result.failureOrNull, isA<NetworkFailure>());
      verifyNever(() => repository.createCustomExercise(any(), any()));
    });
  });
}
