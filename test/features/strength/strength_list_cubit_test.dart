import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/strength/presentation/strength_list_cubit.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  const alice = AuthUser(id: 'u1', isAnonymous: true);
  const bob = AuthUser(id: 'u2', isAnonymous: true);
  final squat = move('squat', name: 'Back Squat');
  final bench = move('bench', name: 'Bench Press');

  ExerciseStats doneOn(DateTime date) => ExerciseStats(
    history: [HistoryPoint(date: date, workoutId: 'w')],
  );

  final aliceStats = {
    'squat': doneOn(DateTime(2026, 11, 1)),
    'bench': doneOn(DateTime(2026, 11, 10)),
    'ex_retired': doneOn(DateTime(2026, 10, 1)),
  };

  late StreamController<AuthUser?> users;
  late StreamController<Map<String, ExerciseStats>> stats;
  late StreamController<ExerciseCatalogueState> catalogueStates;
  late MockWorkoutRepository repository;
  late MockCatalogueCubit catalogue;

  setUp(() {
    users = StreamController<AuthUser?>.broadcast();
    stats = StreamController<Map<String, ExerciseStats>>.broadcast();
    catalogueStates = StreamController<ExerciseCatalogueState>.broadcast();
    repository = MockWorkoutRepository();
    when(() => repository.watchAllStats(any())).thenAnswer((_) => stats.stream);
    catalogue = MockCatalogueCubit();
    whenListen(
      catalogue,
      catalogueStates.stream,
      initialState: CatalogueReady([squat, bench]),
    );
  });

  tearDown(() async {
    await users.close();
    await stats.close();
    await catalogueStates.close();
  });

  StrengthListCubit build() {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    return StrengthListCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchAllStats: WatchAllExerciseStats(repository),
      catalogue: catalogue,
    );
  }

  Future<void> signIn(AuthUser? user) async {
    users.add(user);
    await pumpEventQueue();
  }

  Future<void> show(Map<String, ExerciseStats> value) async {
    stats.add(value);
    await pumpEventQueue();
  }

  List<String> ids(StrengthListState state) => [
    for (final item in state.items) item.exerciseId,
  ];

  test('most recently trained first, named from the catalogue', () async {
    final cubit = build();
    await signIn(alice);
    expect(cubit.state.status, StrengthListStatus.loading);
    await show(aliceStats);

    expect(cubit.state.status, StrengthListStatus.ready);
    expect(ids(cubit.state), ['bench', 'squat', 'ex_retired']);
    expect(cubit.state.items.first.exercise, bench);
    expect(cubit.state.items.first.lastTrained, DateTime(2026, 11, 10));
    expect(cubit.state.trainedCount, 3);
    verify(() => repository.watchAllStats('u1')).called(1);
    await cubit.close();
  });

  test('an exercise no longer in the library is marked removed', () async {
    final cubit = build();
    await signIn(alice);
    await show(aliceStats);
    final retired = cubit.state.items.last;
    expect(retired.exercise, isNull);
    expect(retired.removed, isTrue);
    await cubit.close();
  });

  test('a custom exercise is not removed before custom ones load', () async {
    whenListen(
      catalogue,
      catalogueStates.stream,
      initialState: CatalogueReady([squat], customLoaded: false),
    );
    final cubit = build();
    await signIn(alice);
    await show({'custom_abc': doneOn(DateTime(2026, 11, 1))});
    expect(cubit.state.items.single.removed, isFalse);

    catalogueStates.add(
      CatalogueReady([squat, move('custom_abc', name: 'Mine')]),
    );
    await pumpEventQueue();
    expect(cubit.state.items.single.exercise?.id, 'custom_abc');
    await cubit.close();
  });

  test('a search keeps the matching exercises in their order', () async {
    final cubit = build();
    await signIn(alice);
    await show({...aliceStats, 'front': doneOn(DateTime(2026, 11, 11))});
    catalogueStates.add(
      CatalogueReady([squat, bench, move('front', name: 'Front Squat')]),
    );
    await pumpEventQueue();

    cubit.setQuery('squat');
    expect(ids(cubit.state), ['front', 'squat']);
    expect(cubit.state.trainedCount, 4);
    expect(cubit.state.query, 'squat');

    cubit.setQuery('');
    expect(ids(cubit.state), ['front', 'bench', 'squat', 'ex_retired']);
    await cubit.close();
  });

  test('none trained is ready and empty', () async {
    final cubit = build();
    await signIn(alice);
    await show({});
    expect(cubit.state.status, StrengthListStatus.ready);
    expect(cubit.state.trainedCount, 0);
    await cubit.close();
  });

  test('a failure shows, and retry follows again', () async {
    final cubit = build();
    await signIn(alice);
    stats.addError(const NetworkFailure());
    await pumpEventQueue();
    expect(cubit.state.status, StrengthListStatus.failure);

    cubit.retry();
    await show(aliceStats);
    expect(cubit.state.status, StrengthListStatus.ready);
    await cubit.close();
  });

  test('another user starts over and never sees the previous list', () async {
    final cubit = build();
    await signIn(alice);
    await show(aliceStats);
    await signIn(bob);
    expect(cubit.state, const StrengthListState());
    verify(() => repository.watchAllStats('u2')).called(1);
    await cubit.close();
  });

  blocTest<StrengthListCubit, StrengthListState>(
    'a query typed while loading is kept',
    build: build,
    act: (cubit) => cubit.setQuery('be'),
    expect: () => [const StrengthListState(query: 'be')],
  );
}
