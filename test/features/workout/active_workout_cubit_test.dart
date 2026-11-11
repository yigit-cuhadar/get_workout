import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockStore extends Mock implements LocalWorkoutStore {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  const alice = AuthUser(id: 'u1', isAnonymous: true);
  const bob = AuthUser(id: 'u2', email: 'b@b.co');
  final now = DateTime(2026, 11, 11, 18);
  final end = now.add(const Duration(minutes: 45));
  final squat = move('squat', name: 'Back Squat');
  final bench = move('bench');
  final plank = move('plank', type: LoggingType.duration);
  final legs = Program(
    id: 'p1',
    name: 'Legs',
    days: [
      ProgramDay(
        items: [item('squat', sets: 2, targetKg: 100, repMin: 5), item('gone')],
      ),
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
  final saved = workout('w0', [
    exercise('squat', [lift(100, 5)]),
  ]);

  late StreamController<AuthUser?> users;
  late MockStore store;
  late MockWorkoutRepository repository;
  late MockProgramRepository programRepository;
  late MockProgramListCubit programs;
  late Map<String, StreamController<ExerciseStats?>> stats;
  late StreamController<ExerciseCatalogueState> catalogueStates;
  late ExerciseCatalogueState catalogueState;
  var clock = now;

  setUpAll(() {
    registerFallbackValue(saved);
    registerFallbackValue(<String, ExerciseStats>{});
    registerFallbackValue(active);
    registerFallbackValue(const Program(name: 'x', days: []));
    registerFallbackValue(const LocalWorkouts());
  });

  setUp(() {
    clock = now;
    users = StreamController<AuthUser?>();
    store = MockStore();
    repository = MockWorkoutRepository();
    programRepository = MockProgramRepository();
    programs = MockProgramListCubit();
    stats = {};
    catalogueStates = StreamController<ExerciseCatalogueState>.broadcast();
    catalogueState = CatalogueReady([squat, bench, plank]);
    when(() => store.load(any()))
        .thenAnswer((_) async => const Ok(LocalWorkouts()));
    when(() => store.save(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.newWorkoutId(any())).thenReturn('w1');
    when(() => repository.isStored(any(), any()))
        .thenAnswer((_) async => const Ok(true));
    when(() => repository.workoutsWith(any(), any()))
        .thenAnswer((_) async => const Ok((workouts: [], complete: true)));
    when(() => repository.saveStats(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.watchStats(any(), any())).thenAnswer(
      (call) => stats
          .putIfAbsent(
            call.positionalArguments[1] as String,
            StreamController<ExerciseStats?>.broadcast,
          )
          .stream,
    );
    when(() => repository.getStats(any(), any()))
        .thenAnswer((_) async => const Ok({}));
    when(
      () => repository.saveWorkout(
        any(),
        any(),
        any(),
        advance: any(named: 'advance'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    when(() => programs.state).thenReturn(
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: [legs],
        active: active,
      ),
    );
  });

  tearDown(() async {
    await users.close();
    await catalogueStates.close();
  });

  ActiveWorkoutCubit build() {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    final catalogue = MockCatalogueCubit();
    when(() => catalogue.state).thenAnswer((_) => catalogueState);
    when(() => catalogue.stream).thenAnswer((_) => catalogueStates.stream);
    return ActiveWorkoutCubit(
      watchAuthUser: WatchAuthUser(auth),
      loadLocal: LoadLocalWorkouts(store),
      keepLocal: KeepLocalWorkouts(store),
      newWorkoutId: NewWorkoutId(repository),
      watchStats: WatchExerciseStats(repository),
      finishWorkout: FinishWorkout(repository, clock: () => clock),
      confirmStored: ConfirmStoredWorkout(repository),
      rebuildStats: RebuildExerciseStats(repository),
      saveAsProgram: SaveWorkoutAsProgram(SaveProgram(programRepository)),
      programs: programs,
      catalogue: catalogue,
      clock: () => clock,
      retryDelay: const Duration(milliseconds: 10),
    );
  }

  /// A cubit signed in as [user] with [local] kept, settled.
  Future<ActiveWorkoutCubit> signedIn({
    AuthUser user = alice,
    Workout? draft,
    LocalWorkouts? local,
  }) async {
    when(() => store.load(user.id))
        .thenAnswer((_) async => Ok(local ?? LocalWorkouts(draft: draft)));
    final cubit = build();
    users.add(user);
    await pumpEventQueue();
    return cubit;
  }

  LocalWorkouts keptLocal() =>
      verify(() => store.save('u1', captureAny())).captured.last
          as LocalWorkouts;

  Workout? kept() => keptLocal().draft;

  group('recovery and users', () {
    test('restores the user\'s workout in progress', () async {
      final cubit = await signedIn(draft: saved);
      expect(cubit.state.status, WorkoutStatus.active);
      expect(cubit.state.workout, saved);
      await cubit.close();
    });

    test('without one there is none', () async {
      final cubit = await signedIn();
      expect(cubit.state.status, WorkoutStatus.none);
      await cubit.close();
    });

    test('another user never sees the previous one\'s workout', () async {
      final cubit = await signedIn(draft: saved);
      final load = Completer<Result<LocalWorkouts>>();
      when(() => store.load('u2')).thenAnswer((_) => load.future);
      users.add(bob);
      await pumpEventQueue();
      expect(cubit.state, const ActiveWorkoutState());
      load.complete(const Ok(LocalWorkouts()));
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutStatus.none);
      expect(cubit.state.workout, isNull);
      await cubit.close();
    });

    test('a load finishing after a user change is ignored', () async {
      final slow = Completer<Result<LocalWorkouts>>();
      when(() => store.load('u1')).thenAnswer((_) => slow.future);
      final cubit = build();
      users.add(alice);
      await pumpEventQueue();
      users.add(bob);
      await pumpEventQueue();
      slow.complete(Ok(LocalWorkouts(draft: saved)));
      await pumpEventQueue();
      expect(cubit.state.workout, isNull);
      expect(cubit.state.status, WorkoutStatus.none);
      await cubit.close();
    });

    test('unreadable kept workouts are reported, then kept anew', () async {
      when(() => store.load('u1'))
          .thenAnswer((_) async => const Err(UnknownFailure('set aside')));
      final cubit = build();
      users.add(alice);
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutStatus.none);
      expect(cubit.state.localUnreadable, isTrue);
      cubit.localUnreadableShown();
      expect(cubit.state.localUnreadable, isFalse);
      expect(cubit.startFree('Workout'), isTrue);
      await pumpEventQueue();
      expect(kept()!.name, 'Workout');
      await cubit.close();
    });

    test('signing out leaves no workout', () async {
      final cubit = await signedIn(draft: saved);
      users.add(null);
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutStatus.none);
      expect(cubit.state.workout, isNull);
      await cubit.close();
    });
  });

  group('start', () {
    test('an empty workout is kept at once', () async {
      final cubit = await signedIn();
      expect(cubit.startFree('Workout'), isTrue);
      final expected = Workout(id: 'w1', startedAt: now, name: 'Workout');
      expect(cubit.state.workout, expected);
      await pumpEventQueue();
      expect(kept(), expected);
      await cubit.close();
    });

    test('a program day takes its available exercises as goals', () async {
      final cubit = await signedIn();
      expect(
        await cubit.startProgramDay(
          legs,
          0,
          name: 'Legs · Day 1',
          language: 'en',
        ),
        (started: true, skipped: 1),
      );
      final workout = cubit.state.workout!;
      expect(workout.programId, 'p1');
      expect(workout.dayIndex, 0);
      expect(workout.exercises.single.name, 'Back Squat');
      expect(workout.exercises.single.sets, hasLength(2));
      await cubit.close();
    });

    test('only one workout at a time', () async {
      final cubit = await signedIn(draft: saved);
      expect(cubit.startFree('Workout'), isFalse);
      expect(cubit.state.workout, saved);
      await cubit.close();
    });

    test('a day without available exercises does not start', () async {
      final cubit = await signedIn();
      final gone = Program(
        id: 'p2',
        name: 'Gone',
        days: [
          ProgramDay(items: [item('gone')]),
        ],
      );
      expect(
        await cubit.startProgramDay(gone, 0, name: 'Gone', language: 'en'),
        (started: false, skipped: 0),
      );
      expect(cubit.state.status, WorkoutStatus.none);
      await cubit.close();
    });

    test('a custom exercise is waited for, not dropped', () async {
      final mine = Exercise.custom(
        id: '${Exercise.customIdPrefix}1',
        name: 'My Row',
        loggingType: LoggingType.weightReps,
        mainMuscles: const [Muscle.lat],
      );
      final day = Program(
        id: 'p3',
        name: 'Mine',
        days: [
          ProgramDay(items: [item('squat'), item(mine.id)]),
        ],
      );
      catalogueState = CatalogueReady([squat], customLoaded: false);
      final cubit = await signedIn();
      final start = cubit.startProgramDay(day, 0, name: 'Mine', language: 'en');
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutStatus.none);
      catalogueState = CatalogueReady([squat, mine]);
      catalogueStates.add(catalogueState);
      expect(await start, (started: true, skipped: 0));
      expect(cubit.state.workout!.exercises.map((e) => e.name), [
        'Back Squat',
        'My Row',
      ]);
      await cubit.close();
    });

    test('an exercise starts a workout or joins the one going', () async {
      final cubit = await signedIn();
      expect(cubit.startWith(bench, 'Workout', 'en'), isTrue);
      expect(cubit.state.workout!.exercises.single.exerciseId, 'bench');
      expect(cubit.addExercises([squat], 'en'), isTrue);
      expect(cubit.state.workout!.exercises, hasLength(2));
      await cubit.close();
    });
  });

  group('editing', () {
    const first = (exercise: 0, set: 0);

    Future<ActiveWorkoutCubit> withSquat() async {
      final cubit = await signedIn();
      await cubit.startProgramDay(legs, 0, name: 'Legs', language: 'en');
      return cubit;
    }

    test('weights are typed in the unit and kept in kg', () async {
      final cubit = await withSquat();
      cubit.setWeight(first, '225', WeightUnit.lb);
      cubit.setReps(first, '5');
      final set = cubit.state.workout!.exercises.first.sets.first;
      expect(set.weightKg, closeTo(102.06, 0.01));
      expect(set.reps, 5);
      await pumpEventQueue();
      expect(kept()!.exercises.first.sets.first, set);
      await cubit.close();
    });

    test('ticking fills empty values from last time', () async {
      final cubit = await withSquat();
      stats['squat']!.add(applyWorkout(null, saved, 'squat'));
      await pumpEventQueue();
      expect(cubit.state.suggestion(first).weightKg, 100);
      cubit.toggleDone(first);
      expect(
        cubit.state.workout!.exercises.first.sets.first,
        const WorkoutSet(weightKg: 100, reps: 5, done: true),
      );
      cubit.toggleDone(first);
      expect(cubit.state.workout!.exercises.first.sets.first.done, isFalse);
      await cubit.close();
    });

    test('a set that cannot be completed is marked, not ticked', () async {
      final cubit = await signedIn();
      cubit
        ..startFree('Workout')
        ..addExercises([bench], 'en')
        ..toggleDone(first);
      expect(cubit.state.invalidSet, first);
      expect(cubit.state.workout!.exercises.first.sets.first.done, isFalse);
      cubit.setWeight(first, '60', WeightUnit.kg);
      expect(cubit.state.invalidSet, isNull);
      await cubit.close();
    });

    test('clearing a value of a done set unticks it', () async {
      final cubit = await withSquat();
      cubit.toggleDone(first);
      expect(cubit.state.workout!.exercises.first.sets.first.done, isTrue);
      cubit.setReps(first, '');
      expect(cubit.state.workout!.exercises.first.sets.first.done, isFalse);
      await cubit.close();
    });

    test('a first-time exercise carries the weight to its next set', () async {
      final cubit = await signedIn();
      cubit
        ..startFree('Workout')
        ..addExercises([bench], 'en')
        ..addSet(0)
        ..setWeight(first, '60', WeightUnit.kg)
        ..setReps(first, '8')
        ..toggleDone(first);
      const second = (exercise: 0, set: 1);
      expect(cubit.state.suggestion(second).weightKg, 60);
      cubit.toggleDone(second);
      expect(
        cubit.state.workout!.exercises.first.sets[1],
        const WorkoutSet(weightKg: 60, reps: 8, done: true),
      );
      await cubit.close();
    });

    test('set types, drops, failure, effort and notes', () async {
      final cubit = await withSquat();
      cubit
        ..setType(first, SetType.drop)
        ..addDrop(first)
        ..setDropWeight(first, 0, '80', WeightUnit.kg)
        ..setDropReps(first, 0, '6')
        ..setToFailure(first, true)
        ..setRir(first, 1)
        ..setSetNote(first, 'Grip slipped');
      expect(
        cubit.state.workout!.exercises.first.sets.first,
        const WorkoutSet(
          type: SetType.drop,
          toFailure: true,
          rir: 1,
          note: 'Grip slipped',
          drops: [Drop(weightKg: 80, reps: 6)],
        ),
      );
      cubit.setType(first, SetType.warmup);
      expect(cubit.state.workout!.exercises.first.sets.first.drops, isEmpty);
      await cubit.close();
    });

    test('duration exercises have no drop sets', () async {
      final cubit = await signedIn();
      cubit
        ..startFree('Workout')
        ..addExercises([plank], 'en')
        ..setType(first, SetType.drop);
      expect(
        cubit.state.workout!.exercises.first.sets.first.type,
        SetType.normal,
      );
      await cubit.close();
    });

    test('sets are added and removed', () async {
      final cubit = await withSquat();
      cubit.addSet(0);
      expect(cubit.state.workout!.exercises.first.sets, hasLength(3));
      cubit.removeSet((exercise: 0, set: 1));
      expect(cubit.state.workout!.exercises.first.sets, hasLength(2));
      await cubit.close();
    });

    test('exercises are added, swapped, grouped, moved and removed', () async {
      final cubit = await withSquat();
      cubit.addExercises([bench, plank], 'en');
      List<String> ids() => [
        for (final e in cubit.state.workout!.exercises) e.exerciseId,
      ];
      expect(ids(), ['squat', 'bench', 'plank']);
      cubit.swapExercise(1, plank, 'en');
      expect(
        cubit.state.workout!.exercises[1].loggingType,
        LoggingType.duration,
      );
      cubit.swapExercise(1, bench, 'en');
      cubit.linkWithNext(0);
      expect(cubit.state.workout!.exercises.map((e) => e.group), [
        'A',
        'A',
        null,
      ]);
      cubit.moveExercise(2, 0);
      expect(ids(), ['plank', 'squat', 'bench']);
      cubit.removeExercise(1);
      expect(ids(), ['plank', 'bench']);
      expect(cubit.state.workout!.exercises.last.group, isNull);
      await cubit.close();
    });

    test('notes are kept, blank ones removed', () async {
      final cubit = await withSquat();
      cubit
        ..setNote('Good day')
        ..setExerciseNote(0, 'Belt');
      expect(cubit.state.workout!.note, 'Good day');
      expect(cubit.state.workout!.exercises.first.note, 'Belt');
      cubit.setExerciseNote(0, '  ');
      expect(cubit.state.workout!.exercises.first.note, isNull);
      await cubit.close();
    });

    test('follows the stats of exactly the workout\'s exercises', () async {
      final cubit = await withSquat();
      expect(stats.keys, ['squat']);
      expect(stats['squat']!.hasListener, isTrue);
      cubit.swapExercise(0, bench, 'en');
      await pumpEventQueue();
      expect(stats['squat']!.hasListener, isFalse);
      expect(stats['bench']!.hasListener, isTrue);
      await cubit.close();
    });
  });

  group('finish', () {
    final draft = Workout(
      id: 'w1',
      startedAt: now,
      programId: 'p1',
      dayIndex: 0,
      name: 'Legs',
      exercises: [
        exercise('squat', [lift(100, 5), const WorkoutSet()]),
      ],
    );

    test(
      'stores it with the program advance and keeps it until confirmed',
      () async {
        final confirmed = Completer<Result<bool>>();
        when(() => repository.isStored('u1', 'w1'))
            .thenAnswer((_) => confirmed.future);
        final cubit = await signedIn(draft: draft);
        clock = end;
        await cubit.finish();

        expect(cubit.state.status, WorkoutStatus.finished);
        final finished = cubit.state.workout!;
        expect(finished.finishedAt, end);
        expect(finished.exercises.single.sets, [lift(100, 5)]);
        expect(cubit.state.summary!.setCount, 1);
        final advance =
            verify(
                  () => repository.saveWorkout(
                    'u1',
                    finished,
                    any(),
                    advance: captureAny(named: 'advance'),
                  ),
                ).captured.single
                as ActiveProgram;
        expect(advance.nextDayIndex, 1);
        expect(advance.nextDate, CalendarDate(2026, 11, 16));
        await pumpEventQueue();
        // Read offline (no stats at all): squat's stats are rebuilt later.
        expect(
          keptLocal(),
          LocalWorkouts(finished: [finished], staleStats: const {'squat'}),
        );

        confirmed.complete(const Ok(true));
        await pumpEventQueue();
        expect(keptLocal(), const LocalWorkouts());
        verify(() => repository.workoutsWith('u1', 'squat')).called(1);
        verify(() => repository.saveStats('u1', 'squat', null)).called(1);

        cubit.summaryShown();
        expect(cubit.state.status, WorkoutStatus.none);
        expect(cubit.state.workout, isNull);
        await cubit.close();
      },
    );

    test(
      'programs not yet loaded leave the program, said in the summary',
      () async {
        when(() => programs.state).thenReturn(const ProgramListState());
        final cubit = await signedIn(draft: draft);
        await cubit.finish();
        expect(cubit.state.summary!.programUnknown, isTrue);
        verify(() => repository.saveWorkout('u1', any(), any(), advance: null))
            .called(1);
        await cubit.close();
      },
    );

    test('a refused workout comes back in progress', () async {
      when(() => repository.isStored('u1', 'w1'))
          .thenAnswer((_) async => const Ok(false));
      final cubit = await signedIn(draft: draft);
      await cubit.finish();
      // Its summary is open; it comes back once that is put away.
      expect(cubit.state.status, WorkoutStatus.finished);
      cubit.summaryShown();
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutStatus.active);
      expect(cubit.state.restored, 'Legs');
      final back = cubit.state.workout!;
      expect(back.id, 'w1');
      expect(back.finishedAt, isNull);
      expect(back.exercises.single.sets, [lift(100, 5)]);
      expect(keptLocal(), LocalWorkouts(draft: back));
      cubit.restoredShown();
      expect(cubit.state.restored, isNull);
      await cubit.close();
    });

    test('a refused workout kept from before comes back on launch', () async {
      final refused = workout('w0', [
        exercise('squat', [lift(100, 5)]),
      ], finishedAt: end);
      when(() => repository.isStored('u1', 'w0'))
          .thenAnswer((_) async => const Ok(false));
      final cubit = await signedIn(local: LocalWorkouts(finished: [refused]));
      expect(cubit.state.status, WorkoutStatus.active);
      expect(cubit.state.workout!.id, 'w0');
      expect(cubit.state.restored, refused.name);
      await cubit.close();
    });

    test('while one is in progress a refused one waits its turn', () async {
      final refused = workout('w0', [
        exercise('squat', [lift(100, 5)]),
      ], finishedAt: end);
      when(() => repository.isStored('u1', 'w0'))
          .thenAnswer((_) async => const Ok(false));
      final cubit = await signedIn(
        local: LocalWorkouts(draft: draft, finished: [refused]),
      );
      expect(cubit.state.workout, draft);
      await cubit.discard();
      await pumpEventQueue();
      expect(cubit.state.workout!.id, 'w0');
      await cubit.close();
    });

    test('stale stats wait while the server cannot be asked', () async {
      var answers = [const Err<bool>(NetworkFailure()), const Ok<bool>(true)];
      when(() => repository.isStored('u1', 'w0'))
          .thenAnswer((_) async => answers.removeAt(0));
      final cubit = await signedIn(
        local: LocalWorkouts(
          finished: [workout('w0', const [], finishedAt: end)],
          staleStats: const {'bench'},
        ),
      );
      verifyNever(() => repository.workoutsWith(any(), any()));
      final rebuilt = Completer<void>();
      when(() => repository.workoutsWith('u1', 'bench')).thenAnswer((_) async {
        rebuilt.complete();
        return const Ok((workouts: [], complete: true));
      });
      // After the retry delay.
      await rebuilt.future.timeout(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(keptLocal(), const LocalWorkouts());
      answers = [];
      await cubit.close();
    });

    test('a failure keeps the workout in progress', () async {
      when(() => repository.getStats(any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final cubit = await signedIn(draft: draft);
      await cubit.finish();
      expect(cubit.state.status, WorkoutStatus.active);
      expect(cubit.state.workout, draft);
      expect(cubit.state.failure, isA<NetworkFailure>());
      cubit.failureShown();
      expect(cubit.state.failure, isNull);
      await cubit.close();
    });

    test('a free workout is saved as a program', () async {
      when(() => programRepository.createProgram('u1', any()))
          .thenAnswer((_) async => const Ok('p9'));
      final cubit = await signedIn(draft: saved);
      await cubit.finish();
      await cubit.saveAsProgram('Mine');
      expect(cubit.state.savedProgramId, 'p9');
      final program =
          verify(() => programRepository.createProgram('u1', captureAny()))
                  .captured
                  .single
              as Program;
      expect(program.name, 'Mine');
      // Once is enough.
      await cubit.saveAsProgram('Again');
      verifyNever(() => programRepository.createProgram('u1', any()));
      await cubit.close();
    });
  });

  test('discarding drops the kept draft', () async {
    final cubit = await signedIn(draft: saved);
    await cubit.discard();
    await pumpEventQueue();
    expect(cubit.state.status, WorkoutStatus.none);
    expect(cubit.state.workout, isNull);
    expect(keptLocal(), const LocalWorkouts());
    await cubit.close();
  });

  group('stored workout changes', () {
    test('stats from the cache are rebuilt from the server', () async {
      final cubit = await signedIn();
      cubit.storedWorkoutChanged(
        'u1',
        'w0',
        deleted: false,
        staleStats: const {'squat'},
      );
      await pumpEventQueue();
      verify(() => repository.workoutsWith('u1', 'squat')).called(1);
      verify(() => repository.saveStats('u1', 'squat', null)).called(1);
      expect(keptLocal(), const LocalWorkouts());
      await cubit.close();
    });

    test('a deleted workout awaiting confirmation never comes back', () async {
      final finished = workout('w0', [
        exercise('squat', [lift(100, 5)]),
      ], finishedAt: end);
      final stored = Completer<Result<bool>>();
      when(() => repository.isStored('u1', 'w0'))
          .thenAnswer((_) => stored.future);
      final cubit = await signedIn(local: LocalWorkouts(finished: [finished]));
      cubit.storedWorkoutChanged(
        'u1',
        'w0',
        deleted: true,
        staleStats: const {},
      );
      expect(keptLocal().finished, isEmpty);
      // The confirmation in flight then finds it gone.
      stored.complete(const Ok(false));
      await pumpEventQueue();
      expect(cubit.state.status, WorkoutStatus.none);
      expect(cubit.state.restored, isNull);
      await cubit.close();
    });

    test('another user\'s change is ignored', () async {
      final cubit = await signedIn();
      cubit.storedWorkoutChanged(
        'u2',
        'w0',
        deleted: false,
        staleStats: const {'squat'},
      );
      await pumpEventQueue();
      verifyNever(() => repository.workoutsWith(any(), any()));
      await cubit.close();
    });
  });
}
