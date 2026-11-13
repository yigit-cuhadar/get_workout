import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/progress/domain/progress_usecases.dart';
import 'package:get_workout/features/progress/presentation/progress_strength_cubit.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
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

  ExerciseStats best(double kg, DateTime date) => ExerciseStats(
    records: {
      RecordKind.bestE1rm: StatRecord(value: kg, date: date, workoutId: 'w'),
    },
    history: [HistoryPoint(date: date, workoutId: 'w')],
  );

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

  ProgressStrengthCubit build() {
    final auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    return ProgressStrengthCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchHighlights: WatchStrengthHighlights(repository),
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

  test('the highlights, named from the catalogue', () async {
    final cubit = build();
    await signIn(alice);
    expect(cubit.state.status, ProgressStrengthStatus.loading);
    await show({
      'squat': best(120, DateTime(2026, 11, 1)),
      'bench': best(90, DateTime(2026, 11, 10)),
      'ex_retired': best(50, DateTime(2026, 10, 1)),
    });

    expect(
      cubit.state,
      ProgressStrengthState(
        status: ProgressStrengthStatus.ready,
        tiles: [
          StrengthTile(exerciseId: 'bench', e1rmKg: 90, exercise: bench),
          StrengthTile(exerciseId: 'squat', e1rmKg: 120, exercise: squat),
          // No longer in the library: no name.
          const StrengthTile(exerciseId: 'ex_retired', e1rmKg: 50),
        ],
      ),
    );
    verify(() => repository.watchAllStats('u1')).called(1);
    await cubit.close();
  });

  test('ready and empty before any e1RM', () async {
    final cubit = build();
    await signIn(alice);
    await show(const {});
    expect(
      cubit.state,
      const ProgressStrengthState(status: ProgressStrengthStatus.ready),
    );
    await cubit.close();
  });

  test('loading until custom exercises can be named', () async {
    whenListen(
      catalogue,
      catalogueStates.stream,
      initialState: CatalogueReady([squat], customLoaded: false),
    );
    final cubit = build();
    await signIn(alice);
    await show({'custom_abc': best(70, DateTime(2026, 11, 1))});
    expect(cubit.state.status, ProgressStrengthStatus.loading);

    catalogueStates.add(
      CatalogueReady([squat, move('custom_abc', name: 'Mine')]),
    );
    await pumpEventQueue();
    expect(cubit.state.status, ProgressStrengthStatus.ready);
    expect(cubit.state.tiles.single.exercise?.id, 'custom_abc');
    await cubit.close();
  });

  test('a failed stream is a failure until it delivers again', () async {
    final cubit = build();
    await signIn(alice);
    stats.addError(const NetworkFailure('offline'));
    await pumpEventQueue();
    expect(cubit.state.status, ProgressStrengthStatus.failure);

    cubit.retry();
    await show({'squat': best(120, DateTime(2026, 11, 1))});
    expect(cubit.state.status, ProgressStrengthStatus.ready);
    await cubit.close();
  });

  test('a failed catalogue is a failure, and retry reloads it', () async {
    when(() => catalogue.retry()).thenAnswer((_) async {});
    whenListen(
      catalogue,
      catalogueStates.stream,
      initialState: const CatalogueFailed(NetworkFailure('offline')),
    );
    final cubit = build();
    await signIn(alice);
    await show({'squat': best(120, DateTime(2026, 11, 1))});
    expect(cubit.state.status, ProgressStrengthStatus.failure);

    cubit.retry();
    verify(() => catalogue.retry()).called(1);
    await cubit.close();
  });

  test(
    'a user change starts over, never showing the previous user\'s',
    () async {
      final cubit = build();
      await signIn(alice);
      await show({'squat': best(120, DateTime(2026, 11, 1))});
      expect(cubit.state.status, ProgressStrengthStatus.ready);

      await signIn(bob);
      expect(cubit.state, const ProgressStrengthState());
      verify(() => repository.watchAllStats('u2')).called(1);
      await cubit.close();
    },
  );
}
