import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

void main() {
  final monday = DateTime(2026, 11, 9, 18);
  final end = DateTime(2026, 11, 11, 19);
  late MockWorkoutRepository repository;
  late FinishWorkout finish;

  setUpAll(() {
    registerFallbackValue(workout('x', const []));
    registerFallbackValue(<String, ExerciseStats>{});
    registerFallbackValue(const Program(name: 'x', days: []));
  });

  setUp(() {
    repository = MockWorkoutRepository();
    finish = FinishWorkout(repository, clock: () => end);
    when(() => repository.saveWorkout(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));
  });

  final previous = workout('w0', [
    exercise('squat', [lift(100, 5)]),
  ], startedAt: monday);
  final draft = workout('w1', [
    exercise('squat', [lift(110, 5), lift(120, 1, done: false)]),
    exercise('bench', [lift(80, 5)]),
    exercise('row', [lift(70, 8)]),
  ]);

  test('stores the finished workout with every readable stats', () async {
    final squatBefore = applyWorkout(null, previous, 'squat');
    when(() => repository.getStats('u1', ['squat', 'bench', 'row']))
        .thenAnswer((_) async => Ok({'squat': squatBefore, 'bench': null}));

    final result = await finish((uid: 'u1', workout: draft));

    final finished = result.valueOrNull!;
    expect(finished.workout.finishedAt, end);
    expect(finished.workout.exercises.first.sets, [lift(110, 5)]);
    final saved =
        verify(
              () =>
                  repository.saveWorkout('u1', finished.workout, captureAny()),
            ).captured.single
            as Map<String, ExerciseStats>;
    // Row's stats could not be read, so they are left alone.
    expect(saved.keys, {'squat', 'bench'});
    expect(
      saved['squat'],
      applyWorkout(squatBefore, finished.workout, 'squat'),
    );
    expect(finished.summary.records, [
      const NewRecord(
        exerciseId: 'squat',
        name: 'squat',
        kind: RecordKind.heaviestWeight,
        value: 110,
      ),
      const NewRecord(
        exerciseId: 'squat',
        name: 'squat',
        kind: RecordKind.bestE1rm,
        value: 110 * (1 + 5 / 30),
      ),
      const NewRecord(
        exerciseId: 'squat',
        name: 'squat',
        kind: RecordKind.bestSetVolume,
        value: 550,
      ),
    ]);
    expect(finished.summary.setCount, 3);
    expect(finished.summary.duration, end.difference(draft.startedAt));
  });

  test('refuses a workout without a done set', () async {
    final result = await finish((
      uid: 'u1',
      workout: workout('w1', [
        exercise('squat', [lift(100, 5, done: false)]),
      ]),
    ));
    expect(result.failureOrNull, isA<ValidationFailure>());
    verifyNever(() => repository.getStats(any(), any()));
  });

  test('refuses a done set that is not valid', () async {
    final result = await finish((
      uid: 'u1',
      workout: workout('w1', [
        exercise('squat', [const WorkoutSet(reps: 5, done: true)]),
      ]),
    ));
    expect(result.failureOrNull, isA<ValidationFailure>());
  });

  test('a failed read stores nothing', () async {
    when(() => repository.getStats(any(), any()))
        .thenAnswer((_) async => const Err(UnknownFailure()));
    final result = await finish((uid: 'u1', workout: draft));
    expect(result.failureOrNull, isA<UnknownFailure>());
    verifyNever(() => repository.saveWorkout(any(), any(), any()));
  });

  test('SaveWorkoutAsProgram saves a valid one-day program', () async {
    final programs = MockProgramRepository();
    when(() => programs.createProgram('u1', any()))
        .thenAnswer((_) async => const Ok('p9'));
    final save = SaveWorkoutAsProgram(SaveProgram(programs));
    final catalogue = {'squat': move('squat'), 'bench': move('bench')};

    final result = await save((
      uid: 'u1',
      workout: draft,
      name: 'Monday',
      catalogue: catalogue,
    ));

    expect(result.valueOrNull, 'p9');
    final program =
        verify(() => programs.createProgram('u1', captureAny())).captured.single
            as Program;
    expect(program.name, 'Monday');
    expect(program.days.single.items.map((i) => i.exerciseId), [
      'squat',
      'bench',
    ]);
  });
}
