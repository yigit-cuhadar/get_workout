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
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/effort.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/rest.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/features/workout/presentation/workout_editor.dart';
import 'package:mocktail/mocktail.dart';

import '../../fake_time.dart';
import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockStore extends Mock implements LocalWorkoutStore {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

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
  const userSettings = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
    restTimer: RestTimerSettings(defaultS: 75),
    autoWarmups: false,
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
  late StreamController<UserSettings> settings;
  var clock = now;
  const retryDelay = Duration(milliseconds: 10);

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
    settings = StreamController<UserSettings>.broadcast();
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
    await settings.close();
  });

  ActiveWorkoutCubit build() {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    final catalogue = MockCatalogueCubit();
    when(() => catalogue.state).thenAnswer((_) => catalogueState);
    when(() => catalogue.stream).thenAnswer((_) => catalogueStates.stream);
    final settingsRepository = MockSettingsRepository();
    when(() => settingsRepository.watchSettings(any()))
        .thenAnswer((_) => settings.stream);
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
      watchSettings: WatchSettings(settingsRepository),
      clock: () => clock,
      retryDelay: retryDelay,
    );
  }

  /// A cubit signed in as [user] with [local] kept, settled.
  /// Without [warmups], settings arrive as the defaults but with no
  /// automatic warm-ups, so sets stay where the tests put them.
  Future<ActiveWorkoutCubit> signedIn({
    AuthUser user = alice,
    Workout? draft,
    LocalWorkouts? local,
    bool warmups = false,
    WeightUnit unit = WeightUnit.kg,
  }) async {
    when(() => store.load(user.id))
        .thenAnswer((_) async => Ok(local ?? LocalWorkouts(draft: draft)));
    final cubit = build();
    users.add(user);
    await pumpEventQueue();
    settings.add(
      UserSettings(
        weightUnit: unit,
        lengthUnit: LengthUnit.cm,
        autoWarmups: warmups,
      ),
    );
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
      expect(cubit.startWith(squat, 'Workout', 'en'), isTrue);
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

    test('a user let go of keeps nothing more, until resumed', () async {
      final cubit = await signedIn(draft: saved);
      await cubit.releaseUser('u1');
      expect(cubit.state.status, WorkoutStatus.none);
      // No user is followed, so nothing can start or be kept.
      expect(cubit.startFree('Workout'), isFalse);
      await pumpEventQueue();
      verifyNever(() => store.save('u1', any()));

      await cubit.resumeUser();
      expect(cubit.state.workout, saved);
      await cubit.close();
    });

    test(
      'letting go of another user than the one followed does nothing',
      () async {
        final cubit = await signedIn(draft: saved);
        await cubit.releaseUser('u2');
        expect(cubit.state.workout, saved);
        await cubit.close();
      },
    );
  });

  group('start', () {
    test('a free workout is in progress only while it has exercises', () async {
      final cubit = await signedIn();
      expect(cubit.startFree('Workout'), isTrue);
      final empty = Workout(id: 'w1', startedAt: now, name: 'Workout');
      expect(cubit.state.status, WorkoutStatus.active);
      expect(cubit.state.workout, empty);
      expect(cubit.state.inProgress, isFalse);
      await pumpEventQueue();
      expect(kept(), isNull);

      cubit.addExercises([squat], 'en');
      expect(cubit.state.inProgress, isTrue);
      await pumpEventQueue();
      expect(kept()!.exerciseIds, ['squat']);

      // Empty again: no exercise, so nothing logged either.
      cubit.removeExercise(0);
      expect(cubit.state.inProgress, isFalse);
      await pumpEventQueue();
      expect(kept(), isNull);
      await cubit.close();
    });

    test('a program day is in progress at once', () async {
      final cubit = await signedIn();
      await cubit.startProgramDay(legs, 0, name: 'Legs', language: 'en');
      expect(cubit.state.inProgress, isTrue);
      await pumpEventQueue();
      expect(kept()!.exerciseIds, ['squat']);
      await cubit.close();
    });

    test('leaving an empty workout ends it, never kept or stored', () async {
      final cubit = await signedIn();
      cubit.startFree('Workout');
      await cubit.leave();
      expect(cubit.state.status, WorkoutStatus.none);
      expect(cubit.state.workout, isNull);
      await pumpEventQueue();
      for (final local in verify(
        () => store.save('u1', captureAny()),
      ).captured.cast<LocalWorkouts>()) {
        expect(local.draft, isNull);
      }
      verifyNever(
        () => repository.saveWorkout(
          any(),
          any(),
          any(),
          advance: any(named: 'advance'),
        ),
      );
      await cubit.close();
    });

    test('leaving a workout in progress keeps it', () async {
      final cubit = await signedIn(draft: saved);
      await cubit.leave();
      expect(cubit.state.status, WorkoutStatus.active);
      expect(cubit.state.workout, saved);
      await cubit.close();
    });

    test('an empty workout never blocks starting another', () async {
      final cubit = await signedIn();
      when(() => repository.newWorkoutId(any())).thenReturn('w2');
      cubit.startFree('Workout');
      when(() => repository.newWorkoutId(any())).thenReturn('w3');
      expect(
        await cubit.startProgramDay(legs, 0, name: 'Legs', language: 'en'),
        (started: true, skipped: 1),
      );
      expect(cubit.state.workout!.id, 'w3');
      expect(cubit.state.inProgress, isTrue);
      await cubit.close();
    });

    test('an empty workout kept by an older version is none', () async {
      final cubit = await signedIn(
        draft: Workout(id: 'w0', startedAt: now, name: 'Workout'),
      );
      expect(cubit.state.status, WorkoutStatus.none);
      expect(cubit.state.workout, isNull);
      expect(cubit.startFree('Workout'), isTrue);
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

    group('a premium copy', () {
      final paid = Program(
        id: 'p9',
        name: 'Paid',
        premium: true,
        days: [
          ProgramDay(items: [item('squat')]),
        ],
      );

      ProgramListState listWith(bool? premium) => ProgramListState(
        status: ProgramListStatus.ready,
        programs: [paid],
        premium: premium,
      );

      Future<WorkoutStart> start(ActiveWorkoutCubit cubit) =>
          cubit.startProgramDay(paid, 0, name: 'Paid', language: 'en');

      test('starts with premium', () async {
        when(() => programs.state).thenReturn(listWith(true));
        final cubit = await signedIn();
        expect(cubit.access(paid), ProgramAccess.open);
        expect((await start(cubit)).started, isTrue);
        await cubit.close();
      });

      test('does not start without premium', () async {
        when(() => programs.state).thenReturn(listWith(false));
        when(() => programs.stream).thenAnswer((_) => const Stream.empty());
        final cubit = await signedIn();
        expect(cubit.access(paid), ProgramAccess.locked);
        expect(await start(cubit), (started: false, skipped: 0));
        expect(cubit.state.workout, isNull);
        await cubit.close();
      });

      test('waits for premium, e.g. right after the paywall', () async {
        final lists = StreamController<ProgramListState>.broadcast();
        addTearDown(lists.close);
        when(() => programs.state).thenReturn(listWith(null));
        when(() => programs.stream).thenAnswer((_) => lists.stream);
        final cubit = await signedIn();
        expect(cubit.access(paid), ProgramAccess.waiting);

        final starting = start(cubit);
        await pumpEventQueue();
        expect(cubit.state.workout, isNull);
        when(() => programs.state).thenReturn(listWith(true));
        lists.add(listWith(true));

        expect((await starting).started, isTrue);
        await cubit.close();
      });

      test('an own program is never gated', () async {
        when(() => programs.state).thenReturn(listWith(false));
        final cubit = await signedIn();
        expect(cubit.access(legs), ProgramAccess.open);
        expect(
          (await cubit.startProgramDay(
            legs,
            1,
            name: 'Legs',
            language: 'en',
          )).started,
          isTrue,
        );
        await cubit.close();
      });

      test('one in progress can still be finished without premium', () async {
        when(() => programs.state).thenReturn(listWith(false));
        final cubit = await signedIn(
          draft: Workout(
            id: 'w1',
            startedAt: now,
            programId: 'p9',
            dayIndex: 0,
            name: 'Paid',
            exercises: [
              exercise('squat', [lift(100, 5)]),
            ],
          ),
        );
        await cubit.finish();
        verify(
          () => repository.saveWorkout(
            'u1',
            any(),
            any(),
            advance: any(named: 'advance'),
          ),
        ).called(1);
        await cubit.close();
      });
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

  group('automatic warm-ups', () {
    Future<ActiveWorkoutCubit> warmedSquat({
      WeightUnit unit = WeightUnit.kg,
    }) async {
      final cubit = await signedIn(warmups: true, unit: unit);
      await cubit.startProgramDay(legs, 0, name: 'Legs', language: 'en');
      return cubit;
    }

    List<SetType> types(ActiveWorkoutCubit cubit, int exercise) => [
      for (final s in cubit.state.workout!.exercises[exercise].sets) s.type,
    ];

    test('a program day starts with two before the working sets', () async {
      final cubit = await warmedSquat();
      expect(types(cubit, 0), [
        SetType.warmup,
        SetType.warmup,
        SetType.normal,
        SetType.normal,
      ]);
      expect(cubit.state.selection, (exercise: 0, set: 0));
      await cubit.close();
    });

    test('they suggest a ramp to the first working set', () async {
      final cubit = await warmedSquat();
      // The goal's 100 kg.
      expect(cubit.state.suggestion((exercise: 0, set: 0)), (
        weightKg: 50.0,
        reps: 8,
        durationS: null,
      ));
      expect(cubit.state.suggestion((exercise: 0, set: 1)).weightKg, 75);
      // Typing the working weight moves them; ticking stores them.
      cubit.setWeight((exercise: 0, set: 2), '120', WeightUnit.kg);
      expect(cubit.state.suggestion((exercise: 0, set: 1)).weightKg, 90);
      cubit.toggleDone((exercise: 0, set: 0));
      final done = cubit.state.workout!.exercises[0].sets[0];
      expect((done.weightKg, done.reps, done.done), (60, 8, true));
      await cubit.close();
    });

    test('in pounds they round to 5 lb', () async {
      final cubit = await warmedSquat(unit: WeightUnit.lb);
      cubit.setWeight((exercise: 0, set: 2), '225', WeightUnit.lb);
      final kg = cubit.state.suggestion((exercise: 0, set: 0)).weightKg!;
      expect(WeightUnit.lb.fromKg(kg), closeTo(115, 1e-9));
      await cubit.close();
    });

    test('exercises added or swapped in get them, timed ones not', () async {
      final cubit = await warmedSquat();
      cubit.addExercises([bench, plank], 'en');
      expect(types(cubit, 1), [SetType.warmup, SetType.warmup, SetType.normal]);
      expect(types(cubit, 2), [SetType.normal]);
      cubit
        ..selectSet((exercise: 2, set: 0))
        ..swapExercise(2, bench, 'en');
      expect(types(cubit, 2), [SetType.warmup, SetType.warmup, SetType.normal]);
      expect(cubit.state.selection, (exercise: 2, set: 0));
      await cubit.close();
    });

    test('none for an exercise swapped after a done set', () async {
      final cubit = await signedIn(warmups: true);
      cubit
        ..startFree('Workout')
        ..addExercises([plank], 'en')
        ..setDuration((exercise: 0, set: 0), '30')
        ..toggleDone((exercise: 0, set: 0))
        ..swapExercise(0, bench, 'en');
      expect(types(cubit, 0), [SetType.normal]);
      await cubit.close();
    });

    test('an empty workout started with an exercise gets them', () async {
      final cubit = await signedIn(warmups: true);
      cubit.startWith(bench, 'Workout', 'en');
      expect(types(cubit, 0), [SetType.warmup, SetType.warmup, SetType.normal]);
      await cubit.close();
    });

    test('turned off, none are added', () async {
      final cubit = await signedIn();
      await cubit.startProgramDay(legs, 0, name: 'Legs', language: 'en');
      cubit.addExercises([bench], 'en');
      expect(types(cubit, 0), [SetType.normal, SetType.normal]);
      expect(types(cubit, 1), [SetType.normal]);
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
        ..addSet(0, SetType.normal)
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
        ..setEffort(first, EffortStep.failure)
        ..setSetNote(first, 'Grip slipped');
      expect(
        cubit.state.workout!.exercises.first.sets.first,
        const WorkoutSet(
          type: SetType.drop,
          toFailure: true,
          rir: 0,
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
      cubit.addSet(0, SetType.normal);
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

  group('selection', () {
    Future<ActiveWorkoutCubit> withSquat() async {
      final cubit = await signedIn();
      await cubit.startProgramDay(legs, 0, name: 'Legs', language: 'en');
      return cubit;
    }

    test('starts on the next set to do, a tick moves it on', () async {
      final cubit = await withSquat();
      cubit.addExercises([bench], 'en');
      expect(cubit.state.selection, (exercise: 0, set: 0));
      cubit.toggleDone((exercise: 0, set: 0));
      expect(cubit.state.selection, (exercise: 0, set: 1));
      // The exercise's last set opens the next one.
      cubit.toggleDone((exercise: 0, set: 1));
      expect(cubit.state.selection, (exercise: 1, set: 0));
      // Unticking keeps the set selected.
      cubit
        ..selectSet((exercise: 0, set: 1))
        ..toggleDone((exercise: 0, set: 1));
      expect(cubit.state.selection, (exercise: 0, set: 1));
      await cubit.close();
    });

    test('a set that cannot be ticked stays selected', () async {
      final cubit = await signedIn();
      cubit
        ..startFree('Workout')
        ..addExercises([bench], 'en')
        ..toggleDone((exercise: 0, set: 0));
      expect(cubit.state.invalidSet, (exercise: 0, set: 0));
      expect(cubit.state.selection, (exercise: 0, set: 0));
      await cubit.close();
    });

    test('a superset moves round by round', () async {
      final cubit = await withSquat();
      cubit
        ..addExercises([bench], 'en')
        ..linkWithNext(0)
        ..setWeight((exercise: 1, set: 0), '60', WeightUnit.kg)
        ..setReps((exercise: 1, set: 0), '8')
        ..addSet(1, SetType.normal)
        ..toggleDone((exercise: 0, set: 0));
      expect(cubit.state.selection, (exercise: 1, set: 0));
      cubit.toggleDone((exercise: 1, set: 0));
      expect(cubit.state.selection, (exercise: 0, set: 1));
      await cubit.close();
    });

    test(
      'an added set is selected; a warm-up goes before working sets',
      () async {
        final cubit = await withSquat();
        cubit.addSet(0, SetType.drop);
        expect(cubit.state.workout!.exercises[0].sets[2].type, SetType.drop);
        expect(cubit.state.selection, (exercise: 0, set: 2));
        cubit.addSet(0, SetType.warmup);
        expect(cubit.state.workout!.exercises[0].sets.map((s) => s.type), [
          SetType.warmup,
          SetType.normal,
          SetType.normal,
          SetType.drop,
        ]);
        expect(cubit.state.selection, (exercise: 0, set: 0));
        cubit.addSet(0, SetType.warmup);
        expect(cubit.state.workout!.exercises[0].sets[1].type, SetType.warmup);
        expect(cubit.state.selection, (exercise: 0, set: 1));
        await cubit.close();
      },
    );

    test('duration exercises get a normal set for a drop set', () async {
      final cubit = await signedIn();
      cubit
        ..startFree('Workout')
        ..addExercises([plank], 'en')
        ..addSet(0, SetType.drop);
      expect(cubit.state.workout!.exercises[0].sets.map((s) => s.type), [
        SetType.normal,
        SetType.normal,
      ]);
      await cubit.close();
    });

    test('removing sets and exercises, and moving, keep it in place', () async {
      final cubit = await withSquat();
      cubit
        ..addExercises([bench, plank], 'en')
        ..openExercise(2);
      expect(cubit.state.selection, (exercise: 2, set: 0));
      cubit.moveExercise(2, 0);
      expect(cubit.state.selection, (exercise: 0, set: 0));
      cubit.removeExercise(1);
      expect(cubit.state.selection, (exercise: 0, set: 0));
      cubit
        ..addSet(1, SetType.normal)
        ..selectSet((exercise: 1, set: 1))
        ..removeSet((exercise: 1, set: 0));
      expect(cubit.state.selection, (exercise: 1, set: 0));
      // Its own exercise removed: the next set to do.
      cubit.removeExercise(1);
      expect(cubit.state.selection, (exercise: 0, set: 0));
      await cubit.close();
    });

    test('a set made a warm-up moves before the working sets', () async {
      final cubit = await withSquat();
      List<SetType> types() => [
        for (final s in cubit.state.workout!.exercises[0].sets) s.type,
      ];
      cubit
        ..addSet(0, SetType.drop)
        ..selectSet((exercise: 0, set: 2))
        ..addDrop((exercise: 0, set: 2))
        ..setType((exercise: 0, set: 2), SetType.warmup);
      expect(types(), [SetType.warmup, SetType.normal, SetType.normal]);
      expect(cubit.state.workout!.exercises[0].sets[0].drops, isEmpty);
      expect(cubit.state.selection, (exercise: 0, set: 0));
      // Another set picked: it moves along as the warm-up passes it.
      cubit
        ..selectSet((exercise: 0, set: 1))
        ..setType((exercise: 0, set: 2), SetType.warmup);
      expect(types(), [SetType.warmup, SetType.warmup, SetType.normal]);
      expect(cubit.state.selection, (exercise: 0, set: 2));
      // A warm-up made a working set becomes the first of them.
      cubit.setType((exercise: 0, set: 0), SetType.normal);
      expect(types(), [SetType.warmup, SetType.normal, SetType.normal]);
      expect(cubit.state.selection, (exercise: 0, set: 2));
      // Normal and drop sets stay in place.
      cubit.setType((exercise: 0, set: 1), SetType.drop);
      expect(types(), [SetType.warmup, SetType.drop, SetType.normal]);
      await cubit.close();
    });

    test('a card moves whole and the selection follows it', () async {
      final cubit = await withSquat();
      cubit
        ..addExercises([bench, plank], 'en')
        ..linkWithNext(0)
        ..selectSet((exercise: 1, set: 0));
      List<String> ids() => [
        for (final e in cubit.state.workout!.exercises) e.exerciseId,
      ];
      // Blocks: [squat, bench] as a superset, then plank.
      cubit.moveBlock(0, 1);
      expect(ids(), ['plank', 'squat', 'bench']);
      expect(cubit.state.workout!.exercises.map((e) => e.group), [
        null,
        'A',
        'A',
      ]);
      expect(cubit.state.selection, (exercise: 2, set: 0));
      cubit.moveBlock(1, 0);
      expect(ids(), ['squat', 'bench', 'plank']);
      expect(cubit.state.selection, (exercise: 1, set: 0));
      cubit.moveBlock(0, 2);
      expect(ids(), ['squat', 'bench', 'plank']);
      await cubit.close();
    });

    test('opening an exercise selects its first set to do', () async {
      final cubit = await withSquat();
      cubit
        ..addExercises([bench], 'en')
        ..openExercise(1);
      expect(cubit.state.selection, (exercise: 1, set: 0));
      cubit.openExercise(0);
      expect(cubit.state.selection, (exercise: 0, set: 0));
      await cubit.close();
    });

    test('skipping the rest keeps the selection', () async {
      final cubit = await withSquat();
      cubit.toggleDone((exercise: 0, set: 0));
      final selected = cubit.state.selection;
      cubit.skipRest();
      expect(cubit.state.selection, selected);
      await cubit.close();
    });

    test('effort is stored as reps in reserve, failure as before', () async {
      final cubit = await withSquat();
      const first = (exercise: 0, set: 0);
      cubit.setEffort(first, const EffortStep.reserve(2));
      expect(cubit.state.workout!.exercises[0].sets[0].rir, 2);
      cubit.setEffort(first, EffortStep.failure);
      final set = cubit.state.workout!.exercises[0].sets[0];
      expect((set.rir, set.toFailure), (0, true));
      cubit.setEffort(first, null);
      final cleared = cubit.state.workout!.exercises[0].sets[0];
      expect((cleared.rir, cleared.toFailure), (null, false));
      await cubit.close();
    });

    test('the next workout starts with nothing picked', () async {
      final cubit = await withSquat();
      cubit.selectSet((exercise: 0, set: 1));
      await cubit.discard();
      expect(cubit.state.picked, isNull);
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

    test('stale stats wait while the server cannot be asked', () {
      final answers = [const Err<bool>(NetworkFailure()), const Ok<bool>(true)];
      when(() => repository.isStored('u1', 'w0'))
          .thenAnswer((_) async => answers.removeAt(0));
      when(() => store.load('u1')).thenAnswer(
        (_) async => Ok(
          LocalWorkouts(
            finished: [workout('w0', const [], finishedAt: end)],
            staleStats: const {'bench'},
          ),
        ),
      );
      onFakeTime(build, (async, _) {
        users.add(alice);
        async.flushMicrotasks();
        async.elapse(retryDelay - const Duration(microseconds: 1));
        verifyNever(() => repository.workoutsWith(any(), any()));
        async.elapse(const Duration(microseconds: 1));
        verify(() => repository.workoutsWith('u1', 'bench')).called(1);
        expect(keptLocal(), const LocalWorkouts());
      });
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

  group('rest', () {
    const first = (exercise: 0, set: 0);
    const second = (exercise: 0, set: 1);
    final restEnd = now.add(const Duration(seconds: 90));

    /// Squat, two sets, a program rest of 90 s.
    Future<ActiveWorkoutCubit> withSquat() async {
      final cubit = await signedIn();
      settings.add(userSettings);
      await cubit.startProgramDay(legs, 0, name: 'Legs', language: 'en');
      return cubit;
    }

    test('a tick starts the rest and keeps it with the workout', () async {
      final cubit = await withSquat();
      cubit.toggleDone(first);
      expect(cubit.state.rest, Rest(endsAt: restEnd, after: first));
      await pumpEventQueue();
      expect(keptLocal().rest, cubit.state.rest);
      await cubit.close();
    });

    test('a free workout rests the exercise\'s default', () async {
      final cubit = await signedIn();
      cubit
        ..startWith(squat, 'Workout', 'en')
        ..setWeight(first, '100', WeightUnit.kg)
        ..setReps(first, '5')
        ..toggleDone(first);
      expect(cubit.state.rest!.endsAt, now.add(const Duration(seconds: 90)));
      await cubit.close();
    });

    test('without a program or exercise rest, the user\'s default', () async {
      final mine = Exercise.custom(
        id: '${Exercise.customIdPrefix}1',
        name: 'My Row',
        loggingType: LoggingType.reps,
        mainMuscles: const [Muscle.lat],
      );
      final cubit = await signedIn();
      settings.add(userSettings);
      await pumpEventQueue();
      cubit
        ..startWith(mine, 'Workout', 'en')
        ..setReps(first, '10')
        ..toggleDone(first);
      expect(cubit.state.rest!.endsAt, now.add(const Duration(seconds: 75)));
      await cubit.close();
    });

    test('another user\'s settings are never used', () async {
      final mine = Exercise.custom(
        id: '${Exercise.customIdPrefix}1',
        name: 'My Row',
        loggingType: LoggingType.reps,
        mainMuscles: const [Muscle.lat],
      );
      final cubit = await signedIn();
      settings.add(userSettings);
      await pumpEventQueue();
      users.add(bob);
      await pumpEventQueue();
      cubit
        ..startWith(mine, 'Workout', 'en')
        ..setReps(first, '10')
        ..toggleDone(first);
      // Bob's settings have not arrived: the defaults, not Alice's 75 s.
      expect(cubit.state.rest!.endsAt, now.add(const Duration(seconds: 90)));
      await cubit.close();
    });

    test('nothing starts while the timer is off', () async {
      final cubit = await withSquat();
      settings.add(
        userSettings.copyWith(
          restTimer: const RestTimerSettings(enabled: false),
        ),
      );
      await pumpEventQueue();
      cubit.toggleDone(first);
      expect(cubit.state.rest, isNull);
      await cubit.close();
    });

    test('unticking the set ends its rest, another set\'s does not', () async {
      final cubit = await withSquat();
      cubit
        ..toggleDone(first)
        ..toggleDone(second);
      expect(cubit.state.rest!.after, second);
      cubit.toggleDone(first);
      expect(cubit.state.rest!.after, second);
      cubit.toggleDone(second);
      expect(cubit.state.rest, isNull);
      await pumpEventQueue();
      expect(keptLocal().rest, isNull);
      await cubit.close();
    });

    test('an edit that unticks the set ends its rest too', () async {
      final cubit = await withSquat();
      cubit
        ..toggleDone(first)
        ..setReps(first, '');
      expect(cubit.state.rest, isNull);
      await cubit.close();
    });

    test('a new tick starts the rest again', () async {
      final cubit = await withSquat();
      cubit.toggleDone(first);
      clock = now.add(const Duration(seconds: 30));
      cubit.toggleDone(second);
      expect(
        cubit.state.rest,
        Rest(endsAt: clock.add(const Duration(seconds: 90)), after: second),
      );
      await cubit.close();
    });

    test('a warm-up leaves the running rest alone', () async {
      final cubit = await withSquat();
      // The first set made a warm-up stays where it is.
      cubit
        ..setType(first, SetType.warmup)
        ..toggleDone(second)
        ..toggleDone(first);
      expect(cubit.state.rest, Rest(endsAt: restEnd, after: second));
      await cubit.close();
    });

    test('+15 s and skip', () async {
      final cubit = await withSquat();
      cubit
        ..toggleDone(first)
        ..extendRest();
      expect(cubit.state.rest!.endsAt, restEnd.add(restExtension));
      await pumpEventQueue();
      expect(keptLocal().rest!.endsAt, restEnd.add(restExtension));
      cubit.skipRest();
      expect(cubit.state.rest, isNull);
      await pumpEventQueue();
      expect(keptLocal().rest, isNull);
      await cubit.close();
    });

    test('+15 s does nothing once the rest is over', () async {
      final cubit = await withSquat();
      cubit.toggleDone(first);
      clock = restEnd;
      cubit.extendRest();
      expect(cubit.state.rest!.endsAt, restEnd);
      await cubit.close();
    });

    test('moving sets keeps the rest but forgets its set', () async {
      final cubit = await signedIn();
      cubit
        ..startWith(squat, 'Workout', 'en')
        ..addExercises([bench], 'en')
        ..setWeight(first, '100', WeightUnit.kg)
        ..setReps(first, '5')
        ..toggleDone(first)
        ..moveExercise(0, 1);
      expect(cubit.state.rest, Rest(endsAt: restEnd));
      // The squat set, now the second exercise's, no longer ends it.
      cubit.toggleDone((exercise: 1, set: 0));
      expect(cubit.state.rest, Rest(endsAt: restEnd));
      await cubit.close();
    });

    test('removing the last exercise ends the rest', () async {
      final cubit = await signedIn();
      cubit
        ..startWith(squat, 'Workout', 'en')
        ..setWeight(first, '100', WeightUnit.kg)
        ..setReps(first, '5')
        ..toggleDone(first);
      expect(cubit.state.rest, isNotNull);
      cubit.removeExercise(0);
      expect(cubit.state.inProgress, isFalse);
      expect(cubit.state.rest, isNull);
      await cubit.close();
    });

    test('discarding ends the rest', () async {
      final cubit = await withSquat();
      cubit.toggleDone(first);
      await cubit.discard();
      expect(cubit.state.rest, isNull);
      await cubit.close();
    });

    test('finishing ends the rest', () async {
      final cubit = await withSquat();
      cubit.toggleDone(first);
      await cubit.finish();
      expect(cubit.state.status, WorkoutStatus.finished);
      expect(cubit.state.rest, isNull);
      expect(keptLocal().rest, isNull);
      await cubit.close();
    });

    test('a kept rest comes back with its workout', () async {
      final rest = Rest(endsAt: restEnd, after: first);
      final cubit = await signedIn(
        local: LocalWorkouts(draft: saved, rest: rest),
      );
      expect(cubit.state.rest, rest);
      await cubit.close();
    });

    test('another user never gets the previous one\'s rest', () async {
      final cubit = await signedIn(
        local: LocalWorkouts(
          draft: saved,
          rest: Rest(endsAt: restEnd),
        ),
      );
      users.add(bob);
      await pumpEventQueue();
      expect(cubit.state.rest, isNull);
      await cubit.close();
    });
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

    test('a rebuild crossed by an edit is done again', () async {
      final firstRead = Completer<Result<ExerciseWorkouts>>();
      var reads = 0;
      when(() => repository.workoutsWith('u1', 'squat')).thenAnswer((_) {
        reads++;
        return reads == 1
            ? firstRead.future
            : Future.value(const Ok((workouts: [], complete: true)));
      });
      final cubit = await signedIn(
        local: const LocalWorkouts(staleStats: {'squat'}),
      );
      expect(reads, 1);
      // The edit's batch starts while the first rebuild has read.
      cubit.storedWorkoutChanged(
        'u1',
        'w0',
        deleted: false,
        staleStats: const {'squat'},
      );
      firstRead.complete(const Ok((workouts: [], complete: true)));
      await pumpEventQueue();
      // Its write may land after the edit's: a second rebuild follows.
      expect(reads, 2);
      verify(() => repository.saveStats('u1', 'squat', null)).called(2);
      expect(keptLocal().staleStats, isEmpty);
      await cubit.close();
    });

    test('a rebuild crossed by a finish is done again after it', () async {
      final firstRead = Completer<Result<ExerciseWorkouts>>();
      var reads = 0;
      when(() => repository.workoutsWith('u1', 'squat')).thenAnswer((_) {
        reads++;
        return reads == 1
            ? firstRead.future
            : Future.value(const Ok((workouts: [], complete: true)));
      });
      when(() => repository.getStats('u1', ['squat'])).thenAnswer(
        (_) async => const Ok({'squat': (stats: null, current: true)}),
      );
      final cubit = await signedIn(
        draft: saved,
        local: LocalWorkouts(draft: saved, staleStats: const {'squat'}),
      );
      await cubit.finish();
      firstRead.complete(const Ok((workouts: [], complete: true)));
      await pumpEventQueue();
      expect(reads, 2);
      expect(keptLocal().staleStats, isEmpty);
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
