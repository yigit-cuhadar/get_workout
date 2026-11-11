import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockExerciseRepository extends Mock implements ExerciseRepository {}

class MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

const _guest = AuthUser(id: 'g1', isAnonymous: true);
const _offline = NetworkFailure();

const _squat = Exercise(
  id: 'squat',
  loggingType: LoggingType.weightReps,
  mechanic: Mechanic.compound,
  laterality: Laterality.bilateral,
  level: Level.beginner,
  force: Force.push,
  movementPattern: MovementPattern.squat,
  position: Position.standing,
  equipment: [Equipment.barbell],
  mainMuscles: [Muscle.quads],
  family: 'squat',
  familyRank: 1,
  defaultRestS: 120,
  popularity: 1,
  l10n: {'en': ExerciseText(name: 'Squat')},
);

const _press = CustomExercise(
  id: 'custom_a',
  name: 'Landmine Press',
  mainMuscles: [Muscle.frontDelt],
);

void main() {
  late MockAuthRepository auth;
  late MockExerciseRepository repository;
  late MockCustomExerciseRepository customRepository;
  late StreamController<AuthUser?> users;
  late StreamController<List<Exercise>> exercises;
  late Map<String, StreamController<List<CustomExercise>>> custom;
  late DateTime now;

  setUp(() {
    auth = MockAuthRepository();
    repository = MockExerciseRepository();
    customRepository = MockCustomExerciseRepository();
    // Followed for the sync and for the custom exercises.
    users = StreamController<AuthUser?>.broadcast();
    exercises = StreamController<List<Exercise>>();
    custom = {};
    now = DateTime(2026, 11, 11, 9);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.watchExercises()).thenAnswer((_) => exercises.stream);
    when(() => customRepository.watchCustomExercises(any())).thenAnswer(
      (call) => custom
          .putIfAbsent(
            call.positionalArguments.single as String,
            StreamController<List<CustomExercise>>.broadcast,
          )
          .stream,
    );
  });

  tearDown(() async {
    await users.close();
    await exercises.close();
    for (final controller in custom.values) {
      await controller.close();
    }
  });

  ExerciseCatalogueCubit build() => ExerciseCatalogueCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchExercises: WatchExercises(repository),
    watchCustomExercises: WatchCustomExercises(customRepository),
    syncExercises: SyncExercises(repository),
    now: () => now,
  );

  /// Custom exercises of user [uid] arrive.
  void customOf(String uid, List<CustomExercise> list) =>
      custom[uid]!.add(list);

  /// A sync that publishes [list] first, as the repository does.
  void syncPublishes(List<Exercise> list) =>
      when(() => repository.sync()).thenAnswer((_) async {
        exercises.add(list);
        await pumpEventQueue();
        return const Ok(null);
      });

  void syncFails() =>
      when(() => repository.sync())
          .thenAnswer((_) async => const Err(_offline));

  test('starts loading', () {
    expect(build().state, const CatalogueLoading());
  });

  blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
    'does not sync before a user exists, even on resume or retry',
    build: build,
    act: (cubit) async {
      users.add(null);
      await pumpEventQueue();
      await cubit.appResumed();
      await cubit.retry();
    },
    expect: () => <ExerciseCatalogueState>[],
    verify: (_) => verifyNever(() => repository.sync()),
  );

  blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
    'the first signed-in user starts the sync, which shows the list',
    setUp: () => syncPublishes([_squat]),
    build: build,
    act: (cubit) async {
      users
        ..add(null)
        ..add(_guest)
        ..add(const AuthUser(id: 'u1', email: 'a@b.co'));
      await pumpEventQueue();
    },
    expect: () => [
      const CatalogueReady([_squat]),
    ],
    verify: (_) => verify(() => repository.sync()).called(1),
  );

  blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
    'a failed first sync with nothing cached fails, and retry recovers',
    setUp: syncFails,
    build: build,
    act: (cubit) async {
      users.add(_guest);
      await pumpEventQueue();
      syncPublishes([_squat]);
      await cubit.retry();
    },
    expect: () => [
      const CatalogueFailed(_offline),
      const CatalogueLoading(),
      const CatalogueReady([_squat]),
    ],
  );

  blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
    'a failed retry fails again',
    setUp: syncFails,
    build: build,
    act: (cubit) async {
      users.add(_guest);
      await pumpEventQueue();
      await cubit.retry();
    },
    expect: () => [
      const CatalogueFailed(_offline),
      const CatalogueLoading(),
      const CatalogueFailed(_offline),
    ],
  );

  blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
    'a later failed sync keeps the list',
    setUp: () => syncPublishes([_squat]),
    build: build,
    act: (cubit) async {
      users.add(_guest);
      await pumpEventQueue();
      syncFails();
      await cubit.retry();
    },
    expect: () => [
      const CatalogueReady([_squat]),
    ],
  );

  blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
    'a cached list shows even when the first sync fails',
    setUp: () => when(() => repository.sync()).thenAnswer((_) async {
      exercises.add([_squat]);
      await pumpEventQueue();
      return const Err(_offline);
    }),
    build: build,
    act: (cubit) async {
      users.add(_guest);
      await pumpEventQueue();
    },
    expect: () => [
      const CatalogueReady([_squat]),
    ],
  );

  blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
    'returning to the foreground syncs at most once per interval',
    setUp: () => syncPublishes([_squat]),
    build: build,
    act: (cubit) async {
      users.add(_guest);
      await pumpEventQueue();
      now = now.add(const Duration(minutes: 4));
      await cubit.appResumed();
      now = now.add(const Duration(minutes: 1));
      await cubit.appResumed();
      now = now.add(const Duration(minutes: 1));
      await cubit.appResumed();
    },
    verify: (_) => verify(() => repository.sync()).called(2),
  );

  group('custom exercises', () {
    final press = _press.toExercise();

    blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
      'wait for the catalogue, then come first in it',
      setUp: () => syncPublishes([_squat]),
      build: build,
      act: (cubit) async {
        when(() => repository.sync()).thenAnswer((_) async => const Ok(null));
        users.add(_guest);
        await pumpEventQueue();
        customOf('g1', [_press]);
        await pumpEventQueue();
        exercises.add([_squat]);
      },
      expect: () => [
        CatalogueReady([press, _squat]),
      ],
    );

    blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
      'follow edits and deletes',
      setUp: () => syncPublishes([_squat]),
      build: build,
      act: (cubit) async {
        users.add(_guest);
        await pumpEventQueue();
        customOf('g1', [_press]);
        await pumpEventQueue();
        customOf('g1', [
          const CustomExercise(
            id: 'custom_a',
            name: 'Half-Kneeling Landmine Press',
            mainMuscles: [Muscle.frontDelt],
          ),
        ]);
        await pumpEventQueue();
        customOf('g1', []);
      },
      expect: () => [
        const CatalogueReady([_squat]),
        CatalogueReady([press, _squat]),
        CatalogueReady([
          Exercise.custom(
            id: 'custom_a',
            name: 'Half-Kneeling Landmine Press',
            loggingType: LoggingType.weightReps,
            mainMuscles: const [Muscle.frontDelt],
          ),
          _squat,
        ]),
        const CatalogueReady([_squat]),
      ],
    );

    blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
      "a change of user drops the previous user's at once",
      setUp: () => syncPublishes([_squat]),
      build: build,
      act: (cubit) async {
        users.add(_guest);
        await pumpEventQueue();
        customOf('g1', [_press]);
        await pumpEventQueue();
        users.add(const AuthUser(id: 'u2', email: 'a@b.co'));
        await pumpEventQueue();
        // A late value for the previous user is not followed any more.
        custom['g1']!.add([_press]);
        await pumpEventQueue();
        customOf('u2', []);
      },
      expect: () => [
        const CatalogueReady([_squat]),
        CatalogueReady([press, _squat]),
        const CatalogueReady([_squat]),
      ],
    );

    blocTest<ExerciseCatalogueCubit, ExerciseCatalogueState>(
      'keep the last list when their stream fails, and follow it again',
      setUp: () => syncPublishes([_squat]),
      build: () => ExerciseCatalogueCubit(
        watchAuthUser: WatchAuthUser(auth),
        watchExercises: WatchExercises(repository),
        watchCustomExercises: WatchCustomExercises(customRepository),
        syncExercises: SyncExercises(repository),
        now: () => now,
        retryDelay: Duration.zero,
      ),
      act: (cubit) async {
        users.add(_guest);
        await pumpEventQueue();
        customOf('g1', [_press]);
        await pumpEventQueue();
        custom['g1']!.addError(_offline);
        await pumpEventQueue();
        customOf('g1', []);
        await pumpEventQueue();
      },
      expect: () => [
        const CatalogueReady([_squat]),
        CatalogueReady([press, _squat]),
        const CatalogueReady([_squat]),
      ],
      verify: (_) =>
          verify(() => customRepository.watchCustomExercises('g1')).called(2),
    );
  });
}
