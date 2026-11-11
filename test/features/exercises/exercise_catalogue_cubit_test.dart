import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockExerciseRepository extends Mock implements ExerciseRepository {}

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

void main() {
  late MockAuthRepository auth;
  late MockExerciseRepository repository;
  late StreamController<AuthUser?> users;
  late StreamController<List<Exercise>> exercises;
  late DateTime now;

  setUp(() {
    auth = MockAuthRepository();
    repository = MockExerciseRepository();
    users = StreamController<AuthUser?>();
    exercises = StreamController<List<Exercise>>();
    now = DateTime(2026, 11, 11, 9);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.watchExercises()).thenAnswer((_) => exercises.stream);
  });

  tearDown(() async {
    await users.close();
    await exercises.close();
  });

  ExerciseCatalogueCubit build() => ExerciseCatalogueCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchExercises: WatchExercises(repository),
    syncExercises: SyncExercises(repository),
    now: () => now,
  );

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
}
