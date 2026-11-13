import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/programs/data/firestore_program_repository.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/workout/data/firestore_workout_repository.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_lock_screen.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockWorkoutLockScreen extends Mock implements WorkoutLockScreen {}

void main() {
  final monday = DateTime(2026, 11, 9, 18);
  final wednesday = DateTime(2026, 11, 11, 18);
  final end = DateTime(2026, 11, 11, 19);
  final legs = Program(
    id: 'p1',
    name: 'Legs',
    days: [
      ProgramDay(items: [item('squat')]),
      ProgramDay(items: [item('bench')]),
    ],
  );
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [1, 3],
    nextDayIndex: 0,
    nextDate: CalendarDate(2026, 11, 11),
    startedAt: DateTime(2026, 11, 1),
  );
  late MockWorkoutRepository repository;
  late FinishWorkout finish;

  setUpAll(() {
    registerFallbackValue(workout('x', const []));
    registerFallbackValue(<String, ExerciseStats>{});
    registerFallbackValue(const Program(name: 'x', days: []));
    registerFallbackValue(active);
  });

  setUp(() {
    repository = MockWorkoutRepository();
    finish = FinishWorkout(repository, clock: () => end);
    when(
      () => repository.saveWorkout(
        any(),
        any(),
        any(),
        advance: any(named: 'advance'),
      ),
    ).thenAnswer((_) async => const Ok(null));
  });

  final previous = workout('w0', [
    exercise('squat', [lift(100, 5)]),
  ], startedAt: monday);
  final draft = workout('w1', [
    exercise('squat', [lift(110, 5), lift(120, 1, done: false)]),
    exercise('bench', [lift(80, 5)]),
    exercise('row', [lift(70, 8)]),
  ], startedAt: wednesday);

  group('FinishWorkout', () {
    test('stores the workout with readable stats; others are stale', () async {
      final squatBefore = applyWorkout(null, previous, 'squat');
      when(() => repository.getStats('u1', ['squat', 'bench', 'row']))
          .thenAnswer(
            (_) async => Ok({
              'squat': (stats: squatBefore, current: true),
              'bench': (stats: null, current: false),
            }),
          );

      final result = await finish((uid: 'u1', workout: draft, program: null));

      final finished = result.valueOrNull!;
      expect(finished.workout.finishedAt, end);
      expect(finished.workout.exercises.first.sets, [lift(110, 5)]);
      final saved =
          verify(
                () => repository.saveWorkout(
                  'u1',
                  finished.workout,
                  captureAny(),
                  advance: null,
                ),
              ).captured.single
              as Map<String, ExerciseStats>;
      // Row's stats could not be read, so they are left alone.
      expect(saved.keys, {'squat', 'bench'});
      expect(
        saved['squat'],
        applyWorkout(squatBefore, finished.workout, 'squat'),
      );
      // Bench came from the cache, row not at all.
      expect(finished.staleStats, {'bench', 'row'});
      expect(finished.summary.records.map((r) => r.kind), [
        RecordKind.heaviestWeight,
        RecordKind.bestE1rm,
        RecordKind.bestSetVolume,
      ]);
      expect(finished.summary.setCount, 3);
      expect(finished.summary.programUnknown, isFalse);
    });

    Workout fromDay(int day) => workout(
      'w1',
      [
        exercise('squat', [lift(100, 5)]),
      ],
      startedAt: wednesday,
      programId: 'p1',
      dayIndex: day,
    );

    setUp(() {
      when(() => repository.getStats(any(), any()))
          .thenAnswer((_) async => const Ok({}));
    });

    test('moves the program on in the same batch for its next day', () async {
      final result = await finish((
        uid: 'u1',
        workout: fromDay(0),
        program: (active: active, program: legs),
      ));
      expect(result.isOk, isTrue);
      final advance =
          verify(
                () => repository.saveWorkout(
                  'u1',
                  any(),
                  any(),
                  advance: captureAny(named: 'advance'),
                ),
              ).captured.single
              as ActiveProgram;
      expect(advance.nextDayIndex, 1);
      expect(advance.nextDate, CalendarDate(2026, 11, 16));
    });

    test('another day leaves the program', () async {
      await finish((
        uid: 'u1',
        workout: fromDay(1),
        program: (active: active, program: legs),
      ));
      verify(() => repository.saveWorkout('u1', any(), any(), advance: null))
          .called(1);
    });

    test('unknown programs leave it and the summary says so', () async {
      final result = await finish((
        uid: 'u1',
        workout: fromDay(0),
        program: null,
      ));
      expect(result.valueOrNull!.summary.programUnknown, isTrue);
      verify(() => repository.saveWorkout('u1', any(), any(), advance: null))
          .called(1);
    });

    test('refuses a workout without a done set', () async {
      final result = await finish((
        uid: 'u1',
        workout: workout('w1', [
          exercise('squat', [lift(100, 5, done: false)]),
        ]),
        program: null,
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
        program: null,
      ));
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('a failed read stores nothing', () async {
      when(() => repository.getStats(any(), any()))
          .thenAnswer((_) async => const Err(UnknownFailure()));
      final result = await finish((uid: 'u1', workout: draft, program: null));
      expect(result.failureOrNull, isA<UnknownFailure>());
      verifyNever(
        () => repository.saveWorkout(
          any(),
          any(),
          any(),
          advance: any(named: 'advance'),
        ),
      );
    });
  });

  group('FinishWorkout with Firestore', () {
    test('finishing twice stores it once, with one history point', () async {
      final firestore = FakeFirebaseFirestore();
      final stored = FirestoreWorkoutRepository(
        firestore,
        waitForPendingWrites: () async {},
      );
      final twice = FinishWorkout(stored, clock: () => end);
      final day = workout(
        'w1',
        [
          exercise('squat', [lift(100, 5)]),
        ],
        startedAt: wednesday,
        programId: 'p1',
        dayIndex: 0,
      );
      await firestore.doc('users/u1').set({
        'activeProgram': FirestoreProgramRepository.activeToMap(active),
        'settings': {'weightUnit': 'kg'},
      });

      final first = await twice((
        uid: 'u1',
        workout: day,
        program: (active: active, program: legs),
      ));
      await pumpEventQueue();
      // The program has moved on, so the second finish does not move it.
      final moved = FirestoreProgramRepository.activeFromMap(
        (await firestore.doc('users/u1').get()).data()!['activeProgram'],
      )!;
      final second = await twice((
        uid: 'u1',
        workout: day,
        program: (active: moved, program: legs),
      ));
      await pumpEventQueue();

      expect(first.valueOrNull!.summary.records, isEmpty);
      expect(second.valueOrNull!.summary.records, isEmpty);
      expect(
        (await firestore.collection('users/u1/workouts').get()).docs,
        hasLength(1),
      );
      final stats = (await stored.watchStats('u1', 'squat').first)!;
      expect(stats.history, hasLength(1));
      final user = (await firestore.doc('users/u1').get()).data()!;
      expect(user['settings'], {'weightUnit': 'kg'});
      final after = FirestoreProgramRepository.activeFromMap(
        user['activeProgram'],
      )!;
      expect(after.nextDayIndex, 1);
      expect(after, moved);
    });
  });

  test('RebuildExerciseStats replaces stats from the workouts', () async {
    final workouts = [
      previous,
      workout('w1', [
        exercise('squat', [lift(110, 5)]),
      ], startedAt: wednesday),
    ];
    when(() => repository.workoutsWith('u1', 'squat'))
        .thenAnswer((_) async => Ok((workouts: workouts, complete: true)));
    when(() => repository.saveStats(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));
    final rebuild = RebuildExerciseStats(repository);

    expect((await rebuild((uid: 'u1', exerciseId: 'squat'))).isOk, isTrue);
    verify(
      () =>
          repository.saveStats('u1', 'squat', rebuildStats('squat', workouts)),
    ).called(1);

    // A partial read leaves the stats alone.
    when(() => repository.workoutsWith('u1', 'squat'))
        .thenAnswer((_) async => Ok((workouts: workouts, complete: false)));
    expect((await rebuild((uid: 'u1', exerciseId: 'squat'))).isOk, isTrue);
    verifyNever(() => repository.saveStats(any(), any(), any()));

    when(() => repository.workoutsWith('u1', 'squat'))
        .thenAnswer((_) async => const Err(NetworkFailure()));
    expect(
      (await rebuild((uid: 'u1', exerciseId: 'squat'))).failureOrNull,
      isA<NetworkFailure>(),
    );
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

  group('AddExerciseToProgram', () {
    late MockProgramRepository programs;
    late AddExerciseToProgram add;
    final types = {
      for (final id in ['squat', 'bench', 'row']) id: move(id).loggingType,
    };

    setUp(() {
      programs = MockProgramRepository();
      when(() => programs.updateProgram('u1', any()))
          .thenAnswer((_) async => const Ok(null));
      add = AddExerciseToProgram(SaveProgram(programs));
    });

    test('appends the exercise to the day with default targets', () async {
      final result = await add((
        uid: 'u1',
        program: legs,
        dayIndex: 1,
        exercise: move('row', rest: 60),
        loggingTypes: types,
      ));
      expect(result.isOk, isTrue);
      final saved =
          verify(() => programs.updateProgram('u1', captureAny()))
                  .captured
                  .single
              as Program;
      expect(saved.days[1].items.map((i) => i.exerciseId), ['bench', 'row']);
      expect(saved.days[1].items.last.restS, 60);
      expect(saved.days[0], legs.days[0]);
    });

    test('refuses a full day or an invalid program', () async {
      final full = legs.copyWith(
        days: [
          ProgramDay(
            items: List.filled(ProgramLimits.maxItemsPerDay, item('squat')),
          ),
        ],
      );
      expect(
        (await add((
          uid: 'u1',
          program: full,
          dayIndex: 0,
          exercise: move('row'),
          loggingTypes: types,
        ))).failureOrNull,
        isA<ValidationFailure>(),
      );
      // Bench is not known, so the program would not be valid.
      expect(
        (await add((
          uid: 'u1',
          program: legs,
          dayIndex: 0,
          exercise: move('row'),
          loggingTypes: {'squat': types['squat']!, 'row': types['row']!},
        ))).failureOrNull,
        isA<ValidationFailure>(),
      );
      verifyNever(() => programs.updateProgram(any(), any()));
    });
  });

  group('lock screen', () {
    late MockWorkoutLockScreen lockScreen;
    final shown = LockScreenWorkout(
      name: 'Legs',
      startedAt: wednesday,
      current: 'Squat · set 2 of 3',
    );

    setUp(() => lockScreen = MockWorkoutLockScreen());

    test('showing passes the workout and its result on', () async {
      when(() => lockScreen.show(shown))
          .thenAnswer((_) async => const Err(UnknownFailure('off')));
      final result = await ShowWorkoutOnLockScreen(lockScreen)(shown);
      expect(result.failureOrNull, isA<UnknownFailure>());
      verify(() => lockScreen.show(shown)).called(1);
    });

    test('clearing clears', () async {
      when(lockScreen.clear).thenAnswer((_) async => const Ok(null));
      final result = await ClearWorkoutFromLockScreen(lockScreen)(
        const NoParams(),
      );
      expect(result.isOk, isTrue);
      verify(lockScreen.clear).called(1);
    });

    test('taps are the lock screen\'s', () async {
      when(lockScreen.taps).thenAnswer((_) => Stream.value(null));
      expect(await WatchLockScreenTaps(lockScreen)().length, 1);
    });
  });
}
